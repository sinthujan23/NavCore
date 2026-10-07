import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';

import '../../engine/ecef_engine.dart';
import '../../engine/osm_place_discovery_service.dart';
import '../../data/destinations.dart';
import '../../data/mall_database_service.dart';

/// Admin Panel OpenStreetMap (OSM) Live Explorer & Coordinate Selector Screen
class AdminOSMMapScreen extends StatefulWidget {
  final GeodeticCoords userCoords;
  final List<DestinationPOI> destinations;
  final MallDatabaseService? mallService;
  final bool isPickerMode;
  final ValueChanged<GeodeticCoords>? onSelectCoordinates;
  final ValueChanged<DestinationPOI>? onImportOsmPoi;

  const AdminOSMMapScreen({
    super.key,
    required this.userCoords,
    required this.destinations,
    this.mallService,
    this.isPickerMode = false,
    this.onSelectCoordinates,
    this.onImportOsmPoi,
  });

  @override
  State<AdminOSMMapScreen> createState() => _AdminOSMMapScreenState();
}

class _AdminOSMMapScreenState extends State<AdminOSMMapScreen> {
  late final MapController _mapController;
  late LatLng _currentCenter;
  LatLng? _selectedPickerPoint;
  
  List<DestinationPOI> _osmDiscoveredPOIs = [];
  bool _isLoadingOSM = false;
  final double _discoveryRadiusMeters = 500.0;
  int _selectedFloorFilter = 0; // 0 = All Floors
  String _selectedCategory = 'ALL';

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _currentCenter = LatLng(
      widget.userCoords.latitude != 0.0 ? widget.userCoords.latitude : 6.9175,
      widget.userCoords.longitude != 0.0 ? widget.userCoords.longitude : 79.8530,
    );

