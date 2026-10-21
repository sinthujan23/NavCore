import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/api_service.dart';
import '../../data/floor_height_model.dart';
import '../../data/parking_service.dart';
import '../../data/mall_database_service.dart';
import '../../engine/ecef_engine.dart';
import '../../engine/bearing_engine.dart';

class AdminParkingManagerScreen extends StatefulWidget {
  final MallMetadata? activeMall;
  final MallDatabaseService? mallService;
  final GeodeticCoords? userCoords;

  const AdminParkingManagerScreen({
    super.key,
    this.activeMall,
    this.mallService,
    this.userCoords,
  });

  @override
  State<AdminParkingManagerScreen> createState() =>
      _AdminParkingManagerScreenState();
}

class _AdminParkingManagerScreenState extends State<AdminParkingManagerScreen> {
  final ParkingService _parkingService = ParkingService();
  late final MallDatabaseService _mallService =
      widget.mallService ?? MallDatabaseService();

  List<MallMetadata> _malls = [];
  MallMetadata? _activeMall;
  List<FloorHeightData> _mallFloorHeights = [];
  String _selectedFloorId = '';
  bool _isLoading = true;
  bool _isServerOnline = false;
  Timer? _adminRefreshTimer;
  StreamSubscription<String>? _syncSubscription;
  bool _isModalOpening = false;
  GeodeticCoords? _liveSurveyorCoords;
  double? _liveSurveyorAccuracy;
  DateTime? _liveSurveyorFixTime;
  final StreamController<Position> _livePositionBroadcast =
      StreamController<Position>.broadcast();
  StreamSubscription<Position>? _positionStreamSub;

