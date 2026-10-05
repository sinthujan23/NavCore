import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import 'engine/ecef_engine.dart';
import 'engine/floor_tracker.dart';
import 'engine/kalman_filter.dart';
import 'engine/pnp_engine.dart';
import 'engine/real_sensor_service.dart';
import 'engine/ar_sensor_engine.dart';
import 'data/destinations.dart';
import 'data/mall_database_service.dart';

import 'ui/welcome_screen.dart';
import 'ui/login_screen.dart';
import 'ui/admin_dashboard_screen.dart';
import 'ui/location_lock_screen.dart';

import 'ui/home_screen.dart';
import 'ui/ar_viewport_screen.dart';
import 'ui/floor_plan_screen.dart';
import 'ui/mall_explorer_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  GeodeticCoords _userCoords = entranceAnchor;
  double _compassHeading = 0.0;
  double _phonePitchDegrees = 0.0;
  PitchTiltDirection _tiltDirection = PitchTiltDirection.level;
  PnPResult? _pnpResult;
  DestinationPOI? _arTargetDestination;

  BuildingElevationProfile _buildingProfile = defaultBuildingProfile;
  List<DestinationPOI> _destinations = mockDestinations;
  List<EntranceMarkerNode> _entranceMarkers = [
    const EntranceMarkerNode(
      markerId: 'mrk-ent-01',
      buildingId: 'mall-one-galle-face',
      name: 'Main Entrance Pillar #01',
      latitude: 6.927079,
      longitude: 79.845612,
      baseHeight: 45.0,
      physicalWidthMeters: 0.20,
      physicalHeightMeters: 0.20,
    ),
  ];

  late final KalmanPositionFilter _kalmanFilter;
  Timer? _imuTimer;
  final GlobalKey<FloorPlanScreenState> _floorPlanKey =
      GlobalKey<FloorPlanScreenState>();

  @override
  void initState() {
    super.initState();
    _kalmanFilter = KalmanPositionFilter(entranceAnchor);
    _initializeRealHardware();
  }

  Future<void> _initializeRealHardware() async {
    // 1. Request OS Permissions for Location & Camera
    final report = await _sensorService.requestAllPermissions();

    // 2. Fetch current real GPS position
    final realPos = await _sensorService.getCurrentPosition();
    if (realPos != null) {
      setState(() {
        _userCoords = realPos;
        _kalmanFilter.setPosition(_userCoords);
      });
    }

    // 3. Start real hardware sensors (GPS + Magnetometer Compass + Barometer)
    _sensorService.startHardwareStreams(
      onLocationUpdated: (coords, accuracy) {
        setState(() {
          _userCoords = GeodeticCoords(
            latitude: coords.latitude,
            longitude: coords.longitude,
            height: _userSelectedFloorHeight ?? coords.height,
          );
          _kalmanFilter.setPosition(_userCoords);
        });
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
          _elevationEngine.calibrateBaseline(
            smoothedPressure,
            _buildingProfile.entranceBaseAnchorHeight,
          );
          if (kDebugMode) {
            print(
              '[BAROMETER] Entrance Baseline Calibrated: ${smoothedPressure.toStringAsFixed(2)} hPa @ ${_buildingProfile.entranceBaseAnchorHeight}m',
            );
          }
        }

        double calculatedHeight = _elevationEngine.calculateAbsoluteHeight(
          smoothedPressure,
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
              height: calculatedHeight,
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

  Future<void> _loadActiveMallPackage(String mallId) async {
    final pkg = await _mallDatabaseService.loadMallPackage(
      mallId,
      userCoords: _userCoords,
    );
    if (mounted) {
      setState(() {
        _buildingProfile = pkg.profile;
        _destinations = pkg.destinations;
        _entranceMarkers = pkg.entranceMarkers;
      });
    }
  }

  Future<void> _autoLoadNearestMallMap() async {
    final pkg = await _mallDatabaseService.autoDownloadAndActivateNearestMall(
      _userCoords,
    );
    if (mounted) {
      setState(() {
        _buildingProfile = pkg.profile;
        _destinations = pkg.destinations;
        _entranceMarkers = pkg.entranceMarkers;
      });
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
    final marker = _entranceMarkers.isNotEmpty
        ? _entranceMarkers.first
        : const EntranceMarkerNode(
            markerId: 'mrk-ent-01',
            buildingId: 'mall-one-galle-face',
            name: 'Main Entrance Pillar #01',
            latitude: 6.927079,
            longitude: 79.845612,
            baseHeight: 45.0,
            physicalWidthMeters: 0.20,
            physicalHeightMeters: 0.20,
          );
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
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _currentRole = UserRole.guest;
                _userEmail = '';
                _requestedLoginRole = UserRole.user;
                _authScreenState = AuthScreenState.login;
              });
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
        onGuestPressed: () {
          setState(() {
            _currentRole = UserRole.guest;
            _authScreenState = _isSetupComplete
                ? AuthScreenState.mainNav
                : AuthScreenState.setup;
          });
        },
        onAdminPortalPressed: () {
          setState(() {
            _requestedLoginRole = UserRole.admin;
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
        onOpenNavigation: () {
          setState(() {
            _authScreenState = _isSetupComplete
                ? AuthScreenState.mainNav
                : AuthScreenState.setup;
          });
        },
        onLogout: () {
          setState(() {
            _currentRole = UserRole.guest;
            _userEmail = '';
            _requestedLoginRole = UserRole.admin;
            _authScreenState = AuthScreenState.login;
          });
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
          await _loadActiveMallPackage(mall.id);
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
    final currentFloor = resolveFloorByHeight(
      _userCoords.height,
      _buildingProfile,
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
      ),
      ARViewportScreen(
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
