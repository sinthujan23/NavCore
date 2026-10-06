import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../engine/ecef_engine.dart';
import '../engine/floor_tracker.dart';
import '../engine/kalman_filter.dart';
import '../engine/real_sensor_service.dart';
import '../engine/ar_sensor_engine.dart';
import '../data/building_data_service.dart';
import '../data/destinations.dart';
import '../data/mall_database_service.dart';

import 'admin_marker_config_modal.dart';
import 'building_config_screen.dart';
import 'telemetry_screen.dart';

import 'admin/admin_poi_manager_screen.dart';
import 'admin/admin_venue_manager_screen.dart';
import 'admin/admin_parking_manager_screen.dart';
import 'admin/admin_osm_map_screen.dart';
import 'admin/admin_floor_heights_screen.dart';
import '../data/mall_api_service.dart';
import '../data/floor_height_model.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String adminEmail;
  final GeodeticCoords userCoords;
  final BuildingElevationProfile buildingProfile;
  final List<DestinationPOI> destinations;
  final MallDatabaseService mallService;
  final VoidCallback onOpenNavigation;
  final VoidCallback onLogout;
  final Function(String mallId) onSelectActiveMall;
  final RealSensorService? sensorService;
  final Function(DestinationPOI newPoi)? onAddPoi;
  final Function(DestinationPOI updatedPoi)? onUpdatePoi;
  final Function(String poiId)? onDeletePoi;
  final Function(List<FloorHeightData> heights)? onFloorHeightsUpdated;

  const AdminDashboardScreen({
    super.key,
    required this.adminEmail,
    required this.userCoords,
    required this.buildingProfile,
    required this.destinations,
    required this.mallService,
    required this.onOpenNavigation,
    required this.onLogout,
    required this.onSelectActiveMall,
    this.sensorService,
    this.onAddPoi,
    this.onUpdatePoi,
    this.onDeletePoi,
    this.onFloorHeightsUpdated,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  int _markerCount = 12;
  late List<DestinationPOI> _currentDestinations;
  late TabController _tabController;
  Timer? _telemetryTimer;

  // Live telemetry stream fields
  late double _liveLat;
  late double _liveLng;
  late double _liveHeight;
  double _liveAccuracy = 3.5;
  double _heading = 42.0;
  double _pitch = 0.0;
  PitchTiltDirection _tiltDir = PitchTiltDirection.level;
  double _rawPressure = 1013.25;
  double _smoothedPressure = 1013.25;
  double _kalmanVariance = 0.00012;
  int _satCount = 18;
  bool _isRealHardwareActive = false;

  @override
  void initState() {
    super.initState();
    _currentDestinations = List.from(widget.destinations);
    _tabController = TabController(length: 3, vsync: this);
    _liveLat = widget.userCoords.latitude;
    _liveLng = widget.userCoords.longitude;
    _liveHeight = widget.userCoords.height;

    // Connect to real hardware sensor stream if available
    if (widget.sensorService != null) {
      _isRealHardwareActive = true;
      widget.sensorService!.startHardwareStreams(
        onLocationUpdated: (coords, accuracy) {
          if (!mounted) return;
          setState(() {
            _liveLat = coords.latitude;
            _liveLng = coords.longitude;
            _liveHeight = coords.height;
            _liveAccuracy = accuracy;
            _satCount = (accuracy <= 5.0) ? 18 : 12;
          });
        },
        onHeadingUpdated: (heading) {
          if (!mounted) return;
          setState(() {
            _heading = heading;
          });
        },
        onPitchUpdated: (pitch, dir) {
          if (!mounted) return;
          setState(() {
            _pitch = pitch;
            _tiltDir = dir;
          });
        },
        onPressureUpdated: (rawPressure, smoothedPressure) {
          if (!mounted) return;
          setState(() {
            _rawPressure = rawPressure;
            _smoothedPressure = smoothedPressure;
          });
        },
      );
    }

    // Timer for latency & kalman variance updates
    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (!mounted) return;
      final rng = math.Random();
      setState(() {
        if (!_isRealHardwareActive) {
          _liveLat = widget.userCoords.latitude + (rng.nextDouble() - 0.5) * 0.00002;
          _liveLng = widget.userCoords.longitude + (rng.nextDouble() - 0.5) * 0.00002;
          _heading = (350 + rng.nextDouble() * 20) % 360;
        }
        _kalmanVariance = 0.00010 + rng.nextDouble() * 0.00004;
      });
    });
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _openMarkerConfigModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AdminMarkerConfigModal(
        initialCoords: GeodeticCoords(
          latitude: _liveLat,
          longitude: _liveLng,
          height: _liveHeight,
        ),
        onSaveMarker: (ReferenceMarker marker) {
          setState(() {
            _markerCount++;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(LucideIcons.checkCircle2, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text('AR Marker ${marker.markerId} registered!'),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Crisp Light Slate Background
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'NexNav Admin Panel',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.adminEmail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Logout',
              icon: const Icon(LucideIcons.logOut, color: Color(0xFFEF4444), size: 16),
              onPressed: widget.onLogout,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Control Center Live Header Card
          _buildLiveTelemetryBanner(),

          // Workstation Tab Navigation Bar
          Container(
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: TabBar(
              controller: _tabController,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              indicatorColor: const Color(0xFF2563EB),
              indicatorSize: TabBarIndicatorSize.label,
              indicatorWeight: 2.5,
              labelColor: const Color(0xFF2563EB),
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
              unselectedLabelStyle: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.layoutDashboard, size: 13),
                      SizedBox(width: 4),
                      Text('DASHBOARD'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.sliders, size: 13),
                      SizedBox(width: 4),
                      Text('FEATURES'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.radio, size: 13),
                      SizedBox(width: 4),
                      Text('LIVE SENSORS'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildControlHubTab(),
                _buildModulesTab(),
                _buildTelemetryStreamTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onOpenNavigation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 4,
                    shadowColor: const Color(0x1A0F172A),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.navigation, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'START AR NAVIGATION',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.5,
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
    );
  }

  // Header Card with Live Status Indicators
  Widget _buildLiveTelemetryBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LIVE SYSTEM STATUS',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          // Sensor Telemetry Strip
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLiveValueItem(
                  label: 'GPS LOCATION',
                  value: '${_liveLat.toStringAsFixed(5)}°, ${_liveLng.toStringAsFixed(5)}°',
                  accentColor: const Color(0xFF2563EB),
                ),
                Container(width: 1, height: 28, color: const Color(0xFFE2E8F0)),
                _buildLiveValueItem(
                  label: 'DIRECTION',
                  value: '${_heading.toStringAsFixed(0)}° ${_getCardinalDir(_heading)}',
                  accentColor: const Color(0xFF7C3AED),
                ),
                Container(width: 1, height: 28, color: const Color(0xFFE2E8F0)),
                _buildLiveValueItem(
                  label: 'GPS SIGNAL',
                  value: '$_satCount Sats',
                  accentColor: const Color(0xFF059669),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveValueItem({
    required String label,
    required String value,
    required Color accentColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF64748B),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  // TAB 1: CONTROL HUB DASHBOARD
  Widget _buildControlHubTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Executive Stat Widgets (2x2 Grid)
        Row(
          children: [
            Expanded(
              child: _buildModernMetricCard(
                title: 'Active Building',
                value: widget.buildingProfile.name.split(' ').first,
                badgeText: '${widget.buildingProfile.floors.length} Floors Added',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AdminVenueManagerScreen(
                        mallService: widget.mallService,
                        onSelectActiveMall: widget.onSelectActiveMall,
                        userCoords: GeodeticCoords(
                          latitude: _liveLat,
                          longitude: _liveLng,
                          height: _liveHeight,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildModernMetricCard(
                title: 'AR Markers',
                value: '$_markerCount Active',
                badgeText: 'QR & Position Pins',
                onTap: _openMarkerConfigModal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildModernMetricCard(
                title: 'Stores & Shops',
                value: '${_currentDestinations.length} Stores',
                badgeText: 'Active Shops',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AdminPOIManagerScreen(
                        destinations: _currentDestinations,
                        userCoords: GeodeticCoords(
                          latitude: _liveLat,
                          longitude: _liveLng,
                          height: _liveHeight,
                        ),
                        onAddPoi: (newPoi) {
                          setState(() {
                            _currentDestinations.insert(0, newPoi);
                          });
                          widget.onAddPoi?.call(newPoi);
                        },
                        onUpdatePoi: (updatedPoi) {
                          setState(() {
                            final idx = _currentDestinations.indexWhere(
                                (p) => p.id == updatedPoi.id);
                            if (idx != -1) _currentDestinations[idx] = updatedPoi;
                          });
                          widget.onUpdatePoi?.call(updatedPoi);
                        },
                        onDeletePoi: (poiId) {
                          setState(() {
                            _currentDestinations.removeWhere((p) => p.id == poiId);
                          });
                          widget.onDeletePoi?.call(poiId);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildModernMetricCard(
                title: 'Parking Slots',
                value: '182 / 350',
                badgeText: '52% Filled',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdminParkingManagerScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Quick Workstation Action Buttons Grid
        Text(
          'QUICK ACTIONS',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF94A3B8),
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),

        _buildQuickActionCard(
          title: 'Height Between Floors Calculator',
          badge: 'Barometer & Lock Config',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AdminFloorHeightsScreen(
                  mallId: widget.buildingProfile.buildingId,
                  apiService: RestMallBackendApi(),
                  onHeightsUpdated: (heights) {
                    widget.onFloorHeightsUpdated?.call(heights);
                  },
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 10),

        _buildQuickActionCard(
          title: 'OpenStreetMap (OSM) Live Explorer',
          badge: 'Live Map & Pins',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AdminOSMMapScreen(
                  userCoords: GeodeticCoords(
                    latitude: _liveLat,
                    longitude: _liveLng,
                    height: _liveHeight,
                  ),
                  destinations: _currentDestinations,
                  mallService: widget.mallService,
                  onImportOsmPoi: (importedPoi) {
                    setState(() {
                      _currentDestinations.insert(0, importedPoi);
                    });
                    widget.onAddPoi?.call(importedPoi);
                  },
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 10),

        _buildQuickActionCard(
          title: 'Manage Stores & Shops',
          badge: '${_currentDestinations.length} Shops',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AdminPOIManagerScreen(
                  destinations: _currentDestinations,
                  userCoords: GeodeticCoords(
                    latitude: _liveLat,
                    longitude: _liveLng,
                    height: _liveHeight,
                  ),
                  onAddPoi: (newPoi) {
                    setState(() {
                      _currentDestinations.insert(0, newPoi);
                    });
                    widget.onAddPoi?.call(newPoi);
                  },
                  onUpdatePoi: (updatedPoi) {
                    setState(() {
                      final idx = _currentDestinations.indexWhere(
                          (p) => p.id == updatedPoi.id);
                      if (idx != -1) _currentDestinations[idx] = updatedPoi;
                    });
                    widget.onUpdatePoi?.call(updatedPoi);
                  },
                  onDeletePoi: (poiId) {
                    setState(() {
                      _currentDestinations.removeWhere((p) => p.id == poiId);
                    });
                    widget.onDeletePoi?.call(poiId);
                  },
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 10),

        _buildQuickActionCard(
          title: 'Manage Buildings & Malls',
          badge: 'Current Mall',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AdminVenueManagerScreen(
                  mallService: widget.mallService,
                  onSelectActiveMall: widget.onSelectActiveMall,
                  userCoords: GeodeticCoords(
                    latitude: _liveLat,
                    longitude: _liveLng,
                    height: _liveHeight,
                  ),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 10),

        _buildQuickActionCard(
          title: 'Manage Parking & Spots',
          badge: 'Basement B1-B3',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AdminParkingManagerScreen(),
              ),
            );
          },
        ),

        const SizedBox(height: 10),

        _buildQuickActionCard(
          title: 'Manage AR Scan Markers',
          badge: '$_markerCount QR Markers',
          onTap: _openMarkerConfigModal,
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  // TAB 2: SYSTEM MODULES LIST
  Widget _buildModulesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildModuleDetailCard(
          title: 'Building Floor & Height Setup',
          subtitle: 'Set floor height levels for accurate indoor navigation',
          statusText: '${widget.buildingProfile.floors.length} Floors Set',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BuildingConfigScreen(
                  profile: widget.buildingProfile,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildModuleDetailCard(
          title: 'Phone Motion & GPS Sensors',
          subtitle: 'View live GPS position, compass direction, and phone sensors',
          statusText: 'Active',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TelemetryScreen(
                  userCoords: GeodeticCoords(
                    latitude: _liveLat,
                    longitude: _liveLng,
                    height: _liveHeight,
                  ),
                  kalmanState: KalmanState(
                    latitude: _liveLat,
                    longitude: _liveLng,
                    height: _liveHeight,
                    varianceLat: _kalmanVariance,
                    varianceLon: _kalmanVariance,
                    varianceHeight: _kalmanVariance * 10,
                  ),
                  pnpResult: null,
                  gpsAccuracyMeters: _liveAccuracy,
                  compassHeadingDegrees: _heading,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildModuleDetailCard(
          title: 'AR Camera Calibration',
          subtitle: 'Calibrate AR navigation camera using QR code markers',
          statusText: 'Ready',
          onTap: _openMarkerConfigModal,
        ),
      ],
    );
  }

  String _getCardinalDir(double deg) {
    if (deg >= 337.5 || deg < 22.5) return 'N';
    if (deg >= 22.5 && deg < 67.5) return 'NE';
    if (deg >= 67.5 && deg < 112.5) return 'E';
    if (deg >= 112.5 && deg < 157.5) return 'SE';
    if (deg >= 157.5 && deg < 202.5) return 'S';
    if (deg >= 202.5 && deg < 247.5) return 'SW';
    if (deg >= 247.5 && deg < 292.5) return 'W';
    return 'NW';
  }

  // TAB 3: REAL-TIME TELEMETRY STREAM
  Widget _buildTelemetryStreamTab() {
    final ecef = geodeticToECEF(GeodeticCoords(
      latitude: _liveLat,
      longitude: _liveLng,
      height: _liveHeight,
    ));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Live Hardware Stream Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0F172A),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'HARDWARE SENSOR STREAM',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      _isRealHardwareActive ? '100 Hz ACTIVE' : 'SENSORS ACTIVE',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTelemetryConsoleLine('GPS.LATITUDE', '${_liveLat.toStringAsFixed(6)}°'),
              _buildTelemetryConsoleLine('GPS.LONGITUDE', '${_liveLng.toStringAsFixed(6)}°'),
              _buildTelemetryConsoleLine('GPS.HEIGHT_WGS84', '${_liveHeight.toStringAsFixed(2)} m'),
              _buildTelemetryConsoleLine('GPS.ACCURACY_FIX', '±${_liveAccuracy.toStringAsFixed(1)} m'),
              _buildTelemetryConsoleLine('MAGNETOMETER.HEADING', '${_heading.toStringAsFixed(1)}° (${_getCardinalDir(_heading)})'),
              _buildTelemetryConsoleLine('ACCELEROMETER.PITCH', '${_pitch.toStringAsFixed(1)}° (${_tiltDir.name.toUpperCase()})'),
              _buildTelemetryConsoleLine('BAROMETER.RAW_PRESSURE', '${_rawPressure.toStringAsFixed(2)} hPa'),
              _buildTelemetryConsoleLine('BAROMETER.SMOOTHED', '${_smoothedPressure.toStringAsFixed(2)} hPa'),
              _buildTelemetryConsoleLine('KALMAN.VARIANCE', _kalmanVariance.toStringAsExponential(3)),
              _buildTelemetryConsoleLine('ACTIVE.MARKERS', '$_markerCount Registered'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ECEF Coordinate Vectors Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0F172A),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ECEF EARTH-FIXED GEODETIC VECTORS',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 14),
              _buildTelemetryConsoleLine('X_ECEF (m)', ecef.x.toStringAsFixed(2)),
              _buildTelemetryConsoleLine('Y_ECEF (m)', ecef.y.toStringAsFixed(2)),
              _buildTelemetryConsoleLine('Z_ECEF (m)', ecef.z.toStringAsFixed(2)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetryConsoleLine(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            key,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: const Color(0xFF64748B),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  // Modern Enterprise Stat Card Widget
  Widget _buildModernMetricCard({
    required String title,
    required String value,
    required String badgeText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x080F172A),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
                const Icon(
                  LucideIcons.arrowUpRight,
                  size: 16,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                badgeText,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Workstation Quick Action Card
  Widget _buildQuickActionCard({
    required String title,
    String? subtitle,
    required String badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x080F172A),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          badge,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        height: 1.3,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleDetailCard({
    required String title,
    required String subtitle,
    required String statusText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x080F172A),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      height: 1.3,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                statusText,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
