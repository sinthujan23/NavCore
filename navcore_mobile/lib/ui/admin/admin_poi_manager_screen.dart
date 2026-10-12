import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../data/destinations.dart';
import '../../data/mall_database_service.dart';
import '../../data/api_service.dart';
import '../../engine/ecef_engine.dart';
import '../../engine/floor_tracker.dart';
import '../../engine/bearing_engine.dart';
import 'admin_osm_map_screen.dart';

class AdminPOIManagerScreen extends StatefulWidget {
  final List<DestinationPOI> destinations;
  final Function(DestinationPOI newPoi) onAddPoi;
  final Function(DestinationPOI updatedPoi) onUpdatePoi;
  final Function(String poiId) onDeletePoi;
  final GeodeticCoords? userCoords;
  final MallDatabaseService? mallService;

  const AdminPOIManagerScreen({
    super.key,
    required this.destinations,
    required this.onAddPoi,
    required this.onUpdatePoi,
    required this.onDeletePoi,
    this.userCoords,
    this.mallService,
  });

  @override
  State<AdminPOIManagerScreen> createState() => _AdminPOIManagerScreenState();
}

class _AdminPOIManagerScreenState extends State<AdminPOIManagerScreen> {
  late List<DestinationPOI> _poiList;
  bool _isLoadingPois = false;
  String _selectedCategory = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, dynamic>> _categoryTabs = [
    {'name': 'ALL', 'icon': LucideIcons.layoutGrid},
    {'name': 'FOOD & DRINK', 'icon': LucideIcons.utensils},
    {'name': 'RETAIL & FASHION', 'icon': LucideIcons.shoppingBag},
    {'name': 'TECH & ELECTRONICS', 'icon': LucideIcons.smartphone},
    {'name': 'ENTERTAINMENT', 'icon': LucideIcons.gamepad2},
    {'name': 'SERVICES', 'icon': LucideIcons.shieldCheck},
  ];

  @override
  void initState() {
    super.initState();
    _poiList = _deduplicatePois(widget.destinations);
    _loadDestinationsFromDatabase();
  }

  List<DestinationPOI> _deduplicatePois(List<DestinationPOI> list) {
    final seen = <String>{};
    final seenIds = <String>{};
    final result = <DestinationPOI>[];
    for (final p in list) {
      final key = '${p.name.trim().toLowerCase()}#${p.floorNumber}#${p.mallId ?? ''}';
      if (!seen.contains(key) && !seenIds.contains(p.id)) {
        seen.add(key);
        seenIds.add(p.id);
        result.add(p);
      }
    }
    return result;
  }

