import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../data/floor_height_model.dart';
import '../../data/mall_api_service.dart';

class AdminFloorHeightsScreen extends StatefulWidget {
  final String mallId;
  final RestMallBackendApi apiService;
  final ValueChanged<List<FloorHeightData>>? onHeightsUpdated;
  final ValueChanged<String>? onMallSelected;

  const AdminFloorHeightsScreen({
    super.key,
    this.mallId = 'mall-one-galle-face',
    required this.apiService,
    this.onHeightsUpdated,
    this.onMallSelected,
  });

  @override
  State<AdminFloorHeightsScreen> createState() => _AdminFloorHeightsScreenState();
}

class _AdminFloorHeightsScreenState extends State<AdminFloorHeightsScreen> {
  late String _selectedMallId;
  List<FloorHeightData> _floors = [];
  bool _isLoading = true;
  bool _isCalculating = false;
  String? _statusMessage;

  final Map<String, String> _knownMallNames = {
    'mall-one-galle-face': 'One Galle Face Mall',
    'mall-colombo-city-centre': 'Colombo City Centre (CCC)',
    'mall-havelock-city': 'Havelock City Mall',
    'mall-kandy-city-centre': 'Kandy City Centre (KCC)',
    'mall-marino-mall': 'Marino Mall',
  };

  late List<String> _availableMallIds;

  @override
  void initState() {
    super.initState();
    _selectedMallId = widget.mallId;
    _availableMallIds = [
      'mall-one-galle-face',
      'mall-colombo-city-centre',
      'mall-havelock-city',
      'mall-kandy-city-centre',
      'mall-marino-mall',
    ];

    if (!_availableMallIds.contains(widget.mallId)) {
      _availableMallIds.insert(0, widget.mallId);
    }

    _loadFloorHeights();
  }

  void _onMallChanged(String? newMallId) {
    if (newMallId == null || newMallId == _selectedMallId) return;
    setState(() {
      _selectedMallId = newMallId;
      _statusMessage = null;
    });
    widget.onMallSelected?.call(newMallId);
    _loadFloorHeights();
  }

