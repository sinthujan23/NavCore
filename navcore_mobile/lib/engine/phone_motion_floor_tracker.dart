import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// NexNav PhoneMotionFloorTracker
/// Continuously tracks physical phone movement, vertical acceleration along the gravity axis,
/// and detects stairs climbing/descending cadence to automatically estimate physical floor-to-floor height.
class PhoneMotionFloorTracker {
  static final PhoneMotionFloorTracker _instance =
      PhoneMotionFloorTracker._internal();
  factory PhoneMotionFloorTracker() => _instance;
  PhoneMotionFloorTracker._internal();

  StreamSubscription<UserAccelerometerEvent>? _userAccelSub;
  StreamSubscription<AccelerometerEvent>? _rawAccelSub;

  // Filtered gravity vector components (from low-pass filtered raw accelerometer)
  double _gravX = 0.0;
  double _gravY = 0.0;
  double _gravZ = 9.80665;

  // Dynamic vertical acceleration along gravity vector
  double _verticalAccel = 0.0;
  double _motionEnergy = 0.0;
  bool _isMoving = false;

  // Stair cadence detection
  final List<double> _vertAccelHistory = [];
  final List<DateTime> _stepTimestamps = [];
  DateTime? _lastStepTime;
  int _consecutiveStairSteps = 0;
  bool _inStairClimb = false;

  // Latest dynamically estimated floor gap (in meters)
  double? _lastEstimatedFloorGap;
  DateTime? _lastFloorGapEstimateTime;

  // Listeners / stream controller
  final _floorGapController = StreamController<double>.broadcast();
  Stream<double> get onFloorGapEstimated => _floorGapController.stream;

  double? get lastEstimatedFloorGap => _lastEstimatedFloorGap;
  double get currentMotionEnergy => _motionEnergy;
  bool get isMoving => _isMoving;
  bool get isClimbingStairs => _inStairClimb;

  bool _isRunning = false;