  @override
  void initState() {
    super.initState();
    _parkingService.addListener(_onParkingChanged);
    _loadMallsAndLayout();
    _checkServerHealth();
    _startLivePositionStream();
    _syncSubscription = ApiService.instance.syncStream.listen((event) {
      if (mounted && _activeMall != null) {
        _parkingService.syncSlotsSilently(_activeMall!.id);
      }
    });
    _checkServerHealth();
    // Optimized: Refresh every 20s instead of every 1s to prevent server overload
    _adminRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _activeMall != null && !_isLoading) {
        _parkingService.syncSlotsSilently(_activeMall!.id);
      }
    });
  }

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

  Future<void> _startLivePositionStream() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      // 1. Instant fix from last known hardware position (if < 30s old)
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null && mounted) {
        final isRecent =
            DateTime.now().difference(lastPos.timestamp).inSeconds < 30;
        setState(() {
          _liveSurveyorCoords = GeodeticCoords(
            latitude: lastPos.latitude,
            longitude: lastPos.longitude,
            height: lastPos.altitude,
          );
          _liveSurveyorAccuracy = lastPos.accuracy;
          if (isRecent) {
            _liveSurveyorFixTime = lastPos.timestamp;
          }
        });
        if (isRecent) {
          _livePositionBroadcast.add(lastPos);
        }
      }

      // 2. Active position stream: continuously tracks as the surveyor moves between spots
      const settings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
      _positionStreamSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen((Position pos) {
        if (!pos.latitude.isNaN &&
            !pos.longitude.isNaN &&
            !(pos.latitude == 0.0 && pos.longitude == 0.0)) {
          final coords = GeodeticCoords(
            latitude: pos.latitude,
            longitude: pos.longitude,
            height: pos.altitude,
          );
          _liveSurveyorCoords = coords;
          _liveSurveyorAccuracy = pos.accuracy;
          _liveSurveyorFixTime = DateTime.now();
          _livePositionBroadcast.add(pos);
          if (mounted) {
            setState(() {});
          }
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  Future<GeodeticCoords?> _captureLiveCoordinates({bool forceFresh = false}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return _liveSurveyorCoords ?? widget.userCoords;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          return _liveSurveyorCoords ?? widget.userCoords;
        }
      }

      // Fast-path: if not forced refresh and we already have a FRESH live fix (< 6s old with high accuracy)
      if (!forceFresh &&
          _liveSurveyorCoords != null &&
          _liveSurveyorFixTime != null &&
          DateTime.now().difference(_liveSurveyorFixTime!).inSeconds < 6 &&
          (_liveSurveyorAccuracy ?? 99) <= 4.0) {
        return _liveSurveyorCoords;
      }

      final List<Position> samples = [];
      final completer = Completer<void>();
      StreamSubscription<Position>? streamSub;

      try {
        const locationSettings = LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        );

        streamSub = Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((pos) {
          if (!pos.latitude.isNaN &&
              !pos.longitude.isNaN &&
              !(pos.latitude == 0.0 && pos.longitude == 0.0)) {
            samples.add(pos);
            _livePositionBroadcast.add(pos);

            // Complete early if precision has converged to tight threshold (<= 3.5m)
            // or we have collected at least 5 good fixes
            if (pos.accuracy <= 3.5 || (samples.length >= 5 && pos.accuracy <= 7.0)) {
              if (!completer.isCompleted) completer.complete();
            }
          }
        }, onError: (_) {});

        // Allow up to 3.8 seconds for satellite convergence
        await Future.any([
          completer.future,
          Future.delayed(const Duration(milliseconds: 3800)),
        ]);
      } finally {
        await streamSub?.cancel();
      }

      if (samples.isNotEmpty) {
        // Multi-sample inverse-variance weighted Kalman filtering
        samples.sort((a, b) => a.accuracy.compareTo(b.accuracy));
        final bestAccuracy = samples.first.accuracy;

        // Filter out initial coarse fixes that are > 2x worse than the best fix
        final validSamples = samples
            .take(8)
            .where((s) => s.accuracy <= math.max(10.0, bestAccuracy * 2.0))
            .toList();

        double totalWeight = 0.0;
        double weightedLat = 0.0;
        double weightedLon = 0.0;
        double weightedAlt = 0.0;

        for (final s in validSamples) {
          final w = 1.0 / math.max(1.0, s.accuracy * s.accuracy);
          totalWeight += w;
          weightedLat += s.latitude * w;
          weightedLon += s.longitude * w;
          weightedAlt += s.altitude * w;
        }

        final refinedLat = weightedLat / totalWeight;
        final refinedLon = weightedLon / totalWeight;
        final refinedAlt = weightedAlt / totalWeight;

        // Statistical uncertainty reduction through noise cancellation
        final combinedErr = 1.0 / math.sqrt(totalWeight);
        final refinedAccuracy = math.max(
          1.8,
          math.min(bestAccuracy * 0.70, combinedErr),
        );

        final res = GeodeticCoords(
          latitude: refinedLat,
          longitude: refinedLon,
          height: refinedAlt,
        );
        _liveSurveyorCoords = res;
        _liveSurveyorAccuracy = refinedAccuracy;
        _liveSurveyorFixTime = DateTime.now();
        return res;
      }

      // Fallback: One-shot direct hardware getCurrentPosition
      try {
        final singlePos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            timeLimit: Duration(seconds: 4),
          ),
        );
        if (!singlePos.latitude.isNaN &&
            !singlePos.longitude.isNaN &&
            !(singlePos.latitude == 0.0 && singlePos.longitude == 0.0)) {
          final singleCoords = GeodeticCoords(
            latitude: singlePos.latitude,
            longitude: singlePos.longitude,
            height: singlePos.altitude,
          );
          _liveSurveyorCoords = singleCoords;
          _liveSurveyorAccuracy = math.max(2.0, singlePos.accuracy * 0.75);
          _liveSurveyorFixTime = DateTime.now();
          _livePositionBroadcast.add(singlePos);
          return singleCoords;
        }
      } catch (_) {}

      // Fallback to recent last known position if non-zero
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null &&
          !lastPos.latitude.isNaN &&
          !lastPos.longitude.isNaN &&
          !(lastPos.latitude == 0.0 && lastPos.longitude == 0.0)) {
        final lastCoords = GeodeticCoords(
          latitude: lastPos.latitude,
          longitude: lastPos.longitude,
          height: lastPos.altitude,
        );
        _liveSurveyorCoords = lastCoords;
        _liveSurveyorAccuracy = lastPos.accuracy;
        return lastCoords;
      }

      return _liveSurveyorCoords ?? widget.userCoords;
    } catch (_) {
      return _liveSurveyorCoords ?? widget.userCoords;
    }
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _livePositionBroadcast.close();
    _syncSubscription?.cancel();
    _adminRefreshTimer?.cancel();
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
      if (widget.activeMall != null) {
        malls.add(widget.activeMall!);
      } else {
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
    }

    final prefs = await SharedPreferences.getInstance();
    final savedActiveId =
        (prefs.getString('NexNav_active_mall_id') ??
                prefs.getString('active_mall_id') ??
                '')
            .trim()
            .toLowerCase();

    // Priority 1: explicitly passed activeMall from caller
    MallMetadata? active = widget.activeMall;

    // Priority 2: refresh active with full copy from malls list if present
    if (active != null) {
      final updated = malls
          .where(
            (m) => m.id.trim().toLowerCase() == active!.id.trim().toLowerCase(),
          )
          .firstOrNull;
      if (updated != null) {
        active = updated;
      }
    }

    // Priority 3: check for mall matching saved active_mall_id
    if (active == null && savedActiveId.isNotEmpty) {
      active = malls.where((m) {
        final mId = m.id.trim().toLowerCase();
        final sId = savedActiveId.trim().toLowerCase();
        return mId == sId ||
            mId.replaceAll(RegExp(r'^0+'), '') ==
                sId.replaceAll(RegExp(r'^0+'), '');
      }).firstOrNull;
    }

    // Priority 4: check for mall that is selected or active
    active ??= malls.where((m) => m.isSelected || m.isActive).firstOrNull;

    // Priority 5: fallback to first active mall in list
    active ??= malls.where((m) => m.isActive).firstOrNull;

    // Priority 6: fallback to first mall
    active ??= malls.first;

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
    final savedParkingFloors = prefs.getStringList(
      'venue_parking_floors_${active.id}',
    );
    if (savedParkingFloors != null && savedParkingFloors.isNotEmpty) {
      final cleanSaved = savedParkingFloors
          .where(
            (f) =>
                !RegExp(r'^F\d+$', caseSensitive: false).hasMatch(f.trim()),
          )
          .toList();
      if (cleanSaved.isNotEmpty) {
        active = active.copyWith(parkingFloors: cleanSaved);
        await prefs.setStringList(
          'venue_parking_floors_${active.id}',
          cleanSaved,
        );
      }
    }

    // Prune legacy dummy slots from cache/memory that do not belong to this mall
    final validFloors = _getFloorOptionsForMall(active, _mallFloorHeights);
    await _parkingService.pruneSlotsToValidFloors(active.id, validFloors);

    // Auto-fix any floors with overlapping duplicate coordinates so each stall has distinct coordinates
    for (final f in validFloors) {
      final floorSlots = _parkingService.fetchFloorMap(f, active.id);
      final seen = <String>{};
      bool hasDupes = false;
      for (final s in floorSlots) {
        final key =
            '${s.location.latitude.toStringAsFixed(5)},${s.location.longitude.toStringAsFixed(5)}';
        if (!seen.add(key)) {
          hasDupes = true;
          break;
        }
      }
      if (hasDupes) {
        await _autoSeparateFloorSlots(f, showToast: false);
      }
    }

    if (mounted) {
      setState(() {
        _malls = malls;
        _activeMall = active;
        if (validFloors.isNotEmpty) {
          if (!validFloors.contains(_selectedFloorId)) {
            String bestFloor = validFloors.first;
            for (final f in validFloors) {
              final slots = _parkingService.fetchFloorMap(f, active?.id);
              if (slots.isNotEmpty) {
                bestFloor = f;
                break;
              }
            }
            _selectedFloorId = bestFloor;
          }
        } else {
          _selectedFloorId = 'P';
        }
        _isLoading = false;
      });
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

    final List<String> floors = [];

    bool isRetailFloor(String floorLabel) {
      final clean = floorLabel.trim();
      return RegExp(r'^F\d+$', caseSensitive: false).hasMatch(clean) ||
          RegExp(r'^Floor\s*\d+$', caseSensitive: false).hasMatch(clean);
    }

    // 1. Designated parking floors configured specifically in the venue package / mall creation
    if (mall.parkingFloors.isNotEmpty) {
      for (final f in mall.parkingFloors) {
        final norm = ParkingService.normalizeFloorId(f);
        if (norm.isEmpty || isRetailFloor(norm)) continue;
        if (!floors.contains(norm)) floors.add(norm);
      }
    }

    // 2. Also check any basement levels (h.floorNo < 0) from floor heights as valid parking floors
    final targetId = mall.id.trim().toLowerCase();
    final matchingHeights = heights.where((h) {
      final hMall = h.mallId.trim().toLowerCase();
      return (hMall.isEmpty ||
              hMall == targetId ||
              hMall.replaceAll(RegExp(r'^0+'), '') ==
                  targetId.replaceAll(RegExp(r'^0+'), '')) &&
          h.floorNo < 0;
    }).toList();

    if (matchingHeights.isNotEmpty) {
      matchingHeights.sort((a, b) => a.floorNo.compareTo(b.floorNo));
      for (final h in matchingHeights) {
        final label = 'B${h.floorNo.abs()}';
        if (!floors.contains(label)) {
          floors.add(label);
        }
      }
    }

    // 3. Include any floor that currently has parking stalls placed in ParkingService (excluding upper retail floors F1, F2...)
    final slotsMap = _parkingService.getFloorSlotsForMall(mall.id);
    for (final f in slotsMap.keys) {
      if (slotsMap[f] != null && slotsMap[f]!.isNotEmpty) {
        final norm = ParkingService.normalizeFloorId(f);
        if (isRetailFloor(norm)) continue;
        if (!floors.contains(norm)) floors.add(norm);
      }
    }

    // 4. Always ensure the primary parking floor 'P' is present if list is empty
    if (floors.isEmpty) {
      floors.add('P');
    }

    // Sort: 'P' first, then basements B1, B2... in numerical order
    floors.sort((a, b) {
      if (a == 'P') return -1;
      if (b == 'P') return 1;
      if (a.startsWith('B') && b.startsWith('B')) {
        final aNum = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final bNum = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        return aNum.compareTo(bNum);
      }
      return a.compareTo(b);
    });

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

    final norm = ParkingService.normalizeFloorId(floorStr);
    if (norm == 'P' || floorStr.toUpperCase() == 'P') {
      return groundAlt - gap;
    }

    for (final fh in _mallFloorHeights) {
      final label = fh.floorNo < 0
          ? 'B${fh.floorNo.abs()}'
          : (fh.floorNo == 0 ? 'GF' : 'F${fh.floorNo}');
      if (label == floorStr ||
          'F${fh.floorNo}' == floorStr ||
          'Floor ${fh.floorNo}' == floorStr ||
          ParkingService.isMatchingFloor(label, floorStr)) {
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

    _showAddSlotDialog(presetFloor: targetFloor);
  }

  void _updateSequentialSlotNumber(
    String floor,
    String section,
    TextEditingController numberController,
  ) {
    final slotsOnFloor = _parkingService.fetchFloorMap(floor, _activeMall?.id);
    final cleanSec = section.trim().toUpperCase();
    final matchingSlots = slotsOnFloor.where((s) {
      if (s.section.trim().toUpperCase() == cleanSec) return true;
      final parts = s.id.split('-');
      if (parts.length >= 2 && parts[1].trim().toUpperCase() == cleanSec) {
        return true;
      }
      return false;
    }).toList();

    int nextN = 1;
    if (matchingSlots.isNotEmpty) {
      final nums = matchingSlots.map((s) {
        final parts = s.id.split('-');
        return parts.isNotEmpty ? (int.tryParse(parts.last) ?? 0) : 0;
      }).toList();
      if (nums.isNotEmpty) {
        nums.sort();
        nextN = nums.last + 1;
      }
    }
    numberController.text = '$nextN';
  }

  Future<String?> _showCreateNewFloorDialog(BuildContext context) async {
    final textController = TextEditingController();
    final suggestions = [
      'B2',
      'B3',
      'GF',
      'Floor 1',
      'Floor 2',
      'Floor 3',
      'Mezzanine',
      'Rooftop',
    ];

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPromptState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
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
                  LucideIcons.layers,
                  color: Color(0xFF2563EB),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Add New Floor Level',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter or choose a floor level identifier:',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: textController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'e.g. B2, Floor 2, GF, Rooftop',
                  hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
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
                onChanged: (_) => setPromptState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: suggestions.map((s) {
                  final isSel =
                      textController.text.trim().toLowerCase() ==
                      s.toLowerCase();
                  return GestureDetector(
                    onTap: () {
                      textController.text = s;
                      setPromptState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSel
                            ? const Color(0xFF2563EB)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isSel ? Colors.white : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
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
              onPressed: () {
                final val = textController.text.trim();
                if (val.isNotEmpty) {
                  Navigator.pop(ctx, val);
                }
              },
              child: const Text('Add Floor'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showCreateNewSectionDialog(BuildContext context) async {
    final textController = TextEditingController();
    final suggestions = ['A', 'B', 'C', 'D', 'E', 'VIP', 'EV', 'VISITOR'];

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPromptState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
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
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Add New Section',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter or select a section code / name:',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: textController,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'e.g. B, C, VIP, North',
                  hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
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
                onChanged: (_) => setPromptState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: suggestions.map((s) {
                  final isSel = textController.text.trim().toUpperCase() == s;
                  return GestureDetector(
                    onTap: () {
                      textController.text = s;
                      setPromptState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSel
                            ? const Color(0xFF2563EB)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isSel ? Colors.white : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
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
              onPressed: () {
                final val = textController.text.trim().toUpperCase();
                if (val.isNotEmpty) {
                  Navigator.pop(ctx, val);
                }
              },
              child: const Text('Add Section'),
            ),
          ],
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
    final existingSlotsOnFloor = _parkingService.fetchFloorMap(
      chosenFloor,
      _activeMall?.id,
    );
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
    final latController = TextEditingController();
    final lonController = TextEditingController();
    ParkingSlotStatus chosenStatus = ParkingSlotStatus.free;
    bool isHandicap = false;
    bool isManualEdit = false;

    // Checks if the surveyor's current phone GPS is at the same spot as an existing stall (< 4.5m).
    // If so, the phone has NOT moved to a new stall yet.
    ParkingSlot? findConflictingSlot(GeodeticCoords coords, String floor) {
      final slots = _parkingService.fetchFloorMap(floor, _activeMall?.id);
      ParkingSlot? nearest;
      double minD = double.infinity;
      for (final s in slots) {
        final d = haversineDistance(coords, s.location);
        if (d < 4.5 && d < minD) {
          minD = d;
          nearest = s;
        }
      }
      return nearest;
    }

    // Resolves coordinates:
    // - If phone has NOT moved from an existing stall (d < 4.5m), auto-separates (+2.5m per col, +5m per row)
    //   so each stall is at a separate, non-overlapping point.
    // - If phone HAS moved to a new spot (d >= 4.5m), locks directly to the exact live phone GPS (0m).
    GeodeticCoords calculateStallCoords({
      required GeodeticCoords baseGps,
      required String floor,
      required String sec,
      required int stallNum,
    }) {
      final conflict = findConflictingSlot(baseGps, floor);
      if (conflict == null) {
        return baseGps;
      }
      final cleanSec = sec.trim().toUpperCase();
      final int secIdx = (cleanSec.isNotEmpty &&
              cleanSec.codeUnitAt(0) >= 65 &&
              cleanSec.codeUnitAt(0) <= 90)
          ? (cleanSec.codeUnitAt(0) - 65)
          : 0;
      final int offsetIndex = (stallNum - 1).clamp(0, 9999);
      final int row = offsetIndex ~/ 4;
      final int col = offsetIndex % 4;
      return GeodeticCoords(
        latitude: baseGps.latitude + (row * 0.000045),
        longitude: baseGps.longitude + (secIdx * 0.000150) + (col * 0.000025),
        height: baseGps.height,
      );
    }

    final bool hasFreshFix = _liveSurveyorCoords != null &&
        _liveSurveyorFixTime != null &&
        DateTime.now().difference(_liveSurveyorFixTime!).inSeconds < 8 &&
        (_liveSurveyorAccuracy ?? 99) <= 8.0;

    GeodeticCoords? rawBaseCoords = _liveSurveyorCoords ?? widget.userCoords;
    GeodeticCoords? spotCoords;
    if (rawBaseCoords != null) {
      final curNum = int.tryParse(numberController.text.trim()) ?? nextNum;
      spotCoords = calculateStallCoords(
        baseGps: rawBaseCoords,
        floor: chosenFloor,
        sec: sectionController.text,
        stallNum: curNum,
      );
      latController.text = spotCoords.latitude.toStringAsFixed(6);
      lonController.text = spotCoords.longitude.toStringAsFixed(6);
    }

    bool useCurrentLocation = true;
    bool isCapturingGps = !hasFreshFix;
    StreamSubscription<Position>? dialogStreamSub;

    final availableSections = <String>['A', 'B', 'C'];
    for (final s in existingSlotsOnFloor) {
      final sec = s.section.trim().toUpperCase();
      if (sec.isNotEmpty && !availableSections.contains(sec)) {
        availableSections.add(sec);
      }
    }
    availableSections.sort();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (dialogStreamSub == null && useCurrentLocation) {
            dialogStreamSub = _livePositionBroadcast.stream.listen((pos) {
              if (ctx.mounted && useCurrentLocation) {
                final newGps = GeodeticCoords(
                  latitude: pos.latitude,
                  longitude: pos.longitude,
                  height: pos.altitude,
                );

                // Stationary filter: ignore small GPS sensor jitter (< 3.0m).
                // ONLY update coordinates if the phone actually moved to a new position.
                if (rawBaseCoords != null) {
                  final distanceMoved = haversineDistance(rawBaseCoords!, newGps);
                  if (distanceMoved < 3.0) {
                    return; // Phone is stationary: keep point locked
                  }
                }

                setDialogState(() {
                  rawBaseCoords = newGps;
                  isCapturingGps = false;
                  if (!isManualEdit && rawBaseCoords != null) {
                    final curNum = int.tryParse(numberController.text.trim()) ?? nextNum;
                    spotCoords = calculateStallCoords(
                      baseGps: rawBaseCoords!,
                      floor: chosenFloor,
                      sec: sectionController.text,
                      stallNum: curNum,
                    );
                    latController.text = spotCoords!.latitude.toStringAsFixed(6);
                    lonController.text = spotCoords!.longitude.toStringAsFixed(6);
                  }
                });
              }
            });

            if (!hasFreshFix) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                final fresh = await _captureLiveCoordinates(forceFresh: true);
                if (ctx.mounted && useCurrentLocation) {
                  setDialogState(() {
                    if (fresh != null) {
                      rawBaseCoords = fresh;
                      if (!isManualEdit) {
                        final curNum = int.tryParse(numberController.text.trim()) ?? nextNum;
                        spotCoords = calculateStallCoords(
                          baseGps: fresh,
                          floor: chosenFloor,
                          sec: sectionController.text,
                          stallNum: curNum,
                        );
                        latController.text = spotCoords!.latitude.toStringAsFixed(6);
                        lonController.text = spotCoords!.longitude.toStringAsFixed(6);
                      }
                    }
                    isCapturingGps = false;
                  });
                }
              });
            }
          }
          return AlertDialog(
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
                  key: ValueKey('floor-picker-$chosenFloor-${floors.length}'),
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
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        chosenFloor = val;
                        _updateSequentialSlotNumber(
                          chosenFloor,
                          sectionController.text,
                          numberController,
                        );
                        if (!isManualEdit && rawBaseCoords != null) {
                          final curNum = int.tryParse(numberController.text.trim()) ?? nextNum;
                          spotCoords = calculateStallCoords(
                            baseGps: rawBaseCoords!,
                            floor: chosenFloor,
                            sec: sectionController.text,
                            stallNum: curNum,
                          );
                          latController.text = spotCoords!.latitude.toStringAsFixed(6);
                          lonController.text = spotCoords!.longitude.toStringAsFixed(6);
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 6),
                // MARKED PLACE 1: Add New Floor Level Button Flow
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    InkWell(
                      onTap: () async {
                        final newFloor = await _showCreateNewFloorDialog(ctx);
                        if (newFloor != null && newFloor.trim().isNotEmpty) {
                          final cleanFloor = newFloor.trim();
                          if (!floors.contains(cleanFloor)) {
                            floors.add(cleanFloor);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setStringList(
                              'venue_parking_floors_${_activeMall!.id}',
                              floors,
                            );
                            _activeMall = _activeMall!.copyWith(
                              parkingFloors: floors,
                            );
                            if (mounted) setState(() {});
                          }
                          setDialogState(() {
                            chosenFloor = cleanFloor;
                            _updateSequentialSlotNumber(
                              chosenFloor,
                              sectionController.text,
                              numberController,
                            );
                            if (!isManualEdit && rawBaseCoords != null) {
                              final curNum = int.tryParse(numberController.text.trim()) ?? nextNum;
                              spotCoords = calculateStallCoords(
                                baseGps: rawBaseCoords!,
                                floor: chosenFloor,
                                sec: sectionController.text,
                                stallNum: curNum,
                              );
                              latController.text = spotCoords!.latitude.toStringAsFixed(6);
                              lonController.text = spotCoords!.longitude.toStringAsFixed(6);
                            }
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.plus,
                              size: 13,
                              color: Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Add New Floor Level',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                            onChanged: (val) {
                              setDialogState(() {
                                _updateSequentialSlotNumber(
                                  chosenFloor,
                                  val,
                                  numberController,
                                );
                                if (!isManualEdit && rawBaseCoords != null) {
                                  final curNum = int.tryParse(numberController.text.trim()) ?? nextNum;
                                  spotCoords = calculateStallCoords(
                                    baseGps: rawBaseCoords!,
                                    floor: chosenFloor,
                                    sec: val,
                                    stallNum: curNum,
                                  );
                                  latController.text = spotCoords!.latitude.toStringAsFixed(6);
                                  lonController.text = spotCoords!.longitude.toStringAsFixed(6);
                                }
                              });
                            },
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
                            onChanged: (val) {
                              setDialogState(() {
                                if (!isManualEdit && rawBaseCoords != null) {
                                  final curNum = int.tryParse(val.trim()) ?? nextNum;
                                  spotCoords = calculateStallCoords(
                                    baseGps: rawBaseCoords!,
                                    floor: chosenFloor,
                                    sec: sectionController.text,
                                    stallNum: curNum,
                                  );
                                  latController.text = spotCoords!.latitude.toStringAsFixed(6);
                                  lonController.text = spotCoords!.longitude.toStringAsFixed(6);
                                }
                              });
                            },
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
                const SizedBox(height: 8),
                // MARKED PLACE 2: Sections chips + Add New Section flow
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(
                        'Sections: ',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      ...availableSections.map((sec) {
                        final isSel =
                            sectionController.text.trim().toUpperCase() == sec;
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              sectionController.text = sec;
                              _updateSequentialSlotNumber(
                                chosenFloor,
                                sec,
                                numberController,
                              );
                              if (!isManualEdit && rawBaseCoords != null) {
                                final curNum = int.tryParse(numberController.text.trim()) ?? nextNum;
                                spotCoords = calculateStallCoords(
                                  baseGps: rawBaseCoords!,
                                  floor: chosenFloor,
                                  sec: sec,
                                  stallNum: curNum,
                                );
                                latController.text = spotCoords!.latitude.toStringAsFixed(6);
                                lonController.text = spotCoords!.longitude.toStringAsFixed(6);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3.5,
                            ),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSel
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Text(
                              sec,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: isSel
                                    ? Colors.white
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        );
                      }),
                      InkWell(
                        onTap: () async {
                          final newSec = await _showCreateNewSectionDialog(ctx);
                          if (newSec != null && newSec.trim().isNotEmpty) {
                            final cleanSec = newSec.trim().toUpperCase();
                            if (!availableSections.contains(cleanSec)) {
                              availableSections.add(cleanSec);
                              availableSections.sort();
                            }
                            setDialogState(() {
                              sectionController.text = cleanSec;
                              _updateSequentialSlotNumber(
                                chosenFloor,
                                cleanSec,
                                numberController,
                              );
                              if (!isManualEdit && rawBaseCoords != null) {
                                final curNum = int.tryParse(numberController.text.trim()) ?? nextNum;
                                spotCoords = calculateStallCoords(
                                  baseGps: rawBaseCoords!,
                                  floor: chosenFloor,
                                  sec: cleanSec,
                                  stallNum: curNum,
                                );
                                latController.text = spotCoords!.latitude.toStringAsFixed(6);
                                lonController.text = spotCoords!.longitude.toStringAsFixed(6);
                              }
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                LucideIcons.plus,
                                size: 11,
                                color: Color(0xFF2563EB),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'Add New Section',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF2563EB),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
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
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: useCurrentLocation
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            useCurrentLocation
                                ? LucideIcons.mapPin
                                : LucideIcons.building,
                            size: 16,
                            color: useCurrentLocation
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Use Current Spot Location',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          Switch(
                            value: useCurrentLocation,
                            activeThumbColor: const Color(0xFF2563EB),
                            onChanged: (val) async {
                              if (val) {
                                setDialogState(() {
                                  useCurrentLocation = true;
                                  isCapturingGps = true;
                                });
                                dialogStreamSub?.cancel();
                                dialogStreamSub = _livePositionBroadcast.stream
                                    .listen((pos) {
                                  if (ctx.mounted && useCurrentLocation) {
                                    final curGps = GeodeticCoords(
                                      latitude: pos.latitude,
                                      longitude: pos.longitude,
                                      height: pos.altitude,
                                    );

                                    // Stationary deadband filter: ignore small GPS jitter (< 3.0m)
                                    if (rawBaseCoords != null) {
                                      final moved = haversineDistance(rawBaseCoords!, curGps);
                                      if (moved < 3.0) return;
                                    }

                                    setDialogState(() {
                                      rawBaseCoords = curGps;
                                      isCapturingGps = false;
                                      if (!isManualEdit) {
                                        final curNum = int.tryParse(numberController.text.trim()) ?? 1;
                                        final computed = calculateStallCoords(
                                          baseGps: curGps,
                                          floor: chosenFloor,
                                          sec: sectionController.text.trim(),
                                          stallNum: curNum,
                                        );
                                        spotCoords = computed;
                                        latController.text = computed.latitude.toStringAsFixed(6);
                                        lonController.text = computed.longitude.toStringAsFixed(6);
                                      }
                                    });
                                  }
                                });
                                final live = await _captureLiveCoordinates(
                                  forceFresh: true,
                                );
                                if (ctx.mounted && useCurrentLocation) {
                                  setDialogState(() {
                                    isCapturingGps = false;
                                    if (live != null) {
                                      rawBaseCoords = live;
                                      if (!isManualEdit) {
                                        final curNum = int.tryParse(numberController.text.trim()) ?? 1;
                                        final computed = calculateStallCoords(
                                          baseGps: live,
                                          floor: chosenFloor,
                                          sec: sectionController.text.trim(),
                                          stallNum: curNum,
                                        );
                                        spotCoords = computed;
                                        latController.text = computed.latitude.toStringAsFixed(6);
                                        lonController.text = computed.longitude.toStringAsFixed(6);
                                      }
                                    }
                                  });
                                }
                              } else {
                                dialogStreamSub?.cancel();
                                dialogStreamSub = null;
                                setDialogState(() {
                                  useCurrentLocation = false;
                                  isCapturingGps = false;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      if (useCurrentLocation) ...[
                        const SizedBox(height: 8),
                        if (isCapturingGps)
                          Row(
                            children: [
                              const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Auto-locking to current spot GPS...',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2563EB),
                                ),
                              ),
                            ],
                          )
                        else ...[
                          // Status indicator: Auto-Separated vs Manual Custom vs Exact Spot Point Locked
                          Builder(
                            builder: (context) {
                              final conflict = rawBaseCoords != null
                                  ? findConflictingSlot(rawBaseCoords!, chosenFloor)
                                  : null;

                              final Color bgColor;
                              final Color borderColor;
                              final Color textColor;
                              final IconData iconData;
                              final String statusText;

                              if (isManualEdit) {
                                bgColor = const Color(0xFFFEF3C7);
                                borderColor = const Color(0xFFFDE68A);
                                textColor = const Color(0xFF92400E);
                                iconData = LucideIcons.pencil;
                                statusText = 'Custom coordinates set';
                              } else if (conflict != null) {
                                bgColor = const Color(0xFFEFF6FF);
                                borderColor = const Color(0xFFBFDBFE);
                                textColor = const Color(0xFF1E40AF);
                                iconData = LucideIcons.split;
                                statusText = 'Auto-Separated (+2.5m) • Same spot as ${conflict.id} (Move phone to lock 0m)';
                              } else {
                                bgColor = const Color(0xFFF0FDF4);
                                borderColor = const Color(0xFFBBF7D0);
                                textColor = const Color(0xFF15803D);
                                iconData = LucideIcons.checkCircle2;
                                statusText = 'Exact Spot Point Locked • Distance: 0m (Exact Point)';
                              }

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      iconData,
                                      size: 13,
                                      color: textColor,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        statusText,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                    if (isManualEdit && rawBaseCoords != null)
                                      GestureDetector(
                                        onTap: () {
                                          setDialogState(() {
                                            isManualEdit = false;
                                            final curNum = int.tryParse(numberController.text.trim()) ?? 1;
                                            final computed = calculateStallCoords(
                                              baseGps: rawBaseCoords!,
                                              floor: chosenFloor,
                                              sec: sectionController.text.trim(),
                                              stallNum: curNum,
                                            );
                                            spotCoords = computed;
                                            latController.text = computed.latitude.toStringAsFixed(6);
                                            lonController.text = computed.longitude.toStringAsFixed(6);
                                          });
                                        },
                                        child: Text(
                                          'Reset GPS',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF2563EB),
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),

                          // Editable Latitude & Longitude inputs side-by-side
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Latitude',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF475569),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: latController,
                                      keyboardType: const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF0F172A),
                                      ),
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                        isDense: true,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF2563EB),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                      onChanged: (val) {
                                        final p = double.tryParse(val.trim());
                                        if (p != null) {
                                          setDialogState(() {
                                            isManualEdit = true;
                                            spotCoords = GeodeticCoords(
                                              latitude: p,
                                              longitude: double.tryParse(lonController.text.trim()) ??
                                                  (spotCoords?.longitude ?? 0.0),
                                              height: spotCoords?.height ?? 0.0,
                                            );
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Longitude',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF475569),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: lonController,
                                      keyboardType: const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF0F172A),
                                      ),
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                        isDense: true,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF2563EB),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                      onChanged: (val) {
                                        final p = double.tryParse(val.trim());
                                        if (p != null) {
                                          setDialogState(() {
                                            isManualEdit = true;
                                            spotCoords = GeodeticCoords(
                                              latitude: double.tryParse(latController.text.trim()) ??
                                                  (spotCoords?.latitude ?? 0.0),
                                              longitude: p,
                                              height: spotCoords?.height ?? 0.0,
                                            );
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                              onTap: isCapturingGps
                                  ? null
                                  : () async {
                                      setDialogState(() => isCapturingGps = true);
                                      final live = await _captureLiveCoordinates(
                                        forceFresh: true,
                                      );
                                      if (ctx.mounted && useCurrentLocation) {
                                        setDialogState(() {
                                          isCapturingGps = false;
                                          if (live != null) {
                                            rawBaseCoords = live;
                                            final curNum = int.tryParse(numberController.text.trim()) ?? 1;
                                            final computed = calculateStallCoords(
                                              baseGps: live,
                                              floor: chosenFloor,
                                              sec: sectionController.text.trim(),
                                              stallNum: curNum,
                                            );
                                            spotCoords = computed;
                                            latController.text = computed.latitude.toStringAsFixed(6);
                                            lonController.text = computed.longitude.toStringAsFixed(6);
                                            isManualEdit = false;
                                          }
                                        });
                                      }
                                    },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isCapturingGps)
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.8,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            Color(0xFF2563EB),
                                          ),
                                        ),
                                      )
                                    else
                                      const Icon(
                                        LucideIcons.locateFixed,
                                        size: 13,
                                        color: Color(0xFF2563EB),
                                      ),
                                    const SizedBox(width: 5),
                                    Text(
                                      isCapturingGps
                                          ? 'Locking High-Accuracy GPS...'
                                          : 'Re-sync Live GPS',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF2563EB),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                      if (!useCurrentLocation) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Using default mall center coordinates',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
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
                final cleanMall = _activeMall!.id.trim();
                final slotId = '$cleanMall-$chosenFloor-$section-$numStr';

                final floorAlt = _resolveFloorAltitude(chosenFloor);
                final enteredLat = double.tryParse(latController.text.trim());
                final enteredLon = double.tryParse(lonController.text.trim());
                var targetCoords = (useCurrentLocation && enteredLat != null && enteredLon != null)
                    ? GeodeticCoords(
                        latitude: enteredLat,
                        longitude: enteredLon,
                        height: floorAlt,
                      )
                    : (useCurrentLocation && spotCoords != null)
                        ? spotCoords!
                        : GeodeticCoords(
                            latitude: _activeMall!.latitude,
                            longitude: _activeMall!.longitude,
                            height: floorAlt,
                          );

                final int offsetIdx = (slotNum - 1).clamp(0, 9999);
                final int r = offsetIdx ~/ 4;
                final int c = offsetIdx % 4;

                // Ensure no two stalls ever occupy the identical coordinate on the same floor
                final floorSlots = _parkingService
                    .fetchFloorMap(chosenFloor, _activeMall?.id)
                    .where((s) => s.id != slotId)
                    .toList();
                final bool hasExactDuplicate = floorSlots.any((s) =>
                    (s.location.latitude - targetCoords.latitude).abs() < 0.000005 &&
                    (s.location.longitude - targetCoords.longitude).abs() < 0.000005);

                if (hasExactDuplicate && !isManualEdit) {
                  final double dLat = (r * 0.000045) + 0.000025;
                  final double dLon = (c * 0.000025) + 0.000025;
                  targetCoords = GeodeticCoords(
                    latitude: targetCoords.latitude + dLat,
                    longitude: targetCoords.longitude + dLon,
                    height: floorAlt,
                  );
                }

                final newSlot = ParkingSlot(
                  id: slotId,
                  mallId: cleanMall,
                  floorId: chosenFloor,
                  section: section,
                  slotNumber: slotNum,
                  status: chosenStatus,
                  location: GeodeticCoords(
                    latitude: targetCoords.latitude,
                    longitude: targetCoords.longitude,
                    height: floorAlt,
                  ),
                  gridRow: r,
                  gridCol: c,
                  isEVCharging: false,
                  isHandicapAccessible: isHandicap,
                  sensorId: 'SNS-$cleanMall-$chosenFloor-$section$numStr',
                );

                Navigator.pop(ctx);
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
                      duration: const Duration(milliseconds: 1400),
                    ),
                  );
                }
                final prefs = await SharedPreferences.getInstance();
                final rawFloors = prefs.getStringList(
                      'venue_parking_floors_${_activeMall!.id}',
                    ) ??
                    List<String>.from(_activeMall!.parkingFloors);
                final curFloors = rawFloors
                    .where(
                      (f) => !RegExp(
                        r'^F\d+$',
                        caseSensitive: false,
                      ).hasMatch(f.trim()),
                    )
                    .toList();
                if (!curFloors.contains(chosenFloor)) {
                  curFloors.add(chosenFloor);
                  await prefs.setStringList(
                    'venue_parking_floors_${_activeMall!.id}',
                    curFloors,
                  );
                  if (mounted) {
                    setState(() {
                      _activeMall = _activeMall!.copyWith(
                        parkingFloors: curFloors,
                      );
                    });
                  }
                }
                await _parkingService.addParkingSlot(_activeMall!.id, newSlot);
              },
              child: const Text('Add Stall'),
            ),
          ],
        );
      },
    ),
  ).whenComplete(() {
      dialogStreamSub?.cancel();
      dialogStreamSub = null;
    });
  }



  void _showSlotDetailsModal(ParkingSlot slot) {
    if (_activeMall == null || _isModalOpening) return;
    _isModalOpening = true;
    final parkedVehicle = _parkingService.getParkedVehicleForSlot(slot.id);
    if (parkedVehicle != null) {
      slot.status = ParkingSlotStatus.occupied;
    }
    final isOccupied =
        slot.status == ParkingSlotStatus.occupied || parkedVehicle != null;
    final isReserved = slot.status == ParkingSlotStatus.reserved && !isOccupied;
    final isFree = !isOccupied && !isReserved;

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
                  icon: Icon(
                    LucideIcons.trash2,
                    color: isOccupied
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFFEF4444),
                    size: 20,
                  ),
                  tooltip: isOccupied
                      ? 'Cannot delete occupied slot'
                      : 'Delete Slot',
                  onPressed: () {
                    if (isOccupied) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Cannot delete slot ${slot.id}: A vehicle (${parkedVehicle?.licensePlate ?? "active vehicle"}) is currently parked here. User must unpark first.',
                          ),
                          backgroundColor: const Color(0xFFDC2626),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Deleted parking stall ${slot.id}'),
                          backgroundColor: const Color(0xFFEF4444),
                          duration: const Duration(milliseconds: 1400),
                        ),
                      );
                      setState(() {});
                    }
                    unawaited(
                      _parkingService.deleteParkingSlot(
                        _activeMall!.id,
                        slot.id,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Live Slot Coordinates Card with Change / Separate button
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.mapPin,
                            size: 14,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Bay Coordinates',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _showEditSlotCoordsDialog(slot);
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                LucideIcons.pencil,
                                size: 11,
                                color: Color(0xFF2563EB),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Change / Separate',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF2563EB),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Lat: ${slot.location.latitude.toStringAsFixed(6)}, Lon: ${slot.location.longitude.toStringAsFixed(6)} (Alt: ${slot.location.height.toStringAsFixed(1)}m)',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            const SizedBox(height: 10),
            if (isOccupied)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.lock,
                          size: 16,
                          color: Color(0xFFDC2626),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Auto-Locked: Vehicle currently parked in this bay.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (parkedVehicle != null) ...[
                      const SizedBox(height: 10),
                      const Divider(color: Color(0xFFFECACA), height: 1),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Driver / User:',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF991B1B),
                            ),
                          ),
                          Text(
                            parkedVehicle.userId,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF991B1B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Vehicle Plate:',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF991B1B),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFFCA5A5),
                              ),
                            ),
                            child: Text(
                              parkedVehicle.licensePlate.isNotEmpty
                                  ? parkedVehicle.licensePlate
                                  : 'WP CAB-8821',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Parked Time:',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF991B1B),
                            ),
                          ),
                          Text(
                            '${parkedVehicle.timestamp.hour.toString().padLeft(2, '0')}:${parkedVehicle.timestamp.minute.toString().padLeft(2, '0')} (${parkedVehicle.floorName})',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF7F1D1D),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      const Divider(color: Color(0xFFFECACA), height: 1),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Occupant:',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF991B1B),
                            ),
                          ),
                          Text(
                            'Active Shopper / Driver',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF991B1B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Vehicle Status:',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF991B1B),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFFCA5A5),
                              ),
                            ),
                            child: Text(
                              'PARKED & LOCKED',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            if (isOccupied) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(
                    LucideIcons.unlock,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: Text(
                    'FORCE FREE / UNPARK VEHICLE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 1,
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    slot.status = ParkingSlotStatus.free;
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Force unparked stall ${slot.id} & marked FREE',
                          ),
                          backgroundColor: const Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(milliseconds: 1400),
                        ),
                      );
                    }
                    await _parkingService.updateSlotStatus(
                      _activeMall!.id,
                      slot.id,
                      ParkingSlotStatus.free,
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
            ],
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
                    onPressed: () {
                      Navigator.pop(ctx);
                      slot.status = ParkingSlotStatus.free;
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Stall ${slot.id} unlocked and marked Free',
                            ),
                            backgroundColor: const Color(0xFF10B981),
                            duration: const Duration(milliseconds: 1400),
                          ),
                        );
                      }
                      _parkingService.updateSlotStatus(
                        _activeMall!.id,
                        slot.id,
                        ParkingSlotStatus.free,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isFree
                          ? const Color(0xFFECFDF5)
                          : Colors.white,
                      side: BorderSide(
                        color: isFree
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
                    onPressed: () {
                      Navigator.pop(ctx);
                      slot.status = ParkingSlotStatus.occupied;
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Stall ${slot.id} locked and marked Occupied',
                            ),
                            backgroundColor: const Color(0xFF0F172A),
                            duration: const Duration(milliseconds: 1400),
                          ),
                        );
                      }
                      _parkingService.updateSlotStatus(
                        _activeMall!.id,
                        slot.id,
                        ParkingSlotStatus.occupied,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isOccupied
                          ? const Color(0xFF0F172A)
                          : Colors.white,
                      side: BorderSide(
                        color: isOccupied
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFCBD5E1),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'Occupied',
                      style: TextStyle(
                        color: isOccupied
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
                    onPressed: () {
                      Navigator.pop(ctx);
                      slot.status = ParkingSlotStatus.reserved;
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Stall ${slot.id} marked as Reserved',
                            ),
                            backgroundColor: const Color(0xFFD97706),
                            duration: const Duration(milliseconds: 1400),
                          ),
                        );
                      }
                      _parkingService.updateSlotStatus(
                        _activeMall!.id,
                        slot.id,
                        ParkingSlotStatus.reserved,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isReserved
                          ? const Color(0xFFFEF3C7)
                          : Colors.white,
                      side: BorderSide(
                        color: isReserved
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
    ).whenComplete(() {
      _isModalOpening = false;
    });
  }


  void _showEditSlotCoordsDialog(ParkingSlot slot) {
    if (_activeMall == null) return;
    final latCtrl = TextEditingController(
      text: slot.location.latitude.toStringAsFixed(6),
    );
    final lonCtrl = TextEditingController(
      text: slot.location.longitude.toStringAsFixed(6),
    );

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) => AlertDialog(
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
                  LucideIcons.mapPin,
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
                      'Move / Separate Bay',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Stall ${slot.id} (Floor ${slot.floorId} • Sec ${slot.section})',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
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
                  'Fine-tune or change the exact GPS location of this bay:',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Latitude',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: latCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Longitude',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: lonCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
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
                final newLat = double.tryParse(latCtrl.text.trim()) ?? slot.location.latitude;
                final newLon = double.tryParse(lonCtrl.text.trim()) ?? slot.location.longitude;
                final offsetIdx = (slot.slotNumber - 1).clamp(0, 9999);
                final updatedSlot = ParkingSlot(
                  id: slot.id,
                  mallId: slot.mallId,
                  floorId: slot.floorId,
                  section: slot.section,
                  slotNumber: slot.slotNumber,
                  status: slot.status,
                  location: GeodeticCoords(
                    latitude: newLat,
                    longitude: newLon,
                    height: slot.location.height,
                  ),
                  gridRow: offsetIdx ~/ 4,
                  gridCol: offsetIdx % 4,
                  isEVCharging: slot.isEVCharging,
                  isHandicapAccessible: slot.isHandicapAccessible,
                  sensorId: slot.sensorId,
                );

                Navigator.pop(dlgCtx);
                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Updated coordinates for stall "${slot.id}" successfully!',
                      ),
                      backgroundColor: const Color(0xFF10B981),
                      duration: const Duration(milliseconds: 1400),
                    ),
                  );
                }
                await _parkingService.addParkingSlot(_activeMall!.id, updatedSlot);
              },
              child: const Text('Save Coordinates'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _autoSeparateFloorSlots(String floorId, {bool showToast = true}) async {
    if (_activeMall == null) return;
    final slots = _parkingService.fetchFloorMap(floorId, _activeMall!.id);
    if (slots.isEmpty) return;

    final baseLat = _liveSurveyorCoords?.latitude ?? _activeMall!.latitude;
    final baseLon = _liveSurveyorCoords?.longitude ?? _activeMall!.longitude;
    final base = GeodeticCoords(
      latitude: baseLat,
      longitude: baseLon,
      height: _resolveFloorAltitude(floorId),
    );

    // Group by section and sort
    final bySection = <String, List<ParkingSlot>>{};
    for (final s in slots) {
      final sec = s.section.trim().toUpperCase().isEmpty ? 'A' : s.section.trim().toUpperCase();
      bySection.putIfAbsent(sec, () => []).add(s);
    }

    int updatedCount = 0;
    for (final entry in bySection.entries) {
      final sec = entry.key;
      final secSlots = entry.value..sort((a, b) => a.slotNumber.compareTo(b.slotNumber));
      final int secIdx = (sec.isNotEmpty && sec.codeUnitAt(0) >= 65 && sec.codeUnitAt(0) <= 90)
          ? (sec.codeUnitAt(0) - 65)
          : 0;

      for (int i = 0; i < secSlots.length; i++) {
        final s = secSlots[i];
        final num = s.slotNumber > 0 ? s.slotNumber : (i + 1);
        final int offsetIndex = (num - 1).clamp(0, 9999);
        final int row = offsetIndex ~/ 4;
        final int col = offsetIndex % 4;
        final newCoords = GeodeticCoords(
          latitude: base.latitude + (row * 0.000045),
          longitude: base.longitude + (secIdx * 0.000150) + (col * 0.000025),
          height: base.height,
        );

        final updatedSlot = ParkingSlot(
          id: s.id,
          mallId: s.mallId,
          floorId: s.floorId,
          section: s.section,
          slotNumber: s.slotNumber,
          status: s.status,
          location: newCoords,
          gridRow: row,
          gridCol: col,
          isEVCharging: s.isEVCharging,
          isHandicapAccessible: s.isHandicapAccessible,
          sensorId: s.sensorId,
        );
        await _parkingService.addParkingSlot(_activeMall!.id, updatedSlot);
        updatedCount++;
      }
    }

    if (mounted) {
      setState(() {});
      if (showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Auto-separated $updatedCount parking bays into distinct coordinates!',
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allFloorSlots = _parkingService.getFloorSlotsForMall(_activeMall?.id);
    final allSlots = _parkingService.deduplicateSlots(
      allFloorSlots.values.expand((s) => s).toList(),
    );

    final totalBays = allSlots.length;
    final occupiedBays = allSlots
        .where(
          (s) =>
              s.status == ParkingSlotStatus.occupied ||
              _parkingService.getParkedVehicleForSlot(s.id) != null,
        )
        .length;
    final reservedVipBays = allSlots
        .where(
          (s) =>
              s.status == ParkingSlotStatus.reserved &&
              _parkingService.getParkedVehicleForSlot(s.id) == null,
        )
        .length;
    final availableBays = allSlots
        .where(
          (s) =>
              s.status == ParkingSlotStatus.free &&
              _parkingService.getParkedVehicleForSlot(s.id) == null,
        )
        .length;
    final accessibleBays = allSlots.where((s) => s.isHandicapAccessible).length;

    final occupancyRate = totalBays > 0 ? (occupiedBays / totalBays) : 0.0;
    final indicatedFloors = _getFloorOptions();
    if (indicatedFloors.isNotEmpty &&
        !indicatedFloors.contains(_selectedFloorId)) {
      _selectedFloorId = indicatedFloors.first;
    }

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
        actions: [
          IconButton(
            icon: const Icon(
              LucideIcons.refreshCw,
              size: 19,
              color: Color(0xFF0F172A),
            ),
            tooltip: 'Sync Real-Time Slots',
            onPressed: () {
              if (_activeMall != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Syncing parking slots with server...'),
                    duration: Duration(milliseconds: 1000),
                  ),
                );
                unawaited(_parkingService.syncSlotsSilently(_activeMall!.id));
              }
            },
          ),
          const SizedBox(width: 4),
        ],
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
                // OVERVIEW SUMMARY CARD
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
                          _buildStatCol('ACCESSIBLE', '$accessibleBays'),
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
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () {
                                          setState(() {
                                            _selectedFloorId = fId;
                                          });
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                            left: 4,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF0F172A)
                                                : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
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
                                .fetchFloorMap(
                                  _selectedFloorId,
                                  _activeMall?.id,
                                );
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

                            final hasOverlaps = () {
                              final seen = <String>{};
                              for (final s in currentFloorSlots) {
                                final key =
                                    '${s.location.latitude.toStringAsFixed(5)},${s.location.longitude.toStringAsFixed(5)}';
                                if (!seen.add(key)) return true;
                              }
                              return false;
                            }();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasOverlaps)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFFDE68A),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          LucideIcons.alertTriangle,
                                          size: 15,
                                          color: Color(0xFFD97706),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Multiple bays on this floor share identical coordinates.',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF92400E),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        InkWell(
                                          onTap: () => _autoSeparateFloorSlots(
                                            _selectedFloorId,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFD97706),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Auto-Separate All',
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                GridView.builder(
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
                                final parkedVehicle = _parkingService
                                    .getParkedVehicleForSlot(slot.id);
                                if (parkedVehicle != null) {
                                  slot.status = ParkingSlotStatus.occupied;
                                }
                                final isOccupied =
                                    slot.status == ParkingSlotStatus.occupied ||
                                    parkedVehicle != null;
                                final isReserved =
                                    slot.status == ParkingSlotStatus.reserved &&
                                    !isOccupied;

                                Color bgColor = const Color(0xFFF8FAFC);
                                Color borderColor = const Color(0xFFE2E8F0);
                                Color textColor = const Color(0xFF0F172A);
                                Color statusTextColor = const Color(0xFF16A34A);

                                if (isOccupied) {
                                  bgColor = const Color(0xFF0F172A);
                                  borderColor = const Color(0xFFEF4444);
                                  textColor = Colors.white;
                                  statusTextColor = const Color(0xFFF87171);
                                } else if (isReserved) {
                                  bgColor = const Color(0xFFFEF3C7);
                                  borderColor = const Color(0xFFFCD34D);
                                  textColor = const Color(0xFF92400E);
                                  statusTextColor = const Color(0xFFD97706);
                                }

                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => _showSlotDetailsModal(slot),
                                    child: Ink(
                                      decoration: BoxDecoration(
                                        color: bgColor,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: borderColor,
                                          width: isOccupied ? 1.5 : 1.0,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              if (slot.isHandicapAccessible)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
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
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: textColor,
                                                    ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            isOccupied
                                                ? (parkedVehicle != null
                                                      ? 'PARKED'
                                                      : 'OCCUPIED')
                                                : (isReserved
                                                      ? 'RESERVED'
                                                      : 'FREE'),
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w800,
                                              color: statusTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
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

                // Clear All Bays Action Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      if (_activeMall != null) {
                        final allSlots = _parkingService
                            .getFloorSlotsForMall(_activeMall?.id)
                            .values
                            .expand((s) => s)
                            .toList();
                        final occupiedSlots = allSlots
                            .where(
                              (s) =>
                                  s.status == ParkingSlotStatus.occupied ||
                                  _parkingService.getParkedVehicleForSlot(
                                        s.id,
                                      ) !=
                                      null,
                            )
                            .toList();
                        final occupiedCount = occupiedSlots.length;
                        final freeCount = allSlots.length - occupiedCount;

                        if (occupiedCount > 0 && freeCount == 0) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Cannot clear bays: All $occupiedCount bay(s) are currently occupied by parked vehicles. Users must unpark first.',
                                ),
                                backgroundColor: const Color(0xFFDC2626),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                          return;
                        }

                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Clear All Bays?'),
                            content: Text(
                              occupiedCount > 0
                                  ? 'This will delete $freeCount free parking stall(s). The $occupiedCount occupied stall(s) will be protected and preserved.'
                                  : 'This will delete all configured parking stalls for ${_activeMall?.name}.',
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
                                child: Text(
                                  occupiedCount > 0
                                      ? 'Clear Free Bays'
                                      : 'Clear All',
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          if (mounted) {
                            // ignore: use_build_context_synchronously
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  occupiedCount > 0
                                      ? 'Cleared $freeCount free bay(s). $occupiedCount occupied bay(s) protected.'
                                      : 'Cleared all parking bays for ${_activeMall?.name}',
                                ),
                                backgroundColor: const Color(0xFF0F172A),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(milliseconds: 1800),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                            setState(() {});
                          }
                          unawaited(
                            _parkingService.clearAllSlotsForMall(
                              _activeMall!.id,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(LucideIcons.trash2, size: 18),
                    label: Text(
                      'Clear All Parking Bays',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFFEF2F2),
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(
                        color: Color(0xFFFCA5A5),
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
