import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;
import '../data/destinations.dart';
import 'ecef_engine.dart';

/// 1. Device Pose Extraction Data Class & Utility
class ARCameraPose {
  final vmath.Matrix4 transformMatrix;
  final vmath.Vector3 cameraPosition;
  final vmath.Quaternion orientation;
  final double pitchDegrees; // θ normalized to [-90°, +90°], 0° = level horizon
  final double rollDegrees;
  final double yawDegrees;
  final vmath.Vector3 forwardRay;

  ARCameraPose({
    required this.transformMatrix,
    required this.cameraPosition,
    required this.orientation,
    required this.pitchDegrees,
    required this.rollDegrees,
    required this.yawDegrees,
    required this.forwardRay,
  });

  /// Extracts 4x4 AR transform matrix into position (x, y, z), quaternion orientation,
  /// Euler angle pitch θ, and forward ray vector.
  factory ARCameraPose.fromMatrix(vmath.Matrix4 matrix) {
    // 1. Camera position (x, y, z) from matrix translation column (index 12, 13, 14)
    final pos = matrix.getTranslation();

    // 2. Quaternion orientation decomposed from 3x3 rotation submatrix
    final rotationMatrix = vmath.Matrix3.zero();
    matrix.copyRotation(rotationMatrix);
    final orientation = vmath.Quaternion.fromRotation(rotationMatrix);

    // 3. Convert Quaternion to Euler angles to derive pitch (tilt) angle θ
    // Decompose rotation matrix R into pitch (X), yaw (Y), roll (Z)
    final r = rotationMatrix.storage;
    // R is column-major: r[0]=R00, r[1]=R10, r[2]=R20, r[3]=R01, r[4]=R11, r[5]=R21, r[6]=R02, r[7]=R12, r[8]=R22
    // pitch (tilt) theta angle around X axis:
    final pitchRad = math.asin((-r[7]).clamp(-1.0, 1.0)); // -R12
    final rollRad = math.atan2(r[6], r[8]); // R02, R22
    final yawRad = math.atan2(r[1], r[0]); // R10, R00

    final rawPitch = pitchRad * (180.0 / math.pi);
    final rawRoll = rollRad * (180.0 / math.pi);
    final rawYaw = (yawRad * (180.0 / math.pi) + 360.0) % 360.0;

    // Pitch θ normalized to [-90°, +90°] range, where 0° = level horizon
    final pitchNormalized = rawPitch.clamp(-90.0, 90.0);

    // 4. Forward vector along camera view axis (-Z in camera space rotated by orientation)
    final forwardInCameraSpace = vmath.Vector3(0.0, 0.0, -1.0);
    final forwardRay = orientation.rotate(forwardInCameraSpace)..normalize();

    return ARCameraPose(
      transformMatrix: matrix,
      cameraPosition: pos,
      orientation: orientation,
      pitchDegrees: pitchNormalized,
      rollDegrees: rawRoll,
      yawDegrees: rawYaw,
      forwardRay: forwardRay,
    );
  }

  /// Synthesizes camera pose from device sensors (pitch, heading, roll) & camera height
  factory ARCameraPose.fromSensors({
    required double pitchDegrees,
    required double headingDegrees,
    double rollDegrees = 0.0,
    double cameraY = 1.65, // Standard eye-level camera height in meters
  }) {
    final pitchNorm = pitchDegrees.clamp(-90.0, 90.0);
    final pitchRad = pitchNorm * (math.pi / 180.0);
    final yawRad = headingDegrees * (math.pi / 180.0);
    final rollRad = rollDegrees * (math.pi / 180.0);

    // Construct rotation matrix from Euler angles (order: Yaw Y -> Pitch X -> Roll Z)
    final qYaw = vmath.Quaternion.axisAngle(vmath.Vector3(0, 1, 0), yawRad);
    final qPitch = vmath.Quaternion.axisAngle(vmath.Vector3(1, 0, 0), -pitchRad);
    final qRoll = vmath.Quaternion.axisAngle(vmath.Vector3(0, 0, 1), rollRad);
    final orientation = qRoll * qPitch * qYaw;

    final transformMatrix = vmath.Matrix4.compose(
      vmath.Vector3(0.0, cameraY, 0.0),
      orientation,
      vmath.Vector3(1.0, 1.0, 1.0),
    );

    final forwardRay = orientation.rotate(vmath.Vector3(0.0, 0.0, -1.0))
      ..normalize();

    return ARCameraPose(
      transformMatrix: transformMatrix,
      cameraPosition: vmath.Vector3(0.0, cameraY, 0.0),
      orientation: orientation,
      pitchDegrees: pitchNorm,
      rollDegrees: rollDegrees,
      yawDegrees: headingDegrees,
      forwardRay: forwardRay,
    );
  }
}

