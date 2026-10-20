import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../engine/floor_tracker.dart';
import '../engine/ecef_engine.dart';
import '../engine/bearing_engine.dart';
import '../data/destinations.dart';
import '../data/parking_service.dart';
import '../data/api_service.dart';
import '../data/mall_database_service.dart';
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
  final DestinationPOI? targetDestination;
  final VoidCallback? onClearTargetDestination;
  final VoidCallback? onBackClicked;
  final String userEmail;
  final VoidCallback? onLogout;
  final MallDatabaseService? mallService;
  final VoidCallback? onOpenMallExplorer;
  final VoidCallback? onRefreshLocation;

  const FloorPlanScreen({
    super.key,
    required this.buildingProfile,
    required this.currentFloor,
    required this.onSelectFloor,
    required this.userCoords,
    required this.destinations,
    required this.onSimulateMove,
    this.targetDestination,
    this.onClearTargetDestination,
    this.onSelectDestination,
    this.onBackClicked,
    this.userEmail = '',
    this.onLogout,
    this.mallService,
    this.onOpenMallExplorer,
    this.onRefreshLocation,
    this.isAdmin = false,
    this.onOpenAdminDashboard,
  });

  final bool isAdmin;
  final VoidCallback? onOpenAdminDashboard;

  @override
  State<FloorPlanScreen> createState() => FloorPlanScreenState();
}