  /// Starts listening to phone motion and accelerometer sensors
  void startTracking({Function(double gap)? onEstimate}) {
    if (_isRunning) return;
    _isRunning = true;

    // 1. Raw accelerometer to maintain accurate gravity reference vector (tilt-compensated)
    try {
      _rawAccelSub = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 40),
      ).listen((AccelerometerEvent event) {
        double rx = event.x;
        double ry = event.y;
        double rz = event.z;

        // Normalize iOS Gs to m/s² if necessary
        final mag = math.sqrt(rx * rx + ry * ry + rz * rz);
        if (mag > 0 && mag < 3.0) {
          rx *= 9.80665;
          ry *= 9.80665;
          rz *= 9.80665;
        }

        // Low-pass filter to isolate gravity
        const double alpha = 0.12;
        _gravX = (alpha * rx) + ((1.0 - alpha) * _gravX);
        _gravY = (alpha * ry) + ((1.0 - alpha) * _gravY);
        _gravZ = (alpha * rz) + ((1.0 - alpha) * _gravZ);
      }, onError: (_) {});
    } catch (_) {}

    // 2. User accelerometer (linear acceleration without gravity) for vertical motion & cadence
    try {
      _userAccelSub = userAccelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 40),
      ).listen((UserAccelerometerEvent event) {
        _processUserMotion(event.x, event.y, event.z, onEstimate);
      }, onError: (_) {});
    } catch (_) {}
  }

  void _processUserMotion(
    double ux,
    double uy,
    double uz,
    Function(double gap)? onEstimate,
  ) {
    final double gNorm = math.sqrt(
      _gravX * _gravX + _gravY * _gravY + _gravZ * _gravZ,
    );
    if (gNorm < 1.0) return;

    // Dot product: project user acceleration onto unit gravity vector
    // Positive = accelerating in direction of gravity (downwards), Negative = accelerating upwards
    final double dot = (ux * _gravX + uy * _gravY + uz * _gravZ) / gNorm;
    _verticalAccel = dot;

    _motionEnergy = math.sqrt(ux * ux + uy * uy + uz * uz);
    _isMoving = _motionEnergy > 0.25;

    final now = DateTime.now();

    // Track vertical acceleration buffer
    _vertAccelHistory.add(_verticalAccel);
    if (_vertAccelHistory.length > 25) {
      _vertAccelHistory.removeAt(0);
    }

    // Step / cadence detection: Look for local peaks with cadence between 400ms and 1100ms
    if (_vertAccelHistory.length >= 5) {
      final mid = _vertAccelHistory[_vertAccelHistory.length - 3];
      final prev = _vertAccelHistory[_vertAccelHistory.length - 4];
      final next = _vertAccelHistory[_vertAccelHistory.length - 2];

      // Vertical step impulse peak (amplitude > 1.1 m/s²)
      if (mid.abs() > 1.1 && mid.abs() > prev.abs() && mid.abs() > next.abs()) {
        if (_lastStepTime == null ||
            now.difference(_lastStepTime!).inMilliseconds >= 380) {
          final stepIntervalMs = _lastStepTime != null
              ? now.difference(_lastStepTime!).inMilliseconds
              : 600;

          // Natural human stair climbing cadence is typically between 400ms and 950ms per step
          if (stepIntervalMs >= 400 && stepIntervalMs <= 950) {
            _consecutiveStairSteps++;
            _stepTimestamps.add(now);
            if (!_inStairClimb && _consecutiveStairSteps >= 6) {
              _inStairClimb = true;
            }
          } else {
            // Irregular interval or flat walking pace: reset flight count if paused
            if (now.difference(_lastStepTime ?? now).inMilliseconds > 1800) {
              _finalizeStairFlight(onEstimate);
            }
          }
          _lastStepTime = now;
        }
      }
    }

    // If phone motion paused for > 2.0s after a climb, finalize floor transition calculation
    if (_inStairClimb && _lastStepTime != null) {
      if (now.difference(_lastStepTime!).inMilliseconds > 2000) {
        _finalizeStairFlight(onEstimate);
      }
    }
  }

  /// Calculates real-world floor gap based on detected stair steps
  /// Standard architectural stair riser in commercial / retail facilities is 17.5cm - 19.0cm (average 18.5cm).
  /// A single building floor flight consists of 18 - 25 steps (e.g. 2 x 10-11 step flights with mid-landing).
  void _finalizeStairFlight(Function(double gap)? onEstimate) {
    if (_consecutiveStairSteps >= 14 && _consecutiveStairSteps <= 32) {
      const double riserHeightM = 0.185;
      final double calculatedGap = _consecutiveStairSteps * riserHeightM;

      if (calculatedGap >= 2.70 && calculatedGap <= 5.80) {
        final rounded = double.parse(calculatedGap.toStringAsFixed(2));
        _lastEstimatedFloorGap = rounded;
        _lastFloorGapEstimateTime = DateTime.now();

        _floorGapController.add(rounded);
        onEstimate?.call(rounded);

        if (kDebugMode) {
          print(
            '[PhoneMotionFloorTracker] Verified floor transition via phone movement: '
            '$_consecutiveStairSteps steps -> Floor Gap: ${rounded}m',
          );
        }
      }
    }

    _consecutiveStairSteps = 0;
    _inStairClimb = false;
    _stepTimestamps.clear();
  }

  /// Manually trigger a phone motion vertical calibration sample
  /// Computes dynamic floor gap from current motion energy & building scale
  double computeMotionCalibratedFloorGap({
    required double baseGap,
    required double currentMotionEnergy,
  }) {
    if (_lastEstimatedFloorGap != null) {
      final elapsed = DateTime.now().difference(
        _lastFloorGapEstimateTime ?? DateTime.now(),
      );
      if (elapsed.inMinutes < 15) {
        return _lastEstimatedFloorGap!;
      }
    }

    // Micro-motion modulation: walking velocity & device dynamics calibrate baseline
    if (currentMotionEnergy > 0.40) {
      final motionMod = ((currentMotionEnergy - 0.40) * 0.15).clamp(
        -0.20,
        0.35,
      );
      return double.parse((baseGap + motionMod).toStringAsFixed(2));
    }
    return baseGap;
  }

  /// Stops tracking sensors
  void stopTracking() {
    _rawAccelSub?.cancel();
    _rawAccelSub = null;
    _userAccelSub?.cancel();
    _userAccelSub = null;
    _isRunning = false;
  }

  void dispose() {
    stopTracking();
    _floorGapController.close();
  }
}
