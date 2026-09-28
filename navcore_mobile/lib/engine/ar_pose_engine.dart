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
    final rollRad = math.atan2(r[6], r[8]);               // R02, R22
    final yawRad = math.atan2(r[1], r[0]);                // R10, R00

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
    final qPitch = vmath.Quaternion.axisAngle(vmath.Vector3(1, 0, 0), pitchRad);
    final qRoll = vmath.Quaternion.axisAngle(vmath.Vector3(0, 0, 1), rollRad);
    final orientation = qYaw * qPitch * qRoll;

    final transformMatrix = vmath.Matrix4.compose(
      vmath.Vector3(0.0, cameraY, 0.0),
      orientation,
      vmath.Vector3(1.0, 1.0, 1.0),
    );

    final forwardRay = orientation.rotate(vmath.Vector3(0.0, 0.0, -1.0))..normalize();

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
  final double thetaDeadzone;     // Buffer around θ=0 to prevent near-level jitter
  final double hysteresisMargin;  // Band gap for up/down transition boundaries

  int _resolvedFloorIndex;

  TiltFloorMapper({
    int initialFloorIndex = 1,
    this.thetaStepPerFloor = 10.0,
    this.thetaDeadzone = 4.0,
    this.hysteresisMargin = 2.5,
  }) : _resolvedFloorIndex = initialFloorIndex;

  int get currentResolvedFloorIndex => _resolvedFloorIndex;

  /// Resolves target floor index using monotonic pitch mapping with hysteresis
  /// floorIndex = clamp(baseFloorIndex + floor((θ - deadzone) / step), 0, maxFloorIndex)
  int updateFloorIndex({
    required double pitchDegrees, // θ in [-90°, +90°]
    required int baseFloorIndex,
    required int maxFloorIndex,
  }) {
    final double theta = pitchDegrees.clamp(-90.0, 90.0);
    int targetFloorStep = 0;

    if (theta > thetaDeadzone) {
      targetFloorStep = ((theta - thetaDeadzone) / thetaStepPerFloor).floor();
    } else if (theta < -thetaDeadzone) {
      targetFloorStep = ((theta + thetaDeadzone) / thetaStepPerFloor).ceil();
    } else {
      targetFloorStep = 0;
    }

    final rawCalculatedFloor = (baseFloorIndex + targetFloorStep).clamp(0, maxFloorIndex);

    // Apply Hysteresis Band: prevent boundary jitter from toggling floors rapidly
    if (rawCalculatedFloor > _resolvedFloorIndex) {
      // Transition UP requires tilt to pass step threshold + hysteresis margin
      final double requiredMinAngle = thetaDeadzone +
          ((rawCalculatedFloor - baseFloorIndex - 1) * thetaStepPerFloor) +
          hysteresisMargin;
      if (theta >= requiredMinAngle) {
        _resolvedFloorIndex = rawCalculatedFloor;
      }
    } else if (rawCalculatedFloor < _resolvedFloorIndex) {
      // Transition DOWN requires tilt to drop below step threshold - hysteresis margin
      final double requiredMaxAngle = -thetaDeadzone +
          ((rawCalculatedFloor - baseFloorIndex + 1) * thetaStepPerFloor) -
          hysteresisMargin;
      if (theta <= requiredMaxAngle) {
        _resolvedFloorIndex = rawCalculatedFloor;
      }
    }

    _resolvedFloorIndex = _resolvedFloorIndex.clamp(0, maxFloorIndex);
    return _resolvedFloorIndex;
  }
}

/// 3. Floor Point Calculation via Ray-Plane Intersection & Screen Projection
class ARFloorPointCalculator {
  final double floorToFloorHeight; // e.g. 4.5m - 15.0m vertical offset per floor

  ARFloorPointCalculator({this.floorToFloorHeight = 5.0});

  /// Computes floor plane vertical offset for floorIndex
  double getFloorPlaneY(int floorIndex) => floorIndex * floorToFloorHeight;

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
  }) {
    const double rEarth = 6378137.0; // WGS84 semi-major axis in meters
    final lat0Rad = userCoords.latitude * (math.pi / 180.0);

    final dLatRad = (shopCoords.latitude - userCoords.latitude) * (math.pi / 180.0);
    final dLonRad = (shopCoords.longitude - userCoords.longitude) * (math.pi / 180.0);

    final east = rEarth * dLonRad * math.cos(lat0Rad);
    final north = rEarth * dLatRad;
    final up = (shopFloorNumber - userFloorNumber) * floorToFloorHeight;

    return vmath.Vector3(east, up, north);
  }

  /// Projects 3D worldPoint to 2D Screen Space using camera projection & viewport transform
  Offset? projectWorldToScreen({
    required vmath.Vector3 worldPoint,
    required vmath.Matrix4 projectionMatrix,
    required vmath.Matrix4 viewMatrix,
    required Size viewportSize,
  }) {
    final worldVec4 = vmath.Vector4(worldPoint.x, worldPoint.y, worldPoint.z, 1.0);
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

  ARShopMarkerManager();

  Map<int, List<DestinationPOI>> get shopsByFloor => Map.unmodifiable(_shopsByFloor);

  /// Group input shop POIs into floorIndex map
  void loadShops(List<DestinationPOI> allPOIs) {
    _shopsByFloor.clear();
    for (final poi in allPOIs) {
      // Map floorNumber (e.g. -1, 1, 2, 3, 4) to non-negative index (e.g. B1=0, F1=1, F2=2, F3=3, F4=4)
      final floorIdx = math.max(0, poi.floorNumber < 0 ? 0 : poi.floorNumber);
      _shopsByFloor.putIfAbsent(floorIdx, () => []).add(poi);
    }
  }

  /// Mounts and returns ONLY markers matching target floorIndex.
  /// Unmounts / removes previous-floor markers from the scene graph/render pass entirely.
  List<DestinationPOI> getMountedMarkersForFloor(int floorIndex) {
    return _shopsByFloor[floorIndex] ?? const [];
  }
}