/// 2. Pitch-to-Floor Index Mapper with Hysteresis & Deadzone
class TiltFloorMapper {
  final double thetaStepPerFloor; // Angular delta per floor (~8°–12°)
  final double thetaDeadzone; // Buffer around θ=0 to prevent near-level jitter
  final double hysteresisMargin; // Band gap for up/down transition boundaries

  int _resolvedFloorIndex;

  TiltFloorMapper({
    int initialFloorIndex = 1,
    this.thetaStepPerFloor = 10.0,
    this.thetaDeadzone = 4.0,
    this.hysteresisMargin = 2.5,
  }) : _resolvedFloorIndex = initialFloorIndex;

  int get currentResolvedFloorIndex => _resolvedFloorIndex;

  void setFloorIndex(int floorNumber) {
    _resolvedFloorIndex = floorNumber;
  }

  double _lastTriggerPitch = 0.0;
  DateTime _lastTransitionTime = DateTime.now();

  /// Resolves target floor dynamically via relative pitch tilt motion
  int updateFloorIndexRelative({
    required double pitchDegrees,
    required List<int> validFloorNumbers,
  }) {
    if (validFloorNumbers.isEmpty) return _resolvedFloorIndex;

    final sortedFloors = List<int>.from(validFloorNumbers)..sort();
    if (!sortedFloors.contains(_resolvedFloorIndex)) {
      _resolvedFloorIndex = sortedFloors.first;
    }

    int currentIdx = sortedFloors.indexOf(_resolvedFloorIndex);
    final now = DateTime.now();

    // Debounce transition steps by 500ms
    if (now.difference(_lastTransitionTime).inMilliseconds < 500) {
      return _resolvedFloorIndex;
    }

    final double theta = pitchDegrees.clamp(-90.0, 90.0);

    // Tilt UP beyond +12° steps UP 1 floor level
    if (theta > 12.0 && currentIdx < sortedFloors.length - 1) {
      if ((theta - _lastTriggerPitch).abs() > 6.0 ||
          _lastTriggerPitch <= 12.0) {
        currentIdx++;
        _resolvedFloorIndex = sortedFloors[currentIdx];
        _lastTriggerPitch = theta;
        _lastTransitionTime = now;
      }
    }
    // Tilt DOWN beyond -12° steps DOWN 1 floor level
    else if (theta < -12.0 && currentIdx > 0) {
      if ((theta - _lastTriggerPitch).abs() > 6.0 ||
          _lastTriggerPitch >= -12.0) {
        currentIdx--;
        _resolvedFloorIndex = sortedFloors[currentIdx];
        _lastTriggerPitch = theta;
        _lastTransitionTime = now;
      }
    }
    // Returning to near level horizon (-6° to +6°) resets baseline pitch trigger
    else if (theta.abs() < 6.0) {
      _lastTriggerPitch = theta;
    }

    return _resolvedFloorIndex;
  }

