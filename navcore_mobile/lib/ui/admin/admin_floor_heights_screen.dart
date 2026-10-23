import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../data/api_service.dart';
import '../../data/floor_height_model.dart';
import '../../data/geocoding_service.dart';
import '../../data/mall_api_service.dart';
import '../../data/mall_database_service.dart';
import '../../engine/ar_sensor_engine.dart';
import '../../engine/real_sensor_service.dart';
import '../../engine/phone_motion_floor_tracker.dart';

class AdminFloorHeightsScreen extends StatefulWidget {
  final String mallId;
  final RestMallBackendApi apiService;
  final RealSensorService? sensorService;
  final ValueChanged<List<FloorHeightData>>? onHeightsUpdated;
  final ValueChanged<String>? onMallSelected;

  const AdminFloorHeightsScreen({
    super.key,
    this.mallId = '',
    required this.apiService,
    this.sensorService,
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
  final Map<String, MallMetadata> _knownMalls = {};
  late List<String> _availableMallIds;

  // Real-time Barometer & Sensor State
  StreamSubscription<BarometerEvent>? _barometerSubscription;
  double _currentPressureHpa = 1013.25;
  double _liveBarometerAltitudeM = 0.0;
  bool _isBarometerActive = false;

  // Current User Location & Elevation Fusion State
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<double>? _motionSubscription;
  double? _lastMeasuredMotionGap;
  Position? _currentUserPosition;
  double _userLocationAltitudeM = 0.0;
  bool _hasLocationFix = false;

  final BarometricElevationEngine _elevationEngine =
      BarometricElevationEngine();

  /// Real-world ground elevation computed dynamically using geoid-compensated GNSS,
  /// regional digital terrain model, and the smartphone barometer hypsometric model
  double get _computedRealWorldElevation {
    double lat = _currentUserPosition?.latitude ?? 0.0;
    double lon = _currentUserPosition?.longitude ?? 0.0;
    double rawGpsAlt = _currentUserPosition?.altitude ?? 0.0;
    double gpsAccuracy = _currentUserPosition?.accuracy ?? 10.0;

    final mall = _selectedMall;
    if (lat == 0.0 && lon == 0.0 && mall != null) {
      lat = mall.latitude;
      lon = mall.longitude;
    }

    // 1. Resolve base terrain elevation for this specific geographical coordinate
    final double terrainAlt = (lat != 0.0 && lon != 0.0)
        ? GeocodingService.resolveTerrainAltitudeFromCoords(
            lat,
            lon,
            rawGpsAltitude: rawGpsAlt,
            gpsAccuracy: gpsAccuracy,
          )
        : 11.4;

    // 2. Resolve base anchor elevation: if venue has a custom anchor (not old legacy 10.0 / 8.5 default)
    // use it; otherwise dynamically resolve from real regional terrain & geoid-corrected GPS!
    final bool isLegacyDefault =
        mall != null &&
        (mall.entranceBaseAnchorHeight == 10.0 ||
            mall.entranceBaseAnchorHeight == 8.5 ||
            mall.entranceBaseAnchorHeight <= 0.0);

    final double baseAnchor =
        (mall != null && mall.entranceBaseAnchorHeight > 0 && !isLegacyDefault)
        ? mall.entranceBaseAnchorHeight
        : terrainAlt;

    // 3. Calibrate baseline pressure if uncalibrated
    final effectivePressure = _currentPressureHpa > 300.0
        ? _currentPressureHpa
        : 1013.25;
    if (!_elevationEngine.isCalibrated ||
        _elevationEngine.baselineAnchorHeight == 0.0) {
      _elevationEngine.calibrateBaseline(effectivePressure, baseAnchor);
    }

    // 4. Compute dynamic altitude from barometer hypsometric model
    final baroHeight = _elevationEngine.calculateAbsoluteHeight(
      effectivePressure,
    );

    // 5. Compensate GPS geoid undulation: if GPS fix is good (< 25m), fuse with barometer/terrain
    final correctedGps = GeocodingService.correctGpsAltitude(
      rawGpsAlt,
      lat,
      lon,
    );
    if (correctedGps > 0.0) {
      if (gpsAccuracy > 0 && gpsAccuracy < 25.0) {
        if (_isBarometerActive && _currentPressureHpa > 300.0) {
          return _elevationEngine.computeFusedLocationHeight(
            currentPressureHpa: effectivePressure,
            gpsAltitude: correctedGps,
            gpsAccuracy: gpsAccuracy,
          );
        }
        return double.parse(correctedGps.toStringAsFixed(2));
      }
      return double.parse(correctedGps.toStringAsFixed(2));
    }

    return double.parse(
      (baroHeight > 0.0 && _isBarometerActive ? baroHeight : baseAnchor)
          .toStringAsFixed(2),
    );
  }

  /// Dynamic height gap between floors computed using physical phone movement,
  /// building category typology, and micro-atmospheric pressure changes
  double get _computedDynamicFloorGap {
    double lat = _currentUserPosition?.latitude ?? 0.0;
    double lon = _currentUserPosition?.longitude ?? 0.0;
    final mall = _selectedMall;
    if (lat == 0.0 && lon == 0.0 && mall != null) {
      lat = mall.latitude;
      lon = mall.longitude;
    }

    // Check if the smartphone barometer detects pressure difference between floors
    double? deltaHpa;
    if (_elevationEngine.isCalibrated &&
        _elevationEngine.baselinePressure != null &&
        _currentPressureHpa > 300.0) {
      deltaHpa = (_elevationEngine.baselinePressure! - _currentPressureHpa)
          .abs();
    }

    final gap = GeocodingService.resolveDynamicFloorGapFromCoords(
      latitude: lat,
      longitude: lon,
      measuredBarometerDeltaHpa: (deltaHpa != null && deltaHpa > 0.08)
          ? deltaHpa
          : null,
      measuredMotionGapMeters: _lastMeasuredMotionGap,
      livePressureHpa: _currentPressureHpa,
      basePressureHpa: _elevationEngine.baselinePressure,
      category: mall?.category,
      venueName: mall?.name,
    );

    return double.parse(gap.toStringAsFixed(2));
  }

  /// Resolved mall metadata for currently selected mall
  MallMetadata? get _selectedMall {
    final cleanId = _selectedMallId.trim().toLowerCase();
    for (final entry in _knownMalls.entries) {
      if (entry.key.trim().toLowerCase() == cleanId ||
          entry.value.name.trim().toLowerCase() == cleanId) {
        return entry.value;
      }
    }
    return null;
  }

  /// Target floor gap: automatically computed using phone's barometer and user's location
  double get _targetFloorGapM => _computedDynamicFloorGap;

  /// Dynamic location-based floor gap alias
  double get _currentFloorGapM => _computedDynamicFloorGap;

  /// Target ground baseline altitude: automatically computed using phone's barometer and user's location
  double get _targetGroundAltM => _computedRealWorldElevation;

  @override
  void initState() {
    super.initState();
    _selectedMallId = widget.mallId;
    _availableMallIds = widget.mallId.isNotEmpty ? [widget.mallId] : [];

    // Pre-seed from hardware sensor service if available
    if (widget.sensorService != null) {
      if (widget.sensorService!.currentPressure > 300.0) {
        _currentPressureHpa = widget.sensorService!.currentPressure;
        _isBarometerActive = true;
      }
      if (widget.sensorService!.lastCoords != null &&
          widget.sensorService!.lastCoords!.latitude != 0.0) {
        _currentUserPosition = Position(
          latitude: widget.sensorService!.lastCoords!.latitude,
          longitude: widget.sensorService!.lastCoords!.longitude,
          timestamp: DateTime.now(),
          altitude: widget.sensorService!.lastCoords!.height,
          accuracy: widget.sensorService!.lastAccuracy,
          heading: 0.0,
          floor: 0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
        _hasLocationFix = true;
        _userLocationAltitudeM = _computedRealWorldElevation;
      }
    }

    // Start physical phone motion vertical tracking & stairs cadence analyzer
    PhoneMotionFloorTracker().startTracking(
      onEstimate: (motionGap) {
        if (!mounted) return;
        setState(() {
          _lastMeasuredMotionGap = motionGap;
        });
        _autoSyncDefaultFloorsToLocation();
      },
    );
    _motionSubscription = PhoneMotionFloorTracker().onFloorGapEstimated.listen((
      gap,
    ) {
      if (!mounted) return;
      setState(() {
        _lastMeasuredMotionGap = gap;
      });
      _autoSyncDefaultFloorsToLocation();
    });

    _initBarometer();
    _initLocation();
    _initMalls();
  }

  @override
  void dispose() {
    _motionSubscription?.cancel();
    _motionSubscription = null;
    PhoneMotionFloorTracker().stopTracking();
    _barometerSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _initBarometer() {
    try {
      _barometerSubscription =
          barometerEventStream(
            samplingPeriod: const Duration(milliseconds: 250),
          ).listen(
            (BarometerEvent event) {
              final p = event.pressure;
              if (p > 0 && !p.isNaN && !p.isInfinite) {
                if (mounted) {
                  setState(() {
                    _currentPressureHpa = p;
                    _isBarometerActive = true;
                    _liveBarometerAltitudeM = _computedRealWorldElevation;
                    _userLocationAltitudeM = _computedRealWorldElevation;
                  });
                  _autoSyncDefaultFloorsToLocation();
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
          _userLocationAltitudeM = _computedRealWorldElevation;
        });
        _autoSyncDefaultFloorsToLocation();
      }

      // Stream continuous high-precision GNSS fixes
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen((Position pos) {
            if (mounted) {
              setState(() {
                _currentUserPosition = pos;
                _hasLocationFix = true;
                _userLocationAltitudeM = _computedRealWorldElevation;
              });
              _autoSyncDefaultFloorsToLocation();
            }
          }, onError: (_) {});
    } catch (_) {}
  }

  /// Automatically updates floor heights and base altitudes from the phone's barometer
  /// and the user's location (GNSS + barometric hypsometric model)
  void _autoSyncDefaultFloorsToLocation() {
    if (_floors.isEmpty) return;

    final targetGap = _computedDynamicFloorGap;
    final targetGround = _computedRealWorldElevation;

    final updated = _floors.map((f) {
      if (f.isLocked && f.heightToNextM > 0.0) {
        return f;
      }
      return f.copyWith(heightToNextM: targetGap, source: 'barometer_gps');
    }).toList();

    final recomputed = _recalculateCumulativeAltitudes(
      updated,
      groundBaselineAlt: targetGround,
    );

    // Only update if difference is noticeable (> 0.05m)
    bool hasChanged = false;
    if (_floors.length != recomputed.length) {
      hasChanged = true;
    } else {
      for (int i = 0; i < _floors.length; i++) {
        if ((_floors[i].baseAltitudeM - recomputed[i].baseAltitudeM).abs() >
                0.05 ||
            (_floors[i].heightToNextM - recomputed[i].heightToNextM).abs() >
                0.05) {
          hasChanged = true;
          break;
        }
      }
    }

    if (hasChanged && mounted) {
      setState(() {
        _floors = recomputed;
        _statusMessage =
            'Real-world elevation computed: Ground ${targetGround.toStringAsFixed(2)}m • Story Gap ${targetGap.toStringAsFixed(2)}m (Phone Barometer & Location)';
      });
      widget.onHeightsUpdated?.call(_floors);
    }
  }

  /// Recalculates cumulative base altitudes sequentially based on floor gaps:
  /// Floor 1 Base Altitude = venue anchor / ground baseline height from location & phone sensors
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

    final bool isLegacyGroundAlt =
        firstFloor.baseAltitudeM == 10.0 ||
        firstFloor.baseAltitudeM == 8.5 ||
        firstFloor.baseAltitudeM == 15.0;

    if (groundBaselineAlt != null && groundBaselineAlt > 0) {
      currentAlt = groundBaselineAlt;
    } else if (firstFloor.baseAltitudeM > 0 &&
        firstFloor.isLocked &&
        !isLegacyGroundAlt) {
      currentAlt = firstFloor.baseAltitudeM;
    } else {
      currentAlt = _computedRealWorldElevation;
    }

    for (int i = 0; i < sorted.length; i++) {
      final f = sorted[i];
      if (i == 0) {
        result.add(
          f.copyWith(
            baseAltitudeM: double.parse(currentAlt.toStringAsFixed(2)),
          ),
        );
      } else {
        final prev = result[i - 1];
        currentAlt = prev.baseAltitudeM + prev.heightToNextM;
        result.add(
          f.copyWith(
            baseAltitudeM: double.parse(currentAlt.toStringAsFixed(2)),
          ),
        );
      }
    }
    return result;
  }

  double _calculateSuggestedFloorGap(FloorHeightData floor) {
    if (_isBarometerActive || _hasLocationFix) {
      double prevAlt = _targetGroundAltM;
      final prevIndex = _floors.indexWhere(
        (f) => f.floorNo == floor.floorNo - 1,
      );
      if (prevIndex >= 0) {
        prevAlt = _floors[prevIndex].baseAltitudeM;
      }
      final refAlt = _hasLocationFix
          ? _userLocationAltitudeM
          : _liveBarometerAltitudeM;
      final diff = (refAlt - prevAlt).abs();
      if (diff >= 2.0 && diff <= 12.0) {
        return double.parse(diff.toStringAsFixed(2));
      }
    }
    return (floor.heightToNextM > 0 && floor.heightToNextM != 4.5)
        ? floor.heightToNextM
        : _targetFloorGapM;
  }

  Future<void> _initMalls() async {
    try {
      final malls = await ApiService.instance.fetchMalls();
      if (mounted) {
        setState(() {
          _availableMallIds.clear();
          _knownMalls.clear();
          for (final m in malls) {
            final mId = m.id.trim();
            if (mId.isNotEmpty) {
              _knownMalls[mId] = m;
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
      var filtered = list
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
          .toList();

      final mall = _selectedMall;
      final configuredGap = _targetFloorGapM;
      final configuredGroundAlt = _targetGroundAltM;

      // If floors were empty or unpopulated, auto-generate standard floor sequence
      if (filtered.isEmpty && mall != null) {
        final floorCount = mall.floorCount > 0 ? mall.floorCount : 5;
        double currentAlt = configuredGroundAlt;
        for (int fn = 1; fn <= floorCount; fn++) {
          filtered.add(
            FloorHeightData(
              mallId: targetMall,
              floorNo: fn,
              heightToNextM: configuredGap,
              baseAltitudeM: double.parse(currentAlt.toStringAsFixed(2)),
              source: 'barometer_gps',
              confidence: 1.0,
              isLocked: false,
              updatedAt: DateTime.now().toIso8601String(),
            ),
          );
          currentAlt += configuredGap;
        }
      } else {
        // Automatically compute unlocked floors using phone barometer & user location
        filtered = filtered.map((f) {
          final isExplicitlyLocked =
              f.isLocked &&
              f.heightToNextM != 4.5 &&
              f.heightToNextM != 3.8 &&
              f.heightToNextM != 3.80 &&
              f.heightToNextM > 0.0;
          final gap = isExplicitlyLocked ? f.heightToNextM : configuredGap;
          final isGroundLocked =
              f.floorNo == 1 &&
              f.isLocked &&
              f.baseAltitudeM != 15.0 &&
              f.baseAltitudeM != 10.0 &&
              f.baseAltitudeM != 8.5 &&
              f.baseAltitudeM > 0.0;
          final baseAlt = (f.floorNo == 1 && !isGroundLocked)
              ? configuredGroundAlt
              : f.baseAltitudeM;

          return f.copyWith(
            heightToNextM: gap,
            baseAltitudeM: baseAlt,
            source: isExplicitlyLocked ? 'admin' : 'barometer_gps',
          );
        }).toList();
      }

      filtered.sort((a, b) => a.floorNo.compareTo(b.floorNo));
      final recomputed = _recalculateCumulativeAltitudes(
        filtered,
        groundBaselineAlt: configuredGroundAlt,
      );

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
      final targetGap = _targetFloorGapM;
      final targetGround = _targetGroundAltM;

      final updatedList = await widget.apiService.triggerFloorHeightCalculation(
        targetMall,
        lat: _currentUserPosition?.latitude ?? _selectedMall?.latitude,
        lon: _currentUserPosition?.longitude ?? _selectedMall?.longitude,
        barometerPressureHpa: _currentPressureHpa,
        liveAltitudeM: targetGround,
        floorGapM: targetGap,
      );
      final lowerTarget = targetMall.toLowerCase();
      final filtered = updatedList.where((f) {
        final fMall = f.mallId.trim().toLowerCase();
        return fMall.isEmpty || fMall == lowerTarget;
      }).toList();

      final preserved = <FloorHeightData>[];
      for (final f in filtered) {
        final existing = _floors.firstWhere(
          (old) => old.floorNo == f.floorNo,
          orElse: () => f,
        );
        final bool isLegacyLocked =
            existing.heightToNextM == 3.8 ||
            existing.heightToNextM == 3.80 ||
            existing.heightToNextM == 4.5 ||
            existing.heightToNextM <= 0.0;
        if (existing.isLocked && !isLegacyLocked) {
          preserved.add(existing);
        } else {
          final isBackendLegacyLocked =
              f.heightToNextM == 3.8 ||
              f.heightToNextM == 3.80 ||
              f.heightToNextM == 4.5 ||
              f.heightToNextM <= 0.0;
          final gap = (f.isLocked && !isBackendLegacyLocked)
              ? f.heightToNextM
              : targetGap;
          preserved.add(
            f.copyWith(
              heightToNextM: gap,
              source: 'barometer_gps',
              confidence: 1.0,
            ),
          );
        }
      }

      final recomputed = _recalculateCumulativeAltitudes(
        preserved,
        groundBaselineAlt: targetGround,
      );

      // Push cascaded cumulative altitudes to backend to keep DB synced
      for (final floor in recomputed) {
        widget.apiService
            .updateFloorHeight(
              targetMall,
              floor.floorNo,
              heightToNextM: floor.heightToNextM,
              baseAltitudeM: floor.baseAltitudeM,
              isLocked: floor.isLocked,
            )
            .catchError((_) => floor);
      }

      if (mounted) {
        setState(() {
          _floors = recomputed;
          _isCalculating = false;
          _statusMessage =
              'Real-world elevation computed: Ground ${targetGround.toStringAsFixed(2)}m • Story Gap ${targetGap.toStringAsFixed(2)}m (Barometer & Location)';
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
                        baseAltController.text = _userLocationAltitudeM
                            .toStringAsFixed(2);
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
                        baseAltController.text = _liveBarometerAltitudeM
                            .toStringAsFixed(2);
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
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.gauge,
                              size: 13,
                              color: Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Baro Alt (${_liveBarometerAltitudeM.toStringAsFixed(1)}m)',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF2563EB),
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
                      const Icon(
                        LucideIcons.layers,
                        size: 16,
                        color: Color(0xFF475569),
                      ),
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
                  labelStyle: const TextStyle(color: Color(0xFF2563EB)),
                  suffixText: 'meters',
                  suffixStyle: const TextStyle(color: Color(0xFF64748B)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(
                      color: Color(0xFF2563EB),
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
                      textController.text = _targetFloorGapM.toStringAsFixed(2);
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
                            LucideIcons.layers,
                            size: 13,
                            color: Color(0xFF1D4ED8),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Venue Gap (${_targetFloorGapM.toStringAsFixed(2)}m)',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1D4ED8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      textController.text = _currentFloorGapM.toStringAsFixed(
                        2,
                      );
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
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.gauge,
                            size: 13,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Suggested Gap (${_calculateSuggestedFloorGap(floor).toStringAsFixed(2)}m)',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF2563EB),
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
              backgroundColor: const Color(0xFF0F172A),
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
              final idx = updatedList.indexWhere(
                (f) => f.floorNo == floor.floorNo,
              );
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
                for (final f in recomputed.where(
                  (f) => f.floorNo > floor.floorNo,
                )) {
                  widget.apiService
                      .updateFloorHeight(
                        _selectedMallId,
                        f.floorNo,
                        heightToNextM: f.heightToNextM,
                        baseAltitudeM: f.baseAltitudeM,
                        isLocked: f.isLocked,
                      )
                      .catchError((_) => f);
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
              color: Color(0xFF2563EB),
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
                labelStyle: const TextStyle(color: Color(0xFF2563EB)),
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
                labelStyle: const TextStyle(color: Color(0xFF2563EB)),
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
              backgroundColor: const Color(0xFF0F172A),
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
      case 'barometer_gps':
      case 'gps_baro_fusion':
      case 'auto_calc':
        return const Color(0xFF2563EB);
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
      case 'barometer_gps':
      case 'gps_baro_fusion':
      case 'auto_calc':
        return const Color(0xFFEFF6FF);
      case 'osm':
        return const Color(0xFFE0F2FE);
      case 'default':
      default:
        return const Color(0xFFFFEDD5);
    }
  }

  String _formatSourceBadgeLabel(String source) {
    switch (source.toLowerCase()) {
      case 'barometer':
      case 'barometer_gps':
      case 'gps_baro_fusion':
      case 'auto_calc':
        return 'BARO + GPS';
      case 'admin':
        return 'ADMIN';
      case 'osm':
        return 'OSM';
      default:
        return source.toUpperCase();
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
          'Automatic Floor Heights',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: const Color(0xFF0F172A),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, color: Color(0xFF2563EB)),
            tooltip: 'Refresh Table',
            onPressed: _loadFloorHeights,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2563EB)),
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
                                            color: Color(0xFF64748B),
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
                            backgroundColor: const Color(0xFF0F172A),
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
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.checkCircle,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: GoogleFonts.inter(
                                color: const Color(0xFF1E40AF),
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
                                                0xFF2563EB,
                                              ),
                                              side: const BorderSide(
                                                color: Color(0xFF2563EB),
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
                                                0xFF0F172A,
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
                                child: Table(
                                  defaultVerticalAlignment:
                                      TableCellVerticalAlignment.middle,
                                  columnWidths: const {
                                    0: FlexColumnWidth(1.25), // Floor
                                    1: FlexColumnWidth(1.20), // Height
                                    2: FlexColumnWidth(1.40), // Altitude
                                    3: FlexColumnWidth(2.05), // Source
                                    4: FixedColumnWidth(52), // Actions
                                  },
                                  children: [
                                    // Header Row
                                    TableRow(
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFF1F5F9),
                                      ),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 12,
                                          ),
                                          child: Text(
                                            'Floor',
                                            style: GoogleFonts.outfit(
                                              color: const Color(0xFF1E293B),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 12,
                                          ),
                                          child: Text(
                                            'Height',
                                            style: GoogleFonts.outfit(
                                              color: const Color(0xFF1E293B),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 12,
                                          ),
                                          child: Text(
                                            'Altitude',
                                            style: GoogleFonts.outfit(
                                              color: const Color(0xFF1E293B),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 12,
                                          ),
                                          child: Center(
                                            child: Text(
                                              'Source',
                                              style: GoogleFonts.outfit(
                                                color: const Color(0xFF1E293B),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                            vertical: 12,
                                          ),
                                          child: Center(
                                            child: Text(
                                              'Actions',
                                              style: GoogleFonts.outfit(
                                                color: const Color(0xFF1E293B),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Data Rows
                                    ..._floors.map((floor) {
                                      final badgeTextColor =
                                          _getSourceBadgeColor(floor.source);
                                      final badgeBgColor =
                                          _getSourceBadgeBgColor(floor.source);
                                      final isTopFloor =
                                          floor.heightToNextM == 0.0 &&
                                          floor.floorNo == _floors.last.floorNo;

                                      return TableRow(
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Color(0xFFF1F5F9),
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                        children: [
                                          // 1. Floor
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 10,
                                            ),
                                            child: Text(
                                              floor.floorNo < 0
                                                  ? 'B${floor.floorNo.abs()}'
                                                  : 'Floor ${floor.floorNo}',
                                              style: GoogleFonts.inter(
                                                color: const Color(0xFF0F172A),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              softWrap: false,
                                            ),
                                          ),
                                          // 2. Height
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 10,
                                            ),
                                            child: Text(
                                              isTopFloor
                                                  ? 'Top'
                                                  : '${floor.heightToNextM.toStringAsFixed(2)}m',
                                              style: GoogleFonts.inter(
                                                color: const Color(0xFF0F172A),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              softWrap: false,
                                            ),
                                          ),
                                          // 3. Base Altitude
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 10,
                                            ),
                                            child: Text(
                                              '${floor.baseAltitudeM.toStringAsFixed(2)}m',
                                              style: GoogleFonts.inter(
                                                color: const Color(0xFF475569),
                                                fontWeight: FontWeight.w500,
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              softWrap: false,
                                            ),
                                          ),
                                          // 4. Source Badge (Centered, single-line, fully visible)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 10,
                                            ),
                                            child: Center(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 3.5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: badgeBgColor,
                                                  border: Border.all(
                                                    color: badgeTextColor
                                                        .withValues(
                                                          alpha: 0.35,
                                                        ),
                                                    width: 1,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                                child: Text(
                                                  _formatSourceBadgeLabel(
                                                    floor.source,
                                                  ),
                                                  style: GoogleFonts.inter(
                                                    color: badgeTextColor,
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.1,
                                                  ),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                ),
                                              ),
                                            ),
                                          ),
                                          // 5. Actions (Both Edit and Delete, fully visible)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 2,
                                              vertical: 10,
                                            ),
                                            child: Center(
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Tooltip(
                                                    message:
                                                        'Edit / Override Height',
                                                    child: InkWell(
                                                      onTap: () =>
                                                          _showEditDialog(
                                                            floor,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      child: const Padding(
                                                        padding: EdgeInsets.all(
                                                          3.5,
                                                        ),
                                                        child: Icon(
                                                          LucideIcons.edit3,
                                                          size: 15,
                                                          color: Color(
                                                            0xFF2563EB,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Tooltip(
                                                    message: 'Delete Floor',
                                                    child: InkWell(
                                                      onTap: () =>
                                                          _confirmAndDeleteFloor(
                                                            floor,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      child: const Padding(
                                                        padding: EdgeInsets.all(
                                                          3.5,
                                                        ),
                                                        child: Icon(
                                                          LucideIcons.trash2,
                                                          size: 15,
                                                          color: Color(
                                                            0xFFEF4444,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ],
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
