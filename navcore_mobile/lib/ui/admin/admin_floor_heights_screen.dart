import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../data/api_service.dart';
import '../../data/floor_height_model.dart';
import '../../data/geocoding_service.dart';
import '../../data/mall_api_service.dart';

class AdminFloorHeightsScreen extends StatefulWidget {
  final String mallId;
  final RestMallBackendApi apiService;
  final ValueChanged<List<FloorHeightData>>? onHeightsUpdated;
  final ValueChanged<String>? onMallSelected;

  const AdminFloorHeightsScreen({
    super.key,
    this.mallId = '',
    required this.apiService,
    this.onHeightsUpdated,
    this.onMallSelected,
  });

  @override
  State<AdminFloorHeightsScreen> createState() =>
      _AdminFloorHeightsScreenState();
}

class _AdminFloorHeightsScreenState extends State<AdminFloorHeightsScreen> {
  late String _selectedMallId;
  List<FloorHeightData> _floors = [];
  bool _isLoading = true;
  bool _isCalculating = false;
  String? _statusMessage;

  final Map<String, String> _knownMallNames = {};
  late List<String> _availableMallIds;

  // Real-time Barometer & Sensor State
  StreamSubscription<BarometerEvent>? _barometerSubscription;
  double _currentPressureHpa = 1013.25;
  double _liveBarometerAltitudeM = 8.5;
  bool _isBarometerActive = false;

  // Current User Location & Elevation Fusion State
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentUserPosition;
  double _userLocationAltitudeM = 8.5;
  bool _hasLocationFix = false;

  /// Dynamic location-based floor gap derived from OSM tags or architectural typology
  double get _currentFloorGapM {
    if (_currentUserPosition != null) {
      return GeocodingService.resolveDynamicFloorGapFromCoords(
        latitude: _currentUserPosition!.latitude,
        longitude: _currentUserPosition!.longitude,
      );
    }
    return 3.80;
  }

  @override
  void initState() {
    super.initState();
    _selectedMallId = widget.mallId;
    _availableMallIds = widget.mallId.isNotEmpty ? [widget.mallId] : [];
    _initBarometer();
    _initLocation();
    _initMalls();
  }

