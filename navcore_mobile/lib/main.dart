import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import 'engine/bearing_engine.dart';
import 'engine/ecef_engine.dart';
import 'engine/floor_tracker.dart';
import 'engine/kalman_filter.dart';
import 'engine/pnp_engine.dart';
import 'engine/real_sensor_service.dart';
import 'engine/ar_sensor_engine.dart';
import 'data/destinations.dart';
import 'data/floor_height_model.dart';
import 'data/mall_database_service.dart';
import 'data/api_service.dart';
import 'data/geocoding_service.dart';
import 'data/parking_service.dart';

import 'ui/welcome_screen.dart';
import 'ui/login_screen.dart';
import 'ui/admin_dashboard_screen.dart';
import 'ui/location_lock_screen.dart';

import 'ui/home_screen.dart';
import 'ui/ar_viewport_screen.dart';
import 'ui/floor_plan_screen.dart';
import 'ui/mall_explorer_screen.dart';

/// Custom HttpOverrides to ensure network requests to nexnav.hashnate.com
/// succeed cleanly even if the remote host has SSL SAN / cert renewal discrepancies.
class NexNavHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        if (host.contains('hashnate.com') ||
            host == '10.0.2.2' ||
            host == 'localhost' ||
            host == '127.0.0.1' ||
            host.startsWith('192.168.') ||
            host.startsWith('10.')) {
          return true;
        }
        return false;
      };
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    HttpOverrides.global = NexNavHttpOverrides();
  }
  runApp(const NexNavApp());
}

class NexNavApp extends StatelessWidget {
  const NexNavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NexNav',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          primary: const Color(0xFF2563EB),
          surface: Colors.white,
        ),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(),
        useMaterial3: true,
      ),
      home: const NexNavMainNavigation(),
    );
  }
}

enum AuthScreenState { welcome, login, setup, mainNav, adminDashboard }

class NexNavMainNavigation extends StatefulWidget {
  const NexNavMainNavigation({super.key});

  @override
  State<NexNavMainNavigation> createState() => _NexNavMainNavigationState();
}

class _NexNavMainNavigationState extends State<NexNavMainNavigation> {
  AuthScreenState _authScreenState = AuthScreenState.welcome;
  UserRole _currentRole = UserRole.guest;
  UserRole _requestedLoginRole = UserRole.user;
  String _userEmail = '';

  int _currentIndex = 0;
  bool _isSetupComplete = false;
  DateTime? _lastBackPressTime;

  final RealSensorService _sensorService = RealSensorService();
  final MallDatabaseService _mallDatabaseService = MallDatabaseService();
  final BarometricElevationEngine _elevationEngine =
      BarometricElevationEngine();
  int _activeFloorNumber = 1;

  double? _userSelectedFloorHeight;
  GeodeticCoords _userCoords = const GeodeticCoords(
    latitude: 0.0,
    longitude: 0.0,
    height: 0.0,
  );
  double _compassHeading = 0.0;
  double _phonePitchDegrees = 0.0;
  PitchTiltDirection _tiltDirection = PitchTiltDirection.level;
  PnPResult? _pnpResult;
  DestinationPOI? _arTargetDestination;

  BuildingElevationProfile _buildingProfile = defaultBuildingProfile;
  List<DestinationPOI> _destinations = <DestinationPOI>[];
  List<EntranceMarkerNode> _entranceMarkers = <EntranceMarkerNode>[];

  late final KalmanPositionFilter _kalmanFilter;
  Timer? _imuTimer;
  Timer? _autoSyncTimer;
  StreamSubscription? _apiSyncSubscription;
  bool _isBackgroundSyncRunning = false;
  final GlobalKey<FloorPlanScreenState> _floorPlanKey =
      GlobalKey<FloorPlanScreenState>();

