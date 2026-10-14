import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/api_service.dart';
import '../../data/floor_height_model.dart';
import '../../data/parking_service.dart';
import '../../data/mall_database_service.dart';
import '../../engine/ecef_engine.dart';

class AdminParkingManagerScreen extends StatefulWidget {
  const AdminParkingManagerScreen({super.key});

  @override
  State<AdminParkingManagerScreen> createState() =>
      _AdminParkingManagerScreenState();
}

class _AdminParkingManagerScreenState extends State<AdminParkingManagerScreen> {
  final ParkingService _parkingService = ParkingService();
  final MallDatabaseService _mallService = MallDatabaseService();

  List<MallMetadata> _malls = [];
  MallMetadata? _activeMall;
  List<FloorHeightData> _mallFloorHeights = [];
  String _selectedFloorId = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _parkingService.addListener(_onParkingChanged);
    _loadMallsAndLayout();
  }

  @override
  void dispose() {
    _parkingService.removeListener(_onParkingChanged);
    super.dispose();
  }

  void _onParkingChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadMallsAndLayout() async {
    setState(() => _isLoading = true);
    final malls = await _mallService.getMallsList();
    if (malls.isEmpty) {
      if (mounted) {
        setState(() {
          _malls = [];
          _activeMall = null;
          _mallFloorHeights = [];
          _isLoading = false;
        });
      }
      return;
    }
    var active = malls.firstWhere(
      (m) => m.isActive,
      orElse: () => malls.first,
    );

    try {
      _mallFloorHeights = await ApiService.instance.fetchFloorHeights(
        active.id,
      );
    } catch (_) {
      _mallFloorHeights = [];
    }

    await _parkingService.loadLayoutForMallMetadata(
      mallId: active.id,
      baseLat: active.latitude,
      baseLon: active.longitude,
    );

    // Load any explicitly designated parking floors for this venue package
    final prefs = await SharedPreferences.getInstance();
    final savedParkingFloors = prefs.getStringList(
      'venue_parking_floors_${active.id}',
    );
    if (savedParkingFloors != null && savedParkingFloors.isNotEmpty) {
      active = active.copyWith(parkingFloors: savedParkingFloors);
    }

    // Prune legacy dummy slots from cache/memory that do not belong to this mall
    final validFloors = _getFloorOptionsForMall(active, _mallFloorHeights);
    await _parkingService.pruneSlotsToValidFloors(active.id, validFloors);

    if (mounted) {
      setState(() {
        _malls = malls;
        _activeMall = active;
        if (validFloors.isNotEmpty) {
          if (!validFloors.contains(_selectedFloorId)) {
            _selectedFloorId = validFloors.first;
          }
        } else {
          _selectedFloorId = 'Floor 1';
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _switchActiveMall(String newMallId) async {
    setState(() => _isLoading = true);
    var selected = _malls.firstWhere(
      (m) => m.id == newMallId,
      orElse: () => _malls.first,
    );
    await _mallService.setActiveMall(selected.id);

    final updatedMalls = await _mallService.getMallsList();

    try {
      _mallFloorHeights = await ApiService.instance.fetchFloorHeights(
        selected.id,
      );
    } catch (_) {
      _mallFloorHeights = [];
    }

    await _parkingService.loadLayoutForMallMetadata(
      mallId: selected.id,
      baseLat: selected.latitude,
      baseLon: selected.longitude,
    );

    final prefs = await SharedPreferences.getInstance();
    final savedParkingFloors = prefs.getStringList(
      'venue_parking_floors_${selected.id}',
    );
    if (savedParkingFloors != null && savedParkingFloors.isNotEmpty) {
      selected = selected.copyWith(parkingFloors: savedParkingFloors);
    }

    final validFloors = _getFloorOptionsForMall(selected, _mallFloorHeights);
    await _parkingService.pruneSlotsToValidFloors(selected.id, validFloors);

    if (mounted) {
      setState(() {
        _malls = updatedMalls;
        _activeMall = selected;
        if (validFloors.isNotEmpty) {
          if (!validFloors.contains(_selectedFloorId)) {
            _selectedFloorId = validFloors.first;
          }
        } else {
          _selectedFloorId = 'Floor 1';
        }
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Switched parking lot layout to ${selected.name} (${selected.city})',
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  List<String> _getFloorOptions() {
    return _getFloorOptionsForMall(_activeMall, _mallFloorHeights);
  }

  List<String> _getFloorOptionsForMall(
    MallMetadata? mall,
    List<FloorHeightData> heights,
  ) {
    if (mall == null) return [];

    // 1. If designated parking floors are configured in venue package, return strictly those floors
    if (mall.parkingFloors.isNotEmpty) {
      return List<String>.from(mall.parkingFloors);
    }

    final List<String> floors = [];

    final targetId = mall.id.trim().toLowerCase();
    final matchingHeights = heights.where((h) {
      final hMall = h.mallId.trim().toLowerCase();
      return hMall.isEmpty || hMall == targetId;
    }).toList();

    if (matchingHeights.isNotEmpty) {
      matchingHeights.sort((a, b) => a.floorNo.compareTo(b.floorNo));
      for (final h in matchingHeights) {
        final label = h.floorNo < 0
            ? 'B${h.floorNo.abs()}'
            : (h.floorNo == 0 ? 'GF' : 'Floor ${h.floorNo}');
        if (!floors.contains(label)) {
          floors.add(label);
        }
      }
    } else {
      final count = mall.floorCount > 0 ? mall.floorCount : 1;
      for (int i = 1; i <= count; i++) {
        floors.add('Floor $i');
      }
    }

    return floors;
  }

  double _resolveFloorAltitude(String floorStr) {
    if (_activeMall == null) return 45.0;
    final groundAlt = _activeMall!.entranceBaseAnchorHeight > 0
        ? _activeMall!.entranceBaseAnchorHeight
        : 15.0;
    final gap = _activeMall!.floorGapMeters > 0
        ? _activeMall!.floorGapMeters
        : 3.8;

    for (final fh in _mallFloorHeights) {
      final label = fh.floorNo < 0
          ? 'B${fh.floorNo.abs()}'
          : (fh.floorNo == 0 ? 'GF' : 'Floor ${fh.floorNo}');
      if (label == floorStr || 'F${fh.floorNo}' == floorStr) {
        return fh.baseAltitudeM;
      }
    }

    final digits =
        int.tryParse(floorStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
    if (floorStr.toUpperCase().startsWith('B')) {
      return groundAlt - (digits * gap);
    }
    return groundAlt + ((digits - 1) * gap);
  }

  void _showAddParkingSlotsSheet({String? presetFloor}) {
    if (_activeMall == null) return;
    final floors = _getFloorOptions();
    if (floors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No parking floors configured for this mall venue.'),
        ),
      );
      return;
    }
    final targetFloor = (presetFloor != null && floors.contains(presetFloor))
        ? presetFloor
        : (floors.contains(_selectedFloorId) ? _selectedFloorId : floors.first);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      LucideIcons.parkingSquare,
                      color: Color(0xFF2563EB),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Parking Slots',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Target Floor: $targetFloor (${_activeMall?.name})',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.plusCircle,
                    color: Color(0xFF2563EB),
                    size: 20,
                  ),
                ),
                title: Text(
                  'Add Single Stall',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                subtitle: Text(
                  'Configure an individual bay on $targetFloor with EV/VIP options',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: const Color(0xFF64748B),
                  ),
                ),
                trailing: const Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddSlotDialog(presetFloor: targetFloor);
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.layoutGrid,
                    color: Color(0xFF0F172A),
                    size: 20,
                  ),
                ),
                title: Text(
                  'Generate Row / Panel of Bays',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                subtitle: Text(
                  'Batch generate sequential bays (e.g. 5, 10, or 20 bays)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: const Color(0xFF64748B),
                  ),
                ),
                trailing: const Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddPanelDialog(presetFloor: targetFloor);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddSlotDialog({String? presetFloor}) {
    if (_activeMall == null) return;
    final floors = _getFloorOptions();
    if (floors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No floors indicated for this mall venue.'),
        ),
      );
      return;
    }
    String chosenFloor = (presetFloor != null && floors.contains(presetFloor))
        ? presetFloor
        : (floors.contains(_selectedFloorId) ? _selectedFloorId : floors.first);

    // Auto-detect next sequential slot number for chosenFloor
    final existingSlotsOnFloor = _parkingService.fetchFloorMap(chosenFloor);
    int nextNum = 1;
    if (existingSlotsOnFloor.isNotEmpty) {
      final numbers = existingSlotsOnFloor.map((s) {
        final parts = s.id.split('-');
        return parts.isNotEmpty ? (int.tryParse(parts.last) ?? 0) : 0;
      }).toList();
      if (numbers.isNotEmpty) {
        numbers.sort();
        nextNum = numbers.last + 1;
      }
    }

    final sectionController = TextEditingController(text: 'A');
    final numberController = TextEditingController(text: '$nextNum');
    ParkingSlotStatus chosenStatus = ParkingSlotStatus.free;
    bool isEV = false;
    bool isHandicap = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.plusCircle,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Add Parking Stall',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Floor Level',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: chosenFloor,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: floors
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => chosenFloor = val ?? chosenFloor),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Section',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: sectionController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: 'e.g. A',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Slot Number',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: numberController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'e.g. 1',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Initial Status',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<ParkingSlotStatus>(
                  initialValue: chosenStatus,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ParkingSlotStatus.free,
                      child: Text('Free / Available'),
                    ),
                    DropdownMenuItem(
                      value: ParkingSlotStatus.occupied,
                      child: Text('Occupied'),
                    ),
                    DropdownMenuItem(
                      value: ParkingSlotStatus.reserved,
                      child: Text('Reserved / VIP'),
                    ),
                  ],
                  onChanged: (val) =>
                      setDialogState(() => chosenStatus = val ?? chosenStatus),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'EV Charging Station',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  value: isEV,
                  onChanged: (val) => setDialogState(() => isEV = val),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'Accessible / Handicap',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  value: isHandicap,
                  onChanged: (val) => setDialogState(() => isHandicap = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final section =
                    sectionController.text.trim().toUpperCase().isEmpty
                    ? 'A'
                    : sectionController.text.trim().toUpperCase();
                final slotNum = int.tryParse(numberController.text.trim()) ?? 1;
                final numStr = slotNum < 10 ? '0$slotNum' : '$slotNum';
                final slotId = '$chosenFloor-$section-$numStr';

                final floorAlt = _resolveFloorAltitude(chosenFloor);
                final newSlot = ParkingSlot(
                  id: slotId,
                  floorId: chosenFloor,
                  section: section,
                  slotNumber: slotNum,
                  status: chosenStatus,
                  location: GeodeticCoords(
                    latitude: _activeMall!.latitude,
                    longitude: _activeMall!.longitude,
                    height: floorAlt,
                  ),
                  gridRow: 0,
                  gridCol: 0,
                  isEVCharging: isEV,
                  isHandicapAccessible: isHandicap,
                  sensorId: 'SNS-$chosenFloor-$section$numStr',
                );

                Navigator.pop(ctx);
                await _parkingService.addParkingSlot(_activeMall!.id, newSlot);
                if (mounted) {
                  setState(() {
                    _selectedFloorId = chosenFloor;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Added parking stall "$slotId" successfully!',
                      ),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                }
              },
              child: const Text('Add Stall'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPanelDialog({String? presetFloor}) {
    if (_activeMall == null) return;
    final floors = _getFloorOptions();
    if (floors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No floors indicated for this mall venue.'),
        ),
      );
      return;
    }
    String chosenFloor = (presetFloor != null && floors.contains(presetFloor))
        ? presetFloor
        : (floors.contains(_selectedFloorId) ? _selectedFloorId : floors.first);

    // Auto-detect next sequential start slot number for chosenFloor
    final existingSlotsOnFloor = _parkingService.fetchFloorMap(chosenFloor);
    int nextStartNum = 1;
    if (existingSlotsOnFloor.isNotEmpty) {
      final numbers = existingSlotsOnFloor.map((s) {
        final parts = s.id.split('-');
        return parts.isNotEmpty ? (int.tryParse(parts.last) ?? 0) : 0;
      }).toList();
      if (numbers.isNotEmpty) {
        numbers.sort();
        nextStartNum = numbers.last + 1;
      }
    }

    final sectionController = TextEditingController(text: 'A');
    final startNumController = TextEditingController(text: '$nextStartNum');
    int bayCount = 10;
    bool hasEV = true;
    bool hasHandicap = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.layoutGrid,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Add Bay Panel / Row',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quickly generate a panel or row of parking bays with sequential numbers.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Floor Level',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: chosenFloor,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: floors
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => chosenFloor = val ?? chosenFloor),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Section Code',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: sectionController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: 'e.g. A',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Start Number',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: startNumController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'e.g. 1',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Number of Bays in Panel',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  initialValue: bayCount,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 4, child: Text('4 Bays')),
                    DropdownMenuItem(value: 8, child: Text('8 Bays')),
                    DropdownMenuItem(value: 10, child: Text('10 Bays')),
                    DropdownMenuItem(value: 12, child: Text('12 Bays')),
                    DropdownMenuItem(value: 16, child: Text('16 Bays')),
                    DropdownMenuItem(value: 20, child: Text('20 Bays')),
                  ],
                  onChanged: (val) =>
                      setDialogState(() => bayCount = val ?? bayCount),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'Include EV Charging Bays (first 2)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  value: hasEV,
                  onChanged: (val) => setDialogState(() => hasEV = val),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'Include Accessible Bays (next 2)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  value: hasHandicap,
                  onChanged: (val) => setDialogState(() => hasHandicap = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final section =
                    sectionController.text.trim().toUpperCase().isEmpty
                    ? 'A'
                    : sectionController.text.trim().toUpperCase();
                final startNum =
                    int.tryParse(startNumController.text.trim()) ?? 1;

                Navigator.pop(ctx);
                await _parkingService.addParkingPanel(
                  _activeMall!.id,
                  floorId: chosenFloor,
                  section: section,
                  startNumber: startNum,
                  count: bayCount,
                  baseLat: _activeMall!.latitude,
                  baseLon: _activeMall!.longitude,
                  height: _resolveFloorAltitude(chosenFloor),
                  isEV: hasEV,
                  isHandicap: hasHandicap,
                );

                if (mounted) {
                  setState(() {
                    _selectedFloorId = chosenFloor;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Added $bayCount parking bays in Section $section on $chosenFloor!',
                      ),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                }
              },
              child: const Text('Create Panel'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSlotDetailsModal(ParkingSlot slot) {
    if (_activeMall == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        LucideIcons.car,
                        size: 20,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Stall ${slot.id}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Floor ${slot.floorId} • Section ${slot.section}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(
                    LucideIcons.trash2,
                    color: Color(0xFFEF4444),
                    size: 20,
                  ),
                  tooltip: 'Delete Slot',
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _parkingService.deleteParkingSlot(
                      _activeMall!.id,
                      slot.id,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Deleted parking stall ${slot.id}'),
                          backgroundColor: const Color(0xFFEF4444),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 10),
            Text(
              'UPDATE OCCUPANCY STATUS',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF94A3B8),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _parkingService.updateSlotStatus(
                        _activeMall!.id,
                        slot.id,
                        ParkingSlotStatus.free,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: slot.status == ParkingSlotStatus.free
                          ? const Color(0xFFECFDF5)
                          : Colors.white,
                      side: BorderSide(
                        color: slot.status == ParkingSlotStatus.free
                            ? const Color(0xFF10B981)
                            : const Color(0xFFCBD5E1),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Free / Vacant',
                      style: TextStyle(
                        color: Color(0xFF059669),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _parkingService.updateSlotStatus(
                        _activeMall!.id,
                        slot.id,
                        ParkingSlotStatus.occupied,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: slot.status == ParkingSlotStatus.occupied
                          ? const Color(0xFF0F172A)
                          : Colors.white,
                      side: BorderSide(
                        color: slot.status == ParkingSlotStatus.occupied
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFCBD5E1),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'Occupied',
                      style: TextStyle(
                        color: slot.status == ParkingSlotStatus.occupied
                            ? Colors.white
                            : const Color(0xFF0F172A),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _parkingService.updateSlotStatus(
                        _activeMall!.id,
                        slot.id,
                        ParkingSlotStatus.reserved,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: slot.status == ParkingSlotStatus.reserved
                          ? const Color(0xFFFEF3C7)
                          : Colors.white,
                      side: BorderSide(
                        color: slot.status == ParkingSlotStatus.reserved
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFFCBD5E1),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Reserved',
                      style: TextStyle(
                        color: Color(0xFFD97706),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allFloorSlots = _parkingService.allFloorSlots;
    final allSlots = allFloorSlots.values.expand((s) => s).toList();

    final totalBays = allSlots.length;
    final occupiedBays = allSlots
        .where((s) => s.status == ParkingSlotStatus.occupied)
        .length;
    final reservedVipBays = allSlots
        .where((s) => s.status == ParkingSlotStatus.reserved)
        .length;
    final availableBays = allSlots
        .where((s) => s.status == ParkingSlotStatus.free)
        .length;
    final evBays = allSlots.where((s) => s.isEVCharging).length;

    final occupancyRate = totalBays > 0 ? (occupiedBays / totalBays) : 0.0;
    final indicatedFloors = _getFloorOptions();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Parking Lot & Bay Manager',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0F172A)),
            )
          : _malls.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      LucideIcons.car,
                      size: 48,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Active Venues',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Register a venue in the Venue Package Manager to automatically manage parking stalls.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. ACTIVE MALL MAP WORKFLOW SELECTOR CARD
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
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
                          Text(
                            'ACTIVE MALL MAP PACKAGE',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                              letterSpacing: 0.8,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'AUTO-SYNCED',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_activeMall?.id ?? 'mall-select'),
                        initialValue: _activeMall?.id,
                        isExpanded: true,
                        dropdownColor: Colors.white,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
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
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                        ),
                        items: _malls.map((m) {
                          return DropdownMenuItem(
                            value: m.id,
                            child: Text(
                              m.name.isNotEmpty ? m.name : 'Mall (${m.city})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            _switchActiveMall(val);
                          }
                        },
                      ),
                      if (_activeMall != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Geodetic Anchor: ${_activeMall!.latitude.toStringAsFixed(6)}°N, ${_activeMall!.longitude.toStringAsFixed(6)}°E • ${_activeMall!.floorCount} Stories',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 2. OVERVIEW SUMMARY CARD
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Real-Time Parking Capacity',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Vehicle bay tracking for ${_activeMall?.name ?? 'Selected Mall'}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: occupancyRate,
                          backgroundColor: const Color(0xFFF1F5F9),
                          color: const Color(0xFF0F172A),
                          minHeight: 10,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatCol('TOTAL', '$totalBays'),
                          _buildStatCol('OCCUPIED', '$occupiedBays'),
                          _buildStatCol('AVAILABLE', '$availableBays'),
                          _buildStatCol('RESERVED', '$reservedVipBays'),
                          _buildStatCol('EV BAYS', '$evBays'),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 4. INTERACTIVE PARKING STALL INSPECTOR & BAY GRID
                if (indicatedFloors.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'BAY LAYOUT INSPECTOR',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF475569),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: indicatedFloors.map((fId) {
                                    final isSelected = fId == _selectedFloorId;
                                    return GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedFloorId = fId;
                                        });
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFF0F172A)
                                              : const Color(0xFFF1F5F9),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          fId,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? Colors.white
                                                : const Color(0xFF475569),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Grid of Parking Slots for Selected Floor
                        Builder(
                          builder: (context) {
                            final currentFloorSlots = _parkingService
                                .fetchFloorMap(_selectedFloorId);
                            if (currentFloorSlots.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  children: [
                                    const Icon(
                                      LucideIcons.parkingSquare,
                                      size: 32,
                                      color: Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No parking stalls generated for $_selectedFloorId yet.',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 1.35,
                              ),
                              itemCount: currentFloorSlots.length,
                              itemBuilder: (context, index) {
                                final slot = currentFloorSlots[index];

                                Color bgColor = const Color(0xFFF8FAFC);
                                Color borderColor = const Color(0xFFE2E8F0);
                                Color textColor = const Color(0xFF0F172A);

                                if (slot.status == ParkingSlotStatus.occupied) {
                                  bgColor = const Color(0xFF0F172A);
                                  borderColor = const Color(0xFF0F172A);
                                  textColor = Colors.white;
                                } else if (slot.status ==
                                    ParkingSlotStatus.reserved) {
                                  bgColor = const Color(0xFFFEF3C7);
                                  borderColor = const Color(0xFFFCD34D);
                                  textColor = const Color(0xFF92400E);
                                }

                                return InkWell(
                                  onTap: () => _showSlotDetailsModal(slot),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            if (slot.isEVCharging)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 2,
                                                ),
                                                child: Icon(
                                                  LucideIcons.zap,
                                                  size: 9,
                                                  color: textColor,
                                                ),
                                              ),
                                            if (slot.isHandicapAccessible)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 2,
                                                ),
                                                child: Icon(
                                                  LucideIcons.accessibility,
                                                  size: 9,
                                                  color: textColor,
                                                ),
                                              ),
                                            Text(
                                              slot.id,
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                    color: textColor,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          slot.status.name.toUpperCase(),
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.bold,
                                            color: textColor.withValues(
                                              alpha: 0.8,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // Primary "Add New Parking Slots" Action Button
                if (indicatedFloors.isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showAddParkingSlotsSheet(
                        presetFloor: _selectedFloorId,
                      ),
                      icon: const Icon(LucideIcons.plusCircle, size: 18),
                      label: Text(
                        'Add New Parking Slots on $_selectedFloorId',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 5. QUICK ACTIONS
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          if (_activeMall != null) {
                            await _parkingService.resetAllSlotsToFree(
                              _activeMall!.id,
                            );
                            if (mounted) {
                              // ignore: use_build_context_synchronously
                              // ignore: use_build_context_synchronously
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'All parking bays reset to FREE for ${_activeMall?.name}',
                                  ),
                                  backgroundColor: const Color(0xFF0F172A),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: const Color(0xFF0F172A),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'RESET TO FREE',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          if (_activeMall != null) {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Clear All Bays?'),
                                content: Text(
                                  'This will delete all configured parking stalls for ${_activeMall?.name}.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFEF4444),
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Clear All'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _parkingService.clearAllSlotsForMall(
                                _activeMall!.id,
                              );
                              if (mounted) {
                                // ignore: use_build_context_synchronously
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Cleared all parking bays for ${_activeMall?.name}',
                                    ),
                                    backgroundColor: const Color(0xFF0F172A),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              }
                            }
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'CLEAR ALL BAYS',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_parkingService.hasParkedVehicle) {
                            _parkingService.clearVehicleLocation();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Cleared active test user parking pin',
                                ),
                                backgroundColor: const Color(0xFF0F172A),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'No active test parking pins to clear',
                                ),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'CLEAR USER PINS',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildStatCol(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}
