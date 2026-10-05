import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ecef_engine.dart';
import 'ar_sensor_engine.dart';

enum SensorPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  unknown,
}

class SensorStatusReport {
  final bool isGpsEnabled;
  final bool hasLocationPermission;
  final bool hasCameraPermission;
  final double currentAccuracyMeters;
  final double currentHeadingDegrees;
  final DateTime? lastGpsFixTime;

  const SensorStatusReport({
    required this.isGpsEnabled,
    required this.hasLocationPermission,
    required this.hasCameraPermission,
    required this.currentAccuracyMeters,
    required this.currentHeadingDegrees,
    this.lastGpsFixTime,
  });
}

class RealSensorService {
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<BarometerEvent>? _barometerSubscription;

  GeodeticCoords? _lastCoords;
  double _lastAccuracyMeters = 0.0;
  double _currentHeadingDegrees = 0.0;
  DateTime? _lastFixTime;
  DateTime? _lastGyroTime;

  double _accelX = 0, _accelY = 0, _accelZ = 9.8;
  double _rawPressureHpa = 1013.25;
  double _smoothedPressureHpa = 1013.25;
  final double _baroAlpha = 0.15; // Low-pass filter smoothing coefficient for atmospheric pressure

  bool _isGpsPermissionGranted = false;
  bool _isCameraPermissionGranted = false;

  GeodeticCoords? get lastCoords => _lastCoords;
  double get lastAccuracy => _lastAccuracyMeters;
  double get currentHeading => _currentHeadingDegrees;
  double get currentPressure => _smoothedPressureHpa;
  bool get isGpsGranted => _isGpsPermissionGranted;
  bool get isCameraGranted => _isCameraPermissionGranted;

  Future<SensorStatusReport> requestAllPermissions() async {
    try {
      final locStatus = await Permission.location.request();
      _isGpsPermissionGranted = locStatus.isGranted;

      final camStatus = await Permission.camera.request();
      _isCameraPermissionGranted = camStatus.isGranted;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      return SensorStatusReport(
        isGpsEnabled: serviceEnabled,
        hasLocationPermission: _isGpsPermissionGranted,
        hasCameraPermission: _isCameraPermissionGranted,
        currentAccuracyMeters: _lastAccuracyMeters,
        currentHeadingDegrees: _currentHeadingDegrees,
        lastGpsFixTime: _lastFixTime,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting hardware permissions: $e');
      }
      return SensorStatusReport(
        isGpsEnabled: false,
        hasLocationPermission: false,
        hasCameraPermission: false,
        currentAccuracyMeters: 0,
        currentHeadingDegrees: 0,
      );
    }
  }

  Future<GeodeticCoords?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _lastCoords = GeodeticCoords(
        latitude: position.latitude,
        longitude: position.longitude,
        height: position.altitude,
      );
      _lastAccuracyMeters = position.accuracy;
      _lastFixTime = DateTime.now();

