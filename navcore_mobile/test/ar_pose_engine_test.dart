import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;
import 'package:nexnav_mobile/engine/ar_pose_engine.dart';
import 'package:nexnav_mobile/data/destinations.dart';

void main() {
  group('1. Device Pose Extraction Tests', () {
    test('Extracts camera position, quaternion orientation, and normalized pitch θ from 4x4 matrix', () {
      final translation = vmath.Vector3(2.5, 1.65, -5.0);
      final rotation = vmath.Quaternion.axisAngle(vmath.Vector3(1, 0, 0), 15.0 * math.pi / 180.0); // 15° pitch tilt
      final transform = vmath.Matrix4.compose(translation, rotation, vmath.Vector3(1, 1, 1));

      final cameraPose = ARCameraPose.fromMatrix(transform);

      expect(cameraPose.cameraPosition.x, closeTo(2.5, 0.001));
      expect(cameraPose.cameraPosition.y, closeTo(1.65, 0.001));
      expect(cameraPose.cameraPosition.z, closeTo(-5.0, 0.001));
      expect(cameraPose.pitchDegrees, closeTo(15.0, 0.5));
      expect(cameraPose.pitchDegrees, greaterThanOrEqualTo(-90.0));
      expect(cameraPose.pitchDegrees, lessThanOrEqualTo(90.0));
    });

    test('Synthesizes camera pose from sensors correctly', () {
      final sensorPose = ARCameraPose.fromSensors(
        pitchDegrees: -20.0,
        headingDegrees: 90.0,
        rollDegrees: 0.0,
        cameraY: 1.65,
      );

      expect(sensorPose.pitchDegrees, equals(-20.0));
      expect(sensorPose.cameraPosition.y, equals(1.65));
      expect(sensorPose.forwardRay.y, lessThan(0.0)); // Tilting downwards
    });
  });

  group('2. Pitch-to-Floor Index Mapping Tests', () {
    test('Maps pitch tilt to floor index monotonically with step and deadzone', () {
      final mapper = TiltFloorMapper(
        initialFloorIndex: 1,
        thetaStepPerFloor: 10.0,
        thetaDeadzone: 4.0,
        hysteresisMargin: 2.5,
      );

      // Level horizon pitch (0°) -> base floor index 1
      final fLevel = mapper.updateFloorIndex(pitchDegrees: 0.0, baseFloorIndex: 1, maxFloorIndex: 4);
      expect(fLevel, equals(1));

      // Upward tilt past deadzone (8.0°) -> floor index 2
      final fUp = mapper.updateFloorIndex(pitchDegrees: 8.0, baseFloorIndex: 1, maxFloorIndex: 4);
      expect(fUp, equals(2));

      // Upward tilt to floor 3 (18.0°) -> floor index 3
      final fFloor3 = mapper.updateFloorIndex(pitchDegrees: 18.0, baseFloorIndex: 1, maxFloorIndex: 4);
      expect(fFloor3, equals(3));

      // Extreme upward tilt (45°) -> clamped to maxFloorIndex 4
      final fMax = mapper.updateFloorIndex(pitchDegrees: 45.0, baseFloorIndex: 1, maxFloorIndex: 4);
      expect(fMax, equals(4));
    });

    test('Hysteresis band prevents rapid floor toggling near boundaries', () {
      final mapper = TiltFloorMapper(
        initialFloorIndex: 1,
        thetaStepPerFloor: 10.0,
        thetaDeadzone: 4.0,
        hysteresisMargin: 2.5,
      );

      // Initial resolved floor = 1
      mapper.updateFloorIndex(pitchDegrees: 0.0, baseFloorIndex: 1, maxFloorIndex: 4);
      expect(mapper.currentResolvedFloorIndex, equals(1));

      // Small jitter near boundary (5°) -> should stay on floor 1 due to deadzone & hysteresis
      final fJitter = mapper.updateFloorIndex(pitchDegrees: 5.0, baseFloorIndex: 1, maxFloorIndex: 4);
      expect(fJitter, equals(1));
    });
  });

  group('3. Floor Point Calculation via Ray-Plane Intersection Tests', () {
    test('Calculates world point ray-plane intersection correctly', () {
      final calculator = ARFloorPointCalculator(floorToFloorHeight: 15.0);
      final cameraPose = ARCameraPose.fromSensors(
        pitchDegrees: -30.0, // Tilting down towards floor
        headingDegrees: 0.0,
        cameraY: 1.65,
      );

      final intersection = calculator.calculateRayFloorIntersection(
        cameraPose: cameraPose,
        floorIndex: 0, // Floor 0 at Y = 0.0m
      );

      expect(intersection, isNotNull);
      expect(intersection!.y, closeTo(0.0, 0.001));
      expect(intersection.z, lessThan(0.0)); // Pointing forward
    });

    test('Projects 3D world point to 2D viewport screen coordinates', () {
      final calculator = ARFloorPointCalculator(floorToFloorHeight: 15.0);
      final worldPoint = vmath.Vector3(0.0, 0.0, -5.0);
      final projectionMatrix = vmath.makePerspectiveMatrix(60.0 * math.pi / 180.0, 1.0, 0.1, 100.0);
      final viewMatrix = vmath.Matrix4.identity();
      final viewportSize = const Size(1080.0, 1920.0);

      final screenOffset = calculator.projectWorldToScreen(
        worldPoint: worldPoint,
        projectionMatrix: projectionMatrix,
        viewMatrix: viewMatrix,
        viewportSize: viewportSize,
      );

      expect(screenOffset, isNotNull);
      expect(screenOffset!.dx, closeTo(540.0, 5.0)); // Screen center X
      expect(screenOffset.dy, closeTo(960.0, 5.0)); // Screen center Y
    });
  });

  group('4. Shop Marker Filtering Tests (Fixes Overlap Bug)', () {
    test('Groups shops by floor and mounts ONLY shops for target floorIndex', () {
      final manager = ARShopMarkerManager();
      final testPOIs = [
        const DestinationPOI(
          id: 's1',
          name: 'Nike Store',
          category: 'Fashion',
          floorNumber: 1,
          location: entranceAnchor,
          rating: 4.8,
          description: 'Sportswear and apparel',
          openStatus: 'Open Now',
        ),
        const DestinationPOI(
          id: 's2',
          name: 'Apple Store',
          category: 'Tech',
          floorNumber: 2,
          location: entranceAnchor,
          rating: 4.9,
          description: 'Electronics and gadgets',
          openStatus: 'Open Now',
        ),
        const DestinationPOI(
          id: 's3',
          name: 'Food Court',
          category: 'Food',
          floorNumber: 3,
          location: entranceAnchor,
          rating: 4.5,
          description: 'Dining and fast food',
          openStatus: 'Open Now',
        ),
      ];

      manager.loadShops(testPOIs);

      final floor1Shops = manager.getMountedMarkersForFloor(1);
      expect(floor1Shops.length, equals(1));
      expect(floor1Shops.first.id, equals('s1'));

      final floor2Shops = manager.getMountedMarkersForFloor(2);
      expect(floor2Shops.length, equals(1));
      expect(floor2Shops.first.id, equals('s2'));

      // Verifies previous floor markers are completely unmounted (empty list for unpopulated floor 0)
      final floor0Shops = manager.getMountedMarkersForFloor(0);
      expect(floor0Shops, isEmpty);
    });
  });
}