  Future<void> _loadDestinationsFromDatabase() async {
    setState(() => _isLoadingPois = true);
    try {
      final list = await ApiService.instance.fetchDestinations();
      if (mounted) {
        setState(() {
          if (list.isNotEmpty) {
            _poiList = _deduplicatePois(list);
          } else {
            _poiList = _deduplicatePois(_poiList);
          }
          _isLoadingPois = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPois = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DestinationPOI> get _filteredPois {
    return _poiList.where((poi) {
      final matchesCat =
          _selectedCategory == 'ALL' ||
          poi.category.toUpperCase().contains(_selectedCategory);
      final q = _searchQuery.trim().toLowerCase();
      if (q.isEmpty) return matchesCat;

      final nameMatches = poi.name.toLowerCase().contains(q);
      final descMatches = poi.description.toLowerCase().contains(q);
      final catMatches = poi.category.toLowerCase().contains(q);

      // Support floor number search like "F1", "B1", "Floor 2"
      bool floorMatches = false;
      if (q == 'f${poi.floorNumber}' ||
          q == 'floor ${poi.floorNumber}' ||
          (poi.floorNumber < 0 && q == 'b${poi.floorNumber.abs()}')) {
        floorMatches = true;
      }

      return matchesCat &&
          (nameMatches || descMatches || catMatches || floorMatches);
    }).toList();
  }

  void _openAddEditPoiScreen([DestinationPOI? existingPoi]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditPoiScreen(
          existingPoi: existingPoi,
          userCoords: widget.userCoords,
          destinations: _poiList,
          mallService: widget.mallService,
          onSavePoi: (savedPoi, isEditing) async {
            if (isEditing) {
              final idx = _poiList.indexWhere((p) => p.id == savedPoi.id);
              if (idx != -1) {
                setState(() {
                  _poiList[idx] = savedPoi;
                });
              }
              await ApiService.instance.updateDestination(savedPoi);
              widget.onUpdatePoi(savedPoi);
            } else {
              final key = '${savedPoi.name.trim().toLowerCase()}#${savedPoi.floorNumber}#${savedPoi.mallId ?? ''}';
              setState(() {
                _poiList.removeWhere((p) => p.id == savedPoi.id || '${p.name.trim().toLowerCase()}#${p.floorNumber}#${p.mallId ?? ''}' == key);
                _poiList.insert(0, savedPoi);
                _poiList = _deduplicatePois(_poiList);
              });
              final targetMallId =
                  savedPoi.mallId ??
                  (_poiList.isNotEmpty && _poiList.first.mallId != null
                      ? _poiList.first.mallId!
                      : 'mall-default');
              await ApiService.instance.createDestination(
                savedPoi,
                mallId: targetMallId,
              );
              widget.onAddPoi(savedPoi);
            }
            await _loadDestinationsFromDatabase();
          },
        ),
      ),
    );
  }

  void _confirmDeletePoi(DestinationPOI poi) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                LucideIcons.trash2,
                color: Color(0xFFEF4444),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Store POI',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "${poi.name}" from the active venue directory?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: const Color(0xFF64748B),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
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
              Navigator.pop(ctx);
              final key = '${poi.name.trim().toLowerCase()}#${poi.floorNumber}#${poi.mallId ?? ''}';
              setState(() {
                _poiList.removeWhere((p) => p.id == poi.id || '${p.name.trim().toLowerCase()}#${p.floorNumber}#${p.mallId ?? ''}' == key);
              });
              await ApiService.instance.deleteDestination(poi.id);
              widget.onDeletePoi(poi.id);
              await _loadDestinationsFromDatabase();
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('"${poi.name}" deleted from database.'),
                  backgroundColor: const Color(0xFFEF4444),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Text(
              'Delete',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredPois;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        surfaceTintColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Center(
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Icon(
                  LucideIcons.arrowLeft,
                  size: 18,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'POI Store Directory',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              '${_filteredPois.length} locations configured',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: InkWell(
                onTap: () => _openAddEditPoiScreen(),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.22),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.plus,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'ADD SHOP',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              children: [
                // Modern Search Bar
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF0F172A),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText:
                          'Search stores by name, category, or floor (e.g. F1)...',
                      hintStyle: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFF94A3B8),
                        fontSize: 12.5,
                      ),
                      prefixIcon: const Icon(
                        LucideIcons.search,
                        size: 18,
                        color: Color(0xFF2563EB),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                LucideIcons.x,
                                size: 16,
                                color: Color(0xFF94A3B8),
                              ),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Category Tabs Carousel
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categoryTabs.map((tab) {
                      final name = tab['name'] as String;
                      final icon = tab['icon'] as IconData;
                      final isSelected = _selectedCategory == name;

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedCategory = name),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFFE2E8F0),
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF2563EB,
                                        ).withValues(alpha: 0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icon,
                                  size: 13,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  name,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF475569),
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // POI List
          Expanded(
            child: _isLoadingPois && _poiList.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2563EB)),
                  )
                : RefreshIndicator(
                    onRefresh: _loadDestinationsFromDatabase,
                    color: const Color(0xFF2563EB),
                    child: filtered.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 80,
                                  left: 24,
                                  right: 24,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: const Icon(
                                        LucideIcons.searchX,
                                        color: Color(0xFF94A3B8),
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'No matching stores found',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Try adjusting your search terms or select another category filter.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12.5,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFF2563EB,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFFBFDBFE),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _searchController.clear();
                                          _searchQuery = '';
                                          _selectedCategory = 'ALL';
                                        });
                                      },
                                      icon: const Icon(
                                        LucideIcons.refreshCw,
                                        size: 14,
                                      ),
                                      label: Text(
                                        'Clear Filters',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, idx) {
                              final poi = filtered[idx];
                              final isBasement = poi.floorNumber < 0;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x060F172A),
                                      blurRadius: 10,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    // Floor Indicator Badge
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: isBasement
                                            ? const Color(0xFFF3E8FF)
                                            : const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isBasement
                                              ? const Color(0xFFE9D5FF)
                                              : const Color(0xFFDBEAFE),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          isBasement
                                              ? 'B${poi.floorNumber.abs()}'
                                              : 'F${poi.floorNumber}',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.w900,
                                            color: isBasement
                                                ? const Color(0xFF7E22CE)
                                                : const Color(0xFF1D4ED8),
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // Store Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  poi.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      GoogleFonts.plusJakartaSans(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: const Color(
                                                          0xFF0F172A,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Wrap(
                                            spacing: 5,
                                            runSpacing: 3,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFF1F5F9,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  poi.category,
                                                  style:
                                                      GoogleFonts.plusJakartaSans(
                                                        fontSize: 9.0,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: const Color(
                                                          0xFF475569,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                              if (poi.mallId != null &&
                                                  poi.mallId!.isNotEmpty)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFEFF6FF,
                                                    ),
                                                    borderRadius:
                                                      BorderRadius.circular(
                                                        6,
                                                      ),
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFFDBEAFE,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    (widget
                                                                    .mallService
                                                                    ?.catalog ??
                                                                [])
                                                            .where(
                                                              (m) =>
                                                                  m.id ==
                                                                  poi.mallId,
                                                            )
                                                            .firstOrNull
                                                            ?.name ??
                                                        poi.mallId!
                                                            .replaceFirst(
                                                              'mall-',
                                                              '',
                                                            )
                                                            .toUpperCase(),
                                                    style:
                                                      GoogleFonts.plusJakartaSans(
                                                        fontSize: 9.0,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: const Color(
                                                          0xFF2563EB,
                                                        ),
                                                      ),
                                                  ),
                                                ),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    LucideIcons.star,
                                                    size: 11,
                                                    color: Color(0xFFD97706),
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    '${poi.rating}',
                                                    style:
                                                      GoogleFonts.plusJakartaSans(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: const Color(
                                                          0xFF64748B,
                                                        ),
                                                      ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${poi.location.latitude.toStringAsFixed(5)}°N, ${poi.location.longitude.toStringAsFixed(5)}°E • Alt: ${poi.location.height.toStringAsFixed(1)}m',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 10,
                                              color: const Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Action Buttons
                                    InkWell(
                                      onTap: () => _openAddEditPoiScreen(poi),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF6FF),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFBFDBFE),
                                          ),
                                        ),
                                        child: const Icon(
                                          LucideIcons.pencil,
                                          size: 15,
                                          color: Color(0xFF2563EB),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => _confirmDeletePoi(poi),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFFECACA),
                                          ),
                                        ),
                                        child: const Icon(
                                          LucideIcons.trash2,
                                          size: 15,
                                          color: Color(0xFFEF4444),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// HIGH-ACCURACY GPS CONVERGENCE RESULT
class _GpsConvergenceResult {
  final GeodeticCoords coords;
  final double accuracy;
  final int sampleCount;

  const _GpsConvergenceResult({
    required this.coords,
    required this.accuracy,
    required this.sampleCount,
  });
}

/// FULL-SCREEN POI CREATION & EDITING SCREEN
class AddEditPoiScreen extends StatefulWidget {
  final DestinationPOI? existingPoi;
  final GeodeticCoords? userCoords;
  final List<DestinationPOI> destinations;
  final MallDatabaseService? mallService;
  final Function(DestinationPOI poi, bool isEditing) onSavePoi;

  const AddEditPoiScreen({
    super.key,
    this.existingPoi,
    this.userCoords,
    required this.destinations,
    this.mallService,
    required this.onSavePoi,
  });

  @override
  State<AddEditPoiScreen> createState() => _AddEditPoiScreenState();
}

class _AddEditPoiScreenState extends State<AddEditPoiScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _descController;
  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  late final TextEditingController _heightController;
  late final TextEditingController _statusController;

  late int _floorNumber;
  late double _activeBaseAltitude;
  bool _isFetchingGps = false;
  bool _isStationaryLocked = false;
  // Phone motion tracking & continuous auto-sync
  final bool _isMotionSyncActive = true;
  bool _isPhoneInMotion = false;
  StreamSubscription<Position>? _positionStreamSub;
  StreamSubscription<UserAccelerometerEvent>? _accelStreamSub;
  StreamSubscription<AccelerometerEvent>? _rawAccelStreamSub;
  Timer? _stationaryDebounceTimer;

  // High-accuracy multi-sample GPS convergence & stationary lock anchor
  GeodeticCoords? _lastStabilizedCoords;

  List<MallMetadata> _malls = [];
  String _selectedMallId = '';
  bool _isLoadingMalls = false;

  final List<String> _categories = [
    'FOOD & DRINK',
    'RETAIL & FASHION',
    'TECH & ELECTRONICS',
    'ENTERTAINMENT',
    'SERVICES',
  ];

  double _floorOffset(int flr) => flr < 0 ? (flr * 4.5) : ((flr - 1) * 4.5);

  @override
  void initState() {
    super.initState();
    final p = widget.existingPoi;
    _nameController = TextEditingController(text: p?.name ?? '');
    _categoryController = TextEditingController(
      text: p?.category ?? 'RETAIL & FASHION',
    );
    _descController = TextEditingController(text: p?.description ?? '');
    _statusController = TextEditingController(
      text: p?.openStatus ?? 'Open Today: 10 AM - 10 PM',
    );

    _floorNumber = p?.floorNumber ?? 1;

    // Initialize Malls strictly from real database (via MallDatabaseService / ApiService)
    _malls = List<MallMetadata>.from(widget.mallService?.catalog ?? []);

    if (p?.mallId != null && p!.mallId!.isNotEmpty) {
      _selectedMallId = p.mallId!;
    } else {
      final active = _malls.where((m) => m.isActive).firstOrNull;
      _selectedMallId =
          active?.id ?? (_malls.isNotEmpty ? _malls.first.id : '');
    }

    _loadMallsFromDatabase();

    if (p != null) {
      _activeBaseAltitude = p.location.height - _floorOffset(p.floorNumber);
      _lastStabilizedCoords = p.location;
    } else if (widget.userCoords != null && widget.userCoords!.height != 0.0) {
      _activeBaseAltitude = widget.userCoords!.height;
    } else {
      _activeBaseAltitude = 45.0;
    }

    final initialLat =
        p?.location.latitude ??
        (widget.userCoords != null && widget.userCoords!.latitude != 0.0
            ? widget.userCoords!.latitude
            : null);
    final initialLng =
        p?.location.longitude ??
        (widget.userCoords != null && widget.userCoords!.longitude != 0.0
            ? widget.userCoords!.longitude
            : null);
    final initialAlt =
        p?.location.height ??
        (_activeBaseAltitude + _floorOffset(_floorNumber));

    _latController = TextEditingController(
      text: initialLat != null ? initialLat.toStringAsFixed(6) : '',
    );
    _lngController = TextEditingController(
      text: initialLng != null ? initialLng.toStringAsFixed(6) : '',
    );
    _heightController = TextEditingController(
      text: initialAlt.toStringAsFixed(1),
    );

    // Start continuous phone motion listener & live auto-sync
    _startLiveMotionSync();

    // Auto-track location if new POI and initial coordinates are blank
    if (widget.existingPoi == null &&
        (_latController.text.isEmpty || _lngController.text.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncCurrentLocation();
      });
    }
  }

  Future<void> _loadMallsFromDatabase() async {
    setState(() => _isLoadingMalls = true);
    try {
      final list =
          await (widget.mallService?.getMallsList() ??
              ApiService.instance.fetchMalls());
      if (mounted) {
        setState(() {
          _malls = list;
          _isLoadingMalls = false;
          if (_selectedMallId.isNotEmpty &&
              _malls.any((m) => m.id == _selectedMallId)) {
            // Keep current selection
          } else if (widget.existingPoi?.mallId != null &&
              widget.existingPoi!.mallId!.isNotEmpty &&
              _malls.any((m) => m.id == widget.existingPoi!.mallId)) {
            _selectedMallId = widget.existingPoi!.mallId!;
          } else {
            final active = _malls.where((m) => m.isActive).firstOrNull;
            _selectedMallId =
                active?.id ?? (_malls.isNotEmpty ? _malls.first.id : '');
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMalls = false);
      }
    }
  }

  void _onMallChanged(String newMallId) {
    setState(() {
      _selectedMallId = newMallId;
      final selectedMall = _malls.where((m) => m.id == newMallId).firstOrNull;
      if (selectedMall != null) {
        final int maxFlr = selectedMall.floorCount > 0
            ? selectedMall.floorCount
            : 5;
        if (_floorNumber > maxFlr) {
          _floorNumber = 1;
        }
        if (widget.existingPoi == null &&
            selectedMall.latitude != 0.0 &&
            selectedMall.longitude != 0.0) {
          _latController.text = selectedMall.latitude.toStringAsFixed(6);
          _lngController.text = selectedMall.longitude.toStringAsFixed(6);
        }
        _recalculateHeight();
      }
    });
  }

  @override
  void dispose() {
    _stopLiveMotionSync();
    _nameController.dispose();
    _categoryController.dispose();
    _descController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _heightController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  void _flagPhoneMotionDetected() {
    _stationaryDebounceTimer?.cancel();
    if (!_isPhoneInMotion) {
      if (mounted) {
        setState(() {
          _isPhoneInMotion = true;
          _isStationaryLocked = false;
        });
      }
    }
    _stationaryDebounceTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted && _isPhoneInMotion) {
        setState(() {
          _isPhoneInMotion = false;
        });
      }
    });
  }

  void _startLiveMotionSync() async {
    _stopLiveMotionSync();
    if (!_isMotionSyncActive) return;

    // 1. High-sensitivity physical phone motion detection (linear user acceleration)
    try {
      _accelStreamSub =
          userAccelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 150),
          ).listen((UserAccelerometerEvent event) {
            if (!mounted || !_isMotionSyncActive) return;
            final double mag = math.sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z,
            );
            // Sensitive threshold for natural phone movement / walking (0.22 m/s²)
            if (mag > 0.22) {
              _flagPhoneMotionDetected();
            }
          }, onError: (_) {});
    } catch (_) {}

    // 1b. Fallback standard accelerometer listener (deviation from static 1G = 9.80665 m/s²)
    try {
      _rawAccelStreamSub =
          accelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 150),
          ).listen((AccelerometerEvent event) {
            if (!mounted || !_isMotionSyncActive) return;
            final double totalG = math.sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z,
            );
            if ((totalG - 9.80665).abs() > 0.28) {
              _flagPhoneMotionDetected();
            }
          }, onError: (_) {});
    } catch (_) {}

    // 2. Real-time GPS stream listener with motion-based coordinate & calculation updates
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      const settings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );

      _positionStreamSub =
          Geolocator.getPositionStream(locationSettings: settings).listen((
            Position pos,
          ) {
            if (!mounted || !_isMotionSyncActive || _isFetchingGps) return;
            _onLivePositionUpdate(pos);
          }, onError: (_) {});
    } catch (_) {}
  }

  void _stopLiveMotionSync() {
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
    _accelStreamSub?.cancel();
    _accelStreamSub = null;
    _rawAccelStreamSub?.cancel();
    _rawAccelStreamSub = null;
    _stationaryDebounceTimer?.cancel();
    _stationaryDebounceTimer = null;
  }

  void _onLivePositionUpdate(Position pos) {
    if (pos.latitude.isNaN ||
        pos.longitude.isNaN ||
        (pos.latitude == 0.0 && pos.longitude == 0.0)) {
      return;
    }

    final newCoords = GeodeticCoords(
      latitude: pos.latitude,
      longitude: pos.longitude,
      height: pos.altitude,
    );

    // If GPS detects movement speed >= 0.15 m/s (~0.5 km/h walking), flag phone motion
    if (!pos.speed.isNaN && pos.speed >= 0.15) {
      _flagPhoneMotionDetected();
    }

    GeodeticCoords? anchorCoords = _lastStabilizedCoords;
    if (anchorCoords == null) {
      final curLat = double.tryParse(_latController.text);
      final curLng = double.tryParse(_lngController.text);
      if (curLat != null && curLng != null && curLat != 0.0 && curLng != 0.0) {
        anchorCoords = GeodeticCoords(
          latitude: curLat,
          longitude: curLng,
          height: pos.altitude,
        );
      }
    }

    if (anchorCoords != null) {
      final double distMeters = haversineDistance(anchorCoords, newCoords);

      // If displacement exceeds 0.70m, physical user motion is verified
      if (distMeters >= 0.70) {
        _flagPhoneMotionDetected();
      }

      // If phone is completely stationary (no motion detected, no speed, displacement < 0.70m)
      if (!_isPhoneInMotion && distMeters < 0.70) {
        if (!_isStationaryLocked) {
          setState(() {
            _isStationaryLocked = true;
          });
        }
        return; // Suppress sub-meter noise while completely still on a desk
      }
    }

    // Phone is in motion or displacement moved beyond stationary threshold:
    _lastStabilizedCoords = newCoords;

    setState(() {
      // Auto-update latitude and longitude continuously based on phone motion
      _latController.text = newCoords.latitude.toStringAsFixed(6);
      _lngController.text = newCoords.longitude.toStringAsFixed(6);

      // Auto-detect floor level & recalculate elevation offset dynamically based on phone altitude
      final autoDetectedFloor = resolveFloorByHeight(newCoords.height);
      _floorNumber = autoDetectedFloor.floorNumber;
      _activeBaseAltitude = newCoords.height - _floorOffset(_floorNumber);
      _recalculateHeight();
    });
  }

  void _recalculateHeight() {
    final double currentOffset = _floorOffset(_floorNumber);
    final double computedHeight = _activeBaseAltitude + currentOffset;
    _heightController.text = computedHeight.toStringAsFixed(1);
  }

  Future<_GpsConvergenceResult?> _getLiveGpsCoordinates() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'GPS Location service is disabled on device. Please enable location.',
              ),
              backgroundColor: Color(0xFFF59E0B),
            ),
          );
        }
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied.'),
                backgroundColor: Color(0xFFEF4444),
              ),
            );
          }
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission is permanently denied in settings.',
              ),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
        return null;
      }

      // Collect multiple high-accuracy samples for satellite convergence
      final List<Position> collectedSamples = [];
      StreamSubscription<Position>? streamSub;

      try {
        const locationSettings = LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        );

        final completer = Completer<void>();

        streamSub =
            Geolocator.getPositionStream(
              locationSettings: locationSettings,
            ).listen((Position pos) {
              if (!pos.latitude.isNaN &&
                  !pos.longitude.isNaN &&
                  !(pos.latitude == 0.0 && pos.longitude == 0.0)) {
                collectedSamples.add(pos);
                // If we have collected at least 4 samples and reached high precision (<= 3.5m), converge early
                if (collectedSamples.length >= 4 && pos.accuracy <= 3.5) {
                  if (!completer.isCompleted) completer.complete();
                } else if (collectedSamples.length >= 6) {
                  if (!completer.isCompleted) completer.complete();
                }
              }
            }, onError: (_) {});

        // Allow up to 2.4 seconds for satellite convergence
        await Future.any([
          completer.future,
          Future.delayed(const Duration(milliseconds: 2400)),
        ]);
      } catch (_) {
        // Stream fallback below
      } finally {
        await streamSub?.cancel();
      }

      // If stream didn't yield enough fixes, take direct high-accuracy reading as fallback
      if (collectedSamples.isEmpty) {
        try {
          final singleFix = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              timeLimit: Duration(seconds: 4),
            ),
          );
          collectedSamples.add(singleFix);
        } catch (_) {}
      }

      if (collectedSamples.isEmpty) {
        return null;
      }

      // Filter out low-accuracy outliers if better readings exist
      List<Position> validSamples = collectedSamples;
      final hasHighAccuracy = validSamples.any((p) => p.accuracy <= 15.0);
      if (hasHighAccuracy) {
        validSamples = validSamples.where((p) => p.accuracy <= 25.0).toList();
      }
      if (validSamples.isEmpty) {
        validSamples = collectedSamples;
      }

      // Compute inverse-variance weighted average coordinates
      double sumWeights = 0.0;
      double weightedLat = 0.0;
      double weightedLng = 0.0;
      double weightedAlt = 0.0;
      double bestAccuracy = double.infinity;

      for (final p in validSamples) {
        final acc = (p.accuracy.isNaN || p.accuracy <= 0.0) ? 5.0 : p.accuracy;
        final w = 1.0 / (acc * acc);
        sumWeights += w;
        weightedLat += p.latitude * w;
        weightedLng += p.longitude * w;
        final alt = (p.altitude.isNaN || p.altitude.isInfinite)
            ? 45.0
            : p.altitude;
        weightedAlt += alt * w;
        if (acc < bestAccuracy) {
          bestAccuracy = acc;
        }
      }

      if (sumWeights <= 0.0) {
        final p = validSamples.first;
        return _GpsConvergenceResult(
          coords: GeodeticCoords(
            latitude: p.latitude,
            longitude: p.longitude,
            height: p.altitude,
          ),
          accuracy: p.accuracy,
          sampleCount: 1,
        );
      }

      final avgCoords = GeodeticCoords(
        latitude: weightedLat / sumWeights,
        longitude: weightedLng / sumWeights,
        height: weightedAlt / sumWeights,
      );

      return _GpsConvergenceResult(
        coords: avgCoords,
        accuracy: bestAccuracy == double.infinity ? 5.0 : bestAccuracy,
        sampleCount: validSamples.length,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching GPS: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _syncCurrentLocation() async {
    setState(() => _isFetchingGps = true);

    final fixData = await _getLiveGpsCoordinates();

    if (fixData != null && mounted) {
      GeodeticCoords finalCoords = fixData.coords;
      bool isStationary = false;

      // Check existing coordinate anchor (previous sync or form values)
      final currentLat = double.tryParse(_latController.text);
      final currentLng = double.tryParse(_lngController.text);
      GeodeticCoords? anchorCoords = _lastStabilizedCoords;

      if (anchorCoords == null &&
          currentLat != null &&
          currentLng != null &&
          currentLat != 0.0 &&
          currentLng != 0.0) {
        anchorCoords = GeodeticCoords(
          latitude: currentLat,
          longitude: currentLng,
          height: double.tryParse(_heightController.text) ?? finalCoords.height,
        );
      }

      if (anchorCoords != null) {
        final double distMeters = haversineDistance(anchorCoords, finalCoords);

        // STATIONARY NOISE CLAMP & DEADBAND FILTER:
        // When staying at the same place, successive GPS fixes drift by ~0.5m-3.5m due to multipath noise.
        if (distMeters <= 2.2) {
          // Strict lock: preserve the exact coordinates so they never fluctuate at the same spot!
          finalCoords = anchorCoords;
          isStationary = true;
        } else if (distMeters <= 3.8) {
          // Gentle damping: blend 85% anchor + 15% new reading to stabilize drift
          final blendedLat =
              anchorCoords.latitude * 0.85 + finalCoords.latitude * 0.15;
          final blendedLng =
              anchorCoords.longitude * 0.85 + finalCoords.longitude * 0.15;
          finalCoords = GeodeticCoords(
            latitude: blendedLat,
            longitude: blendedLng,
            height: finalCoords.height,
          );
          isStationary = true;
        }
      }

      _lastStabilizedCoords = finalCoords;

      setState(() {
        _latController.text = finalCoords.latitude.toStringAsFixed(6);
        _lngController.text = finalCoords.longitude.toStringAsFixed(6);
        final autoDetectedFloor = resolveFloorByHeight(finalCoords.height);
        _floorNumber = autoDetectedFloor.floorNumber;
        _activeBaseAltitude = finalCoords.height - _floorOffset(_floorNumber);
        _recalculateHeight();
        _isFetchingGps = false;
      });

      if (mounted) {
        final accText = '±${fixData.accuracy.toStringAsFixed(1)}m';
        final statusMessage = isStationary
            ? 'Coordinates locked at same place ($accText precision • Anti-jitter active)'
            : 'Live GPS synchronized: ${_latController.text}, ${_lngController.text} ($accText precision • ${fixData.sampleCount} samples)';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  isStationary
                      ? LucideIcons.shieldCheck
                      : LucideIcons.checkCircle2,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusMessage,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: isStationary
                ? const Color(0xFF0D9488)
                : const Color(0xFF16A34A),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else if (widget.userCoords != null && mounted) {
      setState(() {
        _latController.text = widget.userCoords!.latitude.toStringAsFixed(6);
        _lngController.text = widget.userCoords!.longitude.toStringAsFixed(6);
        final autoDetectedFloor = resolveFloorByHeight(
          widget.userCoords!.height,
        );
        _floorNumber = autoDetectedFloor.floorNumber;
        _activeBaseAltitude =
            widget.userCoords!.height - _floorOffset(_floorNumber);
        _recalculateHeight();
        _isFetchingGps = false;
      });
    } else {
      setState(() => _isFetchingGps = false);
    }
  }

  void _savePoi() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a Store / POI Name.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final isEditing = widget.existingPoi != null;
    final lat =
        double.tryParse(_latController.text) ??
        widget.userCoords?.latitude ??
        0.0;
    final lng =
        double.tryParse(_lngController.text) ??
        widget.userCoords?.longitude ??
        0.0;
    final alt =
        double.tryParse(_heightController.text) ??
        (_activeBaseAltitude + _floorOffset(_floorNumber));

    final newPoi = DestinationPOI(
      id: isEditing
          ? widget.existingPoi!.id
          : 'poi-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      category: _categoryController.text.trim(),
      floorNumber: _floorNumber,
      rating: widget.existingPoi?.rating ?? 4.8,
      openStatus: _statusController.text.trim().isNotEmpty
          ? _statusController.text.trim()
          : 'Open Today: 10 AM - 10 PM',
      description: _descController.text.trim(),
      location: GeodeticCoords(latitude: lat, longitude: lng, height: alt),
      mallId: _selectedMallId.isNotEmpty ? _selectedMallId : null,
    );

    widget.onSavePoi(newPoi, isEditing);
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Store "${newPoi.name}" ${isEditing ? 'updated' : 'created'} successfully!',
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildFormFieldCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextInput({
    required String label,
    required TextEditingController controller,
    String? hintText,
    IconData? prefixIcon,
    int maxLines = 1,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          onChanged: onChanged,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF94A3B8),
              fontSize: 12.5,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: 16, color: const Color(0xFF64748B))
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 12,
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFF2563EB),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingPoi != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        surfaceTintColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Center(
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Icon(
                  LucideIcons.arrowLeft,
                  size: 18,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing ? 'Edit Store / POI' : 'Add New POI Destination',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              isEditing
                  ? 'Update waypoint & 3D floor coordinates'
                  : 'Configure store waypoint in venue',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.x,
                        size: 13,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Cancel',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CARD 1: STORE & CLASSIFICATION DETAILS
            _buildFormFieldCard(
              title: 'STORE & BASIC INFORMATION',
              icon: LucideIcons.store,
              iconColor: const Color(0xFF2563EB),
              children: [
                // Target Mall / Building Selection Dropdown
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Target Mall Name',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF475569),
                          ),
                        ),
                        () {
                          final curMall =
                              _malls
                                  .where((m) => m.id == _selectedMallId)
                                  .firstOrNull ??
                              (_malls.isNotEmpty ? _malls.first : null);
                          if (curMall == null) return const SizedBox.shrink();
                          return Text(
                            '${curMall.floorCount} Floors',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF2563EB),
                            ),
                          );
                        }(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_isLoadingMalls && _malls.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Loading venues from database...',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_malls.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.building,
                              size: 16,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No malls registered in database. Add a venue in Venue Manager.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'mall-dropdown-$_selectedMallId-${_malls.length}',
                        ),
                        initialValue: _malls.any((m) => m.id == _selectedMallId)
                            ? _selectedMallId
                            : _malls.first.id,
                        isExpanded: true,
                        dropdownColor: Colors.white,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            LucideIcons.building,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                        ),
                        items: _malls.map((m) {
                          return DropdownMenuItem<String>(
                            value: m.id,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    m.name.isNotEmpty ? m.name : 'Unnamed Mall',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                if (m.isActive)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'ACTIVE',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF16A34A),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            _onMallChanged(val);
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                _buildTextInput(
                  label: 'Store / POI Name',
                  controller: _nameController,
                  hintText: 'e.g. Apple Store, Zara, Starbucks, Nike',
                  prefixIcon: LucideIcons.store,
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    // Category Dropdown
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Category',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _categoryController.text,
                            isExpanded: true,
                            dropdownColor: Colors.white,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                            ),
                            items: _categories.map((c) {
                              return DropdownMenuItem(
                                value: c,
                                child: Text(c, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _categoryController.text = val;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Floor Level Dropdown (Dynamically adapting to selected mall)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final curMall =
                              _malls
                                  .where((m) => m.id == _selectedMallId)
                                  .firstOrNull ??
                              (_malls.isNotEmpty ? _malls.first : null);
                          final int maxFlr =
                              (curMall != null && curMall.floorCount > 0)
                              ? curMall.floorCount
                              : 5;
                          final List<int> floorOptions = [
                            if (maxFlr >= 3) -2,
                            -1,
                            0,
                            ...List.generate(maxFlr, (i) => i + 1),
                          ];
                          if (!floorOptions.contains(_floorNumber)) {
                            floorOptions.add(_floorNumber);
                          }
                          final uniqueFloors = floorOptions.toSet().toList()
                            ..sort();
                          final int safeSelectedFloor =
                              uniqueFloors.contains(_floorNumber)
                              ? _floorNumber
                              : (uniqueFloors.contains(0)
                                    ? 0
                                    : uniqueFloors.first);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Floor Level',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<int>(
                                key: ValueKey(
                                  'floor-picker-$_selectedMallId-$safeSelectedFloor',
                                ),
                                initialValue: safeSelectedFloor,
                                isExpanded: true,
                                dropdownColor: Colors.white,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF0F172A),
                                ),
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFE2E8F0),
                                    ),
                                  ),
                                ),
                                items: uniqueFloors.map((f) {
                                  return DropdownMenuItem(
                                    value: f,
                                    child: Text(
                                      f < 0
                                          ? 'B${f.abs()}'
                                          : (f == 0
                                                ? 'Ground Floor (0)'
                                                : 'Floor $f'),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _floorNumber = val;
                                      _recalculateHeight();
                                    });
                                  }
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                _buildTextInput(
                  label: 'Description / Navigation Tags',
                  controller: _descController,
                  hintText:
                      'e.g. Ground level south atrium, near main escalators',
                ),
                const SizedBox(height: 14),

                _buildTextInput(
                  label: 'Operating Hours / Status',
                  controller: _statusController,
                  hintText: 'e.g. Open Today: 10 AM - 10 PM',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // CARD 2: GEODETIC 3D POSITIONING (WGS84)
            _buildFormFieldCard(
              title: 'GEODETIC POSITIONING (WGS84)',
              icon: LucideIcons.mapPin,
              iconColor: const Color(0xFF16A34A),
              children: [
                // Quick Picker & GPS sync Actions
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AdminOSMMapScreen(
                                userCoords:
                                    widget.userCoords ??
                                    const GeodeticCoords(
                                      latitude: 0.0,
                                      longitude: 0.0,
                                      height: 0.0,
                                    ),
                                destinations: widget.destinations,
                                isPickerMode: true,
                                onSelectCoordinates: (coords) {
                                  setState(() {
                                    _latController.text = coords.latitude
                                        .toStringAsFixed(6);
                                    _lngController.text = coords.longitude
                                        .toStringAsFixed(6);
                                  });
                                },
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                LucideIcons.map,
                                size: 14,
                                color: Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  'PICK ON MAP',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF16A34A),
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: _isFetchingGps ? null : _syncCurrentLocation,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isFetchingGps)
                                const Padding(
                                  padding: EdgeInsets.only(right: 5.0),
                                  child: SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                )
                              else ...[
                                const Icon(
                                  LucideIcons.navigation,
                                  size: 14,
                                  color: Color(0xFF2563EB),
                                ),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text(
                                  _isFetchingGps
                                      ? 'SAMPLING GPS...'
                                      : 'SYNC LIVE GPS',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF2563EB),
                                    letterSpacing: 0.2,
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
                const SizedBox(height: 16),

                // 3 Coordinate Inputs
                Row(
                  children: [
                    Expanded(
                      child: _buildTextInput(
                        label: 'Latitude (°N)',
                        controller: _latController,
                        hintText: '8.502424',
                        onChanged: (_) {
                          _lastStabilizedCoords = null;
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildTextInput(
                        label: 'Longitude (°E)',
                        controller: _lngController,
                        hintText: '81.181251',
                        onChanged: (_) {
                          _lastStabilizedCoords = null;
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildTextInput(
                        label: 'WGS84 Alt (m)',
                        controller: _heightController,
                        hintText: '-84.6',
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null) {
                            setState(() {
                              _activeBaseAltitude =
                                  parsed - _floorOffset(_floorNumber);
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
          border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: _savePoi,
          icon: Icon(
            isEditing ? LucideIcons.check : LucideIcons.plus,
            size: 18,
          ),
          label: Text(
            isEditing ? 'SAVE CHANGES' : 'CREATE POI DESTINATION',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
