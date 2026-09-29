import 'dart:math' as math;
import 'ecef_engine.dart';
import 'kalman_filter.dart';
import 'pnp_engine.dart';
import 'ar_navigation_state.dart';

class FusedSpatialPose {
  final GeodeticCoords position;
  final double headingDegrees;
  final double pitchDegrees;
  final double rollDegrees;
  final double movementVectorX;
  final double movementVectorY;
  final TrackingConfidence confidenceLevel;
  final double confidenceScore; // 0.0 - 1.0
  final DateTime timestamp;

  const FusedSpatialPose({
    required this.position,
    required this.headingDegrees,
    required this.pitchDegrees,
    required this.rollDegrees,
    required this.movementVectorX,
    required this.movementVectorY,
    required this.confidenceLevel,
    required this.confidenceScore,
    required this.timestamp,
  });
}

/// NexNav SensorFusionService: Integrates IMU + Camera + Compass + PnP Reference Markers
class SensorFusionService {
  final KalmanFilter _headingFilter = KalmanFilter(
    processNoise: 0.005,
    measurementNoise: 0.04,
  );
  final KalmanFilter _pitchFilter = KalmanFilter(
    processNoise: 0.01,
    measurementNoise: 0.06,
  );
  final KalmanFilter _rollFilter = KalmanFilter(
    processNoise: 0.01,
    measurementNoise: 0.06,
  );

  GeodeticCoords? _lastPnPPosition;
  DateTime? _lastPnPTime;

  double _smoothHeading = 0.0;
  double _smoothPitch = 0.0;
  double _smoothRoll = 0.0;

  /// Process raw sensor input stream and compute fused pose
  FusedSpatialPose updateFusion({
    required double rawHeading,
    required double rawPitch,
    required double rawRoll,
    required double accelX,
    required double accelY,
    required double accelZ,
    required double gyroX,
    required double gyroY,
    required double gyroZ,
    GeodeticCoords? gpsCoords,
    PnPResult? latestPnPResult,
  }) {
    // Sanitize raw inputs against NaN and Infinite values
    final safeRawHeading = (rawHeading.isNaN || rawHeading.isInfinite) ? 0.0 : rawHeading;
    final safeRawPitch = (rawPitch.isNaN || rawPitch.isInfinite) ? 0.0 : rawPitch;
    final safeRawRoll = (rawRoll.isNaN || rawRoll.isInfinite) ? 0.0 : rawRoll;

    // 1. Filter orientation angles using shortest-path angular Kalman filter
    _smoothHeading = _headingFilter.filterAngle(safeRawHeading);
    _smoothPitch = _pitchFilter.filter(safeRawPitch);
    _smoothRoll = _rollFilter.filter(safeRawRoll);

    if (_smoothHeading.isNaN || _smoothHeading.isInfinite) {
      _smoothHeading = safeRawHeading;
    }
    if (_smoothPitch.isNaN || _smoothPitch.isInfinite) {
      _smoothPitch = safeRawPitch;
    }
    if (_smoothRoll.isNaN || _smoothRoll.isInfinite) {
      _smoothRoll = safeRawRoll;
    }

    // Normalize heading to [0, 360)
    while (_smoothHeading < 0) {
      _smoothHeading += 360.0;
    }
    while (_smoothHeading >= 360.0) {
      _smoothHeading -= 360.0;
    }

    // 2. Compute movement vector from accelerometer & gyroscope
    final movementX = accelX * 0.1 + gyroY * 0.05;
    final movementY = accelY * 0.1 + gyroX * 0.05;

    // 3. Update PnP Reference lock state
    if (latestPnPResult != null) {
      _lastPnPPosition = latestPnPResult.calibratedUserCoords;
      _lastPnPTime = latestPnPResult.calibratedAt;
    }

    // 4. Resolve fused geodetic position (PnP > GPS > Fallback)
    GeodeticCoords effectivePosition =
        gpsCoords ??
        const GeodeticCoords(
          latitude: 6.927079,
          longitude: 79.845612,
          height: 45.0,
        );
    if (_lastPnPPosition != null && _lastPnPTime != null) {
      final secondsSincePnP = DateTime.now()
          .difference(_lastPnPTime!)
          .inSeconds;
      if (secondsSincePnP < 180) {
        effectivePosition = _lastPnPPosition!;
      }
    }

    // 5. Evaluate tracking confidence score & degradation level
    double confidenceScore = 0.95;
    TrackingConfidence confidenceLevel = TrackingConfidence.high;

    double magAccel = math.sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ);
    if (magAccel > 0 && magAccel < 3.0) {
      magAccel *= 9.80665;
    }
    final motionJitter = (magAccel - 9.81).abs();
    if (motionJitter > 6.0) {
      confidenceScore -= 0.15;
    }

    if (_lastPnPPosition == null) {
      confidenceScore -= 0.15;
    }

    if (confidenceScore >= 0.75) {
      confidenceLevel = TrackingConfidence.high;
    } else if (confidenceScore >= 0.50) {
      confidenceLevel = TrackingConfidence.medium;
    } else if (confidenceScore >= 0.25) {
      confidenceLevel = TrackingConfidence.low;
    } else {
      confidenceLevel = TrackingConfidence.lost;
    }

    return FusedSpatialPose(
      position: effectivePosition,
      headingDegrees: _smoothHeading,
      pitchDegrees: _smoothPitch,
      rollDegrees: _smoothRoll,
      movementVectorX: movementX,
      movementVectorY: movementY,
      confidenceLevel: confidenceLevel,
      confidenceScore: confidenceScore,
      timestamp: DateTime.now(),
    );
  }
}
