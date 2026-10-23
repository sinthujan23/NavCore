import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/destinations.dart';
import '../data/mall_database_service.dart';
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
  final MallMetadata? activeMall;
  final VoidCallback onOpenARView;
  final VoidCallback onOpenFloorMap;
  final VoidCallback onOpenMallExplorer;
  final ValueChanged<DestinationPOI> onSelectDestination;
  final String userEmail;
  final VoidCallback? onLogout;
  final Future<void> Function()? onRefresh;
  final bool isAdmin;
  final VoidCallback? onOpenAdminDashboard;
  final VoidCallback? onSignIn;

  const HomeScreen({
    super.key,
    required this.userCoords,
    required this.buildingProfile,
    required this.destinations,
    this.activeMall,
    required this.onOpenARView,
    required this.onOpenFloorMap,
    required this.onOpenMallExplorer,
    required this.onSelectDestination,
    this.userEmail = '',
    this.onLogout,
    this.onRefresh,
    this.isAdmin = false,
    this.onOpenAdminDashboard,
    this.onSignIn,
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
    _prewarmImages();
    _parkingService.addListener(_onParkingChanged);

    _parkedCardAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.destinations != oldWidget.destinations) {
      _prewarmImages();
    }
  }

  void _prewarmImages() {
    if (widget.destinations.isNotEmpty) {
      ShopImage.prewarm(widget.destinations.map((d) => d.effectiveImageUrl));
    }
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

  bool get _isMallActiveAndWithin500m {
    if (widget.buildingProfile.buildingId.isEmpty ||
        widget.buildingProfile.floors.isEmpty) {
      return false;
    }
    return true;
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

    const int allFloorsSentinel = -999999;

    return PopupMenuButton<int>(
      initialValue: _selectedFloorNumber ?? allFloorsSentinel,
      onSelected: (int value) {
        setState(() {
          _selectedFloorNumber = value == allFloorsSentinel ? null : value;
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
      itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
        PopupMenuItem<int>(
          value: allFloorsSentinel,
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
        ...widget.buildingProfile.floors.map((floor) {
          final isCurrentFloor = floor.floorNumber == currentFloor.floorNumber;
          final isSelected = _selectedFloorNumber == floor.floorNumber;

          String floorLabelSimple;
          if (floor.floorId.toUpperCase().startsWith('P') ||
              floor.name.toUpperCase().contains('PARK')) {
            floorLabelSimple = isCurrentFloor
                ? 'My Floor (Parking P)'
                : 'Parking Floor (P)';
          } else if (floor.floorNumber < 0) {
            floorLabelSimple = isCurrentFloor
                ? 'My Floor (B${floor.floorNumber.abs()})'
                : 'Floor B${floor.floorNumber.abs()} (Basement)';
          } else if (floor.floorNumber == 1) {
            floorLabelSimple = isCurrentFloor
                ? 'My Floor (F1)'
                : 'Floor F1 (Ground Floor)';
          } else {
            floorLabelSimple = isCurrentFloor
                ? 'My Floor (F${floor.floorNumber})'
                : 'Floor F${floor.floorNumber}';
          }

          return PopupMenuItem<int>(
            value: floor.floorNumber,
            child: Row(
              children: [
                Icon(
                  isCurrentFloor ? LucideIcons.mapPin : LucideIcons.building,
                  size: 16,
                  color: isSelected
                      ? const Color(0xFF2563EB)
                      : (isCurrentFloor
                            ? const Color(0xFF10B981)
                            : const Color(0xFF64748B)),
                ),
                const SizedBox(width: 10),
                Text(
                  floorLabelSimple,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected || isCurrentFloor
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: isCurrentFloor && !isSelected
                        ? const Color(0xFF065F46)
                        : null,
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: isMyFloor
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              shop.floorNumber < 0
                                  ? 'B${shop.floorNumber.abs()}'
                                  : (shop.floorNumber == 0
                                        ? 'Ground'
                                        : 'Floor ${shop.floorNumber}'),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: isMyFloor
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFF475569),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            LucideIcons.navigation,
                            size: 11,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 3),
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShopDetailsScreen(
          destination: shop,
          userCoords: widget.userCoords,
          onStartARNavigation: () {
            Navigator.pop(context);
            widget.onSelectDestination(shop);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeMallAnchor =
        (widget.activeMall != null && widget.activeMall!.latitude != 0.0)
        ? GeodeticCoords(
            latitude: widget.activeMall!.latitude,
            longitude: widget.activeMall!.longitude,
            height: widget.activeMall!.entranceBaseAnchorHeight > 0
                ? widget.activeMall!.entranceBaseAnchorHeight
                : widget.userCoords.height,
          )
        : (widget.destinations.isNotEmpty
              ? widget.destinations.first.location
              : widget.userCoords);
    final effectiveCoords = getEffectiveUserCoords(
      widget.userCoords,
      activeMallAnchor,
    );
    final currentFloor = widget.buildingProfile.floors.isNotEmpty
        ? widget.buildingProfile.floors.firstWhere(
            (f) =>
                f.floorNumber ==
                resolveFloorByHeight(
                  effectiveCoords.height,
                  widget.buildingProfile,
                ).floorNumber,
            orElse: () => resolveFloorByHeight(
              effectiveCoords.height,
              widget.buildingProfile,
            ),
          )
        : resolveFloorByHeight(effectiveCoords.height, widget.buildingProfile);

    final filteredPOIs = _isMallActiveAndWithin500m
        ? widget.destinations.where((poi) {
            // Strictly match POIs to the active mall (handling '1' vs '01' format)
            if (widget.activeMall != null &&
                poi.mallId != null &&
                poi.mallId!.isNotEmpty) {
              final cleanPoiMall = poi.mallId!.trim().toLowerCase().replaceAll(
                RegExp(r'^0+'),
                '',
              );
              final cleanActiveMall = widget.activeMall!.id
                  .trim()
                  .toLowerCase()
                  .replaceAll(RegExp(r'^0+'), '');
              if (cleanPoiMall != cleanActiveMall &&
                  poi.mallId!.trim().toLowerCase() !=
                      widget.activeMall!.id.trim().toLowerCase()) {
                return false;
              }
            }
            // Strictly exclude parking stalls from retail shops directory
            if (ParkingService.isParkingDestination(poi)) {
              return false;
            }
            final matchesCategory =
                _selectedCategory == 'ALL' ||
                poi.category.toUpperCase() == _selectedCategory;
            final matchesSearch =
                _searchQuery.isEmpty ||
                poi.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                poi.category.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                poi.description.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                );
            final matchesFloor =
                _selectedFloorNumber == null ||
                poi.floorNumber == _selectedFloorNumber;
            return matchesCategory && matchesSearch && matchesFloor;
          }).toList()
        : <DestinationPOI>[];

    if (filteredPOIs.length > 1) {
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
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: widget.onRefresh ?? () async {},
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Top App Bar & Live Location Display Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Bar Header
                      Row(
                        children: [
                          const NexNavLogoWidget(size: 34),
                          const SizedBox(width: 8),
                          Text(
                            'NexNav',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const Spacer(),
                          if (widget.isAdmin && widget.onOpenAdminDashboard != null) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: widget.onOpenAdminDashboard,
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF1E293B),
                                    width: 1,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x240F172A),
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      LucideIcons.shieldCheck,
                                      size: 13,
                                      color: Color(0xFF38BDF8),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'ADMIN PORTAL',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (widget.onSignIn != null) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: widget.onSignIn,
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
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
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      LucideIcons.logIn,
                                      size: 13,
                                      color: Color(0xFF2563EB),
                                    ),
                                    const SizedBox(width: 4),
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
                          if (widget.onLogout != null) ...[
                            const SizedBox(width: 6),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: widget.onLogout,
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  height: 32,
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    3,
                                    6,
                                    3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                      width: 1.2,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x0F000000),
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFF2563EB),
                                              Color(0xFF1D4ED8),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            (widget.userEmail.isNotEmpty
                                                    ? widget.userEmail
                                                          .split('@')
                                                          .first[0]
                                                    : 'U')
                                                .toUpperCase(),
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: widget.isAdmin ? 48 : 80,
                                        ),
                                        child: Text(
                                          widget.userEmail.isNotEmpty
                                              ? '${widget.userEmail.split('@').first[0].toUpperCase()}${widget.userEmail.split('@').first.substring(1)}'
                                              : 'User',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF2F2),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(0xFFFEE2E2),
                                          ),
                                        ),
                                        child: const Center(
                                          child: Icon(
                                            LucideIcons.logOut,
                                            size: 11,
                                            color: Color(0xFFEF4444),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                      if (_parkingService.hasParkedVehicle &&
                          _isMallActiveAndWithin500m)
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
                                0xFF0284C7,
                              ).withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Builder(
                                builder: (context) {
                                  final bool isMallLoaded =
                                      _isMallActiveAndWithin500m;
                                  return Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 11,
                                          vertical: 5.5,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: isMallLoaded
                                                ? const [
                                                    Color(0xFF1E40AF),
                                                    Color(0xFF1E3A8A),
                                                  ]
                                                : const [
                                                    Color(0xFFB45309),
                                                    Color(0xFF92400E),
                                                  ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: isMallLoaded
                                                ? const Color(
                                                    0xFF60A5FA,
                                                  ).withValues(alpha: 0.5)
                                                : const Color(
                                                    0xFFFBBF24,
                                                  ).withValues(alpha: 0.5),
                                            width: 1,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: isMallLoaded
                                                  ? const Color(0x331E40AF)
                                                  : const Color(0x33B45309),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              isMallLoaded
                                                  ? 'CURRENT VENUE'
                                                  : 'NO VENUE LOADED',
                                              style: const TextStyle(
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
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: isMallLoaded
                                                ? const Color(
                                                    0xFF3B82F6,
                                                  ).withValues(alpha: 0.4)
                                                : const Color(
                                                    0xFFF59E0B,
                                                  ).withValues(alpha: 0.4),
                                            width: 1,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: isMallLoaded
                                                  ? const Color(0x333B82F6)
                                                  : const Color(0x33F59E0B),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              isMallLoaded
                                                  ? 'AR READY'
                                                  : 'OUTSIDE COVERAGE',
                                              style: TextStyle(
                                                color: isMallLoaded
                                                    ? const Color(0xFF60A5FA)
                                                    : const Color(0xFFFBBF24),
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _isMallActiveAndWithin500m &&
                                        widget.buildingProfile.name.isNotEmpty
                                    ? widget.buildingProfile.name
                                    : (widget.activeMall?.name ??
                                          'Outside Mall Coverage Area'),
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Builder(
                                builder: (context) {
                                  final bool isMallLoaded =
                                      _isMallActiveAndWithin500m;
                                  if (!isMallLoaded) {
                                    return Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFFB45309,
                                            ).withValues(alpha: 0.25),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: const Color(
                                                0xFFFBBF24,
                                              ).withValues(alpha: 0.5),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                LucideIcons.radar,
                                                size: 11,
                                                color: Color(0xFFFBBF24),
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                'Select a venue package from mall explorer',
                                                style:
                                                    GoogleFonts.plusJakartaSans(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors.white,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                  final distM = haversineDistance(
                                    widget.userCoords,
                                    activeMallAnchor,
                                  );
                                  final isInside = distM < 80.0;
                                  final isWithin500m = distM <= 500.0;
                                  return Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isInside
                                              ? const Color(
                                                  0xFF0284C7,
                                                ).withValues(alpha: 0.28)
                                              : (isWithin500m
                                                    ? const Color(
                                                        0xFF1D4ED8,
                                                      ).withValues(alpha: 0.25)
                                                    : const Color(
                                                        0xFF3B82F6,
                                                      ).withValues(
                                                        alpha: 0.15,
                                                      )),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: isInside
                                                ? const Color(
                                                    0xFF38BDF8,
                                                  ).withValues(alpha: 0.6)
                                                : (isWithin500m
                                                      ? const Color(
                                                          0xFF60A5FA,
                                                        ).withValues(alpha: 0.5)
                                                      : const Color(
                                                          0xFF60A5FA,
                                                        ).withValues(
                                                          alpha: 0.35,
                                                        )),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isInside
                                                  ? LucideIcons.mapPin
                                                  : (isWithin500m
                                                        ? LucideIcons.radar
                                                        : LucideIcons
                                                              .navigation),
                                              size: 11,
                                              color: isInside
                                                  ? const Color(0xFF38BDF8)
                                                  : (isWithin500m
                                                        ? const Color(
                                                            0xFF93C5FD,
                                                          )
                                                        : const Color(
                                                            0xFF93C5FD,
                                                          )),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              isInside
                                                  ? 'Inside Venue'
                                                  : (isWithin500m
                                                        ? 'Within 500m (${distM.toInt()}m)'
                                                        : '${(distM / 1000).toStringAsFixed(1)}km away'),
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              Builder(
                                builder: (context) {
                                  final bool isMallLoaded =
                                      _isMallActiveAndWithin500m;
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              13,
                                            ),
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
                                              backgroundColor:
                                                  Colors.transparent,
                                              shadowColor: Colors.transparent,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(13),
                                              ),
                                            ),
                                            onPressed: isMallLoaded
                                                ? widget.onOpenARView
                                                : widget.onOpenMallExplorer,
                                            icon: Icon(
                                              isMallLoaded
                                                  ? LucideIcons.camera
                                                  : LucideIcons.globe,
                                              size: 15,
                                              color: Colors.white,
                                            ),
                                            label: Text(
                                              isMallLoaded
                                                  ? 'Camera View'
                                                  : 'Explore Malls',
                                              style: const TextStyle(
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
                                              borderRadius:
                                                  BorderRadius.circular(13),
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
                                  );
                                },
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
              if (_isMallActiveAndWithin500m)
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
                      ],
                    ),
                  ),
                ),

              if (_isMallActiveAndWithin500m)
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
                      child: Builder(
                        builder: (context) {
                          final bool isNoMall = !_isMallActiveAndWithin500m;
                          if (isNoMall) {
                            final bool hasBuilding =
                                widget.buildingProfile.buildingId.isNotEmpty;
                            return Column(
                              children: [
                                Icon(
                                  hasBuilding
                                      ? LucideIcons.radar
                                      : LucideIcons.building2,
                                  size: 36,
                                  color: const Color(0xFFF59E0B),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  hasBuilding
                                      ? 'No Mall Within 500m'
                                      : 'No Active Venue Selected',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  hasBuilding
                                      ? 'Indoor store maps automatically load when you are within 500m of a venue. Malls above 500m are not loaded in maps.'
                                      : 'Shops, floor plans, and parking slots are only visible when a shopping mall is selected or detected within 500m.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: widget.onOpenMallExplorer,
                                  icon: const Icon(LucideIcons.globe, size: 14),
                                  label: const Text('Explore All Malls'),
                                ),
                              ],
                            );
                          }
                          return Column(
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
                                icon: const Icon(
                                  LucideIcons.refreshCw,
                                  size: 14,
                                ),
                                label: const Text('Reset All Filters'),
                              ),
                            ],
                          );
                        },
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
