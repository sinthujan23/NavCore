import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';

import '../../engine/ecef_engine.dart';
import '../../engine/bearing_engine.dart';
import '../../engine/osm_place_discovery_service.dart';
import '../../data/destinations.dart';
import '../../data/mall_database_service.dart';

/// Admin & User OpenStreetMap (OSM) Live Explorer Screen
class AdminOSMMapScreen extends StatefulWidget {
  final GeodeticCoords userCoords;
  final List<DestinationPOI> destinations;
  final MallDatabaseService? mallService;
  final List<MallMetadata>? malls;
  final bool isPickerMode;
  final bool isUserMode;
  final String? title;
  final ValueChanged<GeodeticCoords>? onSelectCoordinates;
  final ValueChanged<DestinationPOI>? onImportOsmPoi;
  final ValueChanged<String>? onSelectActiveMall;
  final ValueChanged<DestinationPOI>? onSelectDestination;

  const AdminOSMMapScreen({
    super.key,
    required this.userCoords,
    required this.destinations,
    this.mallService,
    this.malls,
    this.isPickerMode = false,
    this.isUserMode = false,
    this.title,
    this.onSelectCoordinates,
    this.onImportOsmPoi,
    this.onSelectActiveMall,
    this.onSelectDestination,
  });

  @override
  State<AdminOSMMapScreen> createState() => _AdminOSMMapScreenState();
}

class _AdminOSMMapScreenState extends State<AdminOSMMapScreen> {
  late final MapController _mapController;
  LatLng? _currentCenter;
  LatLng? _selectedPickerPoint;

  List<DestinationPOI> _osmDiscoveredPOIs = [];
  bool _isLoadingOSM = false;
  final double _discoveryRadiusMeters = 500.0;
  int _selectedFloorFilter = 0; // 0 = All Floors
  String _selectedCategory = 'ALL';
  String _selectedMallFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    final bool hasValidUserCoords =
        widget.userCoords.latitude != 0.0 && widget.userCoords.longitude != 0.0;
    if (hasValidUserCoords) {
      _currentCenter = LatLng(
        widget.userCoords.latitude,
        widget.userCoords.longitude,
      );
      _fetchLiveOSMVenues();
    }

