import 'dart:async';
import 'dart:math' as math;
import 'ecef_engine.dart';
import 'bearing_engine.dart';
import '../data/destinations.dart';
import '../data/mall_api_service.dart';

enum PitchTiltDirection { level, down, up }

class SensorDataSample {
  final double pitchDegrees; // Tilt Up (+15° to +90°) / Down (-15° to -90°)
  final double rollDegrees;
  final double yawDegrees; // Compass heading (0° - 360°)
  final double smoothedPitchDegrees;
  final double barometricAltitudeMeters;
  final PitchTiltDirection tiltDirection;
  final DateTime timestamp;

  const SensorDataSample({
    required this.pitchDegrees,
    required this.rollDegrees,
    required this.yawDegrees,
    required this.smoothedPitchDegrees,
    required this.barometricAltitudeMeters,
    required this.tiltDirection,
    required this.timestamp,
  });
}

class ARMarkerRenderData {
  final DestinationPOI poi;
  final int distanceMeters;
  final double bearingDegrees;
  final String directionBadge;
  final double relativeAngleDegrees;
  final double screenPosX;
  final double screenPosY;
  final bool isTargetFloor;

  const ARMarkerRenderData({
    required this.poi,
    required this.distanceMeters,
    required this.bearingDegrees,
    required this.directionBadge,
    required this.relativeAngleDegrees,
    required this.screenPosX,
    required this.screenPosY,
    required this.isTargetFloor,
  });
}

/// NexNav Modular AR Sensor & Floor Detection Engine
class ARSensorEngine {
  final MallBackendApi apiHook;

  // Low-Pass Smoothing Filter Coefficient (0.0 < alpha <= 1.0)
  final double _alpha = 0.25;
  double _smoothedPitch = 0.0;

  // Hysteresis Debounce Thresholds
  final double tiltDownThreshold = -15.0; // Pitch < -15° = Downward tilt
  final double tiltUpThreshold = 15.0; // Pitch > +15° = Upward tilt

  ARSensorEngine({MallBackendApi? api}) : apiHook = api ?? RestMallBackendApi();

  /// Modular Function 1: getSensorData()
  /// Ingests raw accelerometer & magnetometer events, calculates pitch, and applies low-pass filter
  SensorDataSample getSensorData({
    required double accelX,
    required double accelY,
    required double accelZ,
    required double compassHeading,
    double barometricPressureHpa = 1013.25,
  }) {
    // 1. Calculate raw pitch & roll in degrees from accelerometer
    final rollRad = math.atan2(accelY, accelZ);
    final pitchRad = math.atan2(
      -accelX,
      math.sqrt(accelY * accelY + accelZ * accelZ),
    );

    final rawPitchDeg = pitchRad * (180.0 / math.pi);
    final rawRollDeg = rollRad * (180.0 / math.pi);

    // 2. Apply Low-Pass Smoothing Filter: Y[n] = alpha * X[n] + (1 - alpha) * Y[n-1]
    _smoothedPitch = (_alpha * rawPitchDeg) + ((1.0 - _alpha) * _smoothedPitch);

    // 3. Estimate Barometric Altitude: h = 44330 * (1 - (p / p0)^(1/5.255))
    final baroAltitude =
        44330.0 * (1.0 - math.pow(barometricPressureHpa / 1013.25, 0.1903));

    // 4. Determine Pitch Tilt Direction via detectFloor()
    final tiltDir = detectFloorDirection(_smoothedPitch);

    return SensorDataSample(
      pitchDegrees: rawPitchDeg,
      rollDegrees: rawRollDeg,
      yawDegrees: compassHeading,
      smoothedPitchDegrees: _smoothedPitch,
      barometricAltitudeMeters: baroAltitude,
      tiltDirection: tiltDir,
      timestamp: DateTime.now(),
    );
  }

  /// Modular Function 2: detectFloor()
  /// Evaluates smoothed pitch angle against hysteresis thresholds (-15° / +15°) to compute target floor level
  PitchTiltDirection detectFloorDirection(double pitchDegrees) {
    if (pitchDegrees < tiltDownThreshold) {
      return PitchTiltDirection.down;
    } else if (pitchDegrees > tiltUpThreshold) {
      return PitchTiltDirection.up;
    }
    return PitchTiltDirection.level;
  }

  /// Computes active floor number based on current floor level and pitch tilt direction
  int resolveFloorByTilt({
    required int currentFloorNumber,
    required PitchTiltDirection tiltDirection,
    int minFloor = 1,
    int maxFloor = 10,
  }) {
    switch (tiltDirection) {
      case PitchTiltDirection.down:
        return math.max(currentFloorNumber - 1, minFloor);
      case PitchTiltDirection.up:
        return math.min(currentFloorNumber + 1, maxFloor);
      case PitchTiltDirection.level:
        return currentFloorNumber;
    }
  }

