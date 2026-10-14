import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import 'engine/ecef_engine.dart';
import 'engine/bearing_engine.dart';
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
  final GlobalKey<FloorPlanScreenState> _floorPlanKey =
      GlobalKey<FloorPlanScreenState>();

  @override
  void initState() {
    super.initState();
    _kalmanFilter = KalmanPositionFilter(_userCoords);
    _initializeRealHardware();
    _loadInitialBackendData();
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

        setState(() {
          _userCoords = GeodeticCoords(
            latitude: coords.latitude,
            longitude: coords.longitude,
            height: targetHeight,
          );
          _kalmanFilter.setPosition(_userCoords);
          if (resolvedFloor.floorNumber != _activeFloorNumber) {
            _activeFloorNumber = resolvedFloor.floorNumber;
          }
        });
        _checkAndAutoUpdateMallProximity();
      },
      onHeadingUpdated: (heading) {
        setState(() {
          _compassHeading = heading;
        });
      },
      onPitchUpdated: (pitch, dir) {
        setState(() {
          _phonePitchDegrees = pitch;
          _tiltDirection = dir;
        });
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

  Future<void> _loadActiveMallPackage(String mallId) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanId = mallId.trim();
    if (cleanId.isEmpty) {
      await prefs.remove('NexNav_active_mall_id');
      await _mallDatabaseService.clearActiveMall();
      if (mounted) {
        setState(() {
          _buildingProfile = const BuildingElevationProfile(
            buildingId: '',
            name: '',
            entranceBaseAnchorHeight: 0.0,
            floorGapMeters: 0.0,
            floors: [],
          );
          _destinations = const [];
          _entranceMarkers = const [];
        });
      }
      return;
    }

    // Proximity Limit: If not admin and user GPS is valid, verify mall is within 500m
    if (_currentRole != UserRole.admin &&
        _userCoords.latitude != 0.0 &&
        _userCoords.longitude != 0.0) {
      final mall = _mallDatabaseService.catalog
          .where((m) => m.id == cleanId)
          .firstOrNull;
      if (mall != null) {
        final dist = _mallDatabaseService.calculateDistanceToMall(
          _userCoords,
          mall,
        );
        if (dist > 500.0) {
          debugPrint(
            '[Main] Proximity limit: mall $cleanId is ${dist.toInt()}m away (>500m). Unloading map.',
          );
          await prefs.remove('NexNav_active_mall_id');
          await _mallDatabaseService.clearActiveMall();
          if (mounted) {
            setState(() {
              _buildingProfile = const BuildingElevationProfile(
                buildingId: '',
                name: '',
                entranceBaseAnchorHeight: 0.0,
                floorGapMeters: 0.0,
                floors: [],
              );
              _destinations = const [];
              _entranceMarkers = const [];
            });
          }
          return;
        }
      }
    }

    await prefs.setString('NexNav_active_mall_id', cleanId);
    await _mallDatabaseService.setActiveMall(cleanId);

    final pkg = await _mallDatabaseService.loadMallPackage(
      cleanId,
      userCoords: _userCoords,
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
        final savedActiveId = prefs.getString('NexNav_active_mall_id');
        // If an active venue was already selected, only restore unconditionally for Admin
        if (_currentRole == UserRole.admin &&
            savedActiveId != null &&
            savedActiveId.isNotEmpty) {
          await _loadActiveMallPackage(savedActiveId);
          return;
        }

        final hasGps =
            _userCoords.latitude != 0.0 && _userCoords.longitude != 0.0;
        if (hasGps) {
          // Check for malls strictly within 500m of user's current GPS location
          final mallsWithin500m = malls.where((m) {
            final dist = haversineDistance(
              _userCoords,
              GeodeticCoords(
                latitude: m.latitude,
                longitude: m.longitude,
                height: _userCoords.height,
              ),
            );
            return dist <= 500.0;
          }).toList();

          if (mallsWithin500m.isNotEmpty) {
            final matchingSaved = savedActiveId != null
                ? mallsWithin500m
                      .where((m) => m.id == savedActiveId)
                      .firstOrNull
                : null;
            final activeMall =
                matchingSaved ??
                () {
                  mallsWithin500m.sort((a, b) {
                    final distA = haversineDistance(
                      _userCoords,
                      GeodeticCoords(
                        latitude: a.latitude,
                        longitude: a.longitude,
                        height: _userCoords.height,
                      ),
                    );
                    final distB = haversineDistance(
                      _userCoords,
                      GeodeticCoords(
                        latitude: b.latitude,
                        longitude: b.longitude,
                        height: _userCoords.height,
                      ),
                    );
                    return distA.compareTo(distB);
                  });
                  return mallsWithin500m.first;
                }();

            await prefs.setString('NexNav_active_mall_id', activeMall.id);
            await _loadActiveMallPackage(activeMall.id);

            if (_destinations.isEmpty) {
              final liveDestinations = await ApiService.instance
                  .fetchDestinations(mallId: activeMall.id);
              final fallbackDestinations = liveDestinations.isNotEmpty
                  ? liveDestinations
                  : await ApiService.instance.fetchDestinations();
              final filteredForMall = fallbackDestinations.where((p) {
                if (p.mallId != null && p.mallId!.isNotEmpty) {
                  return p.mallId == activeMall.id;
                }
                return true;
              }).toList();
              if (mounted && filteredForMall.isNotEmpty) {
                setState(() {
                  _destinations = _deduplicateDestinations(filteredForMall);
                });
              }
            }
          } else {
            // Above 500m: malls above 500m are NOT loaded in maps!
            await prefs.remove('NexNav_active_mall_id');
            await _loadActiveMallPackage('');
          }
        } else {
          // No GPS fixed yet: malls are NOT loaded until GPS is within 500m
          await prefs.remove('NexNav_active_mall_id');
          await _loadActiveMallPackage('');
        }
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
            _destinations = const [];
            _entranceMarkers = const [];
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
    );
    if (mounted) {
      setState(() {
        _buildingProfile = pkg.profile;
        _destinations = _deduplicateDestinations(pkg.destinations);
        _entranceMarkers = pkg.entranceMarkers;
      });
    }
  }

  String? _lastAutoDetectedMallId;
  DateTime? _lastProximityCheckTime;

  /// Dynamically verifies whether user's current GPS position is within 500m of a mall.
  /// If within 500m, auto-loads the mall map. If above 500m, unloads the mall map.
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
    );

    if (mallsWithin500m.isNotEmpty) {
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
        await _mallDatabaseService.setActiveMall(nearestMall.id);
        await _loadActiveMallPackage(nearestMall.id);
      }
    } else {
      // User is outside 500m radius of ALL malls:
      // Malls above 500m are strictly NOT loaded in maps anywhere in the system!
      _lastAutoDetectedMallId = null;
      if (_buildingProfile.buildingId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('NexNav_active_mall_id');
        await _loadActiveMallPackage('');
      }
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
            Text(
              'Log Out',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        content: Text(
          _userEmail.isNotEmpty
              ? 'Are you sure you want to log out as $_userEmail?'
              : 'Are you sure you want to log out of NexNav?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
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
              if (mounted) {
                setState(() {
                  _currentRole = UserRole.guest;
                  _userEmail = '';
                  _requestedLoginRole = UserRole.user;
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
                      Text(
                        'Successfully logged out.',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
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
            child: Text(
              'Log Out',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
            ),
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
        onLoginSuccess: (role, email) {
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
        onLogout: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('NexNav_auto_login_enabled', false);
          await ApiService.instance.logout();
          if (mounted) {
            setState(() {
              _currentRole = UserRole.guest;
              _userEmail = '';
              _requestedLoginRole = UserRole.admin;
              _authScreenState = AuthScreenState.login;
            });
          }
        },
        onSelectActiveMall: (mallId) async {
          await _loadActiveMallPackage(mallId);
        },
      );
    }

    // 4. Initial Venue & Sensor Setup Lock Screen
    if (!_isSetupComplete || _authScreenState == AuthScreenState.setup) {
      return LocationLockScreen(
        sensorService: _sensorService,
        mallService: _mallDatabaseService,
        onSetupCompleted: (coords, mall) async {
          if (mall != null) {
            await _loadActiveMallPackage(mall.id);
          } else {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('NexNav_active_mall_id');
            await _loadActiveMallPackage('');
          }
          setState(() {
            _userCoords = coords;
            _kalmanFilter.setPosition(coords);
            _isSetupComplete = true;
            _authScreenState = AuthScreenState.mainNav;
          });
        },
      );
    }

    // 5. Main Navigation Stack (Home, AR View, Floor Plan, Mall Explorer)
    final currentFloor = _buildingProfile.floors.firstWhere(
      (f) => f.floorNumber == _activeFloorNumber,
      orElse: () => resolveFloorByHeight(_userCoords.height, _buildingProfile),
    );

    final screens = [
      HomeScreen(
        userCoords: _userCoords,
        buildingProfile: _buildingProfile,
        destinations: _destinations,
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
        onRefresh: _loadInitialBackendData,
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
      ),
      MallExplorerScreen(
        mallService: _mallDatabaseService,
        userCoords: _userCoords,
        onSelectActiveMall: (mallId) async {
          await _loadActiveMallPackage(mallId);
          _floorPlanKey.currentState?.clearSelection();
          setState(() => _currentIndex = 2);
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
        body: Stack(
          children: [
            IndexedStack(index: _currentIndex, children: screens),

            // Top Header Bar Overlay for Role Badge & Quick Switch
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_currentRole == UserRole.admin)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _authScreenState = AuthScreenState.adminDashboard;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  LucideIcons.shieldCheck,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'ADMIN PORTAL',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (_currentRole == UserRole.guest)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _requestedLoginRole = UserRole.user;
                              _authScreenState = AuthScreenState.login;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  LucideIcons.logIn,
                                  size: 13,
                                  color: Color(0xFF2563EB),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Sign In',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