      return _lastCoords;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching initial GPS location: $e');
      }
      return null;
    }
  }

  double _smoothedPitch = 0.0;
  final double _alpha = 0.25;

  DateTime _lastPitchNotifyTime = DateTime.now();
  DateTime _lastHeadingNotifyTime = DateTime.now();
  double _lastNotifiedHeading = -999.0;
  double _lastNotifiedPitch = -999.0;

  void startHardwareStreams({
    required Function(GeodeticCoords coords, double accuracyMeters) onLocationUpdated,
    required Function(double headingDegrees) onHeadingUpdated,
    Function(double pitchDegrees, PitchTiltDirection tiltDirection)? onPitchUpdated,
    Function(double rawPressureHpa, double smoothedPressureHpa)? onPressureUpdated,
  }) {
    stopHardwareStreams();

    // 1. GPS Position Stream
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1, // update every 1 meter move
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position pos) {
      if (pos.latitude.isNaN ||
          pos.longitude.isNaN ||
          (pos.latitude == 0.0 && pos.longitude == 0.0)) {
        return;
      }
      _lastCoords = GeodeticCoords(
        latitude: pos.latitude,
        longitude: pos.longitude,
        height: pos.altitude.isNaN || pos.altitude.isInfinite ? 45.0 : pos.altitude,
      );
      _lastAccuracyMeters = pos.accuracy.isNaN || pos.accuracy.isInfinite ? 0.0 : pos.accuracy;
      _lastFixTime = DateTime.now();

      onLocationUpdated(_lastCoords!, _lastAccuracyMeters);
    }, onError: (err) {
      if (kDebugMode) {
        print('GPS Stream error: $err');
      }
    });

    // 2. Accelerometer Stream for tilt compensation & phone pitch angle (Rate Limited ~30FPS max)
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 33),
    ).listen((AccelerometerEvent event) {
      double rawX = event.x;
      double rawY = event.y;
      double rawZ = event.z;

      // Handle iOS CoreMotion vs Android scale mismatch (g-force vs m/s²)
      final double magnitude = math.sqrt(rawX * rawX + rawY * rawY + rawZ * rawZ);
      if (magnitude > 0 && magnitude < 3.0) {
        // Values delivered in G's (iOS scale) -> Convert to m/s²
        rawX *= 9.80665;
        rawY *= 9.80665;
        rawZ *= 9.80665;
      }

      _accelX = rawX.isNaN || rawX.isInfinite ? 0.0 : rawX;
      _accelY = rawY.isNaN || rawY.isInfinite ? 0.0 : rawY;
      _accelZ = rawZ.isNaN || rawZ.isInfinite ? 9.81 : rawZ;

      final pitchRad = math.atan2(_accelZ, _accelY.abs());
      final rawPitchDeg = pitchRad * (180.0 / math.pi);
      final safePitchDeg = rawPitchDeg.isNaN || rawPitchDeg.isInfinite ? 0.0 : rawPitchDeg;

      // Low-Pass Smoothing Filter
      _smoothedPitch = (_alpha * safePitchDeg) + ((1.0 - _alpha) * _smoothedPitch);

      PitchTiltDirection dir = PitchTiltDirection.level;
      if (_smoothedPitch < -15.0) {
        dir = PitchTiltDirection.down;
      } else if (_smoothedPitch > 15.0) {
        dir = PitchTiltDirection.up;
      }

      final now = DateTime.now();
      final pitchDelta = (_smoothedPitch - _lastNotifiedPitch).abs();
      if (now.difference(_lastPitchNotifyTime).inMilliseconds >= 33 || pitchDelta >= 0.4) {
        _lastPitchNotifyTime = now;
        _lastNotifiedPitch = _smoothedPitch;
        if (onPitchUpdated != null) {
          onPitchUpdated(_smoothedPitch, dir);
        }
      }
    });

    // 3. Magnetometer Stream for real-world heading / compass (Rate Limited ~30FPS max)
    _magnetometerSubscription = magnetometerEventStream(
      samplingPeriod: const Duration(milliseconds: 33),
    ).listen((MagnetometerEvent event) {
      double magX = event.x.isNaN || event.x.isInfinite ? 0.0 : event.x;
      double magY = event.y.isNaN || event.y.isInfinite ? 0.0 : event.y;
      double magZ = event.z.isNaN || event.z.isInfinite ? 0.0 : event.z;

      // Pitch & Roll estimate from accelerometer
      double roll = math.atan2(-_accelX, math.sqrt(_accelY * _accelY + _accelZ * _accelZ));
      double pitch = math.atan2(_accelZ, _accelY.abs());

      // Tilt compensated magnetic calculation
      double magCompX = magX * math.cos(pitch) + magZ * math.sin(pitch);
      double magCompY = magX * math.sin(roll) * math.sin(pitch) +
          magY * math.cos(roll) -
          magZ * math.sin(roll) * math.cos(pitch);

      double headingDeg;
      if (magCompX.abs() < 1e-5 && magCompY.abs() < 1e-5) {
        // Fallback when magnetometer is uncalibrated or zero (common on iOS simulator / uncalibrated sensors)
        headingDeg = _currentHeadingDegrees;
      } else {
        double headingRad = math.atan2(-magCompY, magCompX);
        headingDeg = (headingRad * (180 / math.pi) + 360) % 360;
      }

      if (headingDeg.isNaN || headingDeg.isInfinite) {
        headingDeg = 0.0;
      }

      final now = DateTime.now();
      final headingDelta = (headingDeg - _lastNotifiedHeading).abs();
      if (now.difference(_lastHeadingNotifyTime).inMilliseconds >= 33 || headingDelta >= 0.3) {
        _lastHeadingNotifyTime = now;
        _lastNotifiedHeading = headingDeg;
        _currentHeadingDegrees = headingDeg;
        onHeadingUpdated(headingDeg);
      }
    });

    // 4. Gyroscope Stream for high-frequency rotational motion feedback (~60FPS)
    _gyroscopeSubscription = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 16),
    ).listen((GyroscopeEvent event) {
      double gyroX = event.x.isNaN || event.x.isInfinite ? 0.0 : event.x;
      double gyroY = event.y.isNaN || event.y.isInfinite ? 0.0 : event.y;
      double gyroZ = event.z.isNaN || event.z.isInfinite ? 0.0 : event.z;

      final now = DateTime.now();
      if (_lastGyroTime != null) {
        final dt = now.difference(_lastGyroTime!).inMicroseconds / 1000000.0;
        if (dt > 0.001 && dt < 0.1) {
          // Integrate gyro pitch rate (X axis) & yaw rate (Y/Z axes)
          final pitchRad = math.atan2(_accelZ, _accelY.abs());
          final sinP = math.sin(pitchRad).abs();
          final cosP = math.cos(pitchRad).abs();
          final yawRate = (gyroY * cosP) + (gyroZ * sinP);
          final gyroHeadingDelta = (yawRate * dt) * (180.0 / math.pi);

          // Complementary pitch integration using gyroX
          final gyroPitchDelta = (gyroX * dt) * (180.0 / math.pi);
          _smoothedPitch = (0.95 * (_smoothedPitch + gyroPitchDelta)) + (0.05 * _smoothedPitch);

          double newHeading = (_currentHeadingDegrees - gyroHeadingDelta + 360.0) % 360.0;
          if ((newHeading - _lastNotifiedHeading).abs() >= 0.1) {
            _lastNotifiedHeading = newHeading;
            _currentHeadingDegrees = newHeading;
            onHeadingUpdated(newHeading);
          }
        }
      }
      _lastGyroTime = now;
    }, onError: (err) {
      if (kDebugMode) {
        print('Gyroscope sensor stream unavailable: $err');
      }
    });

    // 5. Barometer Stream for Barometric Altitude & Indoor Floor Resolution
    _barometerSubscription = barometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen((BarometerEvent event) {
      double rawPressure = event.pressure;
      if (rawPressure.isNaN || rawPressure.isInfinite || rawPressure <= 0) return;

      _rawPressureHpa = rawPressure;
      _smoothedPressureHpa = (_baroAlpha * rawPressure) + ((1.0 - _baroAlpha) * _smoothedPressureHpa);

      if (onPressureUpdated != null) {
        onPressureUpdated(_rawPressureHpa, _smoothedPressureHpa);
      }
    }, onError: (err) {
      if (kDebugMode) {
        print('Barometer hardware error or sensor unavailable: $err');
      }
    });
  }

  void stopHardwareStreams() {
    _positionSubscription?.cancel();
    _positionSubscription = null;

    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;

    _magnetometerSubscription?.cancel();
    _magnetometerSubscription = null;

    _gyroscopeSubscription?.cancel();
    _gyroscopeSubscription = null;

    _barometerSubscription?.cancel();
    _barometerSubscription = null;
  }
}