  @override
  void initState() {
    super.initState();
    _kalmanFilter = KalmanPositionFilter(_userCoords);
    _initializeRealHardware();
    _loadInitialBackendData();

    // Multi-device real-time sync listeners
    _apiSyncSubscription = ApiService.instance.syncStream.listen((event) {
      _syncLatestDataFromServer(force: true);
    });
    // Fallback periodic sync: set to 30s to prevent constant CPU/network preemption
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _syncLatestDataFromServer();
    });
  }

  Future<void> _initializeRealHardware() async {
    // 1. Request OS Permissions for Location & Camera
    final report = await _sensorService.requestAllPermissions();

    // 2. Fetch current real GPS position (cached or live)
    final realPos = await _sensorService.getLastKnownOrCurrentPosition();
    if (realPos != null) {
      double resolvedInitialHeight = realPos.height;
      if (resolvedInitialHeight <= 0.0 || resolvedInitialHeight > 4000.0) {
        resolvedInitialHeight = _buildingProfile.entranceBaseAnchorHeight > 0
            ? _buildingProfile.entranceBaseAnchorHeight
            : GeocodingService.resolveTerrainAltitudeFromCoords(
                realPos.latitude,
                realPos.longitude,
              );
      }
      final posWithHeight = GeodeticCoords(
        latitude: realPos.latitude,
        longitude: realPos.longitude,
        height: resolvedInitialHeight,
      );
      final initialFloor = resolveFloorByHeight(
        resolvedInitialHeight,
        _buildingProfile,
      );
      setState(() {
        _userCoords = posWithHeight;
        _kalmanFilter.setPosition(_userCoords);
        _activeFloorNumber = initialFloor.floorNumber;
      });
      _elevationEngine.calibrateBaseline(
        _sensorService.currentPressure,
        resolvedInitialHeight,
      );
    }

    // 3. Start real hardware sensors (GPS + Magnetometer Compass + Barometer)
    _sensorService.startHardwareStreams(
      onLocationUpdated: (coords, accuracy) {
        double effectiveAltitude = coords.height;
        if (effectiveAltitude <= 0.0 || effectiveAltitude > 4000.0) {
          effectiveAltitude = _buildingProfile.entranceBaseAnchorHeight > 0
              ? _buildingProfile.entranceBaseAnchorHeight
              : GeocodingService.resolveTerrainAltitudeFromCoords(
                  coords.latitude,
                  coords.longitude,
                );
        }

        if (!_elevationEngine.isCalibrated) {
          _elevationEngine.calibrateBaseline(
            _sensorService.currentPressure,
            effectiveAltitude,
          );
        }

        final liveFusedHeight = _elevationEngine.computeFusedLocationHeight(
          currentPressureHpa: _sensorService.currentPressure,
          gpsAltitude: effectiveAltitude,
          gpsAccuracy: accuracy,
        );

        final targetHeight = _userSelectedFloorHeight ?? liveFusedHeight;
        final resolvedFloor = resolveFloorByHeight(
          targetHeight,
          _buildingProfile,
        );

        final double moveDist = haversineDistance(_userCoords, coords);
        final bool floorChanged =
            resolvedFloor.floorNumber != _activeFloorNumber;
        final bool shouldRebuild = floorChanged ||
            moveDist >= 0.5 ||
            _userCoords.latitude == 0.0;

        _userCoords = GeodeticCoords(
          latitude: coords.latitude,
          longitude: coords.longitude,
          height: targetHeight,
        );
        _kalmanFilter.setPosition(_userCoords);
        if (floorChanged) {
          _activeFloorNumber = resolvedFloor.floorNumber;
        }

        if (shouldRebuild && mounted) {
          setState(() {});
          _checkAndAutoUpdateMallProximity();
        }
      },
      onHeadingUpdated: (heading) {
        final double prevHeading = _compassHeading;
        _compassHeading = heading;
        // ONLY call setState if the user is currently looking at the AR View screen (_currentIndex == 1)!
        // When on Home (0), Map (2), Mall Explorer (3), or Admin Dashboard, NEVER trigger full root rebuilds!
        if (mounted &&
            _currentIndex == 1 &&
            (heading - prevHeading).abs() >= 1.0) {
          setState(() {});
        }
      },
      onPitchUpdated: (pitch, dir) {
        final double prevPitch = _phonePitchDegrees;
        final PitchTiltDirection prevDir = _tiltDirection;
        _phonePitchDegrees = pitch;
        _tiltDirection = dir;
        // ONLY call setState if the user is currently looking at the AR View screen (_currentIndex == 1)!
        if (mounted &&
            _currentIndex == 1 &&
            ((pitch - prevPitch).abs() >= 1.0 || dir != prevDir)) {
          setState(() {});
        }
      },
      onPressureUpdated: (rawPressure, smoothedPressure) {
        if (!_elevationEngine.isCalibrated) {
          final baseAnchor = _userCoords.height > 0
              ? _userCoords.height
              : (_buildingProfile.entranceBaseAnchorHeight > 0
                    ? _buildingProfile.entranceBaseAnchorHeight
                    : GeocodingService.resolveTerrainAltitudeFromCoords(
                        _userCoords.latitude,
                        _userCoords.longitude,
                      ));
          _elevationEngine.calibrateBaseline(smoothedPressure, baseAnchor);
          if (kDebugMode) {
            print(
              '[BAROMETER] Entrance Baseline Calibrated: ${smoothedPressure.toStringAsFixed(2)} hPa @ ${baseAnchor}m',
            );
          }
        }

        double calculatedHeight = _elevationEngine.computeFusedLocationHeight(
          currentPressureHpa: smoothedPressure,
          gpsAltitude: _userCoords.height > 0 ? _userCoords.height : null,
          gpsAccuracy: _sensorService.lastAccuracy > 0
              ? _sensorService.lastAccuracy
              : null,
        );
        FloorLevelConfig resolvedFloor = resolveFloorByHeight(
          calculatedHeight,
          _buildingProfile,
        );

        if (kDebugMode && (calculatedHeight - _userCoords.height).abs() > 0.5) {
          if (kDebugMode) {
            print(
              '[BAROMETER] Live Pressure: ${smoothedPressure.toStringAsFixed(2)} hPa | Height: ${calculatedHeight.toStringAsFixed(1)}m | Floor: ${resolvedFloor.name}',
            );
          }
        }

        if (mounted) {
          setState(() {
            _userCoords = GeodeticCoords(
              latitude: _userCoords.latitude,
              longitude: _userCoords.longitude,
              height: _userSelectedFloorHeight ?? calculatedHeight,
            );
            _kalmanFilter.setPosition(_userCoords);

            if (resolvedFloor.floorNumber != _activeFloorNumber) {
              if (kDebugMode) {
                print(
                  '[BAROMETER] Floor Auto-Switched: Floor $_activeFloorNumber -> Floor ${resolvedFloor.floorNumber} (${resolvedFloor.name})',
                );
              }
              _activeFloorNumber = resolvedFloor.floorNumber;
            }
          });
        }
      },
    );

    // 4. Auto-load nearest or global venue map package based on user's GPS position
    await _autoLoadNearestMallMap();

    if (!report.hasLocationPermission && mounted) {
      _showPermissionOnboardingDialog();
    }
  }

  List<DestinationPOI> _deduplicateDestinations(List<DestinationPOI> list) {
    final seen = <String>{};
    final seenIds = <String>{};
    final result = <DestinationPOI>[];
    for (final p in list) {
      final key =
          '${p.name.trim().toLowerCase()}#${p.floorNumber}#${p.mallId ?? ''}';
      if (!seen.contains(key) && !seenIds.contains(p.id)) {
        seen.add(key);
        seenIds.add(p.id);
        result.add(p);
      }
    }
    return result;
  }

  Future<void> _loadActiveMallPackage(String? mallId, {bool? isAdmin}) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanId = (mallId ?? '').trim();
    final bool adminMode =
        isAdmin ??
        (_currentRole == UserRole.admin ||
            _authScreenState == AuthScreenState.adminDashboard);

    final roleKey = adminMode
        ? 'NexNav_admin_active_mall_id'
        : 'NexNav_user_active_mall_id';

    if (cleanId.isEmpty) {
      await prefs.remove(roleKey);
      await prefs.remove('NexNav_active_mall_id');
      await _mallDatabaseService.clearActiveMall(isAdmin: adminMode);
      if (mounted) {
        setState(() {
          _buildingProfile = const BuildingElevationProfile(
            buildingId: '',
            name: '',
            entranceBaseAnchorHeight: 0.0,
            floorGapMeters: 0.0,
            floors: [],
          );
          _destinations = <DestinationPOI>[];
          _entranceMarkers = <EntranceMarkerNode>[];
        });
      }
      return;
    }

    await prefs.setString(roleKey, cleanId);
    await prefs.setString('NexNav_active_mall_id', cleanId);
    await _mallDatabaseService.setActiveMall(cleanId, isAdmin: adminMode);

    final pkg = await _mallDatabaseService.loadMallPackage(
      cleanId,
      userCoords: _userCoords,
      isAdmin: adminMode,
    );
    if (mounted) {
      double resolvedUserH = _userCoords.height;
      if (resolvedUserH <= 0.0 || resolvedUserH > 4000.0) {
        resolvedUserH = pkg.profile.entranceBaseAnchorHeight > 0
            ? pkg.profile.entranceBaseAnchorHeight
            : GeocodingService.resolveTerrainAltitudeFromCoords(
                _userCoords.latitude,
                _userCoords.longitude,
              );
      }
      final resolvedFloor = resolveFloorByHeight(resolvedUserH, pkg.profile);
      setState(() {
        _buildingProfile = pkg.profile;
        _destinations = _deduplicateDestinations(pkg.destinations);
        _entranceMarkers = pkg.entranceMarkers;
        _userCoords = GeodeticCoords(
          latitude: _userCoords.latitude,
          longitude: _userCoords.longitude,
          height: _userSelectedFloorHeight ?? resolvedUserH,
        );
        _kalmanFilter.setPosition(_userCoords);
        _activeFloorNumber = resolvedFloor.floorNumber;
      });
      _elevationEngine.calibrateBaseline(
        _sensorService.currentPressure,
        resolvedUserH,
      );
    }
    // Synchronize parking bay slots for loaded venue
    try {
      await ParkingService.instance.loadSlotsForMall(cleanId);
    } catch (_) {}
  }

  Future<void> _loadInitialBackendData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Restore session if Remember Me / Auto-login is active
      final bool autoLogin =
          prefs.getBool('NexNav_auto_login_enabled') ?? false;
      final String? savedEmail = prefs.getString('NexNav_remembered_email');
      final String? savedRole = prefs.getString('NexNav_remembered_role');

      if (autoLogin &&
          savedEmail != null &&
          savedEmail.isNotEmpty &&
          savedRole != null) {
        final restoredRole = savedRole == 'admin'
            ? UserRole.admin
            : UserRole.user;
        if (mounted) {
          setState(() {
            _currentRole = restoredRole;
            _userEmail = savedEmail;
            _authScreenState = (restoredRole == UserRole.admin)
                ? AuthScreenState.adminDashboard
                : AuthScreenState.setup;
          });
        }
      }

      final malls = await ApiService.instance.fetchMalls();
      if (malls.isNotEmpty) {
        final bool isAdmin =
            _currentRole == UserRole.admin ||
            _authScreenState == AuthScreenState.adminDashboard;
        final roleKey = isAdmin
            ? 'NexNav_admin_active_mall_id'
            : 'NexNav_user_active_mall_id';
        final savedActiveId =
            prefs.getString(roleKey) ??
            prefs.getString('NexNav_active_mall_id');

        // If an active venue was already selected for this role, restore it
        if (savedActiveId != null && savedActiveId.isNotEmpty) {
          final target = malls.where((m) {
            final mId = m.id.trim().toLowerCase();
            final sId = savedActiveId.trim().toLowerCase();
            return mId == sId ||
                mId.replaceAll(RegExp(r'^0+'), '') ==
                    sId.replaceAll(RegExp(r'^0+'), '');
          }).firstOrNull;
          if (target != null) {
            await _loadActiveMallPackage(target.id, isAdmin: isAdmin);
            return;
          }
        }

        // For user: check if there's any mall within 500m of current GPS coords
        if (!isAdmin &&
            _userCoords.latitude != 0.0 &&
            _userCoords.longitude != 0.0) {
          final mallsWithin500m = await _mallDatabaseService
              .getMallsWithinRadius(
                _userCoords,
                radiusMeters: 500.0,
                activeOnly: false,
              );
          if (mallsWithin500m.isNotEmpty) {
            final nearest = mallsWithin500m.first;
            await _loadActiveMallPackage(nearest.id, isAdmin: false);
            return;
          }
        }

        // Fallback to first mall in catalog
        final fallbackMall = malls.first;
        await _loadActiveMallPackage(fallbackMall.id, isAdmin: isAdmin);
      } else {
        await prefs.remove('NexNav_active_mall_id');
        await _loadActiveMallPackage('');
        if (mounted) {
          setState(() {
            _buildingProfile = const BuildingElevationProfile(
              buildingId: '',
              name: '',
              entranceBaseAnchorHeight: 0.0,
              floorGapMeters: 0.0,
              floors: [],
            );
            _destinations = <DestinationPOI>[];
            _entranceMarkers = <EntranceMarkerNode>[];
          });
        }
      }
    } catch (e) {
      debugPrint('[Main] Error loading initial backend data: $e');
    }
  }

  Future<void> _autoLoadNearestMallMap() async {
    final pkg = await _mallDatabaseService.autoDownloadAndActivateNearestMall(
      _userCoords,
      maxRadiusMeters: 500.0,
      isAdmin: false,
    );
    if (mounted) {
      setState(() {
        _buildingProfile = pkg.profile;
        _destinations = _deduplicateDestinations(pkg.destinations);
        _entranceMarkers = pkg.entranceMarkers;
      });
    }
  }

  Future<void> _syncLatestDataFromServer({bool force = false}) async {
    if (_isBackgroundSyncRunning || !mounted) return;
    _isBackgroundSyncRunning = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isAdmin =
          _currentRole == UserRole.admin ||
          _authScreenState == AuthScreenState.adminDashboard;
      final roleKey = isAdmin
          ? 'NexNav_admin_active_mall_id'
          : 'NexNav_user_active_mall_id';

      String? activeMallId = _buildingProfile.buildingId.isNotEmpty
          ? _buildingProfile.buildingId
          : prefs.getString(roleKey);
      activeMallId ??= prefs.getString('NexNav_active_mall_id');

      // ==========================================
      // 1. SYNC VENUES / MALLS
      // ==========================================
      final liveMalls = await ApiService.instance.fetchMalls();
      if (liveMalls.isNotEmpty) {
        await _mallDatabaseService.getMallsList(isAdmin: isAdmin);

        final exists =
            activeMallId != null &&
            liveMalls.any((m) {
              final mId = m.id.trim().toLowerCase();
              final aId = activeMallId!.trim().toLowerCase();
              return mId == aId ||
                  mId.replaceAll(RegExp(r'^0+'), '') ==
                      aId.replaceAll(RegExp(r'^0+'), '');
            });

        // If not set or deleted from server, point to nearest within 500m or first mall
        if (activeMallId == null || activeMallId.isEmpty || !exists) {
          if (!isAdmin &&
              _userCoords.latitude != 0.0 &&
              _userCoords.longitude != 0.0) {
            final mallsWithin500m = await _mallDatabaseService
                .getMallsWithinRadius(
                  _userCoords,
                  radiusMeters: 500.0,
                  activeOnly: false,
                );
            if (mallsWithin500m.isNotEmpty) {
              activeMallId = mallsWithin500m.first.id;
              await _loadActiveMallPackage(activeMallId, isAdmin: false);
              return;
            }
          }
          activeMallId = liveMalls.first.id;
          await _loadActiveMallPackage(activeMallId, isAdmin: isAdmin);
          return;
        }

        // NOTE: We do NOT force normal users to change their mall when the admin changes theirs!
        // Admin and User selections are decoupled and separate.

        // Check if venue metadata changed (name, anchor altitude, floorGap) FOR THE CURRENTLY LOADED MALL:
        final curMallMeta = liveMalls.where((m) {
          final mId = m.id.trim().toLowerCase();
          final aId = activeMallId!.trim().toLowerCase();
          return mId == aId ||
              mId.replaceAll(RegExp(r'^0+'), '') ==
                  aId.replaceAll(RegExp(r'^0+'), '');
        }).firstOrNull;

        if (curMallMeta != null) {
          final nameChanged =
              curMallMeta.name.isNotEmpty &&
              curMallMeta.name != _buildingProfile.name;
          final anchorChanged =
              curMallMeta.entranceBaseAnchorHeight > 0 &&
              (curMallMeta.entranceBaseAnchorHeight -
                          _buildingProfile.entranceBaseAnchorHeight)
                      .abs() >
                  0.05;
          final gapChanged =
              curMallMeta.floorGapMeters > 0 &&
              (curMallMeta.floorGapMeters - _buildingProfile.floorGapMeters)
                      .abs() >
                  0.05;

          if (nameChanged || anchorChanged || gapChanged) {
            setState(() {
              _buildingProfile = _buildingProfile.copyWith(
                name: curMallMeta.name,
                entranceBaseAnchorHeight:
                    curMallMeta.entranceBaseAnchorHeight > 0
                    ? curMallMeta.entranceBaseAnchorHeight
                    : _buildingProfile.entranceBaseAnchorHeight,
                floorGapMeters: curMallMeta.floorGapMeters > 0
                    ? curMallMeta.floorGapMeters
                    : _buildingProfile.floorGapMeters,
              );
            });
          }
        }
      }

      if (activeMallId != null && activeMallId.isNotEmpty) {
        // ==========================================
        // 2. SYNC FLOORS & ELEVATION PROFILES
        // ==========================================
        final liveFloors = await ApiService.instance.fetchFloorHeights(
          activeMallId,
        );
        if (liveFloors.isNotEmpty) {
          final bool floorCountMismatch =
              liveFloors.length != _buildingProfile.floors.length;
          bool floorHeightsMismatch = false;

          if (!floorCountMismatch) {
            for (int i = 0; i < liveFloors.length; i++) {
              final lf = liveFloors[i];
              final ef = _buildingProfile.floors[i];
              if (lf.floorNo != ef.floorNumber ||
                  (lf.heightToNextM - ef.relativeVectorMeters).abs() > 0.05 ||
                  (lf.baseAltitudeM - ef.absoluteHeightMeters).abs() > 0.05) {
                floorHeightsMismatch = true;
                break;
              }
            }
          }

          if (force ||
              floorCountMismatch ||
              floorHeightsMismatch ||
              _buildingProfile.floors.isEmpty) {
            final gap = _buildingProfile.floorGapMeters > 0
                ? _buildingProfile.floorGapMeters
                : 3.8;
            final updatedFloorConfigs = liveFloors.map((fh) {
              final fn = fh.floorNo;
              final isBasement = fn < 0;
              final floorId = isBasement ? 'B${fn.abs()}' : 'F$fn';
              final floorName = isBasement
                  ? 'Basement B${fn.abs()}'
                  : (fn == 1 ? 'Ground Floor F1' : 'Floor $fn');
              final baseAlt = fh.baseAltitudeM;
              final heightNext = fh.heightToNextM > 0 ? fh.heightToNextM : gap;
              final storesCount = _destinations
                  .where((d) => d.floorNumber == fn)
                  .length;

              return FloorLevelConfig(
                floorId: floorId,
                floorNumber: fn,
                name: floorName,
                relativeVectorMeters: heightNext,
                absoluteHeightMeters: baseAlt,
                bandMinMeters: baseAlt - 2.5,
                bandMaxMeters: baseAlt + 2.5,
                storesCount: storesCount,
              );
            }).toList();

            updatedFloorConfigs.sort(
              (a, b) =>
                  a.absoluteHeightMeters.compareTo(b.absoluteHeightMeters),
            );

            final existsCurrent = updatedFloorConfigs.any(
              (f) => f.floorNumber == _activeFloorNumber,
            );
            final newActiveFloor = existsCurrent
                ? _activeFloorNumber
                : (updatedFloorConfigs.firstOrNull?.floorNumber ?? 1);

            setState(() {
              _buildingProfile = _buildingProfile.copyWith(
                floors: updatedFloorConfigs,
              );
              _activeFloorNumber = newActiveFloor;
            });
          }
        } else if (_buildingProfile.floors.isEmpty) {
          await _loadActiveMallPackage(activeMallId);
        }

        // ==========================================
        // 3. SYNC DESTINATIONS / SHOPS / POIS
        // ==========================================
        final livePois = await ApiService.instance.fetchDestinations(
          mallId: activeMallId,
        );
        final deduped = _deduplicateDestinations(livePois);
        final bool hasPoiChanges =
            force ||
            deduped.length != _destinations.length ||
            deduped.any(
              (p) => !_destinations.any(
                (old) =>
                    old.id == p.id &&
                    old.name == p.name &&
                    old.floorNumber == p.floorNumber &&
                    (old.location.latitude - p.location.latitude).abs() <
                        0.000001 &&
                    (old.location.longitude - p.location.longitude).abs() <
                        0.000001 &&
                    old.category == p.category &&
                    old.rating == p.rating,
              ),
            ) ||
            _destinations.any((old) => !deduped.any((p) => p.id == old.id));

        if (hasPoiChanges && mounted) {
          setState(() {
            _destinations = deduped;
          });
        }

        // ==========================================
        // 4. SYNC PARKING SLOTS
        // ==========================================
        await ParkingService.instance.loadSlotsForMall(activeMallId);
      }
    } catch (e) {
      debugPrint('[Main] Auto-sync background check: $e');
    } finally {
      _isBackgroundSyncRunning = false;
    }
  }

  String? _lastAutoDetectedMallId;
  DateTime? _lastProximityCheckTime;

  /// Dynamically verifies whether user's current GPS position is within 500m of a mall.
  /// If within 500m, auto-loads the mall map. If above 500m, preserves active mall.
  Future<void> _checkAndAutoUpdateMallProximity() async {
    final now = DateTime.now();
    if (_lastProximityCheckTime != null &&
        now.difference(_lastProximityCheckTime!).inMilliseconds < 2500) {
      return;
    }
    _lastProximityCheckTime = now;

    // Do NOT automatically override/unload the active venue if in Admin mode or Admin Dashboard!
    if (_currentRole == UserRole.admin ||
        _authScreenState == AuthScreenState.adminDashboard) {
      return;
    }

    final hasGps = _userCoords.latitude != 0.0 && _userCoords.longitude != 0.0;
    if (!hasGps) return;

    final mallsWithin500m = await _mallDatabaseService.getMallsWithinRadius(
      _userCoords,
      radiusMeters: 500.0,
      activeOnly: false,
    );

    if (mallsWithin500m.isNotEmpty) {
      final currentMallId = _buildingProfile.buildingId.trim().toLowerCase();
      final isCurrentMallWithin500m = mallsWithin500m.any((m) {
        final mId = m.id.trim().toLowerCase();
        return mId == currentMallId ||
            mId.replaceAll(RegExp(r'^0+'), '') ==
                currentMallId.replaceAll(RegExp(r'^0+'), '');
      });

      // If the user's selected mall is already within 500m, keep user's selection
      if (!isCurrentMallWithin500m) {
        mallsWithin500m.sort((a, b) {
          final distA = _mallDatabaseService.calculateDistanceToMall(
            _userCoords,
            a,
          );
          final distB = _mallDatabaseService.calculateDistanceToMall(
            _userCoords,
            b,
          );
          return distA.compareTo(distB);
        });
        final nearestMall = mallsWithin500m.first;
        if (_lastAutoDetectedMallId != nearestMall.id) {
          _lastAutoDetectedMallId = nearestMall.id;
          await _mallDatabaseService.setActiveMall(
            nearestMall.id,
            isAdmin: false,
          );
          await _loadActiveMallPackage(nearestMall.id, isAdmin: false);
        }
      }
    } else {
      // User is outside 500m radius of ALL malls:
      // Keep the current active/selected mall loaded so remote browsing works!
      _lastAutoDetectedMallId = null;
    }
  }

  void _showPermissionOnboardingDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(LucideIcons.shieldAlert, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Text(
              'Location & AR Access',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'NexNav requires Location access to lock your real GPS position and Camera access for AR indoor navigation.',
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _sensorService.requestAllPermissions();
              final pos = await _sensorService.getCurrentPosition();
              if (pos != null) {
                _userCoords = pos;
                await _autoLoadNearestMallMap();
              }
            },
            child: const Text(
              'Allow Real Location',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _apiSyncSubscription?.cancel();
    _sensorService.stopHardwareStreams();
    _imuTimer?.cancel();
    super.dispose();
  }

  void _handleSimulateMove(double deltaLat, double deltaLon) {
    setState(() {
      _userCoords = GeodeticCoords(
        latitude: _userCoords.latitude + deltaLat,
        longitude: _userCoords.longitude + deltaLon,
        height: _userCoords.height,
      );
      _kalmanFilter.setPosition(_userCoords);
    });
  }

  void _handleSelectFloor(FloorLevelConfig floor) {
    _userSelectedFloorHeight = floor.absoluteHeightMeters;
    setState(() {
      _userCoords = GeodeticCoords(
        latitude: _userCoords.latitude,
        longitude: _userCoords.longitude,
        height: floor.absoluteHeightMeters,
      );
      _kalmanFilter.setPosition(_userCoords);
    });
  }

  void _triggerPnPScan() {
    _userSelectedFloorHeight = null;
    if (_entranceMarkers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No entrance reference markers found for this venue.'),
          backgroundColor: Color(0xFF64748B),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final marker = _entranceMarkers.first;
    final pnp = calibratePnP(marker, 240, 240);
    setState(() {
      _pnpResult = pnp;
      _userCoords = pnp.calibratedUserCoords;
      _kalmanFilter.setPosition(_userCoords);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('PnP Entrance Calibrated to ${marker.name}'),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleAddPoi(DestinationPOI newPoi) async {
    final key =
        '${newPoi.name.trim().toLowerCase()}#${newPoi.floorNumber}#${newPoi.mallId ?? ''}';
    setState(() {
      _destinations = [
        newPoi,
        ..._destinations.where(
          (p) =>
              p.id != newPoi.id &&
              '${p.name.trim().toLowerCase()}#${p.floorNumber}#${p.mallId ?? ''}' !=
                  key,
        ),
      ];
    });
    final targetMall = (newPoi.mallId != null && newPoi.mallId!.isNotEmpty)
        ? newPoi.mallId!
        : _buildingProfile.buildingId;
    if (targetMall.isNotEmpty) {
      await ApiService.instance.createDestination(newPoi, mallId: targetMall);
      await _loadActiveMallPackage(_buildingProfile.buildingId);
    }
  }

  void _handleUpdatePoi(DestinationPOI updatedPoi) async {
    setState(() {
      final index = _destinations.indexWhere((p) => p.id == updatedPoi.id);
      if (index != -1) {
        final newList = List<DestinationPOI>.from(_destinations);
        newList[index] = updatedPoi;
        _destinations = newList;
      }
    });
    await ApiService.instance.updateDestination(updatedPoi);
    if (_buildingProfile.buildingId.isNotEmpty) {
      await _loadActiveMallPackage(_buildingProfile.buildingId);
    }
  }

  void _handleDeletePoi(String poiId) async {
    setState(() {
      _destinations = _destinations.where((p) => p.id != poiId).toList();
    });
    await ApiService.instance.deleteDestination(poiId);
    if (_buildingProfile.buildingId.isNotEmpty) {
      await _loadActiveMallPackage(_buildingProfile.buildingId);
    }
  }

  void _handleFloorHeightsUpdated(List<FloorHeightData> heights) async {
    final targetMall = _buildingProfile.buildingId;
    if (targetMall.isEmpty) return;

    if (heights.isEmpty) {
      setState(() {
        _buildingProfile = BuildingElevationProfile(
          buildingId: _buildingProfile.buildingId,
          name: _buildingProfile.name,
          entranceBaseAnchorHeight: _buildingProfile.entranceBaseAnchorHeight,
          floorGapMeters: _buildingProfile.floorGapMeters,
          floors: const <FloorLevelConfig>[],
        );
      });
      await ApiService.instance.deleteAllFloors(targetMall);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cache_package_$targetMall');
      await prefs.remove('cache_floors_$targetMall');
      return;
    }

    final updatedFloors = heights.map((h) {
      String floorName = h.floorNo < 0
          ? 'Basement B${h.floorNo.abs()}'
          : (h.floorNo == 1 ? 'Ground Floor F1' : 'Upper Floor F${h.floorNo}');
      final String floorId = h.floorNo < 0
          ? 'B${h.floorNo.abs()}'
          : 'F${h.floorNo}';
      final int stores = _destinations
          .where((d) => d.floorNumber == h.floorNo)
          .length;
      return FloorLevelConfig(
        floorId: floorId,
        floorNumber: h.floorNo,
        name: floorName,
        relativeVectorMeters: h.heightToNextM,
        absoluteHeightMeters: h.baseAltitudeM,
        bandMinMeters: h.baseAltitudeM - 2.5,
        bandMaxMeters: h.baseAltitudeM + 2.5,
        storesCount: stores,
      );
    }).toList();

    updatedFloors.sort(
      (a, b) => a.absoluteHeightMeters.compareTo(b.absoluteHeightMeters),
    );

    setState(() {
      _buildingProfile = BuildingElevationProfile(
        buildingId: _buildingProfile.buildingId,
        name: _buildingProfile.name,
        entranceBaseAnchorHeight: _buildingProfile.entranceBaseAnchorHeight,
        floorGapMeters: _buildingProfile.floorGapMeters,
        floors: updatedFloors,
      );
    });
    for (final h in heights) {
      await ApiService.instance.updateFloorHeight(
        targetMall,
        h.floorNo,
        heightToNextM: h.heightToNextM,
        baseAltitudeM: h.baseAltitudeM,
        isLocked: h.isLocked,
      );
    }
  }

  void _showLogoutConfirmationDialog() {
    final isAdmin = _currentRole == UserRole.admin;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
        contentPadding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
        actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                LucideIcons.logOut,
                color: Color(0xFFEF4444),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isAdmin ? 'Admin Log Out' : 'Log Out',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          _userEmail.isNotEmpty
              ? 'Are you sure you want to log out as $_userEmail?'
              : (isAdmin
                    ? 'Are you sure you want to log out of the admin panel?'
                    : 'Are you sure you want to log out of NexNav?'),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: const Color(0xFF475569),
            height: 1.4,
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('NexNav_auto_login_enabled', false);
                    await ApiService.instance.logout();
                    final userMallId = prefs.getString(
                      'NexNav_user_active_mall_id',
                    );
                    if (userMallId != null && userMallId.isNotEmpty) {
                      await _loadActiveMallPackage(userMallId, isAdmin: false);
                    }
                    if (mounted) {
                      setState(() {
                        _currentRole = UserRole.guest;
                        _userEmail = '';
                        _requestedLoginRole = isAdmin
                            ? UserRole.admin
                            : UserRole.user;
                        _authScreenState = AuthScreenState.login;
                      });
                    }
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(
                              LucideIcons.checkCircle2,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isAdmin
                                    ? 'Admin session logged out successfully.'
                                    : 'Successfully logged out.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        backgroundColor: const Color(0xFF0F172A),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.logOut, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Log Out',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Welcome Screen State
    if (_authScreenState == AuthScreenState.welcome) {
      return WelcomeScreen(
        onLoginPressed: () {
          setState(() {
            _requestedLoginRole = UserRole.user;
            _authScreenState = AuthScreenState.login;
          });
        },
      );
    }

    // 2. Login Screen State
    if (_authScreenState == AuthScreenState.login) {
      return LoginScreen(
        initialRole: _requestedLoginRole,
        onBackToWelcome: () {
          setState(() {
            _authScreenState = AuthScreenState.welcome;
          });
        },
        onLoginSuccess: (role, email) async {
          final prefs = await SharedPreferences.getInstance();
          setState(() {
            _currentRole = role;
            _userEmail = email;
            if (role == UserRole.admin) {
              _authScreenState = AuthScreenState.adminDashboard;
            } else {
              _authScreenState = _isSetupComplete
                  ? AuthScreenState.mainNav
                  : AuthScreenState.setup;
            }
          });
          if (role == UserRole.admin) {
            final adminMallId = prefs.getString('NexNav_admin_active_mall_id');
            if (adminMallId != null && adminMallId.isNotEmpty) {
              await _loadActiveMallPackage(adminMallId, isAdmin: true);
            }
          } else {
            final userMallId = prefs.getString('NexNav_user_active_mall_id');
            if (userMallId != null && userMallId.isNotEmpty) {
              await _loadActiveMallPackage(userMallId, isAdmin: false);
            }
          }
        },
      );
    }

    // 3. Admin Dashboard Screen State
    if (_authScreenState == AuthScreenState.adminDashboard) {
      return AdminDashboardScreen(
        adminEmail: _userEmail.isNotEmpty ? _userEmail : 'admin@nexnav.com',
        userCoords: _userCoords,
        buildingProfile: _buildingProfile,
        destinations: _destinations,
        mallService: _mallDatabaseService,
        sensorService: _sensorService,
        onAddPoi: _handleAddPoi,
        onUpdatePoi: _handleUpdatePoi,
        onDeletePoi: _handleDeletePoi,
        onFloorHeightsUpdated: _handleFloorHeightsUpdated,
        onOpenNavigation: () {
          setState(() {
            _authScreenState = _isSetupComplete
                ? AuthScreenState.mainNav
                : AuthScreenState.setup;
          });
        },
        onLogout: _showLogoutConfirmationDialog,
        onSelectActiveMall: (mallId) async {
          await _loadActiveMallPackage(mallId, isAdmin: true);
        },
      );
    }

    // 4. Initial Venue & Sensor Setup Lock Screen
    if (!_isSetupComplete || _authScreenState == AuthScreenState.setup) {
      return LocationLockScreen(
        sensorService: _sensorService,
        mallService: _mallDatabaseService,
        onSetupCompleted: (coords, mall, [package]) {
          // Immediately populate building profile, floors, and POIs if package was loaded
          if (package != null && package.profile.buildingId.isNotEmpty) {
            double resolvedUserH = coords.height;
            if (resolvedUserH <= 0.0 || resolvedUserH > 4000.0) {
              resolvedUserH = package.profile.entranceBaseAnchorHeight > 0
                  ? package.profile.entranceBaseAnchorHeight
                  : GeocodingService.resolveTerrainAltitudeFromCoords(
                      coords.latitude,
                      coords.longitude,
                    );
            }
            final resolvedFloor = resolveFloorByHeight(
              resolvedUserH,
              package.profile,
            );
            _buildingProfile = package.profile;
            _destinations = _deduplicateDestinations(package.destinations);
            _entranceMarkers = package.entranceMarkers;
            _activeFloorNumber = resolvedFloor.floorNumber;
          }

          // Transition to Main Navigation page IMMEDIATELY (0 delay!)
          setState(() {
            _userCoords = coords;
            _kalmanFilter.setPosition(coords);
            _isSetupComplete = true;
            _authScreenState = AuthScreenState.mainNav;
          });

          // Run background persistence and slot syncing asynchronously
          unawaited(() async {
            try {
              final prefs = await SharedPreferences.getInstance();
              if (mall != null) {
                await prefs.setString('NexNav_user_active_mall_id', mall.id);
                await prefs.setString('NexNav_active_mall_id', mall.id);
                await _mallDatabaseService.setActiveMall(mall.id, isAdmin: false);
                await ParkingService.instance.loadSlotsForMall(mall.id);
              } else {
                await prefs.remove('NexNav_user_active_mall_id');
                await prefs.remove('NexNav_active_mall_id');
                await _loadActiveMallPackage('', isAdmin: false);
              }
            } catch (e) {
              debugPrint('[Main] Background setup persistence error: $e');
            }
          }());
        },
      );
    }

    // 5. Main Navigation Stack (Home, AR View, Floor Plan, Mall Explorer)
    final currentFloor = _buildingProfile.floors.firstWhere(
      (f) => f.floorNumber == _activeFloorNumber,
      orElse: () => resolveFloorByHeight(_userCoords.height, _buildingProfile),
    );

    final activeMall = _mallDatabaseService.catalog.where((m) {
      final mId = m.id.trim().toLowerCase();
      final bId = _buildingProfile.buildingId.trim().toLowerCase();
      return mId == bId ||
          mId.replaceAll(RegExp(r'^0+'), '') ==
              bId.replaceAll(RegExp(r'^0+'), '');
    }).firstOrNull;

    final screens = [
      HomeScreen(
        userCoords: _userCoords,
        buildingProfile: _buildingProfile,
        destinations: _destinations,
        activeMall: activeMall,
        onOpenARView: () => setState(() {
          _arTargetDestination = null;
          _currentIndex = 1;
        }),
        onOpenFloorMap: () {
          _floorPlanKey.currentState?.clearSelection();
          setState(() => _currentIndex = 2);
        },
        onOpenMallExplorer: () => setState(() => _currentIndex = 3),
        onSelectDestination: (poi) {
          setState(() {
            _arTargetDestination = poi;
            _currentIndex = 1;
          });
        },
        userEmail: _userEmail,
        onLogout: _showLogoutConfirmationDialog,
        isAdmin: _currentRole == UserRole.admin,
        onOpenAdminDashboard: () {
          setState(() {
            _authScreenState = AuthScreenState.adminDashboard;
          });
        },
        onSignIn: _currentRole == UserRole.guest
            ? () {
                setState(() {
                  _requestedLoginRole = UserRole.user;
                  _authScreenState = AuthScreenState.login;
                });
              }
            : null,
        onRefresh: () async {
          await _syncLatestDataFromServer(force: true);
          await _loadInitialBackendData();
        },
      ),
      ARViewportScreen(
        isActive: _currentIndex == 1,
        userCoords: _userCoords,
        currentFloor: currentFloor,
        destinations: _destinations,
        isCalibrated: _pnpResult != null,
        compassHeadingDegrees: _compassHeading,
        phonePitchDegrees: _phonePitchDegrees,
        tiltDirection: _tiltDirection,
        targetDestination: _arTargetDestination,
        onScanMarkerClick: _triggerPnPScan,
        onSelectDestination: (poi) => setState(() {
          _arTargetDestination = poi;
          _currentIndex = 1;
        }),
        onClearTargetDestination: () => setState(() {
          _arTargetDestination = null;
        }),
        onBackClicked: () {
          _floorPlanKey.currentState?.clearSelection();
          setState(() {
            _arTargetDestination = null;
            _currentIndex = 0;
          });
        },
        onOpenMapsClicked: () {
          _floorPlanKey.currentState?.clearSelection();
          setState(() => _currentIndex = 2);
        },
      ),
      FloorPlanScreen(
        key: _floorPlanKey,
        buildingProfile: _buildingProfile,
        currentFloor: currentFloor,
        onSelectFloor: _handleSelectFloor,
        userCoords: _userCoords,
        destinations: _destinations,
        targetDestination: _arTargetDestination,
        onClearTargetDestination: () => setState(() {
          _arTargetDestination = null;
        }),
        onSimulateMove: _handleSimulateMove,
        onSelectDestination: (poi) => setState(() {
          _arTargetDestination = poi;
          _currentIndex = 1;
        }),
        onBackClicked: () {
          _floorPlanKey.currentState?.clearSelection();
          setState(() => _currentIndex = 0);
        },
        userEmail: _userEmail,
        onLogout: _showLogoutConfirmationDialog,
        mallService: _mallDatabaseService,
        onOpenMallExplorer: () => setState(() => _currentIndex = 3),
        onRefreshLocation: _autoLoadNearestMallMap,
        isAdmin: _currentRole == UserRole.admin,
        onOpenAdminDashboard: () {
          setState(() {
            _authScreenState = AuthScreenState.adminDashboard;
          });
        },
      ),
      MallExplorerScreen(
        mallService: _mallDatabaseService,
        userCoords: _userCoords,
        destinations: _destinations,
        onSelectActiveMall: (mallId) async {
          await _loadActiveMallPackage(mallId, isAdmin: false);
          _floorPlanKey.currentState?.clearSelection();
          setState(() => _currentIndex = 2);
        },
        onSelectDestination: (poi) {
          setState(() {
            _arTargetDestination = poi;
            _currentIndex = 1;
          });
        },
        onBackClicked: () {
          _floorPlanKey.currentState?.clearSelection();
          setState(() => _currentIndex = 0);
        },
        userEmail: _userEmail,
        onLogout: _showLogoutConfirmationDialog,
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          _floorPlanKey.currentState?.clearSelection();
          setState(() {
            _arTargetDestination = null;
            _currentIndex = 0;
          });
        } else {
          final now = DateTime.now();
          if (_lastBackPressTime == null ||
              now.difference(_lastBackPressTime!) >
                  const Duration(seconds: 2)) {
            _lastBackPressTime = now;
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Press back again to exit NexNav',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                backgroundColor: const Color(0xFF0F172A),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
                margin: const EdgeInsets.only(bottom: 12, left: 24, right: 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 8,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(index: _currentIndex, children: screens),
        bottomNavigationBar: _buildFloatingPillNavBar(),
      ),
    );
  }

  Widget _buildFloatingPillNavBar() {
    final navItems = [
      {'label': 'Home', 'icon': LucideIcons.compass},
      {'label': 'Camera', 'icon': LucideIcons.camera},
      {'label': 'Map', 'icon': LucideIcons.mapPin},
      {'label': 'Malls', 'icon': LucideIcons.building2},
    ];

    return SafeArea(
      top: false,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(42),
            border: Border.all(color: const Color(0xFFE4E4E7), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 24,
                spreadRadius: 2,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(navItems.length, (idx) {
              final isSelected = _currentIndex == idx;
              final item = navItems[idx];
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (idx == 1 && _currentIndex != 1) {
                      _arTargetDestination = null;
                    }
                    if (_currentIndex == 2 || idx == 2) {
                      _floorPlanKey.currentState?.clearSelection();
                    }
                    _currentIndex = idx;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  padding: EdgeInsets.symmetric(
                    horizontal: isSelected ? 18 : 14,
                    vertical: isSelected ? 9 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF0F172A)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected)
                        Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            item['icon'] as IconData,
                            size: 17,
                            color: const Color(0xFF0F172A),
                          ),
                        )
                      else
                        Icon(
                          item['icon'] as IconData,
                          size: 23,
                          color: const Color(0xFF64748B),
                        ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Text(
                          item['label'] as String,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
