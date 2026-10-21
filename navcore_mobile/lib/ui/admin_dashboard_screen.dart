import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';

import '../engine/ecef_engine.dart';
import '../engine/floor_tracker.dart';
import '../engine/kalman_filter.dart';
import '../engine/real_sensor_service.dart';
import '../engine/ar_sensor_engine.dart';
import '../data/destinations.dart';
import '../data/mall_database_service.dart';
import '../data/geocoding_service.dart';

import '../data/parking_service.dart';

import 'building_config_screen.dart';
import 'telemetry_screen.dart';

import 'admin/admin_poi_manager_screen.dart';
import 'admin/admin_venue_manager_screen.dart';
import 'admin/admin_parking_manager_screen.dart';
import 'admin/admin_osm_map_screen.dart';
import 'admin/admin_floor_heights_screen.dart';
import '../data/mall_api_service.dart';
import '../data/floor_height_model.dart';
import '../data/api_service.dart';

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
  int _markerCount = 0;
  late List<DestinationPOI> _currentDestinations;
  late TabController _tabController;
  Timer? _telemetryTimer;

  // Live telemetry stream fields
  late double _liveLat;
  late double _liveLng;
  late double _liveHeight;
  double _liveAccuracy = 0.0;
  double _heading = 0.0;
  double _pitch = 0.0;
  PitchTiltDirection _tiltDir = PitchTiltDirection.level;
  double _rawPressure = 1013.25;
  double _smoothedPressure = 1013.25;
  final double _kalmanVariance = 0.0001;
  final BarometricElevationEngine _elevationEngine =
      BarometricElevationEngine();

  @override
  void initState() {
    super.initState();
    final seen = <String>{};
    final seenIds = <String>{};
    final deduped = <DestinationPOI>[];
    for (final p in widget.destinations) {
      final key =
          '${p.name.trim().toLowerCase()}#${p.floorNumber}#${p.mallId ?? ''}';
      if (!seen.contains(key) && !seenIds.contains(p.id)) {
        seen.add(key);
        seenIds.add(p.id);
        deduped.add(p);
      }
    }
    _currentDestinations = deduped;
    _tabController = TabController(length: 3, vsync: this);
    _liveLat = widget.userCoords.latitude;
    _liveLng = widget.userCoords.longitude;
    _liveHeight = _calculateResolvedHeight(
      rawGpsAltitude: widget.userCoords.height,
      latitude: _liveLat,
      longitude: _liveLng,
      currentPressureHpa: _smoothedPressure,
    );
    if (_liveLat == 0.0 && _liveLng == 0.0) {
      if (widget.sensorService?.lastCoords != null &&
          widget.sensorService!.lastCoords!.latitude != 0.0) {
        _liveLat = widget.sensorService!.lastCoords!.latitude;
        _liveLng = widget.sensorService!.lastCoords!.longitude;
        _liveHeight = _calculateResolvedHeight(
          rawGpsAltitude: widget.sensorService!.lastCoords!.height,
          latitude: _liveLat,
          longitude: _liveLng,
          currentPressureHpa: _smoothedPressure,
        );
      }
    }
    _markerCount = 0;

    // Connect to real hardware sensor stream if available
    if (widget.sensorService != null) {
      widget.sensorService!.startHardwareStreams(
        onLocationUpdated: (coords, accuracy) {
          if (!mounted) return;
          setState(() {
            _liveLat = coords.latitude;
            _liveLng = coords.longitude;
            _liveAccuracy = accuracy;
            _liveHeight = _calculateResolvedHeight(
              rawGpsAltitude: coords.height,
              latitude: coords.latitude,
              longitude: coords.longitude,
              currentPressureHpa: _smoothedPressure,
            );
          });
        },
        onHeadingUpdated: (heading) {
          _heading = heading;
        },
        onPitchUpdated: (pitch, dir) {
          _pitch = pitch;
          _tiltDir = dir;
        },
        onPressureUpdated: (rawPressure, smoothedPressure) {
          _rawPressure = rawPressure;
          _smoothedPressure = smoothedPressure;
          _liveHeight = _calculateResolvedHeight(
            rawGpsAltitude: _liveHeight,
            latitude: _liveLat,
            longitude: _liveLng,
            currentPressureHpa: smoothedPressure,
          );
        },
      );
    }

    _initLiveLocation();

    ParkingService.instance.addListener(_onParkingServiceChanged);

    // Load malls list to ensure catalog and active venue are refreshed
    widget.mallService.getMallsList(isAdmin: true).then((_) {
      _refreshActiveMallData();
      if (mounted) setState(() {});
    });

    // Refresh telemetry and metrics periodically without generating fake coordinates
    int syncTick = 0;
    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 1500), (
      timer,
    ) {
      if (!mounted) return;
      syncTick++;
      if (_liveLat == 0.0 && _liveLng == 0.0) {
        if (widget.sensorService?.lastCoords != null &&
            widget.sensorService!.lastCoords!.latitude != 0.0) {
          _liveLat = widget.sensorService!.lastCoords!.latitude;
          _liveLng = widget.sensorService!.lastCoords!.longitude;
          _liveHeight = _calculateResolvedHeight(
            rawGpsAltitude: widget.sensorService!.lastCoords!.height,
            latitude: _liveLat,
            longitude: _liveLng,
            currentPressureHpa: _smoothedPressure,
          );
          _liveAccuracy = widget.sensorService!.lastAccuracy;
        } else if (syncTick % 3 == 0) {
          _initLiveLocation();
        }
      } else {
        _liveHeight = _calculateResolvedHeight(
          rawGpsAltitude: _liveHeight,
          latitude: _liveLat,
          longitude: _liveLng,
          currentPressureHpa: _smoothedPressure,
        );
      }
      // Sync active mall parking stalls every 30s (20 ticks) instead of every 3s to avoid overloading backend
      if (syncTick % 20 == 0) {
        final active = _resolveActiveMall();
        if (active != null && active.id.isNotEmpty) {
          ParkingService.instance.syncSlotsSilently(active.id);
        }
      }
      setState(() {});
    });
  }

  double _calculateResolvedHeight({
    required double rawGpsAltitude,
    required double latitude,
    required double longitude,
    required double currentPressureHpa,
  }) {
    // 1. Resolve base anchor elevation from user's location or active venue
    double baseAnchor = 0.0;
    final activeMall = _resolveActiveMall();
    if (activeMall != null && activeMall.entranceBaseAnchorHeight > 0) {
      baseAnchor = activeMall.entranceBaseAnchorHeight;
    } else if (widget.buildingProfile.entranceBaseAnchorHeight > 0) {
      baseAnchor = widget.buildingProfile.entranceBaseAnchorHeight;
    } else if (latitude != 0.0 && longitude != 0.0) {
      baseAnchor = GeocodingService.resolveTerrainAltitudeFromCoords(
        latitude,
        longitude,
      );
    }
    if (baseAnchor <= 0.0) {
      baseAnchor = 8.5; // Sri Lanka / Trincomalee ground anchor
    }

    // 2. Calibrate baseline pressure if uncalibrated
    final effectivePressure = currentPressureHpa > 300.0
        ? currentPressureHpa
        : 1013.25;
    if (!_elevationEngine.isCalibrated ||
        _elevationEngine.baselineAnchorHeight == 0.0) {
      _elevationEngine.calibrateBaseline(effectivePressure, baseAnchor);
    }

    // 3. Compute dynamic altitude using barometer hypsometric model
    final baroHeight = _elevationEngine.calculateAbsoluteHeight(
      effectivePressure,
    );

    // 4. If raw GPS altitude is positive and within reasonable terrain limits (< 4000m)
    // with good accuracy (< 25m), fuse GPS and Barometer.
    // Otherwise (e.g. negative Indian Ocean geoid undulation like -84.6m), use the barometric location height!
    if (rawGpsAltitude > 0.0 && rawGpsAltitude < 4000.0) {
      if (_liveAccuracy > 0 && _liveAccuracy < 25.0) {
        return _elevationEngine.computeFusedLocationHeight(
          currentPressureHpa: effectivePressure,
          gpsAltitude: rawGpsAltitude,
          gpsAccuracy: _liveAccuracy,
        );
      }
      return rawGpsAltitude;
    }

    return baroHeight > 0.0 ? baroHeight : baseAnchor;
  }

  GeodeticCoords get _effectiveCoords {
    double lat = _liveLat;
    double lng = _liveLng;
    double alt = _liveHeight;

    if (lat == 0.0 && lng == 0.0) {
      if (widget.userCoords.latitude != 0.0 &&
          widget.userCoords.longitude != 0.0) {
        lat = widget.userCoords.latitude;
        lng = widget.userCoords.longitude;
        alt = widget.userCoords.height;
      } else if (widget.sensorService?.lastCoords != null &&
          widget.sensorService!.lastCoords!.latitude != 0.0) {
        lat = widget.sensorService!.lastCoords!.latitude;
        lng = widget.sensorService!.lastCoords!.longitude;
        alt = widget.sensorService!.lastCoords!.height;
      } else {
        final activeMall = _resolveActiveMall();
        if (activeMall != null &&
            activeMall.latitude != 0.0 &&
            activeMall.longitude != 0.0) {
          lat = activeMall.latitude;
          lng = activeMall.longitude;
          alt = activeMall.entranceBaseAnchorHeight > 0
              ? activeMall.entranceBaseAnchorHeight
              : 8.5;
        }
      }
    }

    // Automatically resolve height using phone barometer and user location if raw altitude is negative or uncalibrated
    if (alt <= 0.0 || alt > 4000.0) {
      alt = _calculateResolvedHeight(
        rawGpsAltitude: alt,
        latitude: lat,
        longitude: lng,
        currentPressureHpa: _smoothedPressure,
      );
    }

    return GeodeticCoords(latitude: lat, longitude: lng, height: alt);
  }

  Future<void> _initLiveLocation() async {
    try {
      if (widget.sensorService?.lastCoords != null &&
          widget.sensorService!.lastCoords!.latitude != 0.0) {
        if (mounted) {
          setState(() {
            _liveLat = widget.sensorService!.lastCoords!.latitude;
            _liveLng = widget.sensorService!.lastCoords!.longitude;
            _liveAccuracy = widget.sensorService!.lastAccuracy;
            _liveHeight = _calculateResolvedHeight(
              rawGpsAltitude: widget.sensorService!.lastCoords!.height,
              latitude: _liveLat,
              longitude: _liveLng,
              currentPressureHpa: _smoothedPressure,
            );
          });
        }
        return;
      }

      if (widget.sensorService != null) {
        final pos = await widget.sensorService!.getLastKnownOrCurrentPosition();
        if (pos != null && pos.latitude != 0.0 && mounted) {
          setState(() {
            _liveLat = pos.latitude;
            _liveLng = pos.longitude;
            _liveAccuracy = widget.sensorService!.lastAccuracy;
            _liveHeight = _calculateResolvedHeight(
              rawGpsAltitude: pos.height,
              latitude: pos.latitude,
              longitude: pos.longitude,
              currentPressureHpa: _smoothedPressure,
            );
          });
          return;
        }
      }

      final last = await Geolocator.getLastKnownPosition();
      if (last != null && last.latitude != 0.0 && mounted) {
        setState(() {
          _liveLat = last.latitude;
          _liveLng = last.longitude;
          _liveAccuracy = last.accuracy;
          _liveHeight = _calculateResolvedHeight(
            rawGpsAltitude: last.altitude,
            latitude: last.latitude,
            longitude: last.longitude,
            currentPressureHpa: _smoothedPressure,
          );
        });
        return;
      }

      final curr = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (curr.latitude != 0.0 && mounted) {
        setState(() {
          _liveLat = curr.latitude;
          _liveLng = curr.longitude;
          _liveAccuracy = curr.accuracy;
          _liveHeight = _calculateResolvedHeight(
            rawGpsAltitude: curr.altitude,
            latitude: curr.latitude,
            longitude: curr.longitude,
            currentPressureHpa: _smoothedPressure,
          );
        });
      }
    } catch (_) {}
  }

  void _onParkingServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    ParkingService.instance.removeListener(_onParkingServiceChanged);
    _telemetryTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AdminDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((_liveLat == 0.0 && _liveLng == 0.0) &&
        (widget.userCoords.latitude != 0.0 ||
            widget.userCoords.longitude != 0.0)) {
      _liveLat = widget.userCoords.latitude;
      _liveLng = widget.userCoords.longitude;
      _liveHeight = widget.userCoords.height;
    }
    if (widget.destinations != oldWidget.destinations ||
        widget.buildingProfile != oldWidget.buildingProfile) {
      _currentDestinations = _deduplicateDestinations(widget.destinations);
      _refreshActiveMallData();
    }
  }

  List<DestinationPOI> _deduplicateDestinations(List<DestinationPOI> list) {
    final seen = <String>{};
    final seenIds = <String>{};
    final deduped = <DestinationPOI>[];
    for (final p in list) {
      final key =
          '${p.name.trim().toLowerCase()}#${p.floorNumber}#${p.mallId ?? ''}';
      if (!seen.contains(key) && !seenIds.contains(p.id)) {
        seen.add(key);
        seenIds.add(p.id);
        deduped.add(p);
      }
    }
    return deduped;
  }

  Future<void> _refreshActiveMallData() async {
    final activeMall = _resolveActiveMall();
    if (activeMall != null && activeMall.id.isNotEmpty) {
      try {
        final liveDestinations = await ApiService.instance.fetchDestinations(
          mallId: activeMall.id,
        );
        final cleanActive = activeMall.id.trim().toLowerCase();
        final strippedActive = cleanActive.replaceAll(RegExp(r'^0+'), '');
        final filtered = liveDestinations.where((p) {
          if (p.mallId != null && p.mallId!.isNotEmpty) {
            final pClean = p.mallId!.trim().toLowerCase();
            final pStripped = pClean.replaceAll(RegExp(r'^0+'), '');
            return pClean == cleanActive ||
                (pStripped.isNotEmpty && pStripped == strippedActive);
          }
          return false;
        }).toList();
        if (mounted) {
          setState(() {
            _currentDestinations = _deduplicateDestinations(filtered);
          });
        }
      } catch (_) {}

      try {
        await ParkingService.instance.loadSlotsForMall(activeMall.id);
        if (mounted) setState(() {});
      } catch (_) {}
    } else {
      if (mounted) {
        setState(() {
          _currentDestinations = [];
        });
      }
      try {
        await ParkingService.instance.loadSlotsForMall('');
        if (mounted) setState(() {});
      } catch (_) {}
    }
  }

  MallMetadata? _resolveActiveMall() {
    if (widget.mallService.catalog.isNotEmpty) {
      // 1. Check if buildingProfile.buildingId matches any mall in catalog (flexible match)
      final profileId = widget.buildingProfile.buildingId.trim().toLowerCase();
      final strippedProfileId = profileId.replaceAll(RegExp(r'^0+'), '');
      if (profileId.isNotEmpty) {
        final match = widget.mallService.catalog.where((m) {
          final mId = m.id.trim().toLowerCase();
          final mStripped = mId.replaceAll(RegExp(r'^0+'), '');
          return mId == profileId ||
              (strippedProfileId.isNotEmpty && mStripped == strippedProfileId);
        }).firstOrNull;
        if (match != null) return match;
      }

      // 2. Check for explicitly active or selected mall in catalog
      final active = widget.mallService.catalog
          .where((m) => m.isActive || m.isSelected)
          .firstOrNull;
      if (active != null) return active;

      // 3. Check if buildingProfile.name matches any mall in catalog
      final profileName = widget.buildingProfile.name.trim().toLowerCase();
      if (profileName.isNotEmpty) {
        final match = widget.mallService.catalog
            .where((m) => m.name.trim().toLowerCase() == profileName)
            .firstOrNull;
        if (match != null) return match;
      }

      // 4. Fallback to first mall in catalog
      final first = widget.mallService.catalog.firstOrNull;
      if (first != null) return first;
    }

    // 5. Fallback: if buildingProfile has name configured, synthesize active metadata
    if (widget.buildingProfile.name.isNotEmpty) {
      return MallMetadata(
        id: widget.buildingProfile.buildingId,
        name: widget.buildingProfile.name,
        city: '',
        country: '',
        latitude: 0.0,
        longitude: 0.0,
        floorCount: widget.buildingProfile.floors.length,
        packageSizeBytesMB: 0.0,
        category: 'Active Venue',
        rating: '5.0',
        isActive: true,
        isSelected: true,
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final activeMall = _resolveActiveMall();
    final bool hasActiveVenue = activeMall != null;
    final String displayBuildingName = hasActiveVenue
        ? activeMall.name
        : 'No Venue Added';
    final int floorsCount = hasActiveVenue
        ? (activeMall.floorCount > 0
              ? activeMall.floorCount
              : (widget.buildingProfile.buildingId.trim().toLowerCase() ==
                        activeMall.id.trim().toLowerCase()
                    ? widget.buildingProfile.floors.length
                    : 0))
        : 0;

    return Scaffold(
      backgroundColor: const Color(
        0xFF070B1E,
      ), // Deep midnight blue matching top header
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Executive Midnight Header (Inspired by high-end modern design)
            _buildExecutiveHeader(
              displayBuildingName: displayBuildingName,
              hasActiveVenue: hasActiveVenue,
              floorsCount: floorsCount,
            ),

            // Curved Clean White Workspace Sheet
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                  child: Column(
                    children: [
                      // Modern Capsule Tab Navigation Bar
                      _buildModernCapsuleTabBar(),

                      // Tab Views
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
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomActionBar(),
    );
  }

  Widget _buildExecutiveHeader({
    required String displayBuildingName,
    required bool hasActiveVenue,
    required int floorsCount,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF070B1E), Color(0xFF0F1A3A), Color(0xFF132048)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Profile and Quick Actions Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NexNav Admin Panel',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF94A3B8),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.adminEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              // Logout Button
              Tooltip(
                message: 'Log Out of Admin Session',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onLogout,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0x26EF4444),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x4DEF4444)),
                      ),
                      child: const Icon(
                        LucideIcons.logOut,
                        size: 16,
                        color: Color(0xFFFCA5A5),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 2. Active Venue Hero Showcase
          Text(
            'ACTIVE VENUE & LOCATION',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF94A3B8),
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  displayBuildingName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x26FFFFFF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: Text(
                  hasActiveVenue
                      ? (floorsCount > 0 ? '$floorsCount Floors' : 'No Floors')
                      : 'No Venue',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 3. Quick Action Header Pills (inspired by + Deposit, Transfer)
          Row(
            children: [
              Expanded(
                child: _buildHeaderPillButton(
                  label: 'Venues',
                  isPrimary: true,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminVenueManagerScreen(
                          mallService: widget.mallService,
                          onSelectActiveMall: (newMallId) async {
                            await widget.onSelectActiveMall(newMallId);
                            await widget.mallService.getMallsList(
                              isAdmin: true,
                            );
                            await _refreshActiveMallData();
                            if (mounted) setState(() {});
                          },
                          userCoords: _effectiveCoords,
                        ),
                      ),
                    );
                    await widget.mallService.getMallsList(isAdmin: true);
                    await _refreshActiveMallData();
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildHeaderPillButton(
                  label: 'Live Map',
                  isPrimary: false,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminOSMMapScreen(
                          userCoords: _effectiveCoords,
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
                    await _refreshActiveMallData();
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildHeaderPillButton(
                  label: 'Sensors',
                  isPrimary: false,
                  onTap: () {
                    _tabController.animateTo(2);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderPillButton({
    required String label,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isPrimary
                ? const Color(0xFF2563EB)
                : const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPrimary
                  ? const Color(0xFF3B82F6)
                  : const Color(0x33FFFFFF),
            ),
            boxShadow: isPrimary
                ? const [
                    BoxShadow(
                      color: Color(0x332563EB),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernCapsuleTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        controller: _tabController,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F0F172A),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: const Color(0xFF0F172A),
        unselectedLabelColor: const Color(0xFF64748B),
        dividerColor: Colors.transparent,
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
            height: 36,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.layoutDashboard, size: 14),
                  SizedBox(width: 5),
                  Text('Dashboard'),
                ],
              ),
            ),
          ),
          Tab(
            height: 36,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.sliders, size: 14),
                  SizedBox(width: 5),
                  Text('Features'),
                ],
              ),
            ),
          ),
          Tab(
            height: 36,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.radio, size: 14),
                  SizedBox(width: 5),
                  Text('Sensors'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 10,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: widget.onOpenNavigation,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF090E23),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              shadowColor: const Color(0x26090E23),
              padding: EdgeInsets.zero,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0x2638BDF8),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    LucideIcons.navigation,
                    size: 15,
                    color: Color(0xFF38BDF8),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'START AR NAVIGATION',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.6,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // TAB 1: CONTROL HUB DASHBOARD
  Widget _buildControlHubTab() {
    final allSlots = ParkingService.instance.allFloorSlots.values
        .expand((s) => s)
        .toList();
    final totalParking = allSlots.length;
    final occupiedParking = allSlots
        .where((s) => s.status == ParkingSlotStatus.occupied)
        .length;
    final parkingVal = totalParking > 0
        ? '$occupiedParking / $totalParking'
        : '0 / 0';
    final parkingBadge = totalParking > 0
        ? '${(occupiedParking / totalParking * 100).toInt()}% Filled'
        : 'No Slots Added';

    final activeMall = _resolveActiveMall();
    final bool hasActiveVenue = activeMall != null;

    final int floorsCount = hasActiveVenue
        ? (activeMall.floorCount > 0
              ? activeMall.floorCount
              : (widget.buildingProfile.buildingId.trim().toLowerCase() ==
                        activeMall.id.trim().toLowerCase()
                    ? widget.buildingProfile.floors.length
                    : 0))
        : 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Section Header (inspired by "My Cards" with "+ Add")
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'OVERVIEW METRICS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF64748B),
                  letterSpacing: 0.8,
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
                hasActiveVenue ? '$floorsCount Floors Added' : 'No Venue',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Gradient Cards: Stores & Parking (inspired by Visa Cards in reference image)
        Row(
          children: [
            Expanded(
              child: _buildGradientMetricCard(
                title: 'STORES & SHOPS',
                value: hasActiveVenue
                    ? '${_currentDestinations.length} Stores'
                    : '0 Stores',
                badgeText: hasActiveVenue ? 'Active Directory' : 'No Venue',
                gradientColors: const [
                  Color(0xFF2563EB),
                  Color(0xFF1D4ED8),
                  Color(0xFF0284C7),
                ],
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AdminPOIManagerScreen(
                        destinations: _currentDestinations,
                        mallService: widget.mallService,
                        userCoords: _effectiveCoords,
                        initialMallId: _resolveActiveMall()?.id,
                        onAddPoi: (newPoi) {
                          final key =
                              '${newPoi.name.trim().toLowerCase()}#${newPoi.floorNumber}#${newPoi.mallId ?? ''}';
                          setState(() {
                            _currentDestinations.removeWhere(
                              (p) =>
                                  p.id == newPoi.id ||
                                  '${p.name.trim().toLowerCase()}#${p.floorNumber}#${p.mallId ?? ''}' ==
                                      key,
                            );
                            _currentDestinations.insert(0, newPoi);
                          });
                          widget.onAddPoi?.call(newPoi);
                        },
                        onUpdatePoi: (updatedPoi) {
                          setState(() {
                            final idx = _currentDestinations.indexWhere(
                              (p) => p.id == updatedPoi.id,
                            );
                            if (idx != -1) {
                              _currentDestinations[idx] = updatedPoi;
                            }
                          });
                          widget.onUpdatePoi?.call(updatedPoi);
                        },
                        onDeletePoi: (poiId) {
                          setState(() {
                            _currentDestinations.removeWhere(
                              (p) => p.id == poiId,
                            );
                          });
                          widget.onDeletePoi?.call(poiId);
                        },
                      ),
                    ),
                  );
                  await _refreshActiveMallData();
                  if (mounted) setState(() {});
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGradientMetricCard(
                title: 'PARKING SLOTS',
                value: parkingVal,
                badgeText: parkingBadge,
                gradientColors: const [
                  Color(0xFF0F172A),
                  Color(0xFF1E293B),
                  Color(0xFF334155),
                ],
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AdminParkingManagerScreen(
                        activeMall: _resolveActiveMall(),
                        mallService: widget.mallService,
                        userCoords: GeodeticCoords(
                          latitude: _liveLat,
                          longitude: _liveLng,
                          height: _liveHeight,
                        ),
                      ),
                    ),
                  );
                  await _refreshActiveMallData();
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Dedicated Live GPS Geodetic Card (inspired by Upcoming Payment card)
        _buildGpsGeodeticCard(),

        const SizedBox(height: 20),

        // Quick Workstation Action Buttons Grid
        Text(
          'WORKSTATION ACTIONS',
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
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AdminFloorHeightsScreen(
                  mallId:
                      _resolveActiveMall()?.id ??
                      widget.buildingProfile.buildingId,
                  apiService: RestMallBackendApi(),
                  sensorService: widget.sensorService,
                  onHeightsUpdated: (heights) {
                    widget.onFloorHeightsUpdated?.call(heights);
                  },
                  onMallSelected: (newMallId) {
                    widget.onSelectActiveMall(newMallId);
                  },
                ),
              ),
            );
            await _refreshActiveMallData();
            if (mounted) setState(() {});
          },
        ),

        const SizedBox(height: 10),

        _buildQuickActionCard(
          title: 'OpenStreetMap (OSM) Live Explorer',
          badge: 'Live Map & Pins',
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AdminOSMMapScreen(
                  userCoords: _effectiveCoords,
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
            await _refreshActiveMallData();
            if (mounted) setState(() {});
          },
        ),

        const SizedBox(height: 10),

        _buildQuickActionCard(
          title: 'Manage Stores & Shops',
          badge: '${_currentDestinations.length} Shops',
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AdminPOIManagerScreen(
                  destinations: _currentDestinations,
                  mallService: widget.mallService,
                  userCoords: _effectiveCoords,
                  initialMallId: _resolveActiveMall()?.id,
                  onAddPoi: (newPoi) {
                    final key =
                        '${newPoi.name.trim().toLowerCase()}#${newPoi.floorNumber}#${newPoi.mallId ?? ''}';
                    setState(() {
                      _currentDestinations.removeWhere(
                        (p) =>
                            p.id == newPoi.id ||
                            '${p.name.trim().toLowerCase()}#${p.floorNumber}#${p.mallId ?? ''}' ==
                                key,
                      );
                      _currentDestinations.insert(0, newPoi);
                    });
                    widget.onAddPoi?.call(newPoi);
                  },
                  onUpdatePoi: (updatedPoi) {
                    setState(() {
                      final idx = _currentDestinations.indexWhere(
                        (p) => p.id == updatedPoi.id,
                      );
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
            await _refreshActiveMallData();
            if (mounted) setState(() {});
          },
        ),

        const SizedBox(height: 10),

        _buildQuickActionCard(
          title: 'Manage Parking & Spots',
          badge: totalParking > 0
              ? '$totalParking Bays Active'
              : '0 Bays Configured',
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AdminParkingManagerScreen(
                  activeMall: _resolveActiveMall(),
                  mallService: widget.mallService,
                  userCoords: GeodeticCoords(
                    latitude: _liveLat,
                    longitude: _liveLng,
                    height: _liveHeight,
                  ),
                ),
              ),
            );
            await _refreshActiveMallData();
            if (mounted) setState(() {});
          },
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  // TAB 2: SYSTEM MODULES LIST
  Widget _buildModulesTab() {
    final activeMall = _resolveActiveMall();
    final bool hasActiveVenue = activeMall != null;

    final int floorsCount = hasActiveVenue
        ? (activeMall.floorCount > 0
              ? activeMall.floorCount
              : (widget.buildingProfile.buildingId.trim().toLowerCase() ==
                        activeMall.id.trim().toLowerCase()
                    ? widget.buildingProfile.floors.length
                    : 0))
        : 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildModuleDetailCard(
          title: 'Building Floor & Height Setup',
          subtitle: 'Set floor height levels for accurate indoor navigation',
          statusText: hasActiveVenue
              ? '$floorsCount Floors Set'
              : '0 Floors Set',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BuildingConfigScreen(
                  profile: widget.buildingProfile,
                  userCoords: GeodeticCoords(
                    latitude: _liveLat,
                    longitude: _liveLng,
                    height: _liveHeight,
                  ),
                  onProfileUpdated: (updatedProfile) {
                    final heights = updatedProfile.floors.map((f) {
                      return FloorHeightData(
                        mallId: updatedProfile.buildingId,
                        floorNo: f.floorNumber,
                        heightToNextM: f.relativeVectorMeters,
                        baseAltitudeM: f.absoluteHeightMeters,
                        source: 'admin',
                        confidence: 1.0,
                        isLocked: true,
                        updatedAt: DateTime.now().toIso8601String(),
                      );
                    }).toList();
                    widget.onFloorHeightsUpdated?.call(heights);
                  },
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildModuleDetailCard(
          title: 'Phone Motion & GPS Sensors',
          subtitle:
              'View live GPS position, compass direction, and phone sensors',
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
              Text(
                'HARDWARE SENSOR STREAM',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              _buildTelemetryConsoleLine(
                'GPS.LATITUDE',
                '${_liveLat.toStringAsFixed(6)}°',
              ),
              _buildTelemetryConsoleLine(
                'GPS.LONGITUDE',
                '${_liveLng.toStringAsFixed(6)}°',
              ),
              _buildTelemetryConsoleLine(
                'GPS.HEIGHT_WGS84',
                '${_effectiveCoords.height.toStringAsFixed(2)} m',
              ),
              _buildTelemetryConsoleLine(
                'GPS.ACCURACY_FIX',
                _liveAccuracy > 0
                    ? '±${_liveAccuracy.toStringAsFixed(1)} m'
                    : 'Standby',
              ),
              _buildTelemetryConsoleLine(
                'MAGNETOMETER.HEADING',
                _heading > 0
                    ? '${_heading.toStringAsFixed(1)}° (${_getCardinalDir(_heading)})'
                    : 'Standby',
              ),
              _buildTelemetryConsoleLine(
                'ACCELEROMETER.PITCH',
                '${_pitch.toStringAsFixed(1)}° (${_tiltDir.name.toUpperCase()})',
              ),
              _buildTelemetryConsoleLine(
                'BAROMETER.RAW_PRESSURE',
                '${_rawPressure.toStringAsFixed(2)} hPa',
              ),
              _buildTelemetryConsoleLine(
                'BAROMETER.SMOOTHED',
                '${_smoothedPressure.toStringAsFixed(2)} hPa',
              ),
              _buildTelemetryConsoleLine(
                'KALMAN.VARIANCE',
                _kalmanVariance.toStringAsExponential(3),
              ),
              _buildTelemetryConsoleLine(
                'ACTIVE.MARKERS',
                '$_markerCount Registered',
              ),
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

  // Modern Gradient Metric Card (inspired by premium mobile cards in reference image)
  Widget _buildGradientMetricCard({
    required String title,
    required String value,
    required String badgeText,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use
              color: gradientColors.first.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                // ignore: deprecated_member_use
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                badgeText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  // ignore: deprecated_member_use
                  color: Colors.white.withOpacity(0.95),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                // ignore: deprecated_member_use
                color: Colors.white.withOpacity(0.7),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Dedicated Live GPS Geodetic Card (styled after Upcoming Payment card in reference)
  Widget _buildGpsGeodeticCard() {
    final coords = _effectiveCoords;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'LIVE GPS FIX',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${coords.latitude.toStringAsFixed(5)}°, ${coords.longitude.toStringAsFixed(5)}°',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Action Button (Pay Now style pill button in reference image)
          InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AdminOSMMapScreen(
                    userCoords: coords,
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
              await _refreshActiveMallData();
              if (mounted) setState(() {});
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x332563EB),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Live Map',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    LucideIcons.arrowUpRight,
                    color: Colors.white,
                    size: 13,
                  ),
                ],
              ),
            ),
          ),
        ],
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
              color: Color(0x060F172A),
              blurRadius: 8,
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
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          badge,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(
                LucideIcons.chevronRight,
                size: 15,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // System Module Detail Card
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x060F172A),
              blurRadius: 8,
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
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
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
                borderRadius: BorderRadius.circular(8),
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
            const SizedBox(width: 6),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(
                LucideIcons.chevronRight,
                size: 14,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