class FloorPlanScreenState extends State<FloorPlanScreen>
    with SingleTickerProviderStateMixin {
  DestinationPOI? _selectedPOI;
  ParkingSlot? _selectedParkingSlot;
  FloorLevelConfig? _overrideFloor;
  String _selectedCategoryFilter = 'ALL';
  bool _showFilterChips = false;
  final double _zoomScale = 1.0;
  final bool _showDpad = false;
  final ParkingService _parkingService = ParkingService();
  bool _isServerOnline = false;
  Timer? _parkingAutoRefreshTimer;
  StreamSubscription<String>? _parkingSyncSubscription;

  late AnimationController _pulseController;

  FloorLevelConfig get displayFloor => _overrideFloor ?? widget.currentFloor;

  Future<void> _checkServerHealth() async {
    try {
      final isUp = await ApiService.instance.testConnection();
      if (mounted && isUp != _isServerOnline) {
        setState(() => _isServerOnline = isUp);
      }
    } catch (_) {
      if (mounted && _isServerOnline) {
        setState(() => _isServerOnline = false);
      }
    }
  }

  void clearSelection() {
    if (mounted) {
      setState(() {
        _selectedPOI = null;
        _selectedParkingSlot = null;
      });
    }
  }

  String? _resolveActiveMallId() {
    if (widget.buildingProfile.buildingId.isNotEmpty) {
      return widget.buildingProfile.buildingId;
    }
    if (widget.mallService != null) {
      final active = widget.mallService!.catalog.where((m) => m.isActive);
      if (active.isNotEmpty) return active.first.id;
    }
    return null;
  }

  Future<void> _loadParkingSlots() async {
    String? mallId = _resolveActiveMallId();
    if (mallId == null || mallId.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      mallId =
          prefs.getString('NexNav_active_mall_id') ??
          prefs.getString('active_mall_id');
    }
    if (mallId == null || mallId.trim().isEmpty) {
      return;
    }
    await _parkingService.loadSlotsForMall(mallId.trim());
    if (mounted) {
      setState(() {});
    }
  }

  String _getFloorIdString(FloorLevelConfig floor) {
    final norm = ParkingService.normalizeFloorId(floor.floorId);
    if (norm == 'P' || floor.floorId.toUpperCase() == 'P') {
      return 'P';
    }
    if (floor.floorNumber < 0) {
      return 'B${floor.floorNumber.abs()}';
    }
    if (norm == 'B1' || norm == 'B2' || norm == 'B3') {
      return norm;
    }
    final nameNorm = ParkingService.normalizeFloorId(floor.name);
    if (nameNorm == 'P' || floor.name.toUpperCase().contains('PARK')) {
      return 'P';
    }
    if (nameNorm == 'B1' || nameNorm == 'B2' || nameNorm == 'B3') {
      return nameNorm;
    }
    if (floor.floorNumber == 0 || norm == 'GF') {
      return 'GF';
    }
    return floor.floorId.isNotEmpty && floor.floorId.startsWith('F')
        ? floor.floorId
        : 'F${floor.floorNumber}';
  }

  String _getFloorPillLabel(FloorLevelConfig floor) {
    final norm = ParkingService.normalizeFloorId(floor.floorId);
    if (norm == 'P' || floor.floorId.toUpperCase() == 'P') {
      return 'P';
    }
    if (floor.floorNumber < 0) {
      return 'B${floor.floorNumber.abs()}';
    }
    if (norm == 'B1' || norm == 'B2' || norm == 'B3') {
      return norm;
    }
    final nameNorm = ParkingService.normalizeFloorId(floor.name);
    if (nameNorm == 'P' || floor.name.toUpperCase().contains('PARK')) {
      return 'P';
    }
    if (nameNorm == 'B1' || nameNorm == 'B2' || nameNorm == 'B3') {
      return nameNorm;
    }
    if (floor.floorNumber == 0 || norm == 'GF') {
      return 'GF';
    }
    return 'F${floor.floorNumber}';
  }

  List<FloorLevelConfig> get _effectiveFloorLevels {
    if (widget.buildingProfile.buildingId.isEmpty ||
        widget.buildingProfile.floors.isEmpty) {
      return const [];
    }
    final List<FloorLevelConfig> floors = [];

    // Add profile floors first
    for (final f in widget.buildingProfile.floors) {
      floors.add(f);
    }

    final bId = widget.buildingProfile.buildingId.isNotEmpty
        ? widget.buildingProfile.buildingId
        : (_resolveActiveMallId() ?? '');
    final double groundAlt = widget.buildingProfile.entranceBaseAnchorHeight > 0
        ? widget.buildingProfile.entranceBaseAnchorHeight
        : 8.5;
    final double gap = widget.buildingProfile.floorGapMeters > 0
        ? widget.buildingProfile.floorGapMeters
        : 3.8;

    // Collect all candidate parking floors: ALWAYS include 'P' by default so parking is never missing!
    final candidateParkingFloors = <String>{'P'};

    // Check if mall metadata has configured parking floors
    if (widget.mallService != null && bId.isNotEmpty) {
      final matches = widget.mallService!.catalog.where(
        (m) =>
            ParkingService.normalizeMallId(m.id) ==
            ParkingService.normalizeMallId(bId),
      );
      if (matches.isNotEmpty) {
        for (final pf in matches.first.parkingFloors) {
          if (pf.trim().isNotEmpty) candidateParkingFloors.add(pf.trim());
        }
      }
    }

    // Also include any floors detected in ParkingService
    final mallSlots = _parkingService.getFloorSlotsForMall(bId);
    candidateParkingFloors.addAll(mallSlots.keys);

    for (final pId in candidateParkingFloors) {
      final normKey = ParkingService.normalizeFloorId(pId);
      int fNum = -1;
      if (normKey == 'P') {
        fNum = -1;
      } else if (normKey.startsWith('B')) {
        final digits =
            int.tryParse(normKey.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
        fNum = -digits;
      } else if (normKey == 'GF' || normKey == 'G' || normKey == '0') {
        fNum = 0;
      } else {
        final digits = int.tryParse(normKey.replaceAll(RegExp(r'[^0-9]'), ''));
        if (digits != null) fNum = digits;
      }

      final alreadyPresent = floors.any((f) {
        final fNorm = ParkingService.normalizeFloorId(f.floorId);
        final nameNorm = ParkingService.normalizeFloorId(f.name);
        return fNorm == normKey ||
            nameNorm == normKey ||
            (normKey == 'P' &&
                (fNorm == 'P' || f.floorNumber < 0 || fNorm == 'B1'));
      });

      if (!alreadyPresent) {
        final double alt = fNum <= 0
            ? (groundAlt + (fNum * gap))
            : (groundAlt + ((fNum - 1) * gap));

        floors.add(
          FloorLevelConfig(
            floorId: normKey == 'P' ? 'P' : pId,
            floorNumber: fNum,
            name: normKey == 'P'
                ? 'Parking (P)'
                : (normKey.startsWith('B')
                      ? 'Basement $normKey'
                      : (normKey == 'GF' ? 'Ground Floor' : 'Floor F$pId')),
            relativeVectorMeters: (fNum - 1) * gap,
            absoluteHeightMeters: alt,
            bandMinMeters: alt - 2.0,
            bandMaxMeters: alt + 2.0,
            storesCount: 0,
          ),
        );
      }
    }

    // Sort floors by floorNumber ascending (-2, -1, 0, 1, 2...) so P (-1) is first
    floors.sort((a, b) => a.floorNumber.compareTo(b.floorNumber));
    return floors;
  }

  List<ParkingSlot> _getSlotsForDisplayFloor(FloorLevelConfig floor) {
    final bId = widget.buildingProfile.buildingId.isNotEmpty
        ? widget.buildingProfile.buildingId
        : (_resolveActiveMallId() ?? '');
    if (bId.isEmpty) {
      return const [];
    }
    final primaryId = _getFloorIdString(floor);
    final primarySlots = _parkingService.fetchFloorMap(primaryId, bId);
    if (primarySlots.isNotEmpty) return primarySlots;

    final isParkFloor =
        primaryId == 'P' ||
        primaryId == 'B1' ||
        primaryId.startsWith('B') ||
        primaryId.startsWith('P') ||
        floor.floorId.toUpperCase().startsWith('P') ||
        floor.name.toUpperCase().contains('PARK') ||
        floor.name.toUpperCase().contains('BASEMENT') ||
        floor.floorNumber < 0;

    final candidateKeys = <String>{
      primaryId,
      floor.floorId,
      floor.name,
      '${floor.floorNumber}',
      if (isParkFloor) ...['P', 'B1', 'B2', 'B3', 'P1', 'P2', 'Parking', 'GF'],
      if (floor.floorNumber < 0) 'B${floor.floorNumber.abs()}',
      if (floor.floorNumber < 0) 'Basement ${floor.floorNumber.abs()}',
      if (floor.floorNumber == 0) ...['GF', 'G', 'Ground', 'Ground Floor'],
      if (floor.floorNumber > 0) ...[
        'F${floor.floorNumber}',
        'L${floor.floorNumber}',
        'Floor ${floor.floorNumber}',
        'Level ${floor.floorNumber}',
      ],
    };

    for (final candidate in candidateKeys) {
      if (candidate.trim().isEmpty) continue;
      final s = _parkingService.fetchFloorMap(candidate, bId);
      if (s.isNotEmpty) return s;
    }

    final allSlots = _parkingService
        .getFloorSlotsForMall(bId)
        .values
        .expand((l) => l)
        .toList();

    final matched = allSlots.where((s) {
      for (final c in candidateKeys) {
        if (ParkingService.isMatchingFloor(s.floorId, c)) return true;
      }
      return false;
    }).toList();

    if (matched.isNotEmpty) return matched;

    // Fallback: If viewing a parking floor and slots exist for this venue, show them!
    if (isParkFloor && allSlots.isNotEmpty) {
      return allSlots;
    }

    // Zero mock data: return empty if no real slots are generated or loaded
    return const [];
  }

  @override
  void initState() {
    super.initState();
    final effectiveUser = widget.userEmail.isNotEmpty
        ? widget.userEmail
        : 'user-default';
    _parkingService.authenticateUser(userId: effectiveUser, token: 'session');
    _parkingService.addListener(_onParkingStateChanged);
    _loadParkingSlots();
    _checkServerHealth();
    _parkingService.startLiveSync(intervalSeconds: 1);

    _parkingSyncSubscription = ApiService.instance.syncStream.listen((event) {
      if (mounted && (event == 'parking' || event == 'destinations')) {
        _loadParkingSlots();
      }
    });

    _parkingAutoRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _loadParkingSlots();
        if ((_parkingAutoRefreshTimer?.tick ?? 0) % 3 == 0) {
          _checkServerHealth();
        }
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    if (widget.targetDestination != null &&
        widget.buildingProfile.floors.isNotEmpty) {
      _selectedPOI = widget.targetDestination;
      final matchingFloor = widget.buildingProfile.floors.firstWhere(
        (f) => f.floorNumber == widget.targetDestination!.floorNumber,
        orElse: () => widget.currentFloor,
      );
      _overrideFloor = matchingFloor;
    }
  }

  @override
  void didUpdateWidget(FloorPlanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.buildingProfile.buildingId !=
            oldWidget.buildingProfile.buildingId ||
        widget.currentFloor != oldWidget.currentFloor) {
      _loadParkingSlots();
    }
    if (widget.targetDestination != oldWidget.targetDestination) {
      _selectedPOI = widget.targetDestination;
      if (widget.targetDestination != null &&
          widget.buildingProfile.floors.isNotEmpty) {
        final matchingFloor = widget.buildingProfile.floors.firstWhere(
          (f) => f.floorNumber == widget.targetDestination!.floorNumber,
          orElse: () => widget.currentFloor,
        );
        _overrideFloor = matchingFloor;
      }
    } else if (oldWidget.currentFloor.floorNumber !=
            widget.currentFloor.floorNumber &&
        widget.targetDestination == null) {
      _overrideFloor = widget.currentFloor;
    }
  }

  @override
  void dispose() {
    _parkingSyncSubscription?.cancel();
    _parkingAutoRefreshTimer?.cancel();
    _parkingService.stopLiveSync();
    _parkingService.removeListener(_onParkingStateChanged);
    _pulseController.dispose();
    super.dispose();
  }

  void _onParkingStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _showServerConfigDialog() async {
    final currentUrl = await ApiService.instance.getBaseUrl();
    final controller = TextEditingController(text: currentUrl);
    bool testing = false;
    String? testResult;
    Color testResultColor = const Color(0xFF10B981);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
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
                  LucideIcons.server,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backend Server API',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Live Cloud & Local Database Sync',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
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
                  'API Endpoint URL',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12.5,
                    color: const Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: 'https://nexnav.hashnate.com/api',
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
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      avatar: const Icon(
                        LucideIcons.cloud,
                        size: 12,
                        color: Color(0xFF2563EB),
                      ),
                      label: const Text('Live Cloud (nexnav.hashnate.com)'),
                      labelStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2563EB),
                      ),
                      backgroundColor: const Color(0xFFEFF6FF),
                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                      onPressed: () {
                        controller.text = ApiService.productionServerUrl;
                        setDialogState(() => testResult = null);
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(
                        LucideIcons.search,
                        size: 12,
                        color: Color(0xFF16A34A),
                      ),
                      label: const Text('Auto-Detect Server'),
                      labelStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF16A34A),
                      ),
                      backgroundColor: const Color(0xFFF0FDF4),
                      side: const BorderSide(color: Color(0xFFBBF7D0)),
                      onPressed: () async {
                        setDialogState(() {
                          testing = true;
                          testResult = 'Detecting best server...';
                          testResultColor = const Color(0xFF2563EB);
                        });
                        final detected = await ApiService.instance
                            .autoDetectWorkingServerUrl();
                        setDialogState(() {
                          testing = false;
                          if (detected != null) {
                            controller.text = detected;
                            testResult = 'Connected: $detected (200 OK)';
                            testResultColor = const Color(0xFF10B981);
                          } else {
                            testResult = 'No online servers detected';
                            testResultColor = const Color(0xFFEF4444);
                          }
                        });
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(
                        LucideIcons.wifi,
                        size: 12,
                        color: Color(0xFF475569),
                      ),
                      label: const Text('Local LAN (192.168.1.14:5000)'),
                      labelStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF334155),
                      ),
                      backgroundColor: const Color(0xFFF8FAFC),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      onPressed: () {
                        controller.text = 'http://192.168.1.14:5000/api';
                        setDialogState(() => testResult = null);
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(
                        LucideIcons.smartphone,
                        size: 12,
                        color: Color(0xFF475569),
                      ),
                      label: const Text('Emulator (10.0.2.2)'),
                      labelStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF334155),
                      ),
                      backgroundColor: const Color(0xFFF8FAFC),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      onPressed: () {
                        controller.text = 'http://10.0.2.2:5000/api';
                        setDialogState(() => testResult = null);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (testResult != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: testResultColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: testResultColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      testResult!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: testResultColor,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: testing
                            ? null
                            : () async {
                                setDialogState(() {
                                  testing = true;
                                  testResult = 'Testing connection...';
                                  testResultColor = const Color(0xFF3B82F6);
                                });
                                final input = controller.text.trim();
                                final norm = ApiService.normalizeUrl(
                                  input.isNotEmpty
                                      ? input
                                      : ApiService.defaultBaseUrl,
                                );
                                try {
                                  final res = await http
                                      .get(Uri.parse('$norm/health'))
                                      .timeout(const Duration(seconds: 4));
                                  setDialogState(() {
                                    testing = false;
                                    if (res.statusCode == 200) {
                                      testResult = 'Connected (200 OK)';
                                      testResultColor = const Color(0xFF10B981);
                                    } else {
                                      testResult = 'HTTP ${res.statusCode}';
                                      testResultColor = const Color(0xFFEF4444);
                                    }
                                  });
                                } catch (e) {
                                  setDialogState(() {
                                    testing = false;
                                    testResult = 'Connection failed';
                                    testResultColor = const Color(0xFFEF4444);
                                  });
                                }
                              },
                        icon: const Icon(LucideIcons.activity, size: 14),
                        label: Text(
                          testing ? 'Pinging...' : 'Test Ping',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: () {
                        controller.text = ApiService.defaultBaseUrl;
                        setDialogState(() => testResult = null);
                      },
                      child: Text(
                        'Reset Default',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final newUrl = controller.text.trim();
                if (newUrl.isNotEmpty) {
                  await ApiService.instance.setCustomBaseUrl(newUrl);
                }
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                _checkServerHealth();
                if (mounted) {
                  _loadParkingSlots();
                }
              },
              child: const Text('Save & Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutOfRangeView({bool isNoVenue = false}) {
    final hasGps =
        widget.userCoords.latitude != 0.0 && widget.userCoords.longitude != 0.0;
    MallMetadata? nearestMall;
    double? nearestDistance;
    if (widget.mallService != null && hasGps) {
      nearestMall = widget.mallService!.findNearestMall(widget.userCoords);
      if (nearestMall.id.isNotEmpty) {
        nearestDistance = widget.mallService!.calculateDistanceToMall(
          widget.userCoords,
          nearestMall,
        );
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
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
              'Indoor Floor Map',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              isNoVenue ? 'No Active Venue' : 'Proximity: 500m Limit',
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
          if (widget.onLogout != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                icon: const Icon(
                  LucideIcons.logOut,
                  size: 18,
                  color: Color(0xFFEF4444),
                ),
                onPressed: widget.onLogout,
                tooltip: 'Log out',
              ),
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isNoVenue
                      ? const Color(0xFFF1F5F9)
                      : const Color(0xFFEFF6FF),
                  border: Border.all(
                    color: isNoVenue
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFFBFDBFE),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isNoVenue
                          ? const Color(0x1A0F172A)
                          : const Color(0xFF2563EB).withValues(alpha: 0.15),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    isNoVenue ? LucideIcons.building2 : LucideIcons.radar,
                    size: 44,
                    color: isNoVenue
                        ? const Color(0xFF475569)
                        : const Color(0xFF2563EB),
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // Title
              Text(
                isNoVenue ? 'No Active Venue Detected' : 'No Mall Within 500m',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),

              // Description
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(
                  isNoVenue
                      ? 'Select an active mall from the Mall Explorer or move within 500m of a supported venue to load floor plans, stores, and parking.'
                      : 'Indoor maps only auto-load when you are within 500m of a supported shopping mall. Malls above 500m are not loaded in maps.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    height: 1.5,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Nearest Mall Distance Status Card
              if (nearestMall != null && nearestDistance != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              LucideIcons.mapPinOff,
                              size: 18,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Nearest: ${nearestMall.name}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Distance: ${nearestDistance < 1000 ? "${nearestDistance.toInt()}m" : "${(nearestDistance / 1000).toStringAsFixed(1)}km"} away (> 500m)',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Move within 500m of this mall to auto-load the interactive floor plan.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.onOpenMallExplorer != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: widget.onOpenMallExplorer,
                      icon: const Icon(LucideIcons.globe, size: 16),
                      label: Text(
                        'Explore All Malls',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (widget.onRefreshLocation != null) ...[
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0F172A),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: widget.onRefreshLocation,
                      icon: const Icon(LucideIcons.refreshCw, size: 15),
                      label: Text(
                        'Refresh GPS',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isNoMallLoaded =
        widget.buildingProfile.buildingId.isEmpty ||
        widget.buildingProfile.floors.isEmpty;

    final hasGps =
        widget.userCoords.latitude != 0.0 && widget.userCoords.longitude != 0.0;
    double? distM;
    if (hasGps &&
        widget.mallService != null &&
        widget.buildingProfile.buildingId.isNotEmpty) {
      final m = widget.mallService!.catalog
          .where((m) => m.id == widget.buildingProfile.buildingId)
          .firstOrNull;
      if (m != null) {
        distM = widget.mallService!.calculateDistanceToMall(
          widget.userCoords,
          m,
        );
      }
    } else if (hasGps && widget.destinations.isNotEmpty) {
      distM = haversineDistance(
        widget.userCoords,
        widget.destinations.first.location,
      );
    }

    final bool isOutside500m = distM != null && distM > 500.0;
    if (isNoMallLoaded) {
      return _buildOutOfRangeView(isNoVenue: true);
    }
    if (isOutside500m) {
      return _buildOutOfRangeView(isNoVenue: false);
    }
    final List<ParkingSlot> floorSlots = _getSlotsForDisplayFloor(displayFloor);
    final bool isParkingFloor =
        displayFloor.floorNumber < 0 ||
        displayFloor.floorId.trim().toUpperCase().startsWith('P') ||
        displayFloor.floorId.trim().toUpperCase().startsWith('B') ||
        displayFloor.name.trim().toUpperCase().contains('PARK') ||
        displayFloor.name.trim().toUpperCase().contains('BASEMENT') ||
        floorSlots.isNotEmpty;
    final currentFloorPOIs = widget.destinations
        .where((poi) => poi.floorNumber == displayFloor.floorNumber)
        .where((poi) => !ParkingService.isParkingDestination(poi))
        .toList();

    final String floorId = _getFloorIdString(displayFloor);

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
            Builder(
              builder: (context) {
                double? distM;
                if (widget.userCoords.latitude != 0.0 &&
                    widget.mallService != null) {
                  final m = widget.mallService!.catalog
                      .where((m) => m.id == widget.buildingProfile.buildingId)
                      .firstOrNull;
                  if (m != null) {
                    distM = widget.mallService!.calculateDistanceToMall(
                      widget.userCoords,
                      m,
                    );
                  }
                }
                final distStr = distM != null
                    ? (distM < 1000
                          ? ' • ${distM.toInt()}m away'
                          : ' • ${(distM / 1000).toStringAsFixed(1)}km away')
                    : '';
                final isRemote = distM != null && distM > 500.0;
                final venueName =
                    widget.buildingProfile.name.isNotEmpty &&
                        widget.buildingProfile.name != 'Venue'
                    ? widget.buildingProfile.name
                    : 'Indoor Navigation Floor Plan';
                return GestureDetector(
                  onLongPress: _showServerConfigDialog,
                  child: Text(
                    '$venueName$distStr',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isRemote
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          if (widget.isAdmin && widget.onOpenAdminDashboard != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: widget.onOpenAdminDashboard,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33059669),
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
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ADMIN PORTAL',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.onLogout != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onLogout,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
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
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              (widget.userEmail.isNotEmpty
                                      ? widget.userEmail.split('@').first[0]
                                      : 'U')
                                  .toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          widget.userEmail.isNotEmpty
                              ? '${widget.userEmail.split('@').first[0].toUpperCase()}${widget.userEmail.split('@').first.substring(1)}'
                              : 'User',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFFEE2E2)),
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
                    itemCount: _effectiveFloorLevels.length,
                    itemBuilder: (context, idx) {
                      final floor = _effectiveFloorLevels[idx];
                      final bool isSelected =
                          (floor.floorId.isNotEmpty &&
                              displayFloor.floorId.isNotEmpty &&
                              floor.floorId.trim().toUpperCase() ==
                                  displayFloor.floorId.trim().toUpperCase()) ||
                          (floor.floorId == displayFloor.floorId &&
                              floor.floorNumber == displayFloor.floorNumber);
                      final String fId = _getFloorIdString(floor);
                      final isParkedFloor =
                          myVehicle != null &&
                          (myVehicle.floorId.trim().toUpperCase() ==
                                  fId.trim().toUpperCase() ||
                              myVehicle.floorId.trim().toUpperCase() ==
                                  floor.floorId.trim().toUpperCase() ||
                              myVehicle.floorName.trim().toUpperCase().contains(
                                floor.name.trim().toUpperCase(),
                              ));
                      final String pillText = _getFloorPillLabel(floor);
                      final bool isParkingPill =
                          pillText == 'P' ||
                          pillText.startsWith('P') ||
                          pillText.startsWith('B') ||
                          floor.floorNumber < 0;

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
                                ? (isParkingPill
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFF16A34A),
                                            Color(0xFF15803D),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : const LinearGradient(
                                          colors: [
                                            Color(0xFF2563EB),
                                            Color(0xFF1D4ED8),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ))
                                : null,
                            color: isSelected
                                ? null
                                : (isParkedFloor
                                      ? const Color(0xFFDCFCE7)
                                      : (isParkingPill
                                            ? const Color(0xFFF0FDF4)
                                            : const Color(0xFFF1F5F9))),
                            borderRadius: BorderRadius.circular(10),
                            border: isParkedFloor && !isSelected
                                ? Border.all(
                                    color: const Color(0xFF22C55E),
                                    width: 1.5,
                                  )
                                : (isParkingPill && !isSelected
                                      ? Border.all(
                                          color: const Color(0xFF86EFAC),
                                          width: 1.2,
                                        )
                                      : null),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color:
                                          (isParkingPill
                                                  ? const Color(0xFF16A34A)
                                                  : const Color(0xFF2563EB))
                                              .withValues(alpha: 0.35),
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
                              if (isParkedFloor) ...[
                                Icon(
                                  LucideIcons.car,
                                  size: 13,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF16A34A),
                                ),
                                const SizedBox(width: 4),
                              ] else if (isParkingPill) ...[
                                Icon(
                                  LucideIcons.parkingCircle,
                                  size: 13,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF16A34A),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                pillText,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected
                                      ? Colors.white
                                      : (isParkedFloor
                                            ? const Color(0xFF15803D)
                                            : (isParkingPill
                                                  ? const Color(0xFF166534)
                                                  : const Color(0xFF334155))),
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
                if (!isParkingFloor)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: InkWell(
                      onTap: () =>
                          _showFloorDirectoryModal(context, currentFloorPOIs),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
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
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: InkWell(
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
                  ),
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
                    'Dining',
                    LucideIcons.utensils,
                  ),
                  _buildCategoryFilterChip(
                    'FASHION',
                    'Fashion',
                    LucideIcons.shoppingBag,
                  ),
                  _buildCategoryFilterChip(
                    'BEAUTY',
                    'Beauty',
                    LucideIcons.sparkles,
                  ),
                  _buildCategoryFilterChip('TECH', 'Tech', LucideIcons.laptop),
                  _buildCategoryFilterChip(
                    'SERVICES',
                    'Services',
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
                                  selectedParkingSlot: _selectedParkingSlot,
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
                          final activeMallAnchor =
                              widget.destinations.isNotEmpty
                              ? widget.destinations.first.location
                              : widget.userCoords;
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
                                                const SizedBox(width: 8),
                                                Builder(
                                                  builder: (context) {
                                                    final activeAnchor =
                                                        widget
                                                            .destinations
                                                            .isNotEmpty
                                                        ? widget
                                                              .destinations
                                                              .first
                                                              .location
                                                        : widget.userCoords;
                                                    final effectiveUser =
                                                        getEffectiveUserCoords(
                                                          widget.userCoords,
                                                          activeAnchor,
                                                        );
                                                    final storeDistMeters =
                                                        calculateAccurate3DDistance(
                                                          effectiveUser,
                                                          _selectedPOI!
                                                              .location,
                                                          userFloorNumber:
                                                              widget
                                                                  .currentFloor
                                                                  .floorNumber,
                                                          targetFloorNumber:
                                                              _selectedPOI!
                                                                  .floorNumber,
                                                        );
                                                    return Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Icon(
                                                          LucideIcons
                                                              .navigation,
                                                          size: 10,
                                                          color: Color(
                                                            0xFF2563EB,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 3,
                                                        ),
                                                        Text(
                                                          '${storeDistMeters.toStringAsFixed(0)}m away',
                                                          style:
                                                              GoogleFonts.plusJakartaSans(
                                                                fontSize: 10.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color:
                                                                    const Color(
                                                                      0xFF2563EB,
                                                                    ),
                                                              ),
                                                        ),
                                                        if (_selectedPOI!
                                                                .floorNumber !=
                                                            widget
                                                                .currentFloor
                                                                .floorNumber) ...[
                                                          const SizedBox(
                                                            width: 5,
                                                          ),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 5,
                                                                  vertical: 1.5,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                    0xFFEFF6FF,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    5,
                                                                  ),
                                                            ),
                                                            child: Text(
                                                              'Floor ${_selectedPOI!.floorNumber}',
                                                              style: GoogleFonts.plusJakartaSans(
                                                                fontSize: 9,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color:
                                                                    const Color(
                                                                      0xFF1D4ED8,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    );
                                                  },
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

                        // Interactive Touch Target over '▼ Parking Entrance' on Retail Floor
                        if (!isParkingFloor)
                          Positioned(
                            left: width * 0.35,
                            top: height - 42,
                            width: width * 0.30,
                            height: 24,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(7),
                                onTap: () {
                                  final parkingFloor = _effectiveFloorLevels
                                      .firstWhere(
                                        (f) =>
                                            ParkingService.normalizeFloorId(
                                                  f.floorId,
                                                ) ==
                                                'P' ||
                                            f.floorNumber < 0,
                                        orElse: () =>
                                            _effectiveFloorLevels.first,
                                      );
                                  setState(() {
                                    _selectedPOI = null;
                                    _overrideFloor = parkingFloor;
                                  });
                                  widget.onSelectFloor(parkingFloor);
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF2563EB,
                                      ).withValues(alpha: 0.5),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Interactive Shortcuts on Parking Deck
                        if (isParkingFloor) ...[
                          // Top hub: Elevators & Stairs -> Jump back to Ground Floor (F1)
                          Positioned(
                            left: width * 0.35,
                            top: 16,
                            width: width * 0.30,
                            height: 24,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  final groundFloor = _effectiveFloorLevels
                                      .firstWhere(
                                        (f) =>
                                            f.floorNumber == 1 ||
                                            f.floorNumber == 0,
                                        orElse: () =>
                                            _effectiveFloorLevels.first,
                                      );
                                  setState(() {
                                    _selectedPOI = null;
                                    _overrideFloor = groundFloor;
                                  });
                                  widget.onSelectFloor(groundFloor);
                                },
                              ),
                            ),
                          ),
                          // Bottom ramp: Entrance & Exit -> Jump back to Ground Floor (F1)
                          Positioned(
                            left: width * 0.35,
                            top: height - 40,
                            width: width * 0.30,
                            height: 22,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(7),
                                onTap: () {
                                  final groundFloor = _effectiveFloorLevels
                                      .firstWhere(
                                        (f) =>
                                            f.floorNumber == 1 ||
                                            f.floorNumber == 0,
                                        orElse: () =>
                                            _effectiveFloorLevels.first,
                                      );
                                  setState(() {
                                    _selectedPOI = null;
                                    _overrideFloor = groundFloor;
                                  });
                                  widget.onSelectFloor(groundFloor);
                                },
                              ),
                            ),
                          ),
                        ],

                        // Floating Quick Jump Badges
                        if (!isParkingFloor && _selectedPOI == null)
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  final parkingFloor = _effectiveFloorLevels
                                      .firstWhere(
                                        (f) =>
                                            ParkingService.normalizeFloorId(
                                                  f.floorId,
                                                ) ==
                                                'P' ||
                                            f.floorNumber < 0,
                                        orElse: () =>
                                            _effectiveFloorLevels.first,
                                      );
                                  setState(() {
                                    _selectedPOI = null;
                                    _overrideFloor = parkingFloor;
                                  });
                                  widget.onSelectFloor(parkingFloor);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF16A34A),
                                        Color(0xFF15803D),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF16A34A,
                                        ).withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        LucideIcons.parkingCircle,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'View Parking (P)',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        LucideIcons.arrowRight,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                        if (isParkingFloor && _selectedParkingSlot != null)
                          Positioned(
                            left: 14,
                            bottom: 12,
                            child: Material(
                              color: Colors.transparent,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF38BDF8),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF38BDF8),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Place: Spot ${_selectedParkingSlot!.id}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedParkingSlot = null;
                                        });
                                      },
                                      child: const Icon(
                                        LucideIcons.x,
                                        size: 14,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        if (isParkingFloor)
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  final groundFloor = _effectiveFloorLevels
                                      .firstWhere(
                                        (f) =>
                                            f.floorNumber == 1 ||
                                            f.floorNumber == 0,
                                        orElse: () =>
                                            _effectiveFloorLevels.first,
                                      );
                                  setState(() {
                                    _selectedPOI = null;
                                    _overrideFloor = groundFloor;
                                  });
                                  widget.onSelectFloor(groundFloor);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF2563EB),
                                        Color(0xFF1D4ED8),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF2563EB,
                                        ).withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        LucideIcons.store,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Back to Shops (F1)',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        LucideIcons.arrowUp,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
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
    final stalls = ParkingLayoutCalculator.calculateStalls(
      width: width,
      height: height,
      floorNumber: displayFloor.floorNumber,
      floorName: displayFloor.name,
      slots: slots,
      fallbackCoords: widget.userCoords,
    );

    final List<Widget> widgets = [];
    for (final stall in stalls) {
      final bool isMyCar =
          myVehicle != null &&
          myVehicle.status == 'parked' &&
          (myVehicle.slotId.trim().toLowerCase() ==
                  stall.slot.id.trim().toLowerCase() ||
              myVehicle.slotId
                      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
                      .toLowerCase() ==
                  stall.slot.id
                      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
                      .toLowerCase());

      final hitRect = stall.rect.inflate(4.0);
      widgets.add(
        Positioned(
          left: hitRect.left,
          top: hitRect.top,
          width: hitRect.width,
          height: hitRect.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _selectedParkingSlot = stall.slot;
              });
              _showParkingSlotModal(context, stall.slot, isMyCar);
            },
            child: Container(color: Colors.transparent),
          ),
        ),
      );
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
            () {
              final double distM = haversineDistance(
                widget.userCoords,
                slot.location,
              );
              final String compass = classifyCompassBadge(
                calculateBearingAngle(widget.userCoords, slot.location),
              ).name;
              final String distText = distM > 1.0
                  ? '${distM.toStringAsFixed(1)}m away ($compass)'
                  : 'At your current spot';
              return Container(
                margin: const EdgeInsets.only(top: 14, bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        LucideIcons.mapPin,
                        size: 16,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Particular Spot: Zone ${slot.section} • Bay ${slot.slotNumber}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            distText,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }(),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (slot.isHandicapAccessible)
                  _buildFeatureChip(
                    LucideIcons.accessibility,
                    'Handicap Bay',
                    const Color(0xFF2563EB),
                  ),
                _buildFeatureChip(
                  LucideIcons.radio,
                  'Live IoT Sensor Active',
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
                        final activeMallId = _resolveActiveMallId();
                        final slotMall = slot.mallId.isNotEmpty
                            ? slot.mallId
                            : (activeMallId ??
                                  (slot.id.contains('-')
                                      ? slot.id.split('-').first
                                      : '1'));
                        final currentUserId = widget.userEmail.isNotEmpty
                            ? widget.userEmail
                            : (_parkingService.currentUserId.isNotEmpty
                                  ? _parkingService.currentUserId
                                  : 'user-default');

                        unawaited(
                          _parkingService.clearVehicleLocation(
                            userId: currentUserId,
                            mallId: slotMall,
                            slotId:
                                _parkingService.currentVehicleLocation?.slotId,
                          ),
                        );
                      }

                      final activeMallId = _resolveActiveMallId();
                      final slotMall = slot.mallId.isNotEmpty
                          ? slot.mallId
                          : (activeMallId ??
                                (slot.id.contains('-')
                                    ? slot.id.split('-').first
                                    : '1'));
                      final currentUserId = widget.userEmail.isNotEmpty
                          ? widget.userEmail
                          : (_parkingService.currentUserId.isNotEmpty
                                ? _parkingService.currentUserId
                                : 'user-default');

                      final vehicleRecord = MyVehicleLocation(
                        userId: currentUserId,
                        slotId: slot.id,
                        mallId: slotMall,
                        floorId: slot.floorId,
                        floorName: displayFloor.name,
                        location: slot.location,
                        timestamp: DateTime.now(),
                      );

                      // 1. Immediately dismiss modal sheet with zero delay (0ms)
                      // ignore: use_build_context_synchronously
                      Navigator.pop(context);

                      // 2. Optimistically update local bay state
                      slot.status = ParkingSlotStatus.occupied;

                      // 3. Immediately show feedback & trigger screen refresh
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Vehicle parked at Stall ${slot.id} & synced with parking manager!',
                          ),
                          backgroundColor: const Color(0xFF16A34A),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(milliseconds: 1500),
                        ),
                      );
                      setState(() {});

                      // 4. Background network sync
                      unawaited(
                        _parkingService.saveVehicleLocation(
                          vehicleRecord,
                          mallId: slotMall,
                        ),
                      );
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
                  onPressed: () {
                    final activeMallId = _resolveActiveMallId();
                    final slotMall = slot.mallId.isNotEmpty
                        ? slot.mallId
                        : (activeMallId ??
                              (slot.id.contains('-')
                                  ? slot.id.split('-').first
                                  : '1'));
                    final currentUserId = widget.userEmail.isNotEmpty
                        ? widget.userEmail
                        : (_parkingService.currentUserId.isNotEmpty
                              ? _parkingService.currentUserId
                              : 'user-default');

                    // 1. Immediately dismiss modal sheet with zero delay (0ms)
                    Navigator.pop(context);

                    // 2. Optimistically update local bay state
                    slot.status = ParkingSlotStatus.free;

                    // 3. Immediately show feedback & trigger screen refresh
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Vehicle unparked from Stall ${slot.id} & synced with parking manager.',
                        ),
                        backgroundColor: const Color(0xFFDC2626),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(milliseconds: 1500),
                      ),
                    );
                    setState(() {});

                    // 4. Background network sync
                    unawaited(
                      _parkingService.clearVehicleLocation(
                        userId: currentUserId,
                        mallId: slotMall,
                        slotId: slot.id,
                      ),
                    );
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
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.store,
                        color: Color(0xFF2563EB),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Floor Directory (${displayFloor.name})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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

class ComputedParkingStall {
  final ParkingSlot slot;
  final Rect rect;
  final bool isHandicap;

  const ComputedParkingStall({
    required this.slot,
    required this.rect,
    required this.isHandicap,
  });
}

class ParkingLayoutCalculator {
  static List<ComputedParkingStall> calculateStalls({
    required double width,
    required double height,
    required int floorNumber,
    required String floorName,
    required List<ParkingSlot> slots,
    required GeodeticCoords fallbackCoords,
  }) {
    final stalls = <ComputedParkingStall>[];
    if (slots.isEmpty) {
      return stalls;
    }
    final List<ParkingSlot> effectiveSlots = List<ParkingSlot>.from(slots);

    final leftSlots = <ParkingSlot>[];
    final rightSlots = <ParkingSlot>[];

    final hasSectionB = effectiveSlots.any(
      (s) => s.section.trim().toUpperCase() == 'B' || s.id.contains('-B-'),
    );
    final hasSectionA = effectiveSlots.any(
      (s) => s.section.trim().toUpperCase() == 'A' || s.id.contains('-A-'),
    );

    if (hasSectionA && hasSectionB) {
      for (final s in effectiveSlots) {
        final sec = s.section.trim().toUpperCase();
        if (sec == 'B' || sec == 'D' || sec == 'F' || s.id.contains('-B-')) {
          rightSlots.add(s);
        } else {
          leftSlots.add(s);
        }
      }
    } else {
      final sorted = List<ParkingSlot>.from(effectiveSlots)
        ..sort((a, b) {
          final secComp = a.section.compareTo(b.section);
          if (secComp != 0) return secComp;
          return a.slotNumber.compareTo(b.slotNumber);
        });
      final half = (sorted.length + 1) ~/ 2;
      leftSlots.addAll(sorted.take(half));
      rightSlots.addAll(sorted.skip(half));
    }

    leftSlots.sort(
      (a, b) => a.slotNumber != b.slotNumber
          ? a.slotNumber.compareTo(b.slotNumber)
          : a.id.compareTo(b.id),
    );
    rightSlots.sort(
      (a, b) => a.slotNumber != b.slotNumber
          ? a.slotNumber.compareTo(b.slotNumber)
          : a.id.compareTo(b.id),
    );

    const double roomTopPadding = 50.0;
    final double availableHeight = height - roomTopPadding - 46.0;
    final int maxRows = math.max(
      6,
      math.max((leftSlots.length + 1) ~/ 2, (rightSlots.length + 1) ~/ 2),
    );

    final double slotH = maxRows <= 6
        ? availableHeight * 0.135
        : (availableHeight * 0.81) / maxRows;
    final double gapY = maxRows <= 6
        ? (availableHeight - (slotH * 6)) / 5
        : (availableHeight - (slotH * maxRows)) / (maxRows - 1);

    // Symmetric left and right wings around central car lane (corridor is 0.36 to 0.64)
    final double wingWidth = width * 0.35 - 16.0;
    final double slotW = (wingWidth - 4.0) / 2;

    for (int i = 0; i < leftSlots.length; i++) {
      final s = leftSlots[i];
      final int row = i ~/ 2;
      final int col = i % 2;
      final double x = 16.0 + col * (slotW + 4.0);
      final double y = roomTopPadding + row * (slotH + gapY);
      stalls.add(
        ComputedParkingStall(
          slot: s,
          rect: Rect.fromLTWH(x, y, slotW, slotH),
          isHandicap: s.isHandicapAccessible,
        ),
      );
    }

    for (int i = 0; i < rightSlots.length; i++) {
      final s = rightSlots[i];
      final int row = i ~/ 2;
      final int col = i % 2;
      final double x = (width * 0.65) + col * (slotW + 4.0);
      final double y = roomTopPadding + row * (slotH + gapY);
      stalls.add(
        ComputedParkingStall(
          slot: s,
          rect: Rect.fromLTWH(x, y, slotW, slotH),
          isHandicap: s.isHandicapAccessible,
        ),
      );
    }

    return stalls;
  }
}

class ArchitecturalFloorPainter extends CustomPainter {
  final int floorNumber;
  final String floorName;
  final DestinationPOI? selectedPOI;
  final ParkingSlot? selectedParkingSlot;
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
    this.selectedParkingSlot,
    this.selectedCategoryFilter = 'ALL',
    this.currentFloorPOIs = const [],
    this.parkingSlots = const [],
    this.myVehicle,
    required this.userCoords,
    required this.pulseAnimationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bool isParkingFloor =
        floorNumber < 0 ||
        floorName.trim().toUpperCase().contains('PARK') ||
        floorName.trim().toUpperCase().startsWith('P') ||
        parkingSlots.isNotEmpty;

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
    if (isParkingFloor) {
      _paintBasementParkingPlan(canvas, size, roomTopPadding);
    } else {
      _paintRetailPlan(canvas, size, roomTopPadding);
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
  }

  void _paintRetailPlan(Canvas canvas, Size size, double roomTopPadding) {
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
  }

  void _paintBasementParkingPlan(
    Canvas canvas,
    Size size,
    double roomTopPadding,
  ) {
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

    final stalls = ParkingLayoutCalculator.calculateStalls(
      width: size.width,
      height: size.height,
      floorNumber: floorNumber,
      floorName: floorName,
      slots: parkingSlots,
      fallbackCoords: userCoords,
    );

    if (stalls.isEmpty) {
      _drawText(
        canvas,
        'No Parking Stalls on $floorName',
        Offset(midX - 70, size.height * 0.40),
        const Color(0xFF64748B),
        fontSize: 10.0,
        fontWeight: FontWeight.bold,
        maxWidth: 140,
        textAlign: TextAlign.center,
      );
      _drawText(
        canvas,
        'Generate bays in Parking Lot & Bay Manager',
        Offset(midX - 85, size.height * 0.40 + 16),
        const Color(0xFF475569),
        fontSize: 7.5,
        fontWeight: FontWeight.w600,
        maxWidth: 170,
        textAlign: TextAlign.center,
      );
    }

    for (final stall in stalls) {
      final bool isMyCar =
          myVehicle != null &&
          myVehicle!.slotId == stall.slot.id &&
          myVehicle!.status == 'parked';

      final bool isSelected = selectedParkingSlot != null &&
          ParkingService.isMatchingSlotId(stall.slot.id, selectedParkingSlot!.id);

      _drawSingleParkingStall(
        canvas,
        stall.rect,
        stall.slot.id,
        isHandicap: stall.isHandicap,
        status: stall.slot.status,
        isMyCar: isMyCar,
        isSelected: isSelected,
        pulseAnimationValue: pulseAnimationValue,
      );
    }
  }

  void _drawSingleParkingStall(
    Canvas canvas,
    Rect slotRect,
    String slotCode, {
    bool isHandicap = false,
    ParkingSlotStatus status = ParkingSlotStatus.free,
    bool isMyCar = false,
    bool isSelected = false,
    double pulseAnimationValue = 0.0,
  }) {
    Color fillPaintColor = const Color(0xFF1E293B);
    Color borderPaintColor = isHandicap
        ? const Color(0xFF3B82F6)
        : const Color(0xFF475569);

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
    } else if (isSelected) {
      fillPaintColor = const Color(0xFF0C4A6E);
      borderPaintColor = const Color(0xFF38BDF8);

      final glowHaloRadius = 3.0 + (pulseAnimationValue * 4.0);
      final glowPaint = Paint()
        ..color = const Color(0xFF38BDF8)
            .withValues(alpha: 0.85 * (1.0 - pulseAnimationValue * 0.4))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          slotRect.inflate(glowHaloRadius),
          const Radius.circular(8),
        ),
        glowPaint,
      );
    } else if (status == ParkingSlotStatus.occupied) {
      fillPaintColor = const Color(0xFF291518);
      borderPaintColor = const Color(0xFFEF4444);
    } else if (status == ParkingSlotStatus.reserved) {
      fillPaintColor = const Color(0xFF292014);
      borderPaintColor = const Color(0xFFF59E0B);
    }

    final fillPaint = Paint()..color = fillPaintColor;
    final borderPaint = Paint()
      ..color = borderPaintColor
      ..strokeWidth = (isMyCar || isSelected) ? 2.0 : 1.0
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(slotRect, const Radius.circular(5));
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, borderPaint);

    if (isSelected && !isMyCar) {
      final double indicatorY = slotRect.top - 12.0;
      if (indicatorY > 10) {
        final badgeRect = Rect.fromLTWH(
          slotRect.left - 2,
          indicatorY,
          slotRect.width + 4,
          10,
        );
        final badgePaint = Paint()..color = const Color(0xFF0284C7);
        canvas.drawRRect(
          RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
          badgePaint,
        );
        _drawText(
          canvas,
          'HERE',
          Offset(badgeRect.left + 2, badgeRect.top + 1),
          Colors.white,
          fontSize: 6.0,
          fontWeight: FontWeight.w900,
          maxWidth: badgeRect.width - 4,
          textAlign: TextAlign.center,
        );
      }
    }

    if (isMyCar) {
      _drawText(
        canvas,
        slotCode,
        Offset(slotRect.left + 2, slotRect.top + 3),
        Colors.white,
        fontSize: slotCode.length > 8 ? 5.5 : 6.5,
        fontWeight: FontWeight.bold,
        maxWidth: slotRect.width - 4,
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
    if (isHandicap) {
      tag = 'HC';
      tagColor = const Color(0xFF60A5FA);
    }

    final double titleFontSize = slotCode.length > 8 ? 5.5 : 6.5;
    _drawText(
      canvas,
      tag.isNotEmpty ? '$slotCode $tag' : slotCode,
      Offset(slotRect.left + 3, slotRect.top + 3),
      tagColor,
      fontSize: titleFontSize,
      fontWeight: FontWeight.bold,
      maxWidth: slotRect.width - 6,
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
      Offset(
        slotRect.left + 3,
        slotRect.top + (slotCode.length > 8 ? 16.0 : 14.0),
      ),
      statusColor,
      fontSize: 6.0,
      fontWeight: FontWeight.bold,
    );
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