  /// Resolves target floor dynamically based on camera pitch motion angle relative to user's current floor
  int updateFloorIndexFromPitch({
    required double pitchDegrees,
    required int currentFloorNumber,
    required List<int> validFloorNumbers,
  }) {
    if (validFloorNumbers.isEmpty) return currentFloorNumber;

    final sortedFloors = List<int>.from(validFloorNumbers)..sort();
    int baseIdx = sortedFloors.indexOf(currentFloorNumber);
    if (baseIdx < 0) {
      baseIdx = 0;
    }

    final double theta = pitchDegrees.clamp(-90.0, 90.0);
    int offset = 0;

    if (theta > 8.0) {
      offset = ((theta - 8.0) / 10.0).floor() + 1;
    } else if (theta < -8.0) {
      offset = -(((theta.abs() - 8.0) / 10.0).floor() + 1);
    }

    int targetIdx = (baseIdx + offset).clamp(0, sortedFloors.length - 1);
    _resolvedFloorIndex = sortedFloors[targetIdx];
    return _resolvedFloorIndex;
  }

  /// Resolves target floor from ordered list of valid building floors (e.g. [-1, 1, 2, 3, 4])
  int updateFloorIndexFromList({
    required double pitchDegrees,
    required int baseFloorNumber,
    required List<int> validFloorNumbers,
  }) {
    if (validFloorNumbers.isEmpty) return baseFloorNumber;

    final sortedFloors = List<int>.from(validFloorNumbers)..sort();
    int baseIdx = sortedFloors.indexOf(baseFloorNumber);
    if (baseIdx < 0) {
      baseIdx = 0;
    }

    final double theta = pitchDegrees.clamp(-90.0, 90.0);
    int step = 0;

    if (theta > thetaDeadzone) {
      step = ((theta - thetaDeadzone) / thetaStepPerFloor).floor() + 1;
    } else if (theta < -thetaDeadzone) {
      step = ((theta + thetaDeadzone) / thetaStepPerFloor).ceil() - 1;
    } else {
      step = 0;
    }

    final int targetIdx = (baseIdx + step).clamp(0, sortedFloors.length - 1);
    final int rawCalculatedFloor = sortedFloors[targetIdx];

    // Apply Hysteresis Band
    int currentIdx = sortedFloors.indexOf(_resolvedFloorIndex);
    if (currentIdx < 0) currentIdx = baseIdx;

    if (targetIdx > currentIdx) {
      final double requiredMinAngle =
          thetaDeadzone +
          ((targetIdx - baseIdx - 1) * thetaStepPerFloor) +
          hysteresisMargin;
      if (theta >= requiredMinAngle) {
        _resolvedFloorIndex = rawCalculatedFloor;
      }
    } else if (targetIdx < currentIdx) {
      final double requiredMaxAngle =
          -thetaDeadzone +
          ((targetIdx - baseIdx + 1) * thetaStepPerFloor) -
          hysteresisMargin;
      if (theta <= requiredMaxAngle) {
        _resolvedFloorIndex = rawCalculatedFloor;
      }
    } else {
      _resolvedFloorIndex = rawCalculatedFloor;
    }

    if (!sortedFloors.contains(_resolvedFloorIndex)) {
      _resolvedFloorIndex = baseFloorNumber;
    }

    return _resolvedFloorIndex;
  }