    _fetchLiveOSMVenues();
    _fetchLiveGPSAndCenter();
  }

  Future<void> _fetchLiveGPSAndCenter() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (mounted) {
        setState(() {
          _currentCenter = LatLng(pos.latitude, pos.longitude);
        });
        _mapController.move(_currentCenter, 16.5);
        _fetchLiveOSMVenues();
      }
    } catch (e) {
      debugPrint('Live GPS fetch error in OSM explorer: $e');
    }
  }

  Future<void> _fetchLiveOSMVenues() async {
    setState(() {
      _isLoadingOSM = true;
    });

    try {
      final userGeodetic = GeodeticCoords(
        latitude: _currentCenter.latitude,
        longitude: _currentCenter.longitude,
        height: widget.userCoords.height,
      );

      final places = await OSMPlaceDiscoveryService.instance.fetchRealOSMPlacesAroundUser(
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
    if (c.contains('RETAIL') || c.contains('FASHION')) return const Color(0xFF8B5CF6); // Purple
    if (c.contains('TECH') || c.contains('ELECTRONIC')) return const Color(0xFF3B82F6); // Blue
    if (c.contains('PARKING')) return const Color(0xFF64748B); // Slate
    if (c.contains('SERVICES')) return const Color(0xFF10B981); // Emerald
    return const Color(0xFF6366F1); // Indigo default
  }

  IconData _getCategoryIcon(String category) {
    final c = category.toUpperCase();
    if (c.contains('FOOD')) return LucideIcons.utensils;
    if (c.contains('RETAIL') || c.contains('FASHION')) return LucideIcons.shoppingBag;
    if (c.contains('TECH') || c.contains('ELECTRONIC')) return LucideIcons.smartphone;
    if (c.contains('PARKING')) return LucideIcons.car;
    if (c.contains('SERVICES')) return LucideIcons.info;
    return LucideIcons.mapPin;
  }

  List<DestinationPOI> get _effectiveDisplayPOIs {
    final combined = <DestinationPOI>[...widget.destinations, ..._osmDiscoveredPOIs];
    final uniqueMap = <String, DestinationPOI>{};
    for (final p in combined) {
      uniqueMap[p.id] = p;
    }
    
    return uniqueMap.values.where((poi) {
      final matchesFloor = _selectedFloorFilter == 0 || poi.floorNumber == _selectedFloorFilter;
      final matchesCategory = _selectedCategory == 'ALL' || poi.category.toUpperCase().contains(_selectedCategory);
      return matchesFloor && matchesCategory;
    }).toList();
  }

  LatLng _getDispersedCoords(LatLng center, int index, int totalInCluster) {
    if (totalInCluster <= 1) return center;
    final double radius = 0.00015 + (index ~/ 8) * 0.00010;
    final double angle = (index % 8) * (2 * math.pi / math.min(totalInCluster, 8));
    return LatLng(
      center.latitude + radius * math.cos(angle),
      center.longitude + radius * math.sin(angle) * 1.2,
    );
  }

  List<Marker> _buildPoiMarkers(List<DestinationPOI> displayPOIs) {
    final Map<String, List<DestinationPOI>> clusters = {};
    for (final poi in displayPOIs) {
      final key = '${(poi.location.latitude * 10000).round()}_${(poi.location.longitude * 10000).round()}';
      clusters.putIfAbsent(key, () => []).add(poi);
    }

    final List<Marker> markers = [];

    clusters.forEach((key, poiList) {
      for (int i = 0; i < poiList.length; i++) {
        final poi = poiList[i];
        final rawLatLng = LatLng(poi.location.latitude, poi.location.longitude);
        final dispersedLatLng = _getDispersedCoords(rawLatLng, i, poiList.length);
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                      ],
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getCategoryIcon(poi.category), size: 11, color: Colors.white),
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
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
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
                  const Icon(LucideIcons.chevronDown, size: 10, color: Color(0xFF1E293B)),
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
    final displayPOIs = _effectiveDisplayPOIs;

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
              widget.isPickerMode ? 'Pick Coordinates on OSM' : 'OpenStreetMap Live Admin Explorer',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              '${displayPOIs.length} Active POIs • Overpass Live Feed',
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
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
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
              initialCenter: _currentCenter,
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

              // POI Markers Layer
              MarkerLayer(
                markers: [
                  // User Live Location Marker
                  Marker(
                    point: LatLng(widget.userCoords.latitude, widget.userCoords.longitude),
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF38BDF8), width: 2),
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
                                BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3)),
                              ],
                            ),
                            child: const Icon(LucideIcons.mapPin, color: Colors.white, size: 20),
                          ),
                        ],
                      ),
                    ),

                  // POI / Venue Markers
                  ..._buildPoiMarkers(displayPOIs),
                ],
              ),
            ],
          ),

          // Top Control Overlay Panel (Floor & Category Filters)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                // Floor Level Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All Floors', 0, LucideIcons.layers),
                      const SizedBox(width: 6),
                      _buildFilterChip('Floor 1', 1, LucideIcons.store),
                      const SizedBox(width: 6),
                      _buildFilterChip('Floor 2', 2, LucideIcons.shoppingBag),
                      const SizedBox(width: 6),
                      _buildFilterChip('Floor 3', 3, LucideIcons.smartphone),
                      const SizedBox(width: 6),
                      _buildFilterChip('Floor 4', 4, LucideIcons.utensils),
                      const SizedBox(width: 6),
                      _buildFilterChip('Basement -1', -1, LucideIcons.car),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Category Filter Bar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCategoryChip('ALL'),
                      const SizedBox(width: 6),
                      _buildCategoryChip('FOOD & DRINK'),
                      const SizedBox(width: 6),
                      _buildCategoryChip('RETAIL & FASHION'),
                      const SizedBox(width: 6),
                      _buildCategoryChip('TECH & ELECTRONICS'),
                      const SizedBox(width: 6),
                      _buildCategoryChip('PARKING'),
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

  Widget _buildFilterChip(String label, int floorValue, IconData icon) {
    final isSelected = _selectedFloorFilter == floorValue;
    return ChoiceChip(
      showCheckmark: false,
      avatar: Icon(icon, size: 14, color: isSelected ? Colors.white : const Color(0xFF94A3B8)),
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
          color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF1E293B).withValues(alpha: 0.9),
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
          BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
        ],
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.mapPin, color: Color(0xFF38BDF8), size: 20),
              const SizedBox(width: 8),
              Text(
                hasSelection ? 'Location Point Selected' : 'Tap anywhere on OSM Map to select point',
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
          BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
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
                    const Icon(LucideIcons.globe, color: Color(0xFF38BDF8), size: 16),
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
                  'Radius: ${_discoveryRadiusMeters.toInt()}m • $activePoiCount POIs',
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
            icon: const Icon(LucideIcons.crosshair, size: 14, color: Colors.white),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                      color: _getCategoryColor(poi.category).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_getCategoryIcon(poi.category), color: _getCategoryColor(poi.category)),
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
                  const Icon(LucideIcons.mapPin, size: 14, color: Color(0xFF38BDF8)),
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
                          content: Text('Imported "${poi.name}" into Admin POIs!'),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
