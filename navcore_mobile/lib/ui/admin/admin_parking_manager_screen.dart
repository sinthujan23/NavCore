import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/parking_service.dart';

class AdminParkingManagerScreen extends StatefulWidget {
  const AdminParkingManagerScreen({super.key});

  @override
  State<AdminParkingManagerScreen> createState() => _AdminParkingManagerScreenState();
}

class _AdminParkingManagerScreenState extends State<AdminParkingManagerScreen> {
  final ParkingService _parkingService = ParkingService();

  final int _totalBays = 350;
  final int _occupiedBays = 182;
  final int _reservedVipBays = 24;

  final List<Map<String, dynamic>> _parkingFloors = [
    {'level': 'B1 Basement', 'capacity': 120, 'occupied': 68, 'status': 'NORMAL'},
    {'level': 'B2 Basement', 'capacity': 130, 'occupied': 84, 'status': 'HIGH OCCUPANCY'},
    {'level': 'B3 Lower Basement', 'capacity': 100, 'occupied': 30, 'status': 'AVAILABLE'},
  ];

  @override
  Widget build(BuildContext context) {
    final availableBays = _totalBays - _occupiedBays - _reservedVipBays;

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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Overview Summary Card
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(LucideIcons.car, color: Color(0xFFD97706), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
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
                          Text(
                            'Smart vehicle bay tracking across multi-level basements',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _occupiedBays / _totalBays,
                    backgroundColor: const Color(0xFFF1F5F9),
                    color: const Color(0xFFD97706),
                    minHeight: 10,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatCol('TOTAL BAYS', '$_totalBays', const Color(0xFF0F172A)),
                    _buildStatCol('OCCUPIED', '$_occupiedBays', const Color(0xFFEF4444)),
                    _buildStatCol('AVAILABLE', '$availableBays', const Color(0xFF059669)),
                    _buildStatCol('RESERVED', '$_reservedVipBays', const Color(0xFFD97706)),
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

          ..._parkingFloors.map((floor) {
            final capacity = floor['capacity'] as int;
            final occupied = floor['occupied'] as int;
            final percent = (occupied / capacity * 100).toInt();

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
                      Text(
                        floor['level'] as String,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: percent > 70
                              ? const Color(0xFFFEF2F2)
                              : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          floor['status'] as String,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: percent > 70 ? const Color(0xFFDC2626) : const Color(0xFF047857),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$occupied / $capacity Bays Occupied ($percent%)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: occupied / capacity,
                      backgroundColor: const Color(0xFFF1F5F9),
                      color: percent > 70 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          ElevatedButton.icon(
            onPressed: () {
              if (_parkingService.hasParkedVehicle) {
                _parkingService.clearVehicleLocation();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Cleared active test user parking pin'),
                    backgroundColor: const Color(0xFF10B981),
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
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: Text(
              'CLEAR EXPIRED PARKING SESSIONS',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCol(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}