  /// Resolves target floor index using monotonic pitch mapping with hysteresis
  /// floorIndex = clamp(baseFloorIndex + floor((θ - deadzone) / step), 0, maxFloorIndex)
  int updateFloorIndex({
    required double pitchDegrees, // θ in [-90°, +90°]
    required int baseFloorIndex,
    required int maxFloorIndex,
    int minFloorIndex = -1,
  }) {
    final double theta = pitchDegrees.clamp(-90.0, 90.0);
    int targetFloorStep = 0;

    if (theta > thetaDeadzone) {
      targetFloorStep =
          ((theta - thetaDeadzone) / thetaStepPerFloor).floor() + 1;
    } else if (theta < -thetaDeadzone) {
      targetFloorStep =
          ((theta + thetaDeadzone) / thetaStepPerFloor).ceil() - 1;
    } else {
      targetFloorStep = 0;
    }

    final rawCalculatedFloor = (baseFloorIndex + targetFloorStep).clamp(
      minFloorIndex,
      maxFloorIndex,
    );

    // Apply Hysteresis Band: prevent boundary jitter from toggling floors rapidly
    if (rawCalculatedFloor > _resolvedFloorIndex) {
      // Transition UP requires tilt to pass step threshold + hysteresis margin
      final double requiredMinAngle =
          thetaDeadzone +
          ((rawCalculatedFloor - baseFloorIndex - 1) * thetaStepPerFloor) +
          hysteresisMargin;
      if (theta >= requiredMinAngle) {
        _resolvedFloorIndex = rawCalculatedFloor;
      }
    } else if (rawCalculatedFloor < _resolvedFloorIndex) {
      // Transition DOWN requires tilt to drop below step threshold - hysteresis margin
      final double requiredMaxAngle =
          -thetaDeadzone +
          ((rawCalculatedFloor - baseFloorIndex + 1) * thetaStepPerFloor) -
          hysteresisMargin;
      if (theta <= requiredMaxAngle) {
        _resolvedFloorIndex = rawCalculatedFloor;
      }
    } else {
      _resolvedFloorIndex = rawCalculatedFloor;
    }

    _resolvedFloorIndex = _resolvedFloorIndex.clamp(
      minFloorIndex,
      maxFloorIndex,
    );
    return _resolvedFloorIndex;
  }
}

/// 3. Floor Point Calculation via Ray-Plane Intersection & Screen Projection
class ARFloorPointCalculator {
  final double
  floorToFloorHeight; // e.g. 4.5m - 15.0m vertical offset per floor

  ARFloorPointCalculator({this.floorToFloorHeight = 15.0});

  /// Computes floor plane vertical offset for floorIndex
  double getFloorPlaneY(int floorIndex) => floorIndex * floorToFloorHeight;

  /// Calculates total shop marker altitude above sea level / ground
  /// floor.base_altitude_m + 1.5m shop offset
  double calculateShopMarkerAltitude({
    required double floorBaseAltitudeM,
    double shopOffsetM = 1.5,
  }) {
    return floorBaseAltitudeM + shopOffsetM;
  }

  /// Casts a ray from camera position along forward vector and solves ray-plane intersection
  /// for floor plane Y = floorHeight[floorIndex]:
  ///   t = (floorHeight[floorIndex] - cameraY) / rayDirection.y
  ///   worldPoint = cameraPosition + t * rayDirection
  vmath.Vector3? calculateRayFloorIntersection({
    required ARCameraPose cameraPose,
    required int floorIndex,
  }) {
    final double targetFloorY = getFloorPlaneY(floorIndex);
    final double cameraY = cameraPose.cameraPosition.y;
    final double rayY = cameraPose.forwardRay.y;

    // Avoid division by zero when looking directly horizontal
    if (rayY.abs() < 1e-5) {
      return null;
    }

    final double t = (targetFloorY - cameraY) / rayY;

    // Ray must point forward towards the floor plane (t > 0)
    if (t <= 0) {
      return null;
    }

    final worldPoint = cameraPose.cameraPosition + (cameraPose.forwardRay * t);
    return worldPoint;
  }

