import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../engine/floor_tracker.dart';
import '../engine/ecef_engine.dart';
import '../engine/bearing_engine.dart';
import '../data/destinations.dart';
import '../data/parking_service.dart';
import 'shop_details_screen.dart';
import 'dpad_control_widget.dart';
import 'theme/app_theme.dart';
import 'widgets/shop_image_widget.dart';

class FloorPlanScreen extends StatefulWidget {
  final BuildingElevationProfile buildingProfile;
  final FloorLevelConfig currentFloor;
  final ValueChanged<FloorLevelConfig> onSelectFloor;
  final GeodeticCoords userCoords;
  final List<DestinationPOI> destinations;
  final Function(double, double) onSimulateMove;
  final Function(DestinationPOI)? onSelectDestination;
  final VoidCallback? onBackClicked;
  final String userEmail;
  final VoidCallback? onLogout;

  const FloorPlanScreen({
    super.key,
    required this.buildingProfile,
    required this.currentFloor,
    required this.onSelectFloor,
    required this.userCoords,
    required this.destinations,
    required this.onSimulateMove,
    this.onSelectDestination,
    this.onBackClicked,
    this.userEmail = '',
    this.onLogout,
  });

  @override
  State<FloorPlanScreen> createState() => FloorPlanScreenState();
}