  /// Modular Function 3: fetchShopsForFloor()
  /// Queries backend API layer for shop POIs matching current floor & user GPS bounds
  Future<List<DestinationPOI>> fetchShopsForFloor({
    required String buildingId,
    required int floorNumber,
    required GeodeticCoords userCoords,
  }) async {
    final filter = MallApiShopFilter(
      buildingId: buildingId,
      floorNumber: floorNumber,
      userLatitude: userCoords.latitude,
      userLongitude: userCoords.longitude,
    );
    return await apiHook.fetchShopsForFloor(filter);
  }

  /// Modular Function 4: renderARMarkers()
  /// Prepares 3D spatial AR markers for rendering over the camera viewport with collision avoidance
  List<ARMarkerRenderData> renderARMarkers({
    required List<DestinationPOI> pois,
    required GeodeticCoords userCoords,
    required double compassHeadingDegrees,
    required int activeFloorNumber,
    required double screenWidth,
    required double screenHeight,
  }) {
    final activeAnchor = pois.isNotEmpty ? pois.first.location : entranceAnchor;
    final effectiveUser = getEffectiveUserCoords(userCoords, activeAnchor);
    final List<ARMarkerRenderData> markers = [];

    double lastX = -999;
    double lastY = -999;

    for (int i = 0; i < pois.length; i++) {
      final poi = pois[i];
      final distM = calculateAccurate3DDistance(
        effectiveUser,
        poi.location,
        userFloorNumber: activeFloorNumber,
        targetFloorNumber: poi.floorNumber,
      ).round();
      final bearing = calculateBearingAngle(effectiveUser, poi.location);
      final directionStr = _getCardinalBadgeString(bearing);

      // Relative angle math: (bearing - yaw)
      double relAngle = (bearing - compassHeadingDegrees);
      while (relAngle > 180) {
        relAngle -= 360;
      }
      while (relAngle < -180) {
        relAngle += 360;
      }

      final normX = relAngle / 30.0;
      double posX = (screenWidth / 2 - 97.5) + (normX * (screenWidth * 0.42));
      final floorDiff = poi.floorNumber - activeFloorNumber;
      double posY =
          (screenHeight * 0.36) - (floorDiff * 40.0) + ((i % 3) * 25.0);

      // Collision avoidance vertical shift
      if ((posX - lastX).abs() < 170 && (posY - lastY).abs() < 70) {
        posY += 75.0;
      }

      lastX = posX;
      lastY = posY;

      markers.add(
        ARMarkerRenderData(
          poi: poi,
          distanceMeters: distM,
          bearingDegrees: bearing,
          directionBadge: directionStr,
          relativeAngleDegrees: relAngle,
          screenPosX: posX.clamp(16.0, screenWidth - 210.0),
          screenPosY: posY.clamp(130.0, screenHeight - 330.0),
          isTargetFloor: poi.floorNumber == activeFloorNumber,
        ),
      );
    }

    return markers;
  }

  String _getCardinalBadgeString(double deg) {
    if (deg >= 337.5 || deg < 22.5) return 'N';
    if (deg >= 22.5 && deg < 67.5) return 'NE';
    if (deg >= 67.5 && deg < 112.5) return 'E';
    if (deg >= 112.5 && deg < 157.5) return 'SE';
    if (deg >= 157.5 && deg < 202.5) return 'S';
    if (deg >= 202.5 && deg < 247.5) return 'SW';
    if (deg >= 247.5 && deg < 292.5) return 'W';
    return 'NW';
  }
}

/// IndoorAtlas-Style Barometric Elevation Engine
class BarometricElevationEngine {
  double? _entranceBaselinePressureHpa;
  double _entranceAnchorHeightMeters = 45.0;

  bool get isCalibrated => _entranceBaselinePressureHpa != null;
  double? get baselinePressure => _entranceBaselinePressureHpa;

  /// Calibrate reference baseline pressure at building entrance or anchor point
  void calibrateBaseline(double currentPressureHpa, [double baseHeightMeters = 45.0]) {
    if (currentPressureHpa > 0 && !currentPressureHpa.isNaN && !currentPressureHpa.isInfinite) {
      _entranceBaselinePressureHpa = currentPressureHpa;
      _entranceAnchorHeightMeters = baseHeightMeters;
    }
  }

  /// Calculates real-time height in meters using relative hypsometric equation
  double calculateAbsoluteHeight(double currentPressureHpa) {
    if (currentPressureHpa <= 0 || currentPressureHpa.isNaN || currentPressureHpa.isInfinite) {
      return _entranceAnchorHeightMeters;
    }

    if (_entranceBaselinePressureHpa == null || _entranceBaselinePressureHpa == 0) {
      // Standard sea level fallback formula (1013.25 hPa)
      return 44330.0 * (1.0 - math.pow(currentPressureHpa / 1013.25, 0.1903));
    }

    // Relative height delta (m) from calibrated baseline pressure
    double deltaMeters = 44330.0 *
        (1.0 - math.pow(currentPressureHpa / _entranceBaselinePressureHpa!, 0.1903));

    return _entranceAnchorHeightMeters + deltaMeters;
  }
}