  /// Converts shop latitude, longitude, and floor level into ENU (East-North-Up) local 3D vector
  /// relative to user geodetic location. As latitude and longitude increase, the East and North
  /// vector components increase proportionally for precise 3D spatial pointing.
  vmath.Vector3 calculateShopENUVector({
    required GeodeticCoords userCoords,
    required GeodeticCoords shopCoords,
    required int userFloorNumber,
    required int shopFloorNumber,
    double? userBaseAltitudeM,
    double? shopBaseAltitudeM,
  }) {
    const double rEarth = 6378137.0; // WGS84 semi-major axis in meters
    final lat0Rad = userCoords.latitude * (math.pi / 180.0);

    final dLatRad =
        (shopCoords.latitude - userCoords.latitude) * (math.pi / 180.0);
    final dLonRad =
        (shopCoords.longitude - userCoords.longitude) * (math.pi / 180.0);

    final east = rEarth * dLonRad * math.cos(lat0Rad);
    final north = rEarth * dLatRad;
    final up = (shopBaseAltitudeM != null && userBaseAltitudeM != null)
        ? (shopBaseAltitudeM - userBaseAltitudeM)
        : (shopFloorNumber - userFloorNumber) * floorToFloorHeight;

    return vmath.Vector3(east, up, north);
  }

  /// Projects 3D worldPoint to 2D Screen Space using camera projection & viewport transform
  Offset? projectWorldToScreen({
    required vmath.Vector3 worldPoint,
    required vmath.Matrix4 projectionMatrix,
    required vmath.Matrix4 viewMatrix,
    required Size viewportSize,
  }) {
    final worldVec4 = vmath.Vector4(
      worldPoint.x,
      worldPoint.y,
      worldPoint.z,
      1.0,
    );
    final viewSpace = viewMatrix * worldVec4;
    final clipSpace = projectionMatrix * viewSpace;

    if (clipSpace.w <= 0.0) {
      return null; // Behind camera plane
    }

    final ndcX = clipSpace.x / clipSpace.w;
    final ndcY = clipSpace.y / clipSpace.w;

    // Map Normalized Device Coordinates (-1..1) to viewport pixels
    final screenX = ((ndcX + 1.0) / 2.0) * viewportSize.width;
    final screenY = ((1.0 - ndcY) / 2.0) * viewportSize.height;

    return Offset(screenX, screenY);
  }
}

/// 4. Shop Marker Culling & Scene Graph Manager (Fixes Overlap Bug)
class ARShopMarkerManager {
  final Map<int, List<DestinationPOI>> _shopsByFloor = {};
  int _activeFloor = 1;

  ARShopMarkerManager();

  Map<int, List<DestinationPOI>> get shopsByFloor =>
      Map.unmodifiable(_shopsByFloor);

  int get activeFloor => _activeFloor;

  void onFloorChanged(int newFloorNumber) {
    _activeFloor = newFloorNumber;
  }

  /// Group input shop POIs into floorIndex map
  void loadShops(List<DestinationPOI> allPOIs) {
    _shopsByFloor.clear();
    for (final poi in allPOIs) {
      _shopsByFloor.putIfAbsent(poi.floorNumber, () => []).add(poi);
    }
  }

  /// Mounts and returns ONLY markers matching target floorIndex.
  List<DestinationPOI> getMountedMarkersForFloor(int floorIndex) {
    return _shopsByFloor[floorIndex] ?? const [];
  }

  /// Pitch-aware mounted marker selection:
  /// - Default: Current floor markers only.
  /// - Camera tilt UP (> pitchThresholdDegrees, e.g. +8.0°): Show current floor AND upper floors.
  /// - Camera tilt DOWN (< -pitchThresholdDegrees, e.g. -8.0°): Show current floor AND lower floors.
  List<DestinationPOI> getMountedMarkersForCamera({
    required int currentFloorNumber,
    required double cameraPitchDegrees,
    double pitchThresholdDegrees = 8.0,
  }) {
    final bool showUpperFloors = cameraPitchDegrees > pitchThresholdDegrees;
    final bool showLowerFloors = cameraPitchDegrees < -pitchThresholdDegrees;
    final List<DestinationPOI> result = [];
    for (final entry in _shopsByFloor.entries) {
      for (final shop in entry.value) {
        if (shop.floorNumber == currentFloorNumber ||
            (showUpperFloors && shop.floorNumber > currentFloorNumber) ||
            (showLowerFloors && shop.floorNumber < currentFloorNumber)) {
          result.add(shop);
        }
      }
    }
    return result;
  }
}