  @override
  void dispose() {
    _barometerSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _initBarometer() {
    try {
      _barometerSubscription = barometerEventStream(
        samplingPeriod: const Duration(milliseconds: 250),
      ).listen(
        (BarometerEvent event) {
          final p = event.pressure;
          if (p > 0 && !p.isNaN && !p.isInfinite) {
            if (mounted) {
              setState(() {
                _currentPressureHpa = p;
                _isBarometerActive = true;
                final delta = 44330.0 * (1.0 - math.pow(p / 1013.25, 0.1903));
                final baseTerrain = _currentUserPosition != null
                    ? (_currentUserPosition!.altitude > 0 && !_currentUserPosition!.altitude.isNaN
                        ? _currentUserPosition!.altitude
                        : GeocodingService.resolveTerrainAltitudeFromCoords(
                            _currentUserPosition!.latitude,
                            _currentUserPosition!.longitude,
                          ))
                    : 8.5;
                _liveBarometerAltitudeM = double.parse(
                  (baseTerrain + delta).clamp(-50.0, 9000.0).toStringAsFixed(2),
                );
                if (_currentUserPosition != null) {
                  _userLocationAltitudeM = _computeFusedLocationHeight(
                    gpsAltitude: _currentUserPosition!.altitude,
                    gpsAccuracy: _currentUserPosition!.accuracy,
                    currentPressureHpa: _currentPressureHpa,
                    lat: _currentUserPosition!.latitude,
                    lon: _currentUserPosition!.longitude,
                  );
                } else {
                  _userLocationAltitudeM = _liveBarometerAltitudeM;
                }
              });
            }
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() => _isBarometerActive = false);
          }
        },
        cancelOnError: false,
      );
    } catch (_) {
      _isBarometerActive = false;
    }
  }

  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      // Fetch immediate last known fix
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null && mounted) {
        setState(() {
          _currentUserPosition = lastPos;
          _hasLocationFix = true;
          _userLocationAltitudeM = _computeFusedLocationHeight(
            gpsAltitude: lastPos.altitude,
            gpsAccuracy: lastPos.accuracy,
            currentPressureHpa: _currentPressureHpa,
            lat: lastPos.latitude,
            lon: lastPos.longitude,
          );
        });
        _autoSyncDefaultFloorsToLocation();
      }

      // Stream continuous high-precision GNSS fixes
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position pos) {
          if (mounted) {
            setState(() {
              _currentUserPosition = pos;
              _hasLocationFix = true;
              _userLocationAltitudeM = _computeFusedLocationHeight(
                gpsAltitude: pos.altitude,
                gpsAccuracy: pos.accuracy,
                currentPressureHpa: _currentPressureHpa,
                lat: pos.latitude,
                lon: pos.longitude,
              );
            });
            _autoSyncDefaultFloorsToLocation();
          }
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  /// Automatically replaces any uncalibrated dummy defaults (15.0m ground or 4.5m gap)
  /// with user location calculated elevation and dynamic standard gap
  void _autoSyncDefaultFloorsToLocation() {
    if (_floors.isEmpty) return;
    final hasDummyFloors = _floors.any(
      (f) =>
          !f.isLocked &&
          (f.source == 'default' ||
              f.heightToNextM == 4.5 ||
              (f.floorNo == 1 && (f.baseAltitudeM == 15.0 || f.baseAltitudeM <= 0.0))),
    );
    if (!hasDummyFloors) return;

    final updated = _floors.map((f) {
      if (f.isLocked || f.source == 'admin') return f;
      final gap = (f.heightToNextM == 4.5 || f.heightToNextM <= 0.0)
          ? _currentFloorGapM
          : f.heightToNextM;
      return f.copyWith(
        heightToNextM: gap,
        source: 'gps_baro_fusion',
      );
    }).toList();

    final recomputed = _recalculateCumulativeAltitudes(
      updated,
      groundBaselineAlt: _userLocationAltitudeM,
    );

    setState(() {
      _floors = recomputed;
      _statusMessage =
          'Height auto-calibrated from user location (${_userLocationAltitudeM.toStringAsFixed(2)}m) • Gap ${_currentFloorGapM.toStringAsFixed(2)}m';
    });
    widget.onHeightsUpdated?.call(_floors);
  }

  /// Computes optimal elevation based on user's current location:
  /// Suitable method: GNSS Geodetic Datum (WGS84) + Real-Time Barometric Hypsometric Model fusion
  double _computeFusedLocationHeight({
    required double gpsAltitude,
    required double gpsAccuracy,
    required double currentPressureHpa,
    double? lat,
    double? lon,
    double seaLevelPressureHpa = 1013.25,
  }) {
    // Hypsometric formula for atmospheric pressure
    final baroAltitudeDelta = 44330.0 *
        (1.0 - math.pow(currentPressureHpa / seaLevelPressureHpa, 0.1903));

    final targetLat = lat ?? _currentUserPosition?.latitude;
    final targetLon = lon ?? _currentUserPosition?.longitude;
    final terrainElevation = (targetLat != null && targetLon != null)
        ? GeocodingService.resolveTerrainAltitudeFromCoords(targetLat, targetLon)
        : 8.5;

    if (gpsAltitude > 0 && !gpsAltitude.isNaN && gpsAltitude < 9000.0) {
      if (gpsAccuracy > 0 && gpsAccuracy < 25.0) {
        // High confidence GNSS fix: weight GPS altitude as base datum
        final gpsWeight = (1.0 - (gpsAccuracy / 30.0)).clamp(0.60, 0.90);
        final fused = (gpsWeight * gpsAltitude) +
            ((1.0 - gpsWeight) * (terrainElevation + baroAltitudeDelta));
        return double.parse(fused.toStringAsFixed(2));
      }
      return double.parse(gpsAltitude.toStringAsFixed(2));
    }

    // Topographic terrain elevation + barometric hypsometric delta (no dummy 15m!)
    final locationHeight = (terrainElevation + baroAltitudeDelta).clamp(0.0, 5000.0);
    return double.parse(locationHeight.toStringAsFixed(2));
  }


  /// Recalculates cumulative base altitudes sequentially based on floor gaps:
  /// Floor 1 Base Altitude = user location height (or entrance anchor)
  /// Floor N Base Altitude = Floor N-1 Base Altitude + Floor N-1 Height To Next
  List<FloorHeightData> _recalculateCumulativeAltitudes(
    List<FloorHeightData> list, {
    double? groundBaselineAlt,
  }) {
    if (list.isEmpty) return [];
    final sorted = List<FloorHeightData>.from(list)
      ..sort((a, b) => a.floorNo.compareTo(b.floorNo));
    final result = <FloorHeightData>[];

    final firstFloor = sorted.first;
    double currentAlt;

    if (groundBaselineAlt != null && groundBaselineAlt > 0) {
      currentAlt = groundBaselineAlt;
    } else if (firstFloor.baseAltitudeM > 0 && (firstFloor.isLocked || firstFloor.source == 'admin')) {
      currentAlt = firstFloor.baseAltitudeM;
    } else if (_hasLocationFix && _userLocationAltitudeM > 0) {
      currentAlt = _userLocationAltitudeM;
    } else if (_currentUserPosition != null) {
      currentAlt = GeocodingService.resolveTerrainAltitudeFromCoords(
        _currentUserPosition!.latitude,
        _currentUserPosition!.longitude,
      );
    } else if (firstFloor.baseAltitudeM > 0 && firstFloor.baseAltitudeM != 15.0) {
      currentAlt = firstFloor.baseAltitudeM;
    } else {
      currentAlt = _userLocationAltitudeM > 0 ? _userLocationAltitudeM : 8.5;
    }

    for (int i = 0; i < sorted.length; i++) {
      final f = sorted[i];
      if (i == 0) {
        result.add(f.copyWith(
          baseAltitudeM: double.parse(currentAlt.toStringAsFixed(2)),
        ));
      } else {
        final prev = result[i - 1];
        currentAlt = prev.baseAltitudeM + prev.heightToNextM;
        result.add(f.copyWith(
          baseAltitudeM: double.parse(currentAlt.toStringAsFixed(2)),
        ));
      }
    }
    return result;
  }

  double _calculateSuggestedFloorGap(FloorHeightData floor) {
    if (_isBarometerActive || _hasLocationFix) {
      double prevAlt = _userLocationAltitudeM;
      final prevIndex = _floors.indexWhere((f) => f.floorNo == floor.floorNo - 1);
      if (prevIndex >= 0) {
        prevAlt = _floors[prevIndex].baseAltitudeM;
      }
      final refAlt = _hasLocationFix ? _userLocationAltitudeM : _liveBarometerAltitudeM;
      final diff = (refAlt - prevAlt).abs();
      if (diff >= 2.0 && diff <= 12.0) {
        return double.parse(diff.toStringAsFixed(2));
      }
    }
    return (floor.heightToNextM > 0 && floor.heightToNextM != 4.5)
        ? floor.heightToNextM
        : _currentFloorGapM;
  }

  Future<void> _initMalls() async {
    try {
      final malls = await ApiService.instance.fetchMalls();
      if (mounted) {
        setState(() {
          _availableMallIds.clear();
          for (final m in malls) {
            final mId = m.id.trim();
            if (mId.isNotEmpty) {
              _knownMallNames[mId] = m.name.isNotEmpty ? m.name : mId;
              if (!_availableMallIds.any(
                (id) => id.toLowerCase() == mId.toLowerCase(),
              )) {
                _availableMallIds.add(mId);
              }
            }
          }
          final wId = widget.mallId.trim();
          if (wId.isNotEmpty &&
              !_availableMallIds.any(
                (id) => id.toLowerCase() == wId.toLowerCase(),
              )) {
            _availableMallIds.add(wId);
            _knownMallNames[wId] = wId;
          }

          if (_selectedMallId.trim().isEmpty) {
            if (_availableMallIds.isNotEmpty) {
              _selectedMallId = _availableMallIds.first;
            }
          } else {
            final match = _availableMallIds.firstWhere(
              (id) => id.toLowerCase() == _selectedMallId.trim().toLowerCase(),
              orElse: () => _availableMallIds.isNotEmpty
                  ? _availableMallIds.first
                  : _selectedMallId,
            );
            _selectedMallId = match;
          }
        });
      }
    } catch (_) {}
    if (_selectedMallId.isNotEmpty) {
      _loadFloorHeights();
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onMallChanged(String? newMallId) {
    if (newMallId == null || newMallId == _selectedMallId) return;
    setState(() {
      _selectedMallId = newMallId;
      _floors = [];
      _isLoading = true;
      _statusMessage = null;
    });
    widget.onMallSelected?.call(newMallId);
    _loadFloorHeights();
  }

  Future<void> _loadFloorHeights() async {
    final targetMall = _selectedMallId.trim();
    if (targetMall.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _isLoading = true;
      _floors = [];
      _statusMessage = null;
    });

    try {
      var list = await widget.apiService.fetchFloorHeights(targetMall);
      if (list.isEmpty) {
        list = await ApiService.instance.fetchFloorHeights(targetMall);
      }

      final lowerTarget = targetMall.toLowerCase();
      final filtered = list
          .where((f) {
            final fMall = f.mallId.trim().toLowerCase();
            return fMall.isEmpty || fMall == lowerTarget;
          })
          .map((f) {
            if (f.mallId.trim().isEmpty) {
              return f.copyWith(mallId: targetMall);
            }
            return f;
          })
          .map((f) {
            if (!f.isLocked && f.source != 'admin') {
              final gap = (f.heightToNextM == 4.5 || f.heightToNextM <= 0.0)
                  ? _currentFloorGapM
                  : f.heightToNextM;
              final baseAlt = (f.floorNo == 1 && (f.baseAltitudeM == 15.0 || f.baseAltitudeM <= 0.0))
                  ? _userLocationAltitudeM
                  : f.baseAltitudeM;
              return f.copyWith(
                heightToNextM: gap,
                baseAltitudeM: baseAlt,
                source: 'gps_baro_fusion',
              );
            }
            return f;
          })
          .toList();

      filtered.sort((a, b) => a.floorNo.compareTo(b.floorNo));
      final recomputed = _recalculateCumulativeAltitudes(filtered);

      if (mounted) {
        setState(() {
          _floors = recomputed;
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
    final targetMall = _selectedMallId.trim();
    if (targetMall.isEmpty) return;

    setState(() {
      _isCalculating = true;
      _statusMessage = null;
    });

    try {
      final updatedList = await widget.apiService.triggerFloorHeightCalculation(
        targetMall,
        lat: _currentUserPosition?.latitude,
        lon: _currentUserPosition?.longitude,
        barometerPressureHpa: _currentPressureHpa,
        liveAltitudeM: _userLocationAltitudeM,
        floorGapM: _currentFloorGapM,
      );
      final lowerTarget = targetMall.toLowerCase();
      final filtered = updatedList.where((f) {
        final fMall = f.mallId.trim().toLowerCase();
        return fMall.isEmpty || fMall == lowerTarget;
      }).toList();

      // Strictly preserve admin-added floor gaps and locked floors
      final preserved = <FloorHeightData>[];
      for (final f in filtered) {
        final existing = _floors.firstWhere(
          (old) => old.floorNo == f.floorNo,
          orElse: () => f,
        );
        if (existing.isLocked || existing.source == 'admin') {
          preserved.add(existing);
        } else {
          final gap = (f.heightToNextM == 4.5 || f.heightToNextM <= 0.0)
              ? _currentFloorGapM
              : f.heightToNextM;
          preserved.add(f.copyWith(
            heightToNextM: gap,
            source: 'gps_baro_fusion',
            confidence: _isBarometerActive ? 0.95 : 0.85,
          ));
        }
      }

      final recomputed = _recalculateCumulativeAltitudes(
        preserved,
        groundBaselineAlt: _userLocationAltitudeM,
      );

      // Push cascaded cumulative altitudes to backend to keep DB synced
      for (final floor in recomputed) {
        widget.apiService.updateFloorHeight(
          targetMall,
          floor.floorNo,
          heightToNextM: floor.heightToNextM,
          isLocked: floor.isLocked,
        ).catchError((_) => floor);
      }

      if (mounted) {
        setState(() {
          _floors = recomputed;
          _isCalculating = false;
          _statusMessage = _hasLocationFix
              ? 'Height auto-calculated from user location (${_userLocationAltitudeM.toStringAsFixed(1)}m • Lat ${_currentUserPosition!.latitude.toStringAsFixed(4)}°) & Barometer • Admin gaps preserved!'
              : 'Auto-calculated with real-time barometer (${_currentPressureHpa.toStringAsFixed(1)} hPa) • Admin gaps preserved!';
        });
        widget.onHeightsUpdated?.call(_floors);
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
    final baseAltController = TextEditingController(
      text: floor.baseAltitudeM.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Override Height for Floor ${floor.floorNo}',
          style: GoogleFonts.outfit(
            color: const Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                floor.floorNo == 1
                    ? 'Configure Floor 1 baseline ground altitude and floor gap. Upper floor base altitudes chain automatically.'
                    : 'Enter manual height to next floor (meters). This locks this admin floor gap and recalculates upper floor base altitudes.',
                style: GoogleFonts.inter(
                  color: const Color(0xFF64748B),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),

              if (floor.floorNo == 1) ...[
                TextField(
                  controller: baseAltController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: GoogleFonts.inter(color: const Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    labelText: 'Ground Base Altitude (m)',
                    labelStyle: const TextStyle(color: Color(0xFF1D4ED8)),
                    suffixText: 'meters',
                    suffixStyle: const TextStyle(color: Color(0xFF64748B)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(
                        color: Color(0xFF1D4ED8),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    InkWell(
                      onTap: () {
                        baseAltController.text =
                            _userLocationAltitudeM.toStringAsFixed(2);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF93C5FD)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.mapPin,
                              size: 13,
                              color: Color(0xFF1D4ED8),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Location Height (${_userLocationAltitudeM.toStringAsFixed(1)}m)',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1D4ED8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        baseAltController.text =
                            _liveBarometerAltitudeM.toStringAsFixed(2);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.gauge,
                              size: 13,
                              color: Color(0xFF15803D),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Baro Alt (${_liveBarometerAltitudeM.toStringAsFixed(1)}m)',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF15803D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.layers, size: 16, color: Color(0xFF475569)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cumulative Base Altitude: ${floor.baseAltitudeM.toStringAsFixed(2)} m (chained from Floor ${floor.floorNo - 1})',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              TextField(
                controller: textController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF0D9488),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  InkWell(
                    onTap: () {
                      textController.text =
                          _currentFloorGapM.toStringAsFixed(2);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Text(
                        'Location Gap (${_currentFloorGapM.toStringAsFixed(2)}m)',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      final suggested = _calculateSuggestedFloorGap(floor);
                      textController.text = suggested.toStringAsFixed(2);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.gauge,
                            size: 13,
                            color: Color(0xFF15803D),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Suggested Gap (${_calculateSuggestedFloorGap(floor).toStringAsFixed(2)}m)',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF15803D),
                            ),
                          ),
                        ],
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final newHeight = double.tryParse(textController.text.trim());
              final newBaseAlt = floor.floorNo == 1
                  ? double.tryParse(baseAltController.text.trim())
                  : null;
              if (newHeight == null || newHeight < 0.0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid positive floor gap'),
                  ),
                );
                return;
              }

              Navigator.pop(ctx);
              setState(() => _isLoading = true);

              // 1. Update this floor in local list with admin source and locked status
              final updatedList = List<FloorHeightData>.from(_floors);
              final idx = updatedList.indexWhere((f) => f.floorNo == floor.floorNo);
              if (idx >= 0) {
                updatedList[idx] = updatedList[idx].copyWith(
                  heightToNextM: newHeight,
                  baseAltitudeM: newBaseAlt ?? updatedList[idx].baseAltitudeM,
                  source: 'admin',
                  isLocked: true,
                  confidence: 1.0,
                  updatedAt: DateTime.now().toIso8601String(),
                );
              }

              // 2. Cumulatively recalculate base altitudes for all floors based on the admin added floor gap
              final recomputed = _recalculateCumulativeAltitudes(
                updatedList,
                groundBaselineAlt: newBaseAlt,
              );

              try {
                await widget.apiService.updateFloorHeight(
                  _selectedMallId,
                  floor.floorNo,
                  heightToNextM: newHeight,
                  baseAltitudeM: newBaseAlt ?? floor.baseAltitudeM,
                  isLocked: true,
                );
                // Also update subsequent floors on backend to synchronize cascaded base altitudes
                for (final f in recomputed.where((f) => f.floorNo > floor.floorNo)) {
                  widget.apiService.updateFloorHeight(
                    _selectedMallId,
                    f.floorNo,
                    heightToNextM: f.heightToNextM,
                    baseAltitudeM: f.baseAltitudeM,
                    isLocked: f.isLocked,
                  ).catchError((_) => f);
                }
              } catch (_) {}

              if (mounted) {
                setState(() {
                  _floors = recomputed;
                  _isLoading = false;
                  _statusMessage =
                      'Floor ${floor.floorNo} updated (gap: ${newHeight.toStringAsFixed(2)}m) • Base altitudes recalculated!';
                });
                widget.onHeightsUpdated?.call(_floors);
              }
            },
            child: const Text('Save & Lock'),
          ),
        ],
      ),
    );
  }

  void _confirmAndDeleteFloor(FloorHeightData floor) {
    final floorLabel = floor.floorNo < 0
        ? 'B${floor.floorNo.abs()}'
        : 'Floor ${floor.floorNo}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete $floorLabel?',
          style: GoogleFonts.outfit(
            color: const Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete $floorLabel? Base altitudes for remaining floors will automatically be recalculated.',
          style: GoogleFonts.inter(
            color: const Color(0xFF64748B),
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final updatedList = await widget.apiService.deleteFloor(
                  _selectedMallId,
                  floor.floorNo,
                );
                final lowerTarget = _selectedMallId.toLowerCase();
                final filtered = updatedList
                    .where(
                      (f) =>
                          f.mallId.trim().isEmpty ||
                          f.mallId.trim().toLowerCase() == lowerTarget,
                    )
                    .map(
                      (f) => f.mallId.trim().isEmpty
                          ? f.copyWith(mallId: _selectedMallId)
                          : f,
                    )
                    .toList();
                filtered.sort((a, b) => a.floorNo.compareTo(b.floorNo));
                final recomputed = _recalculateCumulativeAltitudes(filtered);
                if (mounted) {
                  setState(() {
                    _floors = recomputed;
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

  void _showAddFloorDialog() {
    final nextFloorNo = _floors.isNotEmpty ? (_floors.last.floorNo + 1) : 1;
    final floorNoController = TextEditingController(
      text: nextFloorNo.toString(),
    );
    final heightController = TextEditingController(
      text: _currentFloorGapM.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              LucideIcons.plusCircle,
              color: Color(0xFF0D9488),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Add Floor (${_knownMallNames[_selectedMallId] ?? _selectedMallId})',
                style: GoogleFonts.outfit(
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter floor number and height gap to the next floor.',
              style: GoogleFonts.inter(
                color: const Color(0xFF64748B),
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: floorNoController,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              style: GoogleFonts.inter(color: const Color(0xFF0F172A)),
              decoration: InputDecoration(
                labelText: 'Floor Number (e.g. 1, 2, 7)',
                labelStyle: const TextStyle(color: Color(0xFF0D9488)),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: heightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: GoogleFonts.inter(color: const Color(0xFF0F172A)),
              decoration: InputDecoration(
                labelText: 'Height to Next Floor (m)',
                labelStyle: const TextStyle(color: Color(0xFF0D9488)),
                suffixText: 'meters',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final fn = int.tryParse(floorNoController.text.trim());
              final h = double.tryParse(heightController.text.trim());
              if (fn == null || h == null || h <= 0.0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Please enter a valid floor number and positive height',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                final updated = await widget.apiService.addFloor(
                  _selectedMallId,
                  fn,
                  h,
                );
                final lowerTarget = _selectedMallId.toLowerCase();
                final filtered = updated
                    .where(
                      (f) =>
                          f.mallId.trim().isEmpty ||
                          f.mallId.trim().toLowerCase() == lowerTarget,
                    )
                    .map(
                      (f) => f.mallId.trim().isEmpty
                          ? f.copyWith(mallId: _selectedMallId)
                          : f,
                    )
                    .toList();
                filtered.sort((a, b) => a.floorNo.compareTo(b.floorNo));
                final recomputed = _recalculateCumulativeAltitudes(filtered);
                if (mounted) {
                  setState(() {
                    _floors = recomputed;
                    _statusMessage =
                        'Floor $fn added for ${_knownMallNames[_selectedMallId] ?? _selectedMallId}.';
                  });
                  widget.onHeightsUpdated?.call(_floors);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error adding floor: $e')),
                  );
                }
              }
            },
            child: const Text('Add Floor'),
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
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0D9488)),
            )
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFCBD5E1),
                                  ),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: _availableMallIds.isEmpty
                                      ? Text(
                                          'No venues available',
                                          style: GoogleFonts.outfit(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF94A3B8),
                                          ),
                                        )
                                      : DropdownButton<String>(
                                          value:
                                              _availableMallIds.contains(
                                                _selectedMallId,
                                              )
                                              ? _selectedMallId
                                              : _availableMallIds.first,
                                          isExpanded: true,
                                          icon: const Icon(
                                            LucideIcons.chevronDown,
                                            size: 18,
                                            color: Color(0xFF0D9488),
                                          ),
                                          style: GoogleFonts.outfit(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF0F172A),
                                          ),
                                          dropdownColor: Colors.white,
                                          items: _availableMallIds.map((
                                            mallId,
                                          ) {
                                            final displayName =
                                                _knownMallNames[mallId] ??
                                                mallId;
                                            return DropdownMenuItem<String>(
                                              value: mallId,
                                              child: Text(
                                                displayName,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.outfit(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: const Color(
                                                    0xFF0F172A,
                                                  ),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: _isCalculating
                              ? null
                              : _runAutoCalculation,
                          icon: _isCalculating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(LucideIcons.calculator, size: 16),
                          label: Text(
                            _isCalculating
                                ? 'Calculating...'
                                : 'Re-run Auto-Calc',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
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
                          const Icon(
                            LucideIcons.checkCircle,
                            size: 16,
                            color: Color(0xFF047857),
                          ),
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
                        child: _floors.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        LucideIcons.layers,
                                        size: 44,
                                        color: Color(0xFF94A3B8),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        'No floor heights found for ${_knownMallNames[_selectedMallId] ?? _selectedMallId}',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.outfit(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF334155),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Add floors manually or click below to auto-generate floor gaps and altitude profiles from the backend.',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        alignment: WrapAlignment.center,
                                        children: [
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFF0D9488,
                                              ),
                                              side: const BorderSide(
                                                color: Color(0xFF0D9488),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 12,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: _showAddFloorDialog,
                                            icon: const Icon(
                                              LucideIcons.plus,
                                              size: 15,
                                            ),
                                            label: const Text('Add Floor'),
                                          ),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFF0D9488,
                                              ),
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 18,
                                                    vertical: 12,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: _isCalculating
                                                ? null
                                                : _runAutoCalculation,
                                            icon: const Icon(
                                              LucideIcons.calculator,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              'Auto-Generate Floors',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columnSpacing: 28,
                                    headingRowHeight: 48,
                                    dataRowMinHeight: 52,
                                    dataRowMaxHeight: 56,
                                    headingRowColor: WidgetStateProperty.all(
                                      const Color(0xFFF1F5F9),
                                    ),
                                    dataRowColor: WidgetStateProperty.all(
                                      Colors.white,
                                    ),
                                    border: const TableBorder(
                                      horizontalInside: BorderSide(
                                        color: Color(0xFFF1F5F9),
                                        width: 1,
                                      ),
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
                                      final badgeTextColor =
                                          _getSourceBadgeColor(floor.source);
                                      final badgeBgColor =
                                          _getSourceBadgeBgColor(floor.source);
                                      final isTopFloor =
                                          floor.heightToNextM == 0.0 &&
                                          floor.floorNo == _floors.last.floorNo;

                                      return DataRow(
                                        cells: [
                                          DataCell(
                                            Text(
                                              floor.floorNo < 0
                                                  ? 'B${floor.floorNo.abs()}'
                                                  : 'Floor ${floor.floorNo}',
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
                                              isTopFloor
                                                  ? 'N/A (Top)'
                                                  : '${floor.heightToNextM.toStringAsFixed(2)} m',
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: badgeBgColor,
                                                border: Border.all(
                                                  color: badgeTextColor
                                                      .withValues(alpha: 0.4),
                                                  width: 1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
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
                                                  icon: const Icon(
                                                    LucideIcons.edit3,
                                                    size: 18,
                                                    color: Color(0xFF0D9488),
                                                  ),
                                                  tooltip:
                                                      'Edit / Override Height',
                                                  onPressed: () =>
                                                      _showEditDialog(floor),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    LucideIcons.trash2,
                                                    size: 18,
                                                    color: Color(0xFFEF4444),
                                                  ),
                                                  tooltip: 'Delete Floor',
                                                  onPressed: () =>
                                                      _confirmAndDeleteFloor(
                                                        floor,
                                                      ),
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