    _fetchLiveGPSAndCenter();
  }

  Future<void> _fetchLiveGPSAndCenter() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted && _currentCenter == null) {
          setState(() {
            _currentCenter = const LatLng(0.0, 0.0);
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted && _currentCenter == null) {
            setState(() {
              _currentCenter = const LatLng(0.0, 0.0);
            });
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted && _currentCenter == null) {
          setState(() {
            _currentCenter = const LatLng(0.0, 0.0);
          });
        }
        return;
      }

      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        final wasNull = _currentCenter == null;
        setState(() {
          _currentCenter = LatLng(last.latitude, last.longitude);
        });
        if (!wasNull) {
          _mapController.move(_currentCenter!, 16.5);
        }
        _fetchLiveOSMVenues();
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      if (mounted) {
        final wasNull = _currentCenter == null;
        setState(() {
          _currentCenter = LatLng(pos.latitude, pos.longitude);
        });
        if (!wasNull) {
          _mapController.move(_currentCenter!, 16.5);
        }
        _fetchLiveOSMVenues();
      }
    } catch (e) {
      debugPrint('Live GPS fetch error in OSM explorer: $e');
      if (mounted && _currentCenter == null) {
        setState(() {
          _currentCenter = const LatLng(0.0, 0.0);
        });
      }
    }
  }

  Future<void> _fetchLiveOSMVenues() async {
    if (_currentCenter == null) return;
    setState(() {
      _isLoadingOSM = true;
    });

    try {
      final userGeodetic = GeodeticCoords(
        latitude: _currentCenter!.latitude,
        longitude: _currentCenter!.longitude,
        height: widget.userCoords.height,
      );

      final places = await OSMPlaceDiscoveryService.instance
          .fetchRealOSMPlacesAroundUser(
            userCoords: userGeodetic,
            radiusMeters: _discoveryRadiusMeters,
          );

      if (mounted) {
        setState(() {
          _osmDiscoveredPOIs = places;
          _isLoadingOSM = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingOSM = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OSM Fetch Warning: $e'),
            backgroundColor: const Color(0xFFE11D48),
          ),
        );
      }
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (widget.isPickerMode) {
      setState(() {
        _selectedPickerPoint = point;
      });
    }
  }

  Color _getCategoryColor(String category) {
    final c = category.toUpperCase();
    if (c.contains('FOOD')) return const Color(0xFFF59E0B); // Amber
    if (c.contains('RETAIL') || c.contains('FASHION')) {
      return const Color(0xFF8B5CF6); // Purple
    }
    if (c.contains('TECH') || c.contains('ELECTRONIC')) {
      return const Color(0xFF3B82F6); // Blue
    }
    if (c.contains('PARKING')) return const Color(0xFF64748B); // Slate
    if (c.contains('SERVICES')) return const Color(0xFF10B981); // Emerald
    return const Color(0xFF6366F1); // Indigo default
  }

  IconData _getCategoryIcon(String category) {
    final c = category.toUpperCase();
    if (c.contains('FOOD')) return LucideIcons.utensils;
    if (c.contains('RETAIL') || c.contains('FASHION')) {
      return LucideIcons.shoppingBag;
    }
    if (c.contains('TECH') || c.contains('ELECTRONIC')) {
      return LucideIcons.smartphone;
    }
    if (c.contains('PARKING')) return LucideIcons.car;
    if (c.contains('SERVICES')) return LucideIcons.info;
    return LucideIcons.mapPin;
  }

  List<MallMetadata> get _mallsWithin500m {
    final center = _currentCenter;
    final allMalls = widget.malls ?? widget.mallService?.catalog ?? [];
    if (center == null || (center.latitude == 0.0 && center.longitude == 0.0)) {
      return allMalls;
    }

    final userGeo = GeodeticCoords(
      latitude: center.latitude,
      longitude: center.longitude,
      height: widget.userCoords.height,
    );

    return allMalls.where((mall) {
      final mallGeo = GeodeticCoords(
        latitude: mall.latitude,
        longitude: mall.longitude,
        height: mall.entranceBaseAnchorHeight,
      );
      final dist = haversineDistance(userGeo, mallGeo);
      return dist <= 500.0;
    }).toList();
  }

  List<DestinationPOI> get _effectiveDisplayPOIs {
    // In 'All Malls' overview mode, indicate only all malls within 500m on the map.
    // Shops are only displayed once a specific mall is chosen.
    if (_selectedMallFilter == 'ALL') {
      return const <DestinationPOI>[];
    }

    final selectedMall = _mallsWithin500m.where((m) {
      final mId = m.id.trim().toLowerCase().replaceAll(RegExp(r'^0+'), '');
      final sId = _selectedMallFilter.trim().toLowerCase().replaceAll(RegExp(r'^0+'), '');
      return mId == sId || m.name.trim().toLowerCase() == _selectedMallFilter.trim().toLowerCase();
    }).firstOrNull;

    final selIds = <String>{
      _selectedMallFilter.trim().toLowerCase(),
      _selectedMallFilter.trim().toLowerCase().replaceAll(RegExp(r'^0+'), ''),
      _selectedMallFilter.trim().toLowerCase().replaceFirst(RegExp(r'^mall-'), ''),
      if (selectedMall != null) ...[
        selectedMall.id.trim().toLowerCase(),
        selectedMall.id.trim().toLowerCase().replaceAll(RegExp(r'^0+'), ''),
        selectedMall.name.trim().toLowerCase(),
      ],
    };

    final combined = <DestinationPOI>[
      ...widget.destinations,
      ..._osmDiscoveredPOIs,
    ];
    final uniqueMap = <String, DestinationPOI>{};
    for (final p in combined) {
      uniqueMap[p.id] = p;
    }

    final center = _currentCenter;
    final userGeo = center != null && center.latitude != 0.0
        ? GeodeticCoords(
            latitude: center.latitude,
            longitude: center.longitude,
            height: widget.userCoords.height,
          )
        : null;

    return uniqueMap.values.where((poi) {
      // 0. Filter by selected mall: POI must belong to the chosen mall
      final poiMall = poi.mallId?.trim().toLowerCase();
      final poiMallClean = poiMall?.replaceAll(RegExp(r'^0+'), '');
      bool matchesMall = poiMall != null &&
          (selIds.contains(poiMall) || (poiMallClean != null && selIds.contains(poiMallClean)));

      // If POI has no mallId, check if it is within 60 meters of the selected mall
      if (!matchesMall && selectedMall != null && (poiMall == null || poiMall.isEmpty)) {
        final mallGeo = GeodeticCoords(
          latitude: selectedMall.latitude,
          longitude: selectedMall.longitude,
          height: selectedMall.entranceBaseAnchorHeight,
        );
        final dist = haversineDistance(mallGeo, poi.location);
        if (dist <= 60.0) {
          matchesMall = true;
        }
      }

      if (!matchesMall) return false;

      // 1. Physical distance check to user location (within 500m)
      if (userGeo != null) {
        final dist = haversineDistance(userGeo, poi.location);
        if (dist > 500.0) {
          return false;
        }
      }

      final matchesFloor =
          _selectedFloorFilter == 0 || poi.floorNumber == _selectedFloorFilter;
      final matchesCategory =
          _selectedCategory == 'ALL' ||
          poi.category.toUpperCase().contains(_selectedCategory);
      return matchesFloor && matchesCategory;
    }).toList();
  }

  List<Marker> _buildMallMarkers() {
    final List<Marker> markers = [];
    final center = _currentCenter;
    final userGeo = center != null && center.latitude != 0.0
        ? GeodeticCoords(
            latitude: center.latitude,
            longitude: center.longitude,
            height: widget.userCoords.height,
          )
        : null;

    for (final mall in _mallsWithin500m) {
      final mallLatLng = LatLng(mall.latitude, mall.longitude);
      final distM = userGeo != null
          ? haversineDistance(
              userGeo,
              GeodeticCoords(
                latitude: mall.latitude,
                longitude: mall.longitude,
                height: mall.entranceBaseAnchorHeight,
              ),
            )
          : 0.0;

      final bool isActive = mall.isActive ||
          mall.isSelected ||
          widget.mallService?.activeMallId == mall.id ||
          _selectedMallFilter == mall.id;

      markers.add(
        Marker(
          point: mallLatLng,
          width: 165,
          height: 60,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedMallFilter = mall.id;
                _selectedFloorFilter = 0;
              });
              if (widget.onSelectActiveMall != null) {
                widget.onSelectActiveMall!(mall.id);
              }
              _mapController.move(mallLatLng, 17.5);
              _showMallDetailsBottomSheet(mall, distM);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isActive
                          ? [
                              const Color(0xFF2563EB),
                              const Color(0xFF1D4ED8),
                            ]
                          : [
                              const Color(0xFF1E293B),
                              const Color(0xFF0F172A),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive
                          ? const Color(0xFF60A5FA)
                          : const Color(0xFF38BDF8),
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.building2,
                          size: 13,
                          color: isActive
                              ? Colors.white
                              : const Color(0xFF38BDF8),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              mall.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 0.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${mall.floorCount > 0 ? mall.floorCount : 1} Floors',
                                    style: const TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${distM.toInt()}m',
                                  style: const TextStyle(
                                    fontSize: 8.5,
                                    color: Color(0xFFCBD5E1),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  LucideIcons.chevronDown,
                  size: 10,
                  color: Color(0xFF0F172A),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return markers;
  }

  LatLng _getDispersedCoords(LatLng center, int index, int totalInCluster) {
    if (totalInCluster <= 1) return center;
    final double radius = 0.00015 + (index ~/ 8) * 0.00010;
    final double angle =
        (index % 8) * (2 * math.pi / math.min(totalInCluster, 8));
    return LatLng(
      center.latitude + radius * math.cos(angle),
      center.longitude + radius * math.sin(angle) * 1.2,
    );
  }

  List<Marker> _buildPoiMarkers(List<DestinationPOI> displayPOIs) {
    final Map<String, List<DestinationPOI>> clusters = {};
    for (final poi in displayPOIs) {
      final key =
          '${(poi.location.latitude * 10000).round()}_${(poi.location.longitude * 10000).round()}';
      clusters.putIfAbsent(key, () => []).add(poi);
    }

    final List<Marker> markers = [];

    clusters.forEach((key, poiList) {
      for (int i = 0; i < poiList.length; i++) {
        final poi = poiList[i];
        final rawLatLng = LatLng(poi.location.latitude, poi.location.longitude);
        final dispersedLatLng = _getDispersedCoords(
          rawLatLng,
          i,
          poiList.length,
        );
        final color = _getCategoryColor(poi.category);

        markers.add(
          Marker(
            point: dispersedLatLng,
            width: 105,
            height: 48,
            child: GestureDetector(
              onTap: () => _showPOIDetailsBottomSheet(poi),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getCategoryIcon(poi.category),
                          size: 11,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            poi.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'L${poi.floorNumber}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronDown,
                    size: 10,
                    color: Color(0xFF1E293B),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    });

    return markers;
  }

  @override
  Widget build(BuildContext meContext) {
    if (_currentCenter == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.isPickerMode
                ? 'Pick Coordinates on OSM'
                : 'OpenStreetMap Live Admin Explorer',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Locating your position...',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFF94A3B8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final center = _currentCenter;
    final userGeo = center != null && center.latitude != 0.0
        ? GeodeticCoords(
            latitude: center.latitude,
            longitude: center.longitude,
            height: widget.userCoords.height,
          )
        : null;

    final displayPOIs = _effectiveDisplayPOIs;

    // Available floors and categories are calculated for the currently selected mall
    final Set<int> allFloorNums = {};
    if (_selectedMallFilter != 'ALL') {
      final selectedMall = _mallsWithin500m.where((m) {
        final mId = m.id.trim().toLowerCase().replaceAll(RegExp(r'^0+'), '');
        final sId = _selectedMallFilter.trim().toLowerCase().replaceAll(RegExp(r'^0+'), '');
        return mId == sId || m.name.trim().toLowerCase() == _selectedMallFilter.trim().toLowerCase();
      }).firstOrNull;

      if (selectedMall != null) {
        final count = selectedMall.floorCount > 0 ? selectedMall.floorCount : 1;
        for (int i = 1; i <= count; i++) {
          allFloorNums.add(i);
        }
      }
      for (final p in displayPOIs) {
        allFloorNums.add(p.floorNumber);
      }
    }
    final availableFloors = allFloorNums.toList()..sort();
    final availableCategories = displayPOIs
        .map((p) => p.category.toUpperCase().trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title ??
                  (widget.isPickerMode
                      ? 'Pick Coordinates on OSM'
                      : (widget.isUserMode
                          ? 'OpenStreetMap Live Explorer'
                          : 'OpenStreetMap Live Admin Explorer')),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              _selectedMallFilter == 'ALL'
                  ? '${_mallsWithin500m.length} Malls within 500m • Select a mall to view shops'
                  : '${_mallsWithin500m.where((m) => m.id == _selectedMallFilter || m.name.toLowerCase() == _selectedMallFilter.toLowerCase()).firstOrNull?.name ?? "Selected Mall"} • ${displayPOIs.length} Shops (${_selectedFloorFilter == 0 ? "All Floors" : "Floor $_selectedFloorFilter"})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isLoadingOSM
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF38BDF8),
                    ),
                  )
                : const Icon(LucideIcons.refreshCw, color: Color(0xFF38BDF8)),
            onPressed: _fetchLiveOSMVenues,
            tooltip: 'Refresh OSM Live Feed',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // OpenStreetMap Flutter Plugin Widget
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter!,
              initialZoom: 16.5,
              maxZoom: 19.0,
              minZoom: 10.0,
              onTap: _onMapTap,
            ),
            children: [
              // OpenStreetMap Standard Tile Layer
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.nexnav.mobile',
              ),

              // 500m Proximity Circle Layer
              if (_currentCenter != null && _currentCenter!.latitude != 0.0)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _currentCenter!,
                      radius: _discoveryRadiusMeters,
                      useRadiusInMeter: true,
                      color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                      borderColor:
                          const Color(0xFF0284C7).withValues(alpha: 0.45),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),

              // POI & Mall Markers Layer
              MarkerLayer(
                markers: [
                  // User Live Location Marker
                  Marker(
                    point: _currentCenter!,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF38BDF8),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Color(0xFF0284C7),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Selected Picker Marker (if in picker mode)
                  if (_selectedPickerPoint != null)
                    Marker(
                      point: _selectedPickerPoint!,
                      width: 50,
                      height: 50,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE11D48),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 6,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              LucideIcons.mapPin,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Malls within 500m (Other malls NOT visible)
                  ..._buildMallMarkers(),

                  // POI / Venue Markers
                  ..._buildPoiMarkers(displayPOIs),
                ],
              ),
            ],
          ),

          // Top Control Overlay Panel (Malls within 500m, Floor & Category Filters)
          if (_mallsWithin500m.isNotEmpty ||
              (_selectedMallFilter != 'ALL' && availableFloors.length > 1) ||
              (_selectedMallFilter != 'ALL' && availableCategories.length > 1))
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Malls within 500m Indicator Chips (Shows Mall Names & Floors)
                  if (_mallsWithin500m.isNotEmpty) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildMallFilterChip(
                            label: 'All Malls (500m)',
                            floorText: '${_mallsWithin500m.length} nearby',
                            mallId: 'ALL',
                            icon: LucideIcons.mapPin,
                          ),
                          ..._mallsWithin500m.map((mall) {
                            final distM = userGeo != null
                                ? haversineDistance(
                                    userGeo,
                                    GeodeticCoords(
                                      latitude: mall.latitude,
                                      longitude: mall.longitude,
                                      height: mall.entranceBaseAnchorHeight,
                                    ),
                                  )
                                : 0.0;
                            return Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: _buildMallFilterChip(
                                label: mall.name,
                                floorText:
                                    '${mall.floorCount > 0 ? mall.floorCount : 1} Floors • ${distM.toInt()}m',
                                mallId: mall.id,
                                icon: LucideIcons.building2,
                                targetLatLng:
                                    LatLng(mall.latitude, mall.longitude),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // 2. Floor Level Filter Chips (Only shown when a specific mall is selected)
                  if (_selectedMallFilter != 'ALL' && availableFloors.length > 1) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('All Floors', 0, LucideIcons.layers),
                          ...availableFloors.map((f) {
                            return Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: _buildFilterChip(
                                f < 0
                                    ? 'Basement $f'
                                    : (f == 1 ? 'Floor 1' : 'Floor $f'),
                                f,
                                f < 0 ? LucideIcons.car : LucideIcons.layers,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    if (availableCategories.length > 1)
                      const SizedBox(height: 8),
                  ],

                  // 3. Category Filter Bar (Only shown when a specific mall is selected)
                  if (_selectedMallFilter != 'ALL' && availableCategories.length > 1)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildCategoryChip('ALL'),
                          ...availableCategories.map((cat) {
                            return Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: _buildCategoryChip(cat),
                            );
                          }),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // Bottom Control Card / Picker Selector Confirmation Bar
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: widget.isPickerMode
                ? _buildPickerConfirmCard()
                : _buildOSMExplorerControlCard(displayPOIs.length),
          ),
        ],
      ),
    );
  }

  Widget _buildMallFilterChip({
    required String label,
    required String floorText,
    required String mallId,
    required IconData icon,
    LatLng? targetLatLng,
  }) {
    final isSelected = _selectedMallFilter == mallId;
    return ChoiceChip(
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 13,
        color: isSelected ? Colors.white : const Color(0xFF0284C7),
      ),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isSelected ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          Text(
            floorText,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? const Color(0xFFBAE6FD)
                  : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF0F172A),
      backgroundColor: Colors.white.withValues(alpha: 0.95),
      elevation: 3,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color:
              isSelected ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
          width: 1,
        ),
      ),
      onSelected: (selected) {
        setState(() {
          _selectedMallFilter = mallId;
          _selectedFloorFilter = 0; // Reset floor filter when changing mall
        });
        if (mallId != 'ALL' && widget.onSelectActiveMall != null) {
          widget.onSelectActiveMall!(mallId);
        }
        if (targetLatLng != null) {
          _mapController.move(targetLatLng, 17.5);
        } else if (_currentCenter != null) {
          _mapController.move(_currentCenter!, 16.5);
        }
      },
    );
  }

  Widget _buildFilterChip(String label, int floorValue, IconData icon) {
    final isSelected = _selectedFloorFilter == floorValue;
    return ChoiceChip(
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 14,
        color: isSelected ? Colors.white : const Color(0xFF94A3B8),
      ),
      label: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          color: isSelected ? Colors.white : const Color(0xFF0F172A),
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF0284C7),
      backgroundColor: Colors.white.withValues(alpha: 0.95),
      elevation: 3,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedFloorFilter = floorValue;
          });
        }
      },
    );
  }

  Widget _buildCategoryChip(String catName) {
    final isSelected = _selectedCategory == catName;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedCategory = catName;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF38BDF8)
              : const Color(0xFF1E293B).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : Colors.white24,
          ),
        ),
        child: Text(
          catName,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildPickerConfirmCard() {
    final hasSelection = _selectedPickerPoint != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.mapPin,
                color: Color(0xFF38BDF8),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                hasSelection
                    ? 'Location Point Selected'
                    : 'Tap anywhere on OSM Map to select point',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          if (hasSelection) ...[
            const SizedBox(height: 8),
            Text(
              'Lat: ${_selectedPickerPoint!.latitude.toStringAsFixed(6)} | Lon: ${_selectedPickerPoint!.longitude.toStringAsFixed(6)}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: hasSelection
                  ? () {
                      if (widget.onSelectCoordinates != null) {
                        widget.onSelectCoordinates!(
                          GeodeticCoords(
                            latitude: _selectedPickerPoint!.latitude,
                            longitude: _selectedPickerPoint!.longitude,
                            height: widget.userCoords.height,
                          ),
                        );
                      }
                      Navigator.pop(context);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                disabledBackgroundColor: const Color(0xFF475569),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Confirm Selected Coordinates',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOSMExplorerControlCard(int activePoiCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.globe,
                      color: Color(0xFF38BDF8),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Live OSM Feed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _selectedMallFilter == 'ALL'
                      ? '500m Radius • ${_mallsWithin500m.length} Malls Nearby (Select a mall to view shops)'
                      : '${_mallsWithin500m.where((m) => m.id == _selectedMallFilter || m.name.toLowerCase() == _selectedMallFilter.toLowerCase()).firstOrNull?.name ?? "Selected Mall"} • $activePoiCount Shops Available',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _fetchLiveGPSAndCenter(),
            icon: const Icon(
              LucideIcons.crosshair,
              size: 14,
              color: Colors.white,
            ),
            label: Text(
              'My Location',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  void _showPOIDetailsBottomSheet(DestinationPOI poi) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final isOsm = poi.id.startsWith('osm-');

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _getCategoryColor(
                        poi.category,
                      ).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _getCategoryIcon(poi.category),
                      color: _getCategoryColor(poi.category),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          poi.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${poi.category} • Floor ${poi.floorNumber}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                poi.description,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: const Color(0xFFCBD5E1),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    LucideIcons.mapPin,
                    size: 14,
                    color: Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Lat: ${poi.location.latitude.toStringAsFixed(6)}, Lon: ${poi.location.longitude.toStringAsFixed(6)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (widget.onSelectDestination != null) ...[
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      widget.onSelectDestination!(poi);
                      Navigator.pop(context);
                    },
                    icon: const Icon(LucideIcons.navigation, size: 18),
                    label: Text(
                      'Navigate to ${poi.name}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
              if (isOsm && widget.onImportOsmPoi != null) ...[
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      widget.onImportOsmPoi!(poi);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Imported "${poi.name}" into Admin POIs!',
                          ),
                          backgroundColor: const Color(0xFF10B981),
                        ),
                      );
                    },
                    icon: const Icon(LucideIcons.download, size: 18),
                    label: Text(
                      'Import into Admin Store Database',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMallStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            color: const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  void _showMallDetailsBottomSheet(MallMetadata mall, double distM) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final bool isActive = mall.isActive ||
            mall.isSelected ||
            widget.mallService?.activeMallId == mall.id;

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      LucideIcons.building2,
                      color: Color(0xFF38BDF8),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mall.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${mall.city}, ${mall.country} • ${mall.floorCount} Floors',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF059669).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF059669)),
                      ),
                      child: const Text(
                        'ACTIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF34D399),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMallStat('Distance', '${distM.toInt()}m'),
                    _buildMallStat('Floors', '${mall.floorCount}'),
                    _buildMallStat('Rating', '${mall.rating} ★'),
                  ],
                ),
              ),
              if (widget.onSelectActiveMall != null) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      widget.onSelectActiveMall?.call(mall.id);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Switched to ${mall.name}!'),
                          backgroundColor: const Color(0xFF059669),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(LucideIcons.navigation, size: 16),
                    label: Text(
                      isActive ? 'Current Active Mall' : 'Use This Mall Map',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive
                          ? const Color(0xFF059669)
                          : const Color(0xFF2563EB),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
