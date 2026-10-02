import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/parking_service.dart';
import '../../data/mall_database_service.dart';

class AdminParkingManagerScreen extends StatefulWidget {
  const AdminParkingManagerScreen({super.key});

  @override
  State<AdminParkingManagerScreen> createState() => _AdminParkingManagerScreenState();
}

class _AdminParkingManagerScreenState extends State<AdminParkingManagerScreen> {
  final ParkingService _parkingService = ParkingService();
  final MallDatabaseService _mallService = MallDatabaseService();

  List<MallMetadata> _malls = [];
  MallMetadata? _activeMall;
  String _selectedFloorId = 'B1';
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
    final active = malls.firstWhere((m) => m.isActive, orElse: () => malls.first);

    _parkingService.loadLayoutForMallMetadata(
      mallId: active.id,
      baseLat: active.latitude,
      baseLon: active.longitude,
      basementFloors: active.floorCount >= 5 ? 3 : 2,
    );

    if (mounted) {
      setState(() {
        _malls = malls;
        _activeMall = active;
        final availableFloors = _parkingService.allFloorSlots.keys.toList();
        if (!availableFloors.contains(_selectedFloorId) && availableFloors.isNotEmpty) {
          _selectedFloorId = availableFloors.first;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _switchActiveMall(String newMallId) async {
    final selected = _malls.firstWhere((m) => m.id == newMallId, orElse: () => _malls.first);
    await _mallService.setActiveMall(selected.id);

    final updatedMalls = await _mallService.getMallsList();

    _parkingService.loadLayoutForMallMetadata(
      mallId: selected.id,
      baseLat: selected.latitude,
      baseLon: selected.longitude,
      basementFloors: selected.floorCount >= 5 ? 3 : 2,
    );

    if (mounted) {
      setState(() {
        _malls = updatedMalls;
        _activeMall = selected;
        final availableFloors = _parkingService.allFloorSlots.keys.toList();
        if (!availableFloors.contains(_selectedFloorId) && availableFloors.isNotEmpty) {
          _selectedFloorId = availableFloors.first;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched parking lot layout to ${selected.name} (${selected.city})'),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allFloorSlots = _parkingService.allFloorSlots;
    final allSlots = allFloorSlots.values.expand((s) => s).toList();

    final totalBays = allSlots.length;
    final occupiedBays = allSlots.where((s) => s.status == ParkingSlotStatus.occupied).length;
    final reservedVipBays = allSlots.where((s) => s.status == ParkingSlotStatus.reserved).length;
    final availableBays = allSlots.where((s) => s.status == ParkingSlotStatus.free).length;
    final evBays = allSlots.where((s) => s.isEVCharging).length;

    final occupancyRate = totalBays > 0 ? (occupiedBays / totalBays) : 0.0;

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
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A)))
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                        ),
                        items: _malls.map((m) {
                          return DropdownMenuItem(
                            value: m.id,
                            child: Text(
                              '${m.name} (${m.city})',
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
                        'Map-based vehicle bay tracking for ${_activeMall?.name ?? 'Selected Mall'}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
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

                const SizedBox(height: 20),

                Text(
                  'FLOOR-BY-FLOOR BAY ALLOCATION',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF94A3B8),
                    letterSpacing: 1.1,
                  ),
                ),

                const SizedBox(height: 10),

                // 3. FLOOR-BY-FLOOR ALLOCATION CARDS
                ...allFloorSlots.entries.map((entry) {
                  final floorId = entry.key;
                  final slots = entry.value;
                  final capacity = slots.length;
                  final occupied = slots.where((s) => s.status == ParkingSlotStatus.occupied).length;
                  final free = slots.where((s) => s.status == ParkingSlotStatus.free).length;
                  final percent = capacity > 0 ? (occupied / capacity * 100).toInt() : 0;
                  final floorEvs = slots.where((s) => s.isEVCharging).length;
                  final floorHandicaps = slots.where((s) => s.isHandicapAccessible).length;

                  String statusText = 'AVAILABLE';
                  if (percent > 75) {
                    statusText = 'HIGH OCCUPANCY';
                  } else if (percent > 40) {
                    statusText = 'NORMAL';
                  }

                  final floorName = floorId == 'GF'
                      ? 'Ground Surface Parking (GF)'
                      : '$floorId Basement Level';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
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
                              child: Text(
                                floorName,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                statusText,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF334155),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          runSpacing: 4,
                          children: [
                            Text(
                              '$occupied / $capacity Bays Occupied ($percent%) • $free Available',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11.5,
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '$floorEvs EV  •  $floorHandicaps Accessible',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: capacity > 0 ? (occupied / capacity) : 0.0,
                            backgroundColor: const Color(0xFFF1F5F9),
                            color: const Color(0xFF0F172A),
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 16),

                // 4. INTERACTIVE PARKING STALL INSPECTOR & BAY GRID
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: allFloorSlots.keys.map((fId) {
                                final isSelected = fId == _selectedFloorId;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedFloorId = fId;
                                    });
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      fId,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? Colors.white : const Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Grid of Parking Slots for Selected Floor
                      Builder(builder: (context) {
                        final currentFloorSlots = allFloorSlots[_selectedFloorId] ?? [];
                        if (currentFloorSlots.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('No parking stalls generated for this floor.'),
                          );
                        }

                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1.4,
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
                            } else if (slot.status == ParkingSlotStatus.reserved) {
                              bgColor = const Color(0xFFE2E8F0);
                              borderColor = const Color(0xFFCBD5E1);
                              textColor = const Color(0xFF334155);
                            }

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  if (slot.status == ParkingSlotStatus.free) {
                                    slot.status = ParkingSlotStatus.occupied;
                                  } else if (slot.status == ParkingSlotStatus.occupied) {
                                    slot.status = ParkingSlotStatus.reserved;
                                  } else {
                                    slot.status = ParkingSlotStatus.free;
                                  }
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      slot.id,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      slot.status.name.toUpperCase(),
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        color: textColor.withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 5. QUICK ACTIONS
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _parkingService.resetAllSlotsToFree();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('All parking bays reset to FREE for ${_activeMall?.name}'),
                              backgroundColor: const Color(0xFF0F172A),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: const Color(0xFF0F172A),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'RESET ALL SLOTS',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_parkingService.hasParkedVehicle) {
                            _parkingService.clearVehicleLocation();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Cleared active test user parking pin'),
                                backgroundColor: const Color(0xFF0F172A),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('No active test parking pins to clear'),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'CLEAR USER PINS',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold),
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
