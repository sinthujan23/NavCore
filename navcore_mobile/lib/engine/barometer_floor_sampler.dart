import 'dart:async';
import 'dart:math' as math;
import 'real_sensor_service.dart';

/// BarometerFloorSampler: Mobile Barometer Sampling & Altitude Stabilization Engine
/// Manages barometric pressure sampling and filters out samples during floor transition windows.
class BarometerFloorSampler {
  final RealSensorService sensorService;
  final Duration transitionWindow;

  int _currentFloorNo;
  bool _isFloorChanging = false;
  DateTime? _lastFloorChangeTime;
  Timer? _transitionTimer;

  final List<double> _pressureSamples = [];
  final int maxSampleCapacity;

  BarometerFloorSampler({
    required this.sensorService,
    int initialFloorNo = 1,
    this.transitionWindow = const Duration(seconds: 10),
    this.maxSampleCapacity = 20,
  }) : _currentFloorNo = initialFloorNo;

  /// Current floor number tracked by the sampler
  int get currentFloorNo => _currentFloorNo;

  /// Whether the user is currently in a floor transition window
  bool get isFloorChanging {
    if (!_isFloorChanging) return false;
    if (_lastFloorChangeTime != null &&
        DateTime.now().difference(_lastFloorChangeTime!) >= transitionWindow) {
      _isFloorChanging = false;
    }
    return _isFloorChanging;
  }

  /// Collected pressure samples
  List<double> get pressureSamples => List.unmodifiable(_pressureSamples);

  /// Notifies the sampler of a floor change, triggering a transition window
  /// during which sampling is skipped or flagged as unstable.
  void notifyFloorChanged(int newFloorNo) {
    _currentFloorNo = newFloorNo;
    _isFloorChanging = true;
    _lastFloorChangeTime = DateTime.now();

    _transitionTimer?.cancel();
    _transitionTimer = Timer(transitionWindow, () {
      _isFloorChanging = false;
    });
  }

  /// Resets the transition flag manually
  void resetTransitionState() {
    _isFloorChanging = false;
    _transitionTimer?.cancel();
  }

  /// Adds a raw pressure reading in hPa to the sampling buffer.
  /// Returns `false` if the sample was skipped due to an active floor transition window.
  bool addPressureSample(double pressureHpa) {
    if (isFloorChanging) {
      return false; // Skip sampling during transition window
    }

    _pressureSamples.add(pressureHpa);
    if (_pressureSamples.length > maxSampleCapacity) {
      _pressureSamples.removeAt(0);
    }
    return true;
  }

  /// Calculates barometric altitude in meters using standard International Barometric Formula:
  /// h = 44330 * (1 - (P / P0)^(1 / 5.25588))
  double calculateAltitudeFromPressure({
    double? pressureHpa,
    double seaLevelPressureHpa = 1013.25,
  }) {
    final pressure = pressureHpa ?? sensorService.currentPressure;
    if (pressure <= 0 || seaLevelPressureHpa <= 0) return 0.0;
    return 44330.0 * (1.0 - math.pow(pressure / seaLevelPressureHpa, 1 / 5.25588));
  }

  /// Returns the stabilized (averaged) pressure value from collected samples,
  /// or current sensor pressure if no samples exist.
  double getStabilizedPressure() {
    if (_pressureSamples.isEmpty) {
      return sensorService.currentPressure;
    }
    final sum = _pressureSamples.reduce((a, b) => a + b);
    return sum / _pressureSamples.length;
  }

  /// Clears collected pressure samples
  void clearSamples() {
    _pressureSamples.clear();
  }

  /// Clean up resources
  void dispose() {
    _transitionTimer?.cancel();
  }
}
