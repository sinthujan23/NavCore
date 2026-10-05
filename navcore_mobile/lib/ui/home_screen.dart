import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/destinations.dart';
import '../data/parking_service.dart';
import '../engine/ecef_engine.dart';
import '../engine/floor_tracker.dart';
import '../engine/bearing_engine.dart';
import 'shop_details_screen.dart';
import 'widgets/shop_image_widget.dart';
import 'widgets/nexnav_logo_widget.dart';

class HomeScreen extends StatefulWidget {
  final GeodeticCoords userCoords;
  final BuildingElevationProfile buildingProfile;
  final List<DestinationPOI> destinations;
  final VoidCallback onOpenARView;
  final VoidCallback onOpenFloorMap;
  final VoidCallback onOpenMallExplorer;
  final ValueChanged<DestinationPOI> onSelectDestination;
  final String userEmail;
  final VoidCallback? onLogout;

  const HomeScreen({
    super.key,
    required this.userCoords,
    required this.buildingProfile,
    required this.destinations,
    required this.onOpenARView,
    required this.onOpenFloorMap,
    required this.onOpenMallExplorer,
    required this.onSelectDestination,
    this.userEmail = '',
    this.onLogout,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _parkedCardAnimController;

  String _selectedCategory = 'ALL';
  int? _selectedFloorNumber; // null = All Floors
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, dynamic>> _categories = [
    {'label': 'ALL', 'icon': LucideIcons.layoutGrid},
    {'label': 'FOOD & DRINK', 'icon': LucideIcons.utensils},
    {'label': 'TECH & ELECTRONICS', 'icon': LucideIcons.smartphone},
    {'label': 'RETAIL & FASHION', 'icon': LucideIcons.shoppingBag},
    {'label': 'ENTERTAINMENT', 'icon': LucideIcons.gamepad2},
    {'label': 'SERVICES', 'icon': LucideIcons.shieldCheck},
  ];

  final ParkingService _parkingService = ParkingService();

  @override
  void initState() {
    super.initState();
    _parkingService.addListener(_onParkingChanged);

    _parkedCardAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _parkingService.removeListener(_onParkingChanged);
    _parkedCardAnimController.dispose();
    super.dispose();
  }

  void _onParkingChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _clearAllFilters() {
    setState(() {
      _selectedCategory = 'ALL';
      _selectedFloorNumber = null;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  Widget _buildFloorDropdown(FloorLevelConfig currentFloor) {
    final isMyFloorSelected = _selectedFloorNumber == currentFloor.floorNumber;
    final isAllFloorsSelected = _selectedFloorNumber == null;

    String floorLabelText = 'All Floors';
    if (isMyFloorSelected) {
      floorLabelText = currentFloor.floorNumber < 0
          ? 'My Floor (B${currentFloor.floorNumber.abs()})'
          : 'My Floor (F${currentFloor.floorNumber})';
    } else if (_selectedFloorNumber != null) {
      floorLabelText = _selectedFloorNumber! < 0
          ? 'Floor B${_selectedFloorNumber!.abs()}'
          : 'Floor F$_selectedFloorNumber';
    }

    return PopupMenuButton<int?>(
      initialValue: _selectedFloorNumber,
      onSelected: (int? value) {
        setState(() {
          _selectedFloorNumber = value;
        });
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMyFloorSelected
              ? const Color(0xFFECFDF5)
              : isAllFloorsSelected
              ? Colors.white
              : const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMyFloorSelected
                ? const Color(0xFFA7F3D0)
                : isAllFloorsSelected
                ? const Color(0xFFE2E8F0)
                : const Color(0xFFBFDBFE),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(
                    isMyFloorSelected
                        ? LucideIcons.mapPin
                        : isAllFloorsSelected
                        ? LucideIcons.layers
                        : LucideIcons.building,
                    size: 15,
                    color: isMyFloorSelected
                        ? const Color(0xFF059669)
                        : isAllFloorsSelected
                        ? const Color(0xFF64748B)
                        : const Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      floorLabelText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isMyFloorSelected
                            ? const Color(0xFF065F46)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronDown,
              size: 15,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<int?>>[
        PopupMenuItem<int?>(
          value: null,
          child: Row(
            children: [
              Icon(
                LucideIcons.layers,
                size: 16,
                color: _selectedFloorNumber == null
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF64748B),
              ),
              const SizedBox(width: 10),
              const Text(
                'All Floors',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              if (_selectedFloorNumber == null) ...[
                const Spacer(),
                const Icon(
                  LucideIcons.check,
                  size: 16,
                  color: Color(0xFF2563EB),
                ),
              ],
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<int?>(
          value: currentFloor.floorNumber,
          child: Row(
            children: [
              const Icon(
                LucideIcons.mapPin,
                size: 16,
                color: Color(0xFF10B981),
              ),
              const SizedBox(width: 10),
              Text(
                currentFloor.floorNumber < 0
                    ? 'My Floor (B${currentFloor.floorNumber.abs()})'
                    : 'My Floor (F${currentFloor.floorNumber})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF065F46),
                ),
              ),
              if (_selectedFloorNumber == currentFloor.floorNumber) ...[
                const Spacer(),
                const Icon(
                  LucideIcons.check,
                  size: 16,
                  color: Color(0xFF10B981),
                ),
              ],
            ],
          ),
        ),
        const PopupMenuDivider(),
        ...widget.buildingProfile.floors.map((floor) {
          String floorLabelSimple;
          if (floor.floorNumber < 0) {
            floorLabelSimple = 'Floor B${floor.floorNumber.abs()} (Basement)';
          } else if (floor.floorNumber == 1) {
            floorLabelSimple = 'Floor F1 (Ground Floor)';
          } else {
            floorLabelSimple = 'Floor F${floor.floorNumber}';
          }

          final isSelected = _selectedFloorNumber == floor.floorNumber;
          return PopupMenuItem<int?>(
            value: floor.floorNumber,
            child: Row(
              children: [
                Icon(
                  LucideIcons.building,
                  size: 16,
                  color: isSelected
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 10),
                Text(
                  floorLabelSimple,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  const Icon(
                    LucideIcons.check,
                    size: 16,
                    color: Color(0xFF2563EB),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCategoryDropdown() {
    final currentCategoryItem = _categories.firstWhere(
      (cat) => cat['label'] == _selectedCategory,
      orElse: () => _categories.first,
    );

    return PopupMenuButton<String>(
      initialValue: _selectedCategory,
      onSelected: (String value) {
        setState(() {
          _selectedCategory = value;
        });
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _selectedCategory != 'ALL'
              ? const Color(0xFFEFF6FF)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _selectedCategory != 'ALL'
                ? const Color(0xFFBFDBFE)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(
                    currentCategoryItem['icon'] as IconData,
                    size: 15,
                    color: _selectedCategory != 'ALL'
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      _selectedCategory == 'ALL'
                          ? 'All Categories'
                          : _selectedCategory,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _selectedCategory != 'ALL'
                            ? const Color(0xFF1E40AF)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronDown,
              size: 15,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
      itemBuilder: (BuildContext context) => _categories.map((cat) {
        final isSelected = _selectedCategory == cat['label'];
        final String labelText = cat['label'] == 'ALL'
            ? 'All Categories'
            : cat['label'];
        return PopupMenuItem<String>(
          value: cat['label'],
          child: Row(
            children: [
              Icon(
                cat['icon'] as IconData,
                size: 16,
                color: isSelected
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF64748B),
              ),
              const SizedBox(width: 10),
              Text(
                labelText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                const Icon(
                  LucideIcons.check,
                  size: 16,
                  color: Color(0xFF2563EB),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActiveFiltersRow() {
    final bool hasActiveFilters =
        _selectedCategory != 'ALL' ||
        _selectedFloorNumber != null ||
        _searchQuery.isNotEmpty;

    if (!hasActiveFilters) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Active:',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            _buildFilterChip('Search: "$_searchQuery"', () {
              setState(() {
                _searchQuery = '';
                _searchController.clear();
              });
            }),
          if (_selectedCategory != 'ALL')
            _buildFilterChip(_selectedCategory, () {
              setState(() => _selectedCategory = 'ALL');
            }),
          if (_selectedFloorNumber != null)
            _buildFilterChip(
              _selectedFloorNumber! < 0
                  ? 'Floor B${_selectedFloorNumber!.abs()}'
                  : 'Floor F$_selectedFloorNumber',
              () => setState(() => _selectedFloorNumber = null),
            ),
          GestureDetector(
            onTap: _clearAllFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: const Text(
                'Clear All',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFDC2626),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D4ED8),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              LucideIcons.x,
              size: 13,
              color: Color(0xFF2563EB),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealWorldStoreCard(
    DestinationPOI shop,
    double dist,
    FloorLevelConfig currentFloor,
  ) {
    final isMyFloor = shop.floorNumber == currentFloor.floorNumber;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isMyFloor
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : const Color(0xFFE2E8F0),
          width: isMyFloor ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isMyFloor
                ? const Color(0xFF10B981).withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showShopDetails(shop),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Store Photo Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ShopImage(
                    imagePathOrUrl: shop.effectiveImageUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 14),

                // Store Title & Distance Only
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        shop.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.navigation,
                            size: 11,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${dist.toStringAsFixed(0)}m away',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: Color(0xFFCBD5E1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showShopDetails(DestinationPOI shop) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ShopDetailsScreen(
        destination: shop,
        userCoords: widget.userCoords,
        onStartARNavigation: () {
          Navigator.pop(context);
          widget.onSelectDestination(shop);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeMallAnchor = widget.destinations.isNotEmpty
        ? widget.destinations.first.location
        : entranceAnchor;
    final effectiveCoords = getEffectiveUserCoords(
      widget.userCoords,
      activeMallAnchor,
    );
    final currentFloor = resolveFloorByHeight(
      effectiveCoords.height,
      widget.buildingProfile,
    );

    final filteredPOIs = widget.destinations.where((poi) {
      final matchesCategory =
          _selectedCategory == 'ALL' ||
          poi.category.toUpperCase() == _selectedCategory;
      final matchesSearch =
          _searchQuery.isEmpty ||
          poi.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          poi.category.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          poi.description.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesFloor =
          _selectedFloorNumber == null ||
          poi.floorNumber == _selectedFloorNumber;
      return matchesCategory && matchesSearch && matchesFloor;
    }).toList();

    filteredPOIs.sort((a, b) {
      final distA = calculateAccurate3DDistance(
        effectiveCoords,
        a.location,
        userFloorNumber: currentFloor.floorNumber,
        targetFloorNumber: a.floorNumber,
      );
      final distB = calculateAccurate3DDistance(
        effectiveCoords,
        b.location,
        userFloorNumber: currentFloor.floorNumber,
        targetFloorNumber: b.floorNumber,
      );
      return distA.compareTo(distB);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Top App Bar & Live Location Display Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar Header
                    Row(
                      children: [
                        const NexNavLogoWidget(size: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'NexNav',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        if (widget.onLogout != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: widget.onLogout,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFBFDBFE),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x14000000),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    LucideIcons.userCheck,
                                    size: 13,
                                    color: Color(0xFF2563EB),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    widget.userEmail.isNotEmpty
                                        ? widget.userEmail.split('@').first
                                        : 'User',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  const Icon(
                                    LucideIcons.logOut,
                                    size: 13,
                                    color: Color(0xFFEF4444),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    if (_parkingService.hasParkedVehicle)
                      _buildParkedVehicleHomeCard(
                        _parkingService.currentVehicleLocation!,
                      ),
                  ],
                ),
              ),
            ),

            // Active Mall Hero Banner Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF0F172A),
                        Color(0xFF1E3A8A),
                        Color(0xFF1E293B),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x661C2541),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Color(0x223B82F6),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Background Ambient Glow Accent
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _AmbientGlowPainter(
                            glowColor: const Color(
                              0xFF3B82F6,
                            ).withValues(alpha: 0.15),
                            accentColor: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 5.5,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF1E40AF),
                                        Color(0xFF1E3A8A),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF60A5FA,
                                      ).withValues(alpha: 0.5),
                                      width: 1,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x331E40AF),
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _LiveStatusPulseDot(
                                        color: Color(0xFF10B981),
                                        size: 6.5,
                                      ),
                                      SizedBox(width: 7),
                                      Text(
                                        'CURRENT MALL',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 5.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF0F172A,
                                    ).withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF3B82F6,
                                      ).withValues(alpha: 0.4),
                                      width: 1,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x333B82F6),
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _LiveStatusPulseDot(
                                        color: Color(0xFF3B82F6),
                                        size: 6.0,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        ' AR READY',
                                        style: TextStyle(
                                          color: Color(0xFF60A5FA),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              widget.buildingProfile.name,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(13),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF2563EB),
                                          Color(0xFF0284C7),
                                        ],
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x552563EB),
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                        ),
                                      ),
                                      onPressed: widget.onOpenARView,
                                      icon: const Icon(
                                        LucideIcons.camera,
                                        size: 15,
                                        color: Colors.white,
                                      ),
                                      label: const Text(
                                        'Camera View',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: const Color(
                                        0xFF1E293B,
                                      ).withValues(alpha: 0.6),
                                      foregroundColor: Colors.white,
                                      side: BorderSide(
                                        color: const Color(
                                          0xFF60A5FA,
                                        ).withValues(alpha: 0.5),
                                        width: 1.2,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                    ),
                                    onPressed: widget.onOpenFloorMap,
                                    icon: const Icon(
                                      LucideIcons.map,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      'Interactive Map',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: Colors.white,
                                      ),
                                    ),
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
              ),
            ),

            // Destinations & Stores Section Header with Selection Dropdowns & Filter Controls
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'Destinations & Stores',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFBFDBFE),
                                  ),
                                ),
                                child: Text(
                                  '${filteredPOIs.length}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Dropdowns Bar (Floor & Category)
                    Row(
                      children: [
                        Expanded(child: _buildFloorDropdown(currentFloor)),
                        const SizedBox(width: 10),
                        Expanded(child: _buildCategoryDropdown()),
                      ],
                    ),
                    _buildActiveFiltersRow(),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            if (filteredPOIs.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          LucideIcons.store,
                          size: 36,
                          color: Color(0xFF94A3B8),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No stores match your filters',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Try resetting search, selecting "All Floors", or another category',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _clearAllFilters,
                          icon: const Icon(LucideIcons.refreshCw, size: 14),
                          label: const Text('Reset All Filters'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Real-World Mall Store Directory Feed
            if (filteredPOIs.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final shop = filteredPOIs[index];
                    final dist = calculateAccurate3DDistance(
                      effectiveCoords,
                      shop.location,
                      userFloorNumber: currentFloor.floorNumber,
                      targetFloorNumber: shop.floorNumber,
                    );
                    return _buildRealWorldStoreCard(shop, dist, currentFloor);
                  }, childCount: filteredPOIs.length),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildParkedVehicleHomeCard(MyVehicleLocation vehicle) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F1D36)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x661E1B4B),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
          BoxShadow(color: Color(0x226366F1), blurRadius: 10, spreadRadius: 1),
        ],
      ),
      child: Stack(
        children: [
          // Background Ambient Glow Accent
          Positioned.fill(
            child: CustomPaint(
              painter: _AmbientGlowPainter(
                glowColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
                accentColor: const Color(0xFF38BDF8).withValues(alpha: 0.12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.car, color: Colors.black, size: 13),
                          SizedBox(width: 6),
                          Text(
                            'MY PARKED CAR',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LiveStatusPulseDot(
                            color: Color(0xFF10B981),
                            size: 6.5,
                          ),
                          SizedBox(width: 7),
                          Text(
                            'PARKED',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Parked at ${vehicle.slotId} • Floor ${vehicle.floorId}',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 14),
                // Custom Content-Suited Parking Sonar Radar Graphic Animation
                SizedBox(
                  height: 38,
                  width: double.infinity,
                  child: AnimatedBuilder(
                    animation: _parkedCardAnimController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _ParkedVehicleSonarPainter(
                          animationValue: _parkedCardAnimController.value,
                          slotId: vehicle.slotId,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(13),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          icon: const Icon(
                            LucideIcons.navigation,
                            size: 15,
                            color: Colors.black,
                          ),
                          label: Text(
                            'Find My Car',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          onPressed: () {
                            final int floorNum = vehicle.floorId.contains('B2')
                                ? -2
                                : -1;
                            final poi = DestinationPOI(
                              id: vehicle.slotId,
                              name: 'My Parked Car (${vehicle.slotId})',
                              category: 'PARKING',
                              floorNumber: floorNum,
                              rating: 5.0,
                              location: vehicle.location,
                              description: 'Your saved vehicle location',
                              openStatus: '24/7',
                            );
                            widget.onSelectDestination(poi);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: OutlinedButton.icon(
                        icon: const Icon(
                          LucideIcons.layers,
                          size: 15,
                          color: Colors.white,
                        ),
                        label: Text(
                          'Floor Map',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(
                            0xFF1E293B,
                          ).withValues(alpha: 0.6),
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: const Color(
                              0xFF818CF8,
                            ).withValues(alpha: 0.5),
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        onPressed: widget.onOpenFloorMap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveStatusPulseDot extends StatefulWidget {
  final Color color;
  final double size;

  const _LiveStatusPulseDot({required this.color, this.size = 6.0});

  @override
  State<_LiveStatusPulseDot> createState() => _LiveStatusPulseDotState();
}

class _LiveStatusPulseDotState extends State<_LiveStatusPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: 1.0 + (progress * 1.8),
              child: Opacity(
                opacity: (1.0 - progress).clamp(0.0, 1.0),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.8),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ParkedVehicleSonarPainter extends CustomPainter {
  final double animationValue;
  final String slotId;

  _ParkedVehicleSonarPainter({
    required this.animationValue,
    required this.slotId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final startX = 24.0;
    final endX = size.width - 24.0;
    final centerY = size.height / 2;

    final linePaint = Paint()
      ..color = const Color(0xFF818CF8).withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final double dashWidth = 5.0;
    final double dashSpace = 4.0;
    double currentX = startX + 16;
    final targetX = endX - 16;

    while (currentX < targetX) {
      canvas.drawLine(
        Offset(currentX, centerY),
        Offset(math.min(currentX + dashWidth, targetX), centerY),
        linePaint,
      );
      currentX += dashWidth + dashSpace;
    }

    // Concentric Sonar Radar Pulse Arcs emitting from car icon
    for (int i = 0; i < 3; i++) {
      final pulseProgress = (animationValue + (i * 0.33)) % 1.0;
      final radius = 6.0 + (pulseProgress * 18.0);
      final opacity = (1.0 - pulseProgress).clamp(0.0, 1.0) * 0.6;

      final sonarPaint = Paint()
        ..color = const Color(0xFF818CF8).withValues(alpha: opacity)
        ..strokeWidth = 1.3
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(Offset(startX, centerY), radius, sonarPaint);
    }

    // Signal Dots traveling along the radar path from car to stall
    final pathLength = targetX - (startX + 16);
    for (int i = 0; i < 2; i++) {
      final signalProgress = (animationValue + (i * 0.5)) % 1.0;
      final signalX = (startX + 16) + (pathLength * signalProgress);

      final signalPaint = Paint()
        ..color = const Color(0xFF38BDF8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(signalX, centerY), 2.8, signalPaint);

      final signalHaloPaint = Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(signalX, centerY), 6.0, signalHaloPaint);
    }

    // Pulse ring around target stall pin
    final targetPulse = (animationValue * 1.5) % 1.0;
    final targetRadius = 6.0 + (targetPulse * 10.0);
    final targetOpacity = (1.0 - targetPulse).clamp(0.0, 1.0) * 0.5;
    final targetPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: targetOpacity)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(Offset(endX, centerY), targetRadius, targetPaint);
  }

  @override
  bool shouldRepaint(covariant _ParkedVehicleSonarPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.slotId != slotId;
  }
}

class _AmbientGlowPainter extends CustomPainter {
  final Color glowColor;
  final Color accentColor;

  _AmbientGlowPainter({required this.glowColor, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [glowColor, glowColor.withValues(alpha: 0)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.85, size.height * 0.2),
              radius: size.width * 0.5,
            ),
          );

    final accentGlowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [accentColor, accentColor.withValues(alpha: 0)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.15, size.height * 0.8),
              radius: size.width * 0.45,
            ),
          );

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), glowPaint);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      accentGlowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AmbientGlowPainter oldDelegate) => false;
}