  Future<void> _loadFloorHeights() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final list = await widget.apiService.fetchFloorHeights(_selectedMallId);
      if (mounted) {
        setState(() {
          _floors = list;
          _isLoading = false;
        });
        widget.onHeightsUpdated?.call(_floors);
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
      final updatedList = await widget.apiService.triggerFloorHeightCalculation(_selectedMallId);
      if (mounted) {
        setState(() {
          _floors = updatedList;
          _isCalculating = false;
          _statusMessage = 'Auto-calculation completed successfully across all unlocked floors!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCalculating = false;
          _statusMessage = 'Auto-calculation failed: $e';
        });
      }
    }
  }

  void _showEditDialog(FloorHeightData floor) {
    final textController = TextEditingController(
      text: floor.heightToNextM.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Override Height for Floor ${floor.floorNo}',
          style: GoogleFonts.outfit(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter manual height to next floor (meters). This will set source to "admin" and lock the floor from auto-updates.',
              style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: textController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.inter(color: const Color(0xFF0F172A)),
              decoration: InputDecoration(
                labelText: 'Height to Next Floor (m)',
                labelStyle: const TextStyle(color: Color(0xFF0D9488)),
                suffixText: 'meters',
                suffixStyle: const TextStyle(color: Color(0xFF64748B)),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF0D9488), width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                  _selectedMallId,
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

  void _confirmAndDeleteFloor(FloorHeightData floor) {
    final floorLabel = floor.floorNo < 0 ? 'B${floor.floorNo.abs()}' : 'Floor ${floor.floorNo}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete $floorLabel?',
          style: GoogleFonts.outfit(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete $floorLabel? Base altitudes for remaining floors will automatically be recalculated.',
          style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final updatedList = await widget.apiService.deleteFloor(_selectedMallId, floor.floorNo);
                if (mounted) {
                  setState(() {
                    _floors = updatedList;
                    _statusMessage = '$floorLabel deleted successfully.';
                  });
                  widget.onHeightsUpdated?.call(_floors);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting floor: $e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Color _getSourceBadgeColor(String source) {
    switch (source.toLowerCase()) {
      case 'admin':
        return const Color(0xFF7E22CE);
      case 'barometer':
        return const Color(0xFF15803D);
      case 'osm':
        return const Color(0xFF0284C7);
      case 'default':
      default:
        return const Color(0xFFC2410C);
    }
  }

  Color _getSourceBadgeBgColor(String source) {
    switch (source.toLowerCase()) {
      case 'admin':
        return const Color(0xFFF3E8FF);
      case 'barometer':
        return const Color(0xFFDCFCE7);
      case 'osm':
        return const Color(0xFFE0F2FE);
      case 'default':
      default:
        return const Color(0xFFFFEDD5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        shape: const Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        title: Text(
          'Automatic Height Between Floors',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: const Color(0xFF0F172A),
          ),
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, color: Color(0xFF0D9488)),
            tooltip: 'Refresh Table',
            onPressed: _loadFloorHeights,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0D9488)))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Info Card with Mall Selector Dropdown
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SELECT MALL',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF64748B),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFCBD5E1)),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedMallId,
                                    isExpanded: true,
                                    icon: const Icon(LucideIcons.chevronDown, size: 18, color: Color(0xFF0D9488)),
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF0F172A),
                                    ),
                                    dropdownColor: Colors.white,
                                    items: _availableMallIds.map((mallId) {
                                      final displayName = _knownMallNames[mallId] ?? mallId;
                                      return DropdownMenuItem<String>(
                                        value: mallId,
                                        child: Text(
                                          displayName,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.outfit(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: _onMallChanged,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isCalculating ? null : _runAutoCalculation,
                          icon: _isCalculating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(LucideIcons.calculator, size: 16),
                          label: Text(
                            _isCalculating ? 'Calculating...' : 'Re-run Auto-Calc',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
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
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.checkCircle, size: 16, color: Color(0xFF047857)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: GoogleFonts.inter(
                                color: const Color(0xFF047857),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Data Table Card
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columnSpacing: 28,
                              headingRowHeight: 48,
                              dataRowMinHeight: 52,
                              dataRowMaxHeight: 56,
                              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                              dataRowColor: WidgetStateProperty.all(Colors.white),
                              border: const TableBorder(
                                horizontalInside: BorderSide(color: Color(0xFFF1F5F9), width: 1),
                              ),
                              columns: [
                                DataColumn(
                                  label: Text(
                                    'Floor',
                                    style: GoogleFonts.outfit(
                                      color: const Color(0xFF1E293B),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Height to Next (m)',
                                    style: GoogleFonts.outfit(
                                      color: const Color(0xFF1E293B),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Base Altitude (m)',
                                    style: GoogleFonts.outfit(
                                      color: const Color(0xFF1E293B),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Source',
                                    style: GoogleFonts.outfit(
                                      color: const Color(0xFF1E293B),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Actions',
                                    style: GoogleFonts.outfit(
                                      color: const Color(0xFF1E293B),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                              rows: _floors.map((floor) {
                                final badgeTextColor = _getSourceBadgeColor(floor.source);
                                final badgeBgColor = _getSourceBadgeBgColor(floor.source);
                                final isTopFloor = floor.heightToNextM == 0.0 && floor.floorNo == _floors.last.floorNo;

                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        floor.floorNo < 0 ? 'B${floor.floorNo.abs()}' : 'Floor ${floor.floorNo}',
                                        style: GoogleFonts.inter(
                                          color: const Color(0xFF0F172A),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                        softWrap: false,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        isTopFloor ? 'N/A (Top)' : '${floor.heightToNextM.toStringAsFixed(2)} m',
                                        style: GoogleFonts.inter(
                                          color: const Color(0xFF0D9488),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                        softWrap: false,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${floor.baseAltitudeM.toStringAsFixed(2)} m',
                                        style: GoogleFonts.inter(
                                          color: const Color(0xFF475569),
                                          fontSize: 13,
                                        ),
                                        softWrap: false,
                                      ),
                                    ),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: badgeBgColor,
                                          border: Border.all(color: badgeTextColor.withValues(alpha: 0.4), width: 1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          floor.source.toUpperCase(),
                                          style: GoogleFonts.inter(
                                            color: badgeTextColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(LucideIcons.edit3, size: 18, color: Color(0xFF0D9488)),
                                            tooltip: 'Edit / Override Height',
                                            onPressed: () => _showEditDialog(floor),
                                          ),
                                          IconButton(
                                            icon: const Icon(LucideIcons.trash2, size: 18, color: Color(0xFFEF4444)),
                                            tooltip: 'Delete Floor',
                                            onPressed: () => _confirmAndDeleteFloor(floor),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
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

