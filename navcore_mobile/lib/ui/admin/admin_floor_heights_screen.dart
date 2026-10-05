import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../data/floor_height_model.dart';
import '../../data/mall_api_service.dart';

class AdminFloorHeightsScreen extends StatefulWidget {
  final String mallId;
  final RestMallBackendApi apiService;

  const AdminFloorHeightsScreen({
    super.key,
    this.mallId = 'mall-one-galle-face',
    required this.apiService,
  });

  @override
  State<AdminFloorHeightsScreen> createState() => _AdminFloorHeightsScreenState();
}

class _AdminFloorHeightsScreenState extends State<AdminFloorHeightsScreen> {
  List<FloorHeightData> _floors = [];
  bool _isLoading = true;
  bool _isCalculating = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadFloorHeights();
  }

  Future<void> _loadFloorHeights() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final list = await widget.apiService.fetchFloorHeights(widget.mallId);
      if (mounted) {
        setState(() {
          _floors = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Error loading floor heights: $e';
        });
      }
    }
  }

  Future<void> _runAutoCalculation() async {
    setState(() {
      _isCalculating = true;
      _statusMessage = null;
    });

    try {
      final updatedList = await widget.apiService.triggerFloorHeightCalculation(widget.mallId);
      if (mounted) {
        setState(() {
          _floors = updatedList;
          _isCalculating = false;
          _statusMessage = '✅ Auto-calculation completed successfully across all unlocked floors!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCalculating = false;
          _statusMessage = '⚠️ Auto-calculation failed: $e';
        });
      }
    }
  }

  Future<void> _toggleLock(FloorHeightData floor, bool newLockState) async {
    try {
      final updated = await widget.apiService.updateFloorHeight(
        widget.mallId,
        floor.floorNo,
        isLocked: newLockState,
      );

      setState(() {
        final idx = _floors.indexWhere((f) => f.floorNo == floor.floorNo);
        if (idx >= 0) {
          _floors[idx] = updated;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update lock state: $e')),
      );
    }
  }

  void _showEditDialog(FloorHeightData floor) {
    final textController = TextEditingController(
      text: floor.heightToNextM.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Override Height for Floor ${floor.floorNo}',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter manual height to next floor (meters). This will set source to "admin" and lock the floor from auto-updates.',
              style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: textController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.inter(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Height to Next Floor (m)',
                labelStyle: const TextStyle(color: Colors.cyanAccent),
                suffixText: 'meters',
                suffixStyle: const TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white30),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.cyanAccent),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final newHeight = double.tryParse(textController.text.trim());
              if (newHeight == null || newHeight < 0.0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid positive number')),
                );
                return;
              }

              Navigator.pop(ctx);
              try {
                await widget.apiService.updateFloorHeight(
                  widget.mallId,
                  floor.floorNo,
                  heightToNextM: newHeight,
                  isLocked: true,
                );

                await _loadFloorHeights();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating floor height: $e')),
                  );
                }
              }
            },
            child: const Text('Save & Lock'),
          ),
        ],
      ),
    );
  }

  Color _getSourceBadgeColor(String source) {
    switch (source.toLowerCase()) {
      case 'admin':
        return Colors.purpleAccent;
      case 'barometer':
        return Colors.greenAccent;
      case 'osm':
        return Colors.lightBlueAccent;
      case 'default':
      default:
        return Colors.orangeAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 2,
        title: Text(
          'Automatic Height Between Floors',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, color: Colors.cyanAccent),
            tooltip: 'Refresh Table',
            onPressed: _loadFloorHeights,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mall ID: ${widget.mallId}',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Auto-calculation derives heights using barometer pressure delta (P_lower - P_upper) * 8.3m, with OSM & default fallbacks.',
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isCalculating ? null : _runAutoCalculation,
                          icon: _isCalculating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(LucideIcons.calculator, size: 18),
                          label: Text(
                            _isCalculating ? 'Calculating...' : 'Re-run Auto-Calc',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _statusMessage!,
                        style: GoogleFonts.inter(color: Colors.cyanAccent, fontSize: 13),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
                          dataRowColor: WidgetStateProperty.all(const Color(0xFF0F172A)),
                          border: TableBorder.all(color: Colors.white12, width: 1, borderRadius: BorderRadius.circular(8)),
                          columns: [
                            DataColumn(label: Text('Floor', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Height to Next (m)', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Base Altitude (m)', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Source', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Confidence', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Locked', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Actions', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold))),
                          ],
                          rows: _floors.map((floor) {
                            final badgeColor = _getSourceBadgeColor(floor.source);
                            final isTopFloor = floor.heightToNextM == 0.0 && floor.floorNo == _floors.last.floorNo;

                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    floor.floorNo < 0 ? 'B${floor.floorNo.abs()}' : 'Floor ${floor.floorNo}',
                                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    isTopFloor ? 'N/A (Top)' : '${floor.heightToNextM.toStringAsFixed(2)} m',
                                    style: GoogleFonts.inter(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${floor.baseAltitudeM.toStringAsFixed(2)} m',
                                    style: GoogleFonts.inter(color: Colors.white70),
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.15),
                                      border: Border.all(color: badgeColor, width: 1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      floor.source.toUpperCase(),
                                      style: GoogleFonts.inter(
                                        color: badgeColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${(floor.confidence * 100).toStringAsFixed(0)}%',
                                    style: GoogleFonts.inter(color: Colors.white),
                                  ),
                                ),
                                DataCell(
                                  Switch(
                                    value: floor.isLocked,
                                    activeTrackColor: Colors.purpleAccent,
                                    onChanged: (val) => _toggleLock(floor, val),
                                  ),
                                ),
                                DataCell(
                                  IconButton(
                                    icon: const Icon(LucideIcons.edit3, size: 18, color: Colors.cyanAccent),
                                    tooltip: 'Edit / Override Height',
                                    onPressed: () => _showEditDialog(floor),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