class FloorPlanScreenState extends State<FloorPlanScreen>
    with SingleTickerProviderStateMixin {
  DestinationPOI? _selectedPOI;
  FloorLevelConfig? _overrideFloor;
  String _selectedCategoryFilter = 'ALL';
  bool _showFilterChips = false;
  final double _zoomScale = 1.0;
  final bool _showDpad = false;
  final ParkingService _parkingService = ParkingService();

  late AnimationController _pulseController;

  FloorLevelConfig get displayFloor => _overrideFloor ?? widget.currentFloor;

  void clearSelection() {
    if (mounted) {
      setState(() {
        _selectedPOI = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _parkingService.addListener(_onParkingStateChanged);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(FloorPlanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentFloor.floorNumber != oldWidget.currentFloor.floorNumber) {
      _overrideFloor = widget.currentFloor;
    }
  }

  @override
  void dispose() {
    _parkingService.removeListener(_onParkingStateChanged);
    _pulseController.dispose();
    super.dispose();
  }

  void _onParkingStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isParkingFloor = displayFloor.floorNumber < 0;
    final currentFloorPOIs = widget.destinations
        .where((poi) => poi.floorNumber == displayFloor.floorNumber)
        .toList();

    final String floorId = displayFloor.floorNumber == -1
        ? 'B1'
        : (displayFloor.floorNumber == -2 ? 'B2' : 'B1');

    final List<ParkingSlot> floorSlots = isParkingFloor
        ? _parkingService.fetchFloorMap(floorId)
        : <ParkingSlot>[];

    final MyVehicleLocation? myVehicle = _parkingService.currentVehicleLocation;
    final int freeSlotsCount = floorSlots
        .where((s) => s.status == ParkingSlotStatus.free)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        titleSpacing: widget.onBackClicked != null ? 0 : 16,
        leading: widget.onBackClicked != null
            ? IconButton(
                icon: const Icon(
                  LucideIcons.arrowLeft,
                  color: Color(0xFF0F172A),
                ),
                onPressed: () {
                  clearSelection();
                  widget.onBackClicked?.call();
                },
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayFloor.name,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              'One Galle Face Mall • Colombo',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          if (!isParkingFloor)
            InkWell(
              onTap: () => _showFloorDirectoryModal(context, currentFloorPOIs),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.store,
                      color: Color(0xFF2563EB),
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${currentFloorPOIs.length} Shops',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E40AF),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            InkWell(
              onTap: () {
                if (myVehicle != null) {
                  final parkedSlot = floorSlots.firstWhere(
                    (s) => s.id == myVehicle.slotId,
                    orElse: () => ParkingSlot(
                      id: myVehicle.slotId,
                      floorId: myVehicle.floorId,
                      section: 'A',
                      slotNumber: 1,
                      status: ParkingSlotStatus.occupied,
                      location: myVehicle.location,
                      gridRow: 0,
                      gridCol: 0,
                      sensorId: '',
                    ),
                  );
                  _showParkingSlotModal(context, parkedSlot, true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Tap any parking slot to reserve or navigate!',
                      ),
                      backgroundColor: Color(0xFF2563EB),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: myVehicle != null
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: myVehicle != null
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFF334155),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      myVehicle != null
                          ? LucideIcons.car
                          : LucideIcons.parkingCircle,
                      color: myVehicle != null
                          ? Colors.white
                          : const Color(0xFF38BDF8),
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      myVehicle != null
                          ? 'Car: ${myVehicle.slotId}'
                          : '$freeSlotsCount Free',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Single Compact Header Row: Floor Pills + Filter Toggle
          Container(
            height: 48,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.buildingProfile.floors.length,
                    itemBuilder: (context, idx) {
                      final floor = widget.buildingProfile.floors[idx];
                      final isSelected =
                          floor.floorNumber == displayFloor.floorNumber;
                      final isParkedFloor =
                          myVehicle != null &&
                          ((floor.floorNumber == -1 &&
                                  myVehicle.floorId.contains('B1')) ||
                              (floor.floorNumber == -2 &&
                                  myVehicle.floorId.contains('B2')));

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedPOI = null;
                            _overrideFloor = floor;
                          });
                          widget.onSelectFloor(floor);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF2563EB),
                                      Color(0xFF1D4ED8),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: isSelected
                                ? null
                                : (isParkedFloor
                                      ? const Color(0xFFDCFCE7)
                                      : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(10),
                            border: isParkedFloor && !isSelected
                                ? Border.all(
                                    color: const Color(0xFF22C55E),
                                    width: 1.5,
                                  )
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF2563EB,
                                      ).withValues(alpha: 0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isParkedFloor && !isSelected) ...[
                                const Icon(
                                  LucideIcons.car,
                                  size: 12,
                                  color: Color(0xFF16A34A),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                floor.floorNumber < 0
                                    ? 'B${floor.floorNumber.abs()}'
                                    : 'F${floor.floorNumber}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected
                                      ? Colors.white
                                      : (isParkedFloor
                                            ? const Color(0xFF15803D)
                                            : const Color(0xFF334155)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (!isParkingFloor) ...[
                  const VerticalDivider(width: 12, indent: 6, endIndent: 6),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _showFilterChips = !_showFilterChips;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _showFilterChips
                            ? const Color(0xFF2563EB)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        LucideIcons.filter,
                        size: 14,
                        color: _showFilterChips
                            ? Colors.white
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
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
          ),

          // Optional Expandable Category Filter Chips Bar
          if (_showFilterChips && !isParkingFloor)
            Container(
              height: 40,
              color: Colors.white,
              padding: const EdgeInsets.only(left: 10, right: 10, bottom: 6),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildCategoryFilterChip(
                    'ALL',
                    'All Places',
                    LucideIcons.layoutGrid,
                  ),
                  _buildCategoryFilterChip(
                    'DINING',
                    'Dining 🍽️',
                    LucideIcons.utensils,
                  ),
                  _buildCategoryFilterChip(
                    'FASHION',
                    'Fashion 👗',
                    LucideIcons.shoppingBag,
                  ),
                  _buildCategoryFilterChip(
                    'BEAUTY',
                    'Beauty 💅',
                    LucideIcons.sparkles,
                  ),
                  _buildCategoryFilterChip(
                    'TECH',
                    'Tech 💻',
                    LucideIcons.laptop,
                  ),
                  _buildCategoryFilterChip(
                    'SERVICES',
                    'Services ℹ️',
                    LucideIcons.info,
                  ),
                ],
              ),
            ),

          // Parked Vehicle Quick Banner
          if (myVehicle != null && !isParkingFloor)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              color: const Color(0xFFDCFCE7),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.car,
                    color: Color(0xFF16A34A),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Vehicle parked at ${myVehicle.slotId} (${myVehicle.floorName})',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF15803D),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      final targetFloorNumber = myVehicle.floorId.contains('B2')
                          ? -2
                          : -1;
                      final targetFloorConfig = widget.buildingProfile.floors
                          .firstWhere(
                            (f) => f.floorNumber == targetFloorNumber,
                            orElse: () => widget.buildingProfile.floors.first,
                          );
                      setState(() {
                        _selectedPOI = null;
                        _overrideFloor = targetFloorConfig;
                      });
                      widget.onSelectFloor(targetFloorConfig);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Go to ${myVehicle.floorId}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Maximized Floor Map Canvas Container
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 96),
              decoration: BoxDecoration(
                color: isParkingFloor ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isParkingFloor
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFCBD5E1),
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final height = constraints.maxHeight;

                    return Stack(
                      children: [
                        // Architectural Custom Floor Canvas
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _zoomScale,
                              alignment: Alignment.center,
                              child: CustomPaint(
                                size: Size(width, height),
                                painter: ArchitecturalFloorPainter(
                                  floorNumber: displayFloor.floorNumber,
                                  floorName: displayFloor.name,
                                  selectedPOI: _selectedPOI,
                                  selectedCategoryFilter:
                                      _selectedCategoryFilter,
                                  currentFloorPOIs: currentFloorPOIs,
                                  parkingSlots: floorSlots,
                                  myVehicle: myVehicle,
                                  userCoords: widget.userCoords,
                                  pulseAnimationValue: _pulseController.value,
                                ),
                              ),
                            );
                          },
                        ),

                        // Render Realistic Shop Photo Cards over Retail Floor Rooms
                        if (!isParkingFloor)
                          ..._buildRetailStorePhotoCards(
                            width,
                            height,
                            currentFloorPOIs,
                          ),

                        // Parking Slot Touch Overlays
                        if (isParkingFloor)
                          ..._buildClickableParkingSlotOverlays(
                            width,
                            height,
                            floorId,
                            floorSlots,
                            myVehicle,
                          ),

                        // User Location Position Pin with Motion Pulsing Radar & Badge
                        () {
                          final activeMallAnchor = widget.destinations.isNotEmpty
                              ? widget.destinations.first.location
                              : entranceAnchor;
                          final effectiveUser = getEffectiveUserCoords(
                            widget.userCoords,
                            activeMallAnchor,
                          );

                          final double centerLat = activeMallAnchor.latitude;
                          final double centerLon = activeMallAnchor.longitude;
                          const double pixelsPerDegLat = 800000.0;
                          const double pixelsPerDegLon = 800000.0;

                          final double deltaLat =
                              effectiveUser.latitude - centerLat;
                          final double deltaLon =
                              effectiveUser.longitude - centerLon;

                          final double rawUserX =
                              (width / 2) + (deltaLon * pixelsPerDegLon);
                          final double rawUserY =
                              (height / 2) - (deltaLat * pixelsPerDegLat);

                          final double userX = rawUserX.clamp(
                            20.0,
                            width - 20.0,
                          );
                          final double userY = rawUserY.clamp(
                            20.0,
                            height - 20.0,
                          );

                          return Positioned(
                            left: userX - 18,
                            top: userY - 18,
                            child: AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                final pulse = _pulseController.value;
                                return SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Motion Radar Wave Ring 1
                                      Transform.scale(
                                        scale: 1.0 + (pulse * 0.8),
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2563EB)
                                                .withValues(
                                                  alpha: 0.3 * (1.0 - pulse),
                                                ),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: const Color(0xFF3B82F6)
                                                  .withValues(
                                                    alpha: 0.6 * (1.0 - pulse),
                                                  ),
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Motion Pulse Glow
                                      Transform.scale(
                                        scale: 1.0 + (pulse * 0.3),
                                        child: Container(
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF2563EB,
                                            ).withValues(alpha: 0.35),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                      // Core Location Pin Dot
                                      Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2563EB),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2.5,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black38,
                                              blurRadius: 6,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Container(
                                            width: 4,
                                            height: 4,
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        }(),

                        // Dynamic Floating D-Pad Move Controls (Bottom Right - Shown in Dev Mode)
                        ValueListenableBuilder<bool>(
                          valueListenable: DeveloperModeNotifier.instance,
                          builder: (context, isDevMode, child) {
                            if (!isDevMode && !_showDpad) {
                              return const SizedBox.shrink();
                            }
                            return Positioned(
                              bottom: 10,
                              right: 10,
                              child: DpadControlWidget(
                                onSimulateMove: widget.onSimulateMove,
                              ),
                            );
                          },
                        ),

                        // Elevated Selected Store Preview Sheet (Bottom Floating)
                        if (_selectedPOI != null && !isParkingFloor)
                          Positioned(
                            left: 10,
                            bottom: 10,
                            right: _showDpad ? 150 : 10,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFF2563EB),
                                  width: 1.5,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x332563EB),
                                    blurRadius: 12,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: ShopImage(
                                          imagePathOrUrl:
                                              _selectedPOI!.effectiveImageUrl,
                                          width: 50,
                                          height: 50,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _selectedPOI!.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w800,
                                                    color: const Color(
                                                      0xFF0F172A,
                                                    ),
                                                  ),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFDCFCE7,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    'Open Now',
                                                    style:
                                                        GoogleFonts.plusJakartaSans(
                                                          fontSize: 8,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: const Color(
                                                            0xFF15803D,
                                                          ),
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '★ ${_selectedPOI!.rating}',
                                                  style:
                                                      GoogleFonts.plusJakartaSans(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: const Color(
                                                          0xFFD97706,
                                                        ),
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () =>
                                            setState(() => _selectedPOI = null),
                                        child: const Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Icon(
                                            LucideIcons.x,
                                            size: 16,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          icon: const Icon(
                                            LucideIcons.compass,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                          label: Text(
                                            'Start Camera Navigation',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF2563EB,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            elevation: 0,
                                          ),
                                          onPressed: () {
                                            if (widget.onSelectDestination !=
                                                null) {
                                              widget.onSelectDestination!(
                                                _selectedPOI!,
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFF2563EB),
                                            width: 1.2,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        onPressed: () => _showStoreDetailsModal(
                                          context,
                                          _selectedPOI!,
                                        ),
                                        child: Text(
                                          'Details',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF2563EB),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds Realistic Store Photo Background Cards positioned over each room space on retail floors
  List<Widget> _buildRetailStorePhotoCards(
    double width,
    double height,
    List<DestinationPOI> pois,
  ) {
    const double roomTopPadding = 50.0;
    final double availableHeight = height - roomTopPadding - 46.0;
    final double roomH = availableHeight * 0.15;
    final double gapY = (availableHeight - (roomH * 3)) / 4;
    final double roomW = width * 0.30;
    final double leftX = 20.0;
    final double rightX = width - 20.0 - roomW;

    final roomRects = [
      Rect.fromLTWH(leftX, roomTopPadding + gapY, roomW, roomH),
      Rect.fromLTWH(rightX, roomTopPadding + gapY, roomW, roomH),
      Rect.fromLTWH(leftX, roomTopPadding + (gapY * 2) + roomH, roomW, roomH),
      Rect.fromLTWH(rightX, roomTopPadding + (gapY * 2) + roomH, roomW, roomH),
      Rect.fromLTWH(
        leftX,
        roomTopPadding + (gapY * 3) + (roomH * 2),
        roomW,
        roomH,
      ),
      Rect.fromLTWH(
        rightX,
        roomTopPadding + (gapY * 3) + (roomH * 2),
        roomW,
        roomH,
      ),
    ];

    final List<Widget> widgets = [];
    for (int i = 0; i < roomRects.length; i++) {
      final rect = roomRects[i];
      final poi = i < pois.length ? pois[i] : null;
      final isSelected = poi != null && _selectedPOI?.id == poi.id;

      final bool matchesCategory =
          _selectedCategoryFilter == 'ALL' ||
          (poi != null &&
              poi.category.toUpperCase().contains(_selectedCategoryFilter));

      final roomCode = 'Store ${i + 1}';
      final storeName = poi != null ? poi.name : 'Store Space';

      widgets.add(
        Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: matchesCategory ? 1.0 : 0.3,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  if (poi != null) {
                    setState(() {
                      _selectedPOI = poi;
                    });
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFEFF6FF)
                        : (poi != null
                              ? Colors.white
                              : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFCBD5E1),
                      width: isSelected ? 2.0 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF2563EB,
                              ).withValues(alpha: 0.25),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6.0,
                      vertical: 4.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top Row: Room Code Tag (Left) + Category Badge (Right)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              roomCode,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 7.5,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                            if (poi != null)
                              Text(
                                _getCategoryTag(poi.category),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 7.0,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1E40AF),
                                ),
                              ),
                          ],
                        ),

                        // Center: Category Icon + Shop Name
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              _getCategoryIcon(poi?.category ?? ''),
                              size: 11,
                              color: const Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                storeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Bottom Row: Rating Badge (Gold Star)
                        if (poi != null)
                          Row(
                            children: [
                              Text(
                                '★ ${poi.rating}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFD97706),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'OPEN',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 7.0,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF15803D),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildCategoryFilterChip(String catKey, String label, IconData icon) {
    final isSelected = _selectedCategoryFilter == catKey;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategoryFilter = catKey;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: const Color(0xFF2563EB), width: 1.2)
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildClickableParkingSlotOverlays(
    double width,
    double height,
    String floorId,
    List<ParkingSlot> slots,
    MyVehicleLocation? myVehicle,
  ) {
    const double roomTopPadding = 50.0;
    final double availableHeight = height - roomTopPadding - 46.0;
    final double slotH = availableHeight * 0.135;
    final double gapY = (availableHeight - (slotH * 6)) / 5;
    final double slotW = (width * 0.34 - 18) / 2;

    final List<Widget> widgets = [];

    // Left Wing
    for (int row = 0; row < 6; row++) {
      for (int col = 0; col < 2; col++) {
        final int num = row * 2 + col + 1;
        final String numStr = num < 10 ? '0$num' : '$num';
        final String code = '$floorId-A-$numStr';
        final double slotX = 20.0 + col * (slotW + 3);
        final double slotY = roomTopPadding + row * (slotH + gapY);

        final slotObj = slots.firstWhere(
          (s) => s.id == code,
          orElse: () => ParkingSlot(
            id: code,
            floorId: floorId,
            section: 'A',
            slotNumber: num,
            status: ParkingSlotStatus.free,
            location: widget.userCoords,
            gridRow: row,
            gridCol: col,
            isEVCharging: num == 1 || num == 2,
            isHandicapAccessible: num == 3 || num == 4,
            sensorId: 'IOT-$code',
          ),
        );

        final bool isMyCar =
            myVehicle != null &&
            myVehicle.slotId == code &&
            myVehicle.status == 'parked';

        widgets.add(
          Positioned(
            left: slotX,
            top: slotY,
            width: slotW,
            height: slotH,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _showParkingSlotModal(context, slotObj, isMyCar),
                child: Container(),
              ),
            ),
          ),
        );
      }
    }

    // Right Wing
    for (int row = 0; row < 6; row++) {
      for (int col = 0; col < 2; col++) {
        final int num = row * 2 + col + 1;
        final String numStr = num < 10 ? '0$num' : '$num';
        final String code = '$floorId-B-$numStr';
        final double slotX = width * 0.65 + col * (slotW + 3);
        final double slotY = roomTopPadding + row * (slotH + gapY);

        final slotObj = slots.firstWhere(
          (s) => s.id == code,
          orElse: () => ParkingSlot(
            id: code,
            floorId: floorId,
            section: 'B',
            slotNumber: num,
            status: ParkingSlotStatus.free,
            location: widget.userCoords,
            gridRow: row,
            gridCol: col,
            sensorId: 'IOT-$code',
          ),
        );

        final bool isMyCar =
            myVehicle != null &&
            myVehicle.slotId == code &&
            myVehicle.status == 'parked';

        widgets.add(
          Positioned(
            left: slotX,
            top: slotY,
            width: slotW,
            height: slotH,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _showParkingSlotModal(context, slotObj, isMyCar),
                child: Container(),
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  void _showParkingSlotModal(
    BuildContext context,
    ParkingSlot slot,
    bool isMyCar,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isMyCar
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isMyCar ? LucideIcons.car : LucideIcons.parkingCircle,
                    color: isMyCar
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF2563EB),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Parking Spot ${slot.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '${displayFloor.name} • Zone ${slot.section}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isMyCar
                        ? const Color(0xFFDCFCE7)
                        : (slot.status == ParkingSlotStatus.free
                              ? const Color(0xFFF0FDF4)
                              : (slot.status == ParkingSlotStatus.occupied
                                    ? const Color(0xFFFEF2F2)
                                    : const Color(0xFFFFFBEB))),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isMyCar
                          ? const Color(0xFF86EFAC)
                          : (slot.status == ParkingSlotStatus.free
                                ? const Color(0xFFBBF7D0)
                                : (slot.status == ParkingSlotStatus.occupied
                                      ? const Color(0xFFFCA5A5)
                                      : const Color(0xFFFDE68A))),
                    ),
                  ),
                  child: Text(
                    isMyCar
                        ? 'PARKED'
                        : (slot.status == ParkingSlotStatus.free
                              ? 'AVAILABLE'
                              : (slot.status == ParkingSlotStatus.occupied
                                    ? 'OCCUPIED'
                                    : 'RESERVED')),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isMyCar
                          ? const Color(0xFF15803D)
                          : (slot.status == ParkingSlotStatus.free
                                ? const Color(0xFF16A34A)
                                : (slot.status == ParkingSlotStatus.occupied
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFFD97706))),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (slot.isEVCharging)
                  _buildFeatureChip(
                    LucideIcons.zap,
                    '⚡ 120kW EV Charger',
                    const Color(0xFF16A34A),
                  ),
                if (slot.isHandicapAccessible)
                  _buildFeatureChip(
                    LucideIcons.accessibility,
                    '♿ Handicap Bay',
                    const Color(0xFF2563EB),
                  ),
                _buildFeatureChip(
                  LucideIcons.radio,
                  '🛰️ Live IoT Sensor Active',
                  const Color(0xFF64748B),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (!isMyCar && slot.status != ParkingSlotStatus.free) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.shieldAlert,
                      color: Color(0xFFDC2626),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PARKING RESTRICTED',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFDC2626),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Spot ${slot.id} is currently taken by another car.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: const Color(0xFF991B1B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  icon: const Icon(
                    LucideIcons.navigation,
                    color: Color(0xFF2563EB),
                    size: 18,
                  ),
                  label: Text(
                    'NAVIGATE TO THIS SPOT',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFF2563EB),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    if (widget.onSelectDestination != null) {
                      widget.onSelectDestination!(slot.toDestinationPOI());
                    }
                  },
                ),
              ),
            ] else if (!isMyCar) ...[
              if (_parkingService.hasParkedVehicle) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.alertTriangle,
                        color: Color(0xFFD97706),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'You already have a car parked at Spot ${_parkingService.currentVehicleLocation?.slotId}. Select replace to park here instead.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(
                    LucideIcons.car,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    'PARK MY CAR HERE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      final currentVehicle =
                          _parkingService.currentVehicleLocation;
                      if (currentVehicle != null &&
                          currentVehicle.slotId != slot.id) {
                        final bool?
                        confirmUnparkAndPark = await showDialog<bool>(
                          context: context,
                          builder: (dialogCtx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            title: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    LucideIcons.alertTriangle,
                                    color: Color(0xFFDC2626),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Car Already Parked',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                RichText(
                                  text: TextSpan(
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13.5,
                                      color: const Color(0xFF334155),
                                      height: 1.4,
                                    ),
                                    children: [
                                      const TextSpan(
                                        text:
                                            'You already have a car parked at ',
                                      ),
                                      TextSpan(
                                        text:
                                            'Spot ${currentVehicle.slotId} (${currentVehicle.floorName})',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const TextSpan(
                                        text:
                                            '.\n\nWould you like to replace your saved spot and park here?',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            actionsPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogCtx, false),
                                child: Text(
                                  'Keep Existing',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: const Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(
                                  LucideIcons.trash2,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                label: Text(
                                  'Remove & Park Here',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () => Navigator.pop(dialogCtx, true),
                              ),
                            ],
                          ),
                        );

                        if (confirmUnparkAndPark != true) {
                          return;
                        }
                        await _parkingService.clearVehicleLocation();
                      }

                      await _parkingService.saveVehicleLocation(
                        MyVehicleLocation(
                          userId: _parkingService.currentUserId,
                          slotId: slot.id,
                          floorId: slot.floorId,
                          floorName: displayFloor.name,
                          location: slot.location,
                          timestamp: DateTime.now(),
                        ),
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Vehicle parked at Stall ${slot.id}!',
                            ),
                            backgroundColor: const Color(0xFF16A34A),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        setState(() {});
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e.toString().replaceAll('Exception: ', ''),
                            ),
                            backgroundColor: const Color(0xFFDC2626),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  icon: const Icon(
                    LucideIcons.navigation,
                    color: Color(0xFF2563EB),
                    size: 18,
                  ),
                  label: Text(
                    'NAVIGATE TO THIS SLOT',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFF2563EB),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    if (widget.onSelectDestination != null) {
                      widget.onSelectDestination!(slot.toDestinationPOI());
                    }
                  },
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(
                    LucideIcons.compass,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    'NAVIGATE TO MY CAR',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    if (widget.onSelectDestination != null) {
                      widget.onSelectDestination!(slot.toDestinationPOI());
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(
                    LucideIcons.logOut,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    'UNPARK VEHICLE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () async {
                    await _parkingService.clearVehicleLocation();
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Vehicle unparked from Stall ${slot.id}.',
                          ),
                          backgroundColor: const Color(0xFFDC2626),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      setState(() {});
                    }
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  void _showFloorDirectoryModal(
    BuildContext context,
    List<DestinationPOI> pois,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      LucideIcons.store,
                      color: Color(0xFF2563EB),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Floor Directory (${displayFloor.name})',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${pois.length} Locations',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: pois.isEmpty
                  ? Center(
                      child: Text(
                        'No shops listed on this floor.',
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: pois.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final poi = pois[idx];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: ShopImage(
                                  imagePathOrUrl: poi.effectiveImageUrl,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      poi.name,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      '${poi.category} • ★ ${poi.rating}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  setState(() => _selectedPOI = poi);
                                  if (widget.onSelectDestination != null) {
                                    widget.onSelectDestination!(poi);
                                  }
                                },
                                child: const Text(
                                  'View',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStoreDetailsModal(BuildContext context, DestinationPOI poi) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ShopDetailsScreen(
        destination: poi,
        userCoords: widget.userCoords,
        onStartARNavigation: () {
          Navigator.pop(context);
          if (widget.onSelectDestination != null) {
            widget.onSelectDestination!(poi);
          }
        },
      ),
    );
  }

  String _getCategoryTag(String category) {
    final cat = category.toUpperCase();
    if (cat.contains('FOOD')) return 'Food';
    if (cat.contains('TECH')) return 'Electronics';
    if (cat.contains('FASHION') || cat.contains('RETAIL')) return 'Clothing';
    if (cat.contains('LUXURY') || cat.contains('BEAUTY')) return 'Beauty';
    if (cat.contains('ENTERTAINMENT')) return 'Movies';
    return 'Services';
  }

  IconData _getCategoryIcon(String cat) {
    if (cat.contains('FOOD')) {
      return LucideIcons.utensils;
    }
    if (cat.contains('TECH')) {
      return LucideIcons.laptop;
    }
    if (cat.contains('FASHION') || cat.contains('RETAIL')) {
      return LucideIcons.shoppingBag;
    }
    if (cat.contains('LUXURY') || cat.contains('BEAUTY')) {
      return LucideIcons.sparkles;
    }
    if (cat.contains('ENTERTAINMENT')) {
      return LucideIcons.film;
    }
    return LucideIcons.mapPin;
  }
}

class RoomCategoryProfile {
  final Color bg;
  final Color border;
  final Color text;
  final Color iconColor;
  final IconData icon;

  const RoomCategoryProfile({
    required this.bg,
    required this.border,
    required this.text,
    required this.iconColor,
    required this.icon,
  });
}

class ArchitecturalFloorPainter extends CustomPainter {
  final int floorNumber;
  final String floorName;
  final DestinationPOI? selectedPOI;
  final String selectedCategoryFilter;
  final List<DestinationPOI> currentFloorPOIs;
  final List<ParkingSlot> parkingSlots;
  final MyVehicleLocation? myVehicle;
  final GeodeticCoords userCoords;
  final double pulseAnimationValue;

  ArchitecturalFloorPainter({
    required this.floorNumber,
    required this.floorName,
    this.selectedPOI,
    this.selectedCategoryFilter = 'ALL',
    this.currentFloorPOIs = const [],
    this.parkingSlots = const [],
    this.myVehicle,
    required this.userCoords,
    required this.pulseAnimationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bool isParkingFloor = floorNumber < 0;

    // 1. Canvas Background
    final bgPaint = Paint()
      ..color = isParkingFloor
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Concourse Architectural Tile Grid Lines
    final gridPaint = Paint()
      ..color = isParkingFloor
          ? const Color(0xFF1E293B).withValues(alpha: 0.4)
          : const Color(0xFFE2E8F0).withValues(alpha: 0.6)
      ..strokeWidth = 0.8;

    const double step = 22.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 2. Outer Building Perimeter Wall & Glass Curtain Accents
    final wallFillPaint = Paint()
      ..color = isParkingFloor
          ? const Color(0xFF1E293B)
          : const Color(0xFFF1F5F9);
    final outerBorderPaint = Paint()
      ..color = isParkingFloor
          ? const Color(0xFF0284C7)
          : const Color(0xFF64748B)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final outerRect = RRect.fromLTRBR(
      12,
      12,
      size.width - 12,
      size.height - 12,
      const Radius.circular(20),
    );
    canvas.drawRRect(outerRect, wallFillPaint);
    canvas.drawRRect(outerRect, outerBorderPaint);

    // 3. Central Concourse Walkway Corridor
    const double roomTopPadding = 50.0;
    final corridorRect = RRect.fromLTRBR(
      size.width * 0.36,
      roomTopPadding,
      size.width * 0.64,
      size.height - 18,
      const Radius.circular(14),
    );

    final corridorPaint = Paint()
      ..color = isParkingFloor ? const Color(0xFF1E293B) : Colors.white;
    canvas.drawRRect(corridorRect, corridorPaint);

    final corridorBorderPaint = Paint()
      ..color = isParkingFloor
          ? const Color(0xFF38BDF8)
          : const Color(0xFFCBD5E1)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(corridorRect, corridorBorderPaint);

    // Central Concourse Compass Watermark
    final compassCenter = Offset(size.width * 0.50, size.height * 0.50);
    final compassCirclePaint = Paint()
      ..color =
          (isParkingFloor ? const Color(0xFF38BDF8) : const Color(0xFF2563EB))
              .withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(compassCenter, 28, compassCirclePaint);

    // 4. Floor Content Layout (Retail vs Basement)
    Offset? selectedTargetDoorOffset;

    if (isParkingFloor) {
      _paintBasementParkingPlan(canvas, size, roomTopPadding);
    } else {
      selectedTargetDoorOffset = _paintRetailPlan(canvas, size, roomTopPadding);
    }

    // 5. Entrance Lobby & Elevator Hub Header
    final facilityRect = Rect.fromLTWH(
      size.width * 0.35,
      16,
      size.width * 0.30,
      24,
    );
    final facilityPaint = Paint()
      ..color = isParkingFloor
          ? const Color(0xFF0284C7)
          : const Color(0xFFE0F2FE);
    final facilityBorder = Paint()
      ..color = isParkingFloor
          ? const Color(0xFF38BDF8)
          : const Color(0xFF0284C7)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(
      RRect.fromRectAndRadius(facilityRect, const Radius.circular(8)),
      facilityPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(facilityRect, const Radius.circular(8)),
      facilityBorder,
    );

    final String hubText = floorNumber == 1
        ? 'Main Entrance & Escalators'
        : (isParkingFloor ? 'Elevators & Stairs' : 'Elevators & Escalators');

    _drawText(
      canvas,
      hubText,
      Offset(facilityRect.left + 2, facilityRect.top + 6),
      isParkingFloor ? Colors.white : const Color(0xFF0369A1),
      fontSize: 7.0,
      fontWeight: FontWeight.w800,
      maxWidth: facilityRect.width - 4,
      textAlign: TextAlign.center,
    );

    // Bottom Parking Ramp Banner
    final rampRect = Rect.fromLTWH(
      size.width * 0.35,
      size.height - 40,
      size.width * 0.30,
      22,
    );
    final rampPaint = Paint()
      ..color = isParkingFloor
          ? const Color(0xFF0F172A)
          : const Color(0xFFDBEAFE);
    final rampBorder = Paint()
      ..color = isParkingFloor
          ? const Color(0xFF38BDF8)
          : const Color(0xFF2563EB)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rampRect, const Radius.circular(7)),
      rampPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rampRect, const Radius.circular(7)),
      rampBorder,
    );

    final String rampLabel = isParkingFloor
        ? '▼ Entrance & Exit'
        : '▼ Parking Entrance';
    _drawText(
      canvas,
      rampLabel,
      Offset(rampRect.left + 2, rampRect.top + 5),
      isParkingFloor ? const Color(0xFF38BDF8) : const Color(0xFF1E40AF),
      fontSize: 7.0,
      fontWeight: FontWeight.w800,
      maxWidth: rampRect.width - 4,
      textAlign: TextAlign.center,
    );

    // 6. Draw Vector Pathfinding Line when POI is selected!
    if (selectedTargetDoorOffset != null) {
      _drawVectorWalkingRoutePath(
        canvas,
        size,
        selectedTargetDoorOffset,
        isParkingFloor,
      );
    }
  }

  Offset? _paintRetailPlan(Canvas canvas, Size size, double roomTopPadding) {
    final double availableHeight = size.height - roomTopPadding - 46.0;
    final double roomH = availableHeight * 0.15;
    final double gapY = (availableHeight - (roomH * 3)) / 4;
    final double roomW = size.width * 0.30;
    final double leftX = 20.0;
    final double rightX = size.width - 20.0 - roomW;

    final roomBoxes = [
      Rect.fromLTWH(leftX, roomTopPadding + gapY, roomW, roomH),
      Rect.fromLTWH(rightX, roomTopPadding + gapY, roomW, roomH),
      Rect.fromLTWH(leftX, roomTopPadding + (gapY * 2) + roomH, roomW, roomH),
      Rect.fromLTWH(rightX, roomTopPadding + (gapY * 2) + roomH, roomW, roomH),
      Rect.fromLTWH(
        leftX,
        roomTopPadding + (gapY * 3) + (roomH * 2),
        roomW,
        roomH,
      ),
      Rect.fromLTWH(
        rightX,
        roomTopPadding + (gapY * 3) + (roomH * 2),
        roomW,
        roomH,
      ),
    ];

    Offset? selectedDoorOffset;

    for (int i = 0; i < roomBoxes.length; i++) {
      final rect = roomBoxes[i];
      final DestinationPOI? poi = i < currentFloorPOIs.length
          ? currentFloorPOIs[i]
          : null;
      final bool isSelected = poi != null && selectedPOI?.id == poi.id;

      final profile = _getProfileForCategory(poi?.category ?? '');

      // Doorway Location
      final isLeftWing = rect.left < size.width * 0.50;
      final doorX = isLeftWing ? rect.right : rect.left;
      final doorY = rect.top + (rect.height / 2);

      if (isSelected) {
        selectedDoorOffset = Offset(doorX, doorY);
      }

      // Render Doorway Arc into Corridor
      final doorArcPaint = Paint()
        ..color = profile.border.withValues(alpha: 0.6)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      final doorArcRect = Rect.fromCircle(
        center: Offset(doorX, doorY),
        radius: 10,
      );
      final double startAngle = isLeftWing ? -math.pi / 2 : math.pi / 2;
      canvas.drawArc(doorArcRect, startAngle, math.pi / 2, false, doorArcPaint);

      // Selection Glow Halo
      if (isSelected) {
        final glowHaloRadius = 1.0 + (pulseAnimationValue * 0.15);
        final glowPaint = Paint()
          ..color = const Color(0xFF2563EB).withValues(alpha: 0.25)
          ..strokeWidth = 5.0
          ..style = PaintingStyle.stroke;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.inflate(2 * glowHaloRadius),
            const Radius.circular(16),
          ),
          glowPaint,
        );
      }
    }

    return selectedDoorOffset;
  }

  void _paintBasementParkingPlan(
    Canvas canvas,
    Size size,
    double roomTopPadding,
  ) {
    final double availableHeight = size.height - roomTopPadding - 46.0;
    final double slotH = availableHeight * 0.135;
    final double gapY = (availableHeight - (slotH * 6)) / 5;

    final dashPaint = Paint()
      ..color = const Color(0xFFFBBF24)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final double midX = size.width * 0.50;
    for (double y = roomTopPadding + 10; y < size.height - 45; y += 22) {
      canvas.drawLine(Offset(midX, y), Offset(midX, y + 10), dashPaint);
    }

    _drawText(
      canvas,
      '▲ CAR LANE ▲',
      Offset(midX - 40, roomTopPadding + 6),
      const Color(0xFFFBBF24),
      fontSize: 7.0,
      fontWeight: FontWeight.bold,
      maxWidth: 80,
      textAlign: TextAlign.center,
    );

    final double slotW = (size.width * 0.34 - 18) / 2;
    final String prefix = floorNumber == -1
        ? 'B1'
        : (floorNumber == -2 ? 'B2' : 'B');

    // Left Wing: Zone A
    for (int row = 0; row < 6; row++) {
      for (int col = 0; col < 2; col++) {
        final int num = row * 2 + col + 1;
        final String numStr = num < 10 ? '0$num' : '$num';
        final String code = '$prefix-A-$numStr';
        final double slotX = 20.0 + col * (slotW + 3);
        final double slotY = roomTopPadding + row * (slotH + gapY);
        final Rect slotRect = Rect.fromLTWH(slotX, slotY, slotW, slotH);

        final bool isEV = num == 1 || num == 2;
        final bool isHandicap = num == 3 || num == 4;

        final slotObj = parkingSlots.firstWhere(
          (s) => s.id == code,
          orElse: () => ParkingSlot(
            id: code,
            floorId: prefix,
            section: 'A',
            slotNumber: num,
            status: ParkingSlotStatus.free,
            location: const GeodeticCoords(
              latitude: 0,
              longitude: 0,
              height: 0,
            ),
            gridRow: row,
            gridCol: col,
            sensorId: 'IOT-$code',
          ),
        );

        final bool isMyCar =
            myVehicle != null &&
            myVehicle!.slotId == code &&
            myVehicle!.status == 'parked';

        _drawSingleParkingStall(
          canvas,
          slotRect,
          code,
          isEV: isEV,
          isHandicap: isHandicap,
          status: slotObj.status,
          isMyCar: isMyCar,
        );
      }
    }

    // Right Wing: Zone B
    for (int row = 0; row < 6; row++) {
      for (int col = 0; col < 2; col++) {
        final int num = row * 2 + col + 1;
        final String numStr = num < 10 ? '0$num' : '$num';
        final String code = '$prefix-B-$numStr';
        final double slotX = size.width * 0.65 + col * (slotW + 3);
        final double slotY = roomTopPadding + row * (slotH + gapY);
        final Rect slotRect = Rect.fromLTWH(slotX, slotY, slotW, slotH);

        final slotObj = parkingSlots.firstWhere(
          (s) => s.id == code,
          orElse: () => ParkingSlot(
            id: code,
            floorId: prefix,
            section: 'B',
            slotNumber: num,
            status: ParkingSlotStatus.free,
            location: const GeodeticCoords(
              latitude: 0,
              longitude: 0,
              height: 0,
            ),
            gridRow: row,
            gridCol: col,
            sensorId: 'IOT-$code',
          ),
        );

        final bool isMyCar =
            myVehicle != null &&
            myVehicle!.slotId == code &&
            myVehicle!.status == 'parked';

        _drawSingleParkingStall(
          canvas,
          slotRect,
          code,
          status: slotObj.status,
          isMyCar: isMyCar,
        );
      }
    }
  }

  void _drawSingleParkingStall(
    Canvas canvas,
    Rect slotRect,
    String slotCode, {
    bool isEV = false,
    bool isHandicap = false,
    ParkingSlotStatus status = ParkingSlotStatus.free,
    bool isMyCar = false,
  }) {
    Color fillPaintColor = const Color(0xFF1E293B);
    Color borderPaintColor = isEV
        ? const Color(0xFF22C55E)
        : (isHandicap ? const Color(0xFF3B82F6) : const Color(0xFF475569));

    if (isMyCar) {
      fillPaintColor = const Color(0xFF047857);
      borderPaintColor = const Color(0xFF4ADE80);

      final glowRect = slotRect.inflate(2);
      final glowPaint = Paint()
        ..color = const Color(0xFF22C55E).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(glowRect, const Radius.circular(7)),
        glowPaint,
      );
    } else if (status == ParkingSlotStatus.occupied) {
      fillPaintColor = const Color(0xFF334155);
      borderPaintColor = const Color(0xFF64748B);
    }

    final fillPaint = Paint()..color = fillPaintColor;
    final borderPaint = Paint()
      ..color = borderPaintColor
      ..strokeWidth = isMyCar ? 2.0 : 1.0
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(slotRect, const Radius.circular(5));
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, borderPaint);

    if (isMyCar) {
      _drawText(
        canvas,
        slotCode,
        Offset(slotRect.left + 2, slotRect.top + 3),
        Colors.white,
        fontSize: 6.5,
        fontWeight: FontWeight.bold,
      );
      _drawText(
        canvas,
        'PARKED',
        Offset(slotRect.left + 2, slotRect.top + 14),
        const Color(0xFF4ADE80),
        fontSize: 6.0,
        fontWeight: FontWeight.bold,
      );
      return;
    }

    String tag = '';
    Color tagColor = const Color(0xFF38BDF8);
    if (isEV) {
      tag = '⚡';
      tagColor = const Color(0xFF4ADE80);
    } else if (isHandicap) {
      tag = '♿';
      tagColor = const Color(0xFF60A5FA);
    }

    _drawText(
      canvas,
      '$slotCode $tag',
      Offset(slotRect.left + 2, slotRect.top + 3),
      tagColor,
      fontSize: 6.5,
      fontWeight: FontWeight.bold,
    );

    final String statusLabel = status == ParkingSlotStatus.free
        ? 'Available'
        : (status == ParkingSlotStatus.occupied ? 'Occupied' : 'Reserved');
    final Color statusColor = status == ParkingSlotStatus.free
        ? const Color(0xFF22C55E)
        : (status == ParkingSlotStatus.occupied
              ? const Color(0xFFEF4444)
              : const Color(0xFFF59E0B));
    _drawText(
      canvas,
      statusLabel,
      Offset(slotRect.left + 2, slotRect.top + 14),
      statusColor,
      fontSize: 6.0,
      fontWeight: FontWeight.bold,
    );
  }

  void _drawVectorWalkingRoutePath(
    Canvas canvas,
    Size size,
    Offset targetDoor,
    bool isDark,
  ) {
    final activeMallAnchor = currentFloorPOIs.isNotEmpty
        ? currentFloorPOIs.first.location
        : entranceAnchor;
    final effectiveUser = getEffectiveUserCoords(
      userCoords,
      activeMallAnchor,
    );

    final double centerLat = activeMallAnchor.latitude;
    final double centerLon = activeMallAnchor.longitude;
    const double pixelsPerDegLat = 800000.0;
    const double pixelsPerDegLon = 800000.0;

    final double deltaLat = effectiveUser.latitude - centerLat;
    final double deltaLon = effectiveUser.longitude - centerLon;

    final double rawUserX = (size.width / 2) + (deltaLon * pixelsPerDegLon);
    final double rawUserY = (size.height / 2) - (deltaLat * pixelsPerDegLat);

    final double userX = rawUserX.clamp(20.0, size.width - 20.0);
    final double userY = rawUserY.clamp(20.0, size.height - 20.0);
    final userPos = Offset(userX, userY);

    final path = Path();
    path.moveTo(userPos.dx, userPos.dy);
    path.lineTo(size.width * 0.50, userPos.dy);
    path.lineTo(size.width * 0.50, targetDoor.dy);
    path.lineTo(targetDoor.dx, targetDoor.dy);

    // Glowing Underlayer Path
    final pathGlowPaint = Paint()
      ..color = (isDark ? const Color(0xFF00E5FF) : const Color(0xFF2563EB))
          .withValues(alpha: 0.25)
      ..strokeWidth = 7.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, pathGlowPaint);

    // Motion Dash Animated Path
    final pathPaint = Paint()
      ..color = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2563EB)
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double dashOffset = pulseAnimationValue * 20.0;

    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      double distance = dashOffset % 12.0;
      while (distance < metric.length) {
        final extract = metric.extractPath(
          distance,
          math.min(distance + 6.0, metric.length),
        );
        canvas.drawPath(extract, pathPaint);
        distance += 12.0;
      }

      // Traveling Motion Light Energy Bead
      final pulseDistance =
          (pulseAnimationValue * metric.length) % metric.length;
      final tangent = metric.getTangentForOffset(pulseDistance);
      if (tangent != null) {
        final beadGlow = Paint()
          ..color = (isDark ? const Color(0xFF00E5FF) : const Color(0xFF2563EB))
              .withValues(alpha: 0.7)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(tangent.position, 7.0, beadGlow);

        final beadPaint = Paint()
          ..color = isDark ? const Color(0xFFE0F2FE) : Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(tangent.position, 4.0, beadPaint);
      }
    }

    // Target Doorway Radar Beacon with Animated Expanding Waves
    final beaconDotPaint = Paint()
      ..color = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2563EB);
    canvas.drawCircle(targetDoor, 5.5, beaconDotPaint);

    final beaconRingRadius = 6.0 + (pulseAnimationValue * 9.0);
    final beaconRingPaint = Paint()
      ..color = (isDark ? const Color(0xFF00E5FF) : const Color(0xFF2563EB))
          .withValues(alpha: (1.0 - pulseAnimationValue).clamp(0.0, 1.0))
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(targetDoor, beaconRingRadius, beaconRingPaint);
  }

  RoomCategoryProfile _getProfileForCategory(String category) {
    final cat = category.toUpperCase();
    if (cat.contains('FOOD')) {
      return const RoomCategoryProfile(
        bg: Color(0xFFFEF3C7),
        border: Color(0xFFF59E0B),
        text: Color(0xFF78350F),
        iconColor: Color(0xFFD97706),
        icon: LucideIcons.utensils,
      );
    } else if (cat.contains('TECH')) {
      return const RoomCategoryProfile(
        bg: Color(0xFFE0F2FE),
        border: Color(0xFF0284C7),
        text: Color(0xFF075985),
        iconColor: Color(0xFF0284C7),
        icon: LucideIcons.laptop,
      );
    } else if (cat.contains('FASHION') || cat.contains('RETAIL')) {
      return const RoomCategoryProfile(
        bg: Color(0xFFF3E8FF),
        border: Color(0xFF8B5CF6),
        text: Color(0xFF4C1D95),
        iconColor: Color(0xFF7C3AED),
        icon: LucideIcons.shoppingBag,
      );
    } else if (cat.contains('LUXURY') || cat.contains('BEAUTY')) {
      return const RoomCategoryProfile(
        bg: Color(0xFFFFE4E6),
        border: Color(0xFFF43F5E),
        text: Color(0xFF881337),
        iconColor: Color(0xFFE11D48),
        icon: LucideIcons.sparkles,
      );
    } else if (cat.contains('ENTERTAINMENT')) {
      return const RoomCategoryProfile(
        bg: Color(0xFFFDF4FF),
        border: Color(0xFFD946EF),
        text: Color(0xFF701A75),
        iconColor: Color(0xFFC026D3),
        icon: LucideIcons.film,
      );
    }
    return const RoomCategoryProfile(
      bg: Color(0xFFEEF2FF),
      border: Color(0xFF6366F1),
      text: Color(0xFF312E81),
      iconColor: Color(0xFF4F46E5),
      icon: LucideIcons.mapPin,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color, {
    double fontSize = 9.0,
    FontWeight fontWeight = FontWeight.normal,
    double maxWidth = 100.0,
    TextAlign textAlign = TextAlign.left,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: GoogleFonts.plusJakartaSans(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      maxLines: 2,
      ellipsis: '...',
    );
    tp.layout(maxWidth: maxWidth);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

