import 'dart:math';
import 'ecef_engine.dart';

/// NexNav Telemetry & Smoothing - 60Hz Low-pass Kalman Filter Engine in Dart
/// Implements Section 7 (Step C) of NexNav Technical Spec

class KalmanState {
  double latitude;
  double longitude;
  double height;
  double velocityLat;
  double velocityLon;
  double velocityHeight;
  double varianceLat;
  double varianceLon;
  double varianceHeight;
  DateTime lastUpdated;

  KalmanState({
    required this.latitude,
    required this.longitude,
    required this.height,
    this.velocityLat = 0.0,
    this.velocityLon = 0.0,
    this.velocityHeight = 0.0,
    this.varianceLat = 1e-4,
    this.varianceLon = 1e-4,
    this.varianceHeight = 1e-4,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  KalmanState copy() {
    return KalmanState(
      latitude: latitude,
      longitude: longitude,
      height: height,
      velocityLat: velocityLat,
      velocityLon: velocityLon,
      velocityHeight: velocityHeight,
      varianceLat: varianceLat,
      varianceLon: varianceLon,
      varianceHeight: varianceHeight,
      lastUpdated: lastUpdated,
    );
  }
}

class KalmanPositionFilter {
  final KalmanState state;
  final double processNoise; // Q
  final double measurementNoise; // R

  KalmanPositionFilter(
    GeodeticCoords initialCoords, {
    this.processNoise = 1e-6,
    this.measurementNoise = 1e-4,
  }) : state = KalmanState(
         latitude: initialCoords.latitude,
         longitude: initialCoords.longitude,
         height: initialCoords.height,
       );

  /// Time update step (Prediction) fed by 60Hz IMU step vectors
  KalmanState predict(
    double dtmilliseconds, {
    required double dx,
    required double dy,
    required double dz,
  }) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLon = 111320.0 * cos((state.latitude * pi) / 180.0);

    final deltaLatDeg = (dx * dtmilliseconds) / metersPerDegreeLat;
    final deltaLonDeg = (dy * dtmilliseconds) / max(metersPerDegreeLon, 1.0);
    final deltaHeight = dz * dtmilliseconds;

    state.latitude += deltaLatDeg;
    state.longitude += deltaLonDeg;
    state.height += deltaHeight;

    state.varianceLat += processNoise;
    state.varianceLon += processNoise;
    state.varianceHeight += processNoise;
    state.lastUpdated = DateTime.now();

    return state.copy();
  }

  /// Measurement update step (Correction) fed by Visual Odometry features
  KalmanState update(GeodeticCoords measurement) {
    final kLat = state.varianceLat / (state.varianceLat + measurementNoise);
    final kLon = state.varianceLon / (state.varianceLon + measurementNoise);
    final kH = state.varianceHeight / (state.varianceHeight + measurementNoise);

    state.latitude += kLat * (measurement.latitude - state.latitude);
    state.longitude += kLon * (measurement.longitude - state.longitude);
    state.height += kH * (measurement.height - state.height);

    state.varianceLat *= (1.0 - kLat);
    state.varianceLon *= (1.0 - kLon);
    state.varianceHeight *= (1.0 - kH);
    state.lastUpdated = DateTime.now();

    return state.copy();
  }

  void setPosition(GeodeticCoords coords) {
    state.latitude = coords.latitude;
    state.longitude = coords.longitude;
    state.height = coords.height;
    state.varianceLat = 1e-4;
    state.varianceLon = 1e-4;
    state.varianceHeight = 1e-4;
    state.lastUpdated = DateTime.now();
  }
}

/// 1D Low-Pass Kalman Filter for scalar orientation angle & sensor telemetry smoothing
class KalmanFilter {
  final double processNoise; // Q
  final double measurementNoise; // R
  double _stateEstimate = 0.0;
  double _estimateError = 1.0;
  bool _initialized = false;

  KalmanFilter({this.processNoise = 0.02, this.measurementNoise = 0.15});

  double filter(double measurement) {
    if (!_initialized) {
      _stateEstimate = measurement;
      _initialized = true;
      return _stateEstimate;
    }

    // Prediction step
    _estimateError += processNoise;

    // Measurement update step
    final kalmanGain = _estimateError / (_estimateError + measurementNoise);
    _stateEstimate += kalmanGain * (measurement - _stateEstimate);
    _estimateError *= (1.0 - kalmanGain);

    return _stateEstimate;
  }

  /// Special 360-degree shortest angular distance Kalman filter for compass headings
  double filterAngle(double measurement) {
    if (!_initialized) {
      _stateEstimate = measurement;
      _initialized = true;
      return _stateEstimate;
    }

    _estimateError += processNoise;
    final kalmanGain = _estimateError / (_estimateError + measurementNoise);

    double diff = measurement - _stateEstimate;
    while (diff < -180.0) {
      diff += 360.0;
    }
    while (diff > 180.0) {
      diff -= 360.0;
    }

    _stateEstimate += kalmanGain * diff;
    while (_stateEstimate < 0.0) {
      _stateEstimate += 360.0;
    }
    while (_stateEstimate >= 360.0) {
      _stateEstimate -= 360.0;
    }

    _estimateError *= (1.0 - kalmanGain);
    return _stateEstimate;
  }

  void reset() {
    _initialized = false;
    _estimateError = 1.0;
  }
}
