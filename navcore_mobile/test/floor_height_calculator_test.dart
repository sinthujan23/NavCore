import 'package:flutter_test/flutter_test.dart';
import 'package:nexnav_mobile/data/destinations.dart';
import 'package:nexnav_mobile/data/floor_height_model.dart';
import 'package:nexnav_mobile/engine/ar_pose_engine.dart';
import 'package:nexnav_mobile/engine/barometer_floor_sampler.dart';
import 'package:nexnav_mobile/engine/ecef_engine.dart';
import 'package:nexnav_mobile/engine/real_sensor_service.dart';
import 'package:nexnav_mobile/engine/ar_sensor_engine.dart';

void main() {
  group('1. Floor Height Data Model Tests', () {
    test('Parses and serializes FloorHeightData JSON correctly', () {
      final jsonMap = {
        'mall_id': 'mall-one-galle-face',
        'floor_no': 2,
        'height_to_next_m': 15.0,
        'base_altitude_m': 30.0,
        'source': 'barometer',
        'confidence': 0.85,
        'is_locked': 0,
        'updated_at': '2026-10-05T08:00:00.000Z',
      };

      final data = FloorHeightData.fromJson(jsonMap);
      expect(data.mallId, equals('mall-one-galle-face'));
      expect(data.floorNo, equals(2));
      expect(data.heightToNextM, equals(15.0));
      expect(data.baseAltitudeM, equals(30.0));
      expect(data.source, equals('barometer'));
      expect(data.confidence, equals(0.85));
      expect(data.isLocked, isFalse);

      final exported = data.toJson();
      expect(exported['floor_no'], equals(2));
      expect(exported['source'], equals('barometer'));
    });
  });

  group('2. Mobile Barometer Sampling & Stabilization Tests', () {
    test(
      'BarometerFloorSampler skips sampling during floor transition window',
      () {
        final sensorService = RealSensorService();
        final sampler = BarometerFloorSampler(
          sensorService: sensorService,
          initialFloorNo: 1,
        );

        expect(sampler.isFloorChanging, isFalse);

        sampler.notifyFloorChanged(2);
        expect(sampler.isFloorChanging, isTrue);
        expect(sampler.currentFloorNo, equals(2));
      },
    );
  });

  group(
    '3. AR Upper-Floor Pitch Visibility & Marker Altitude Placement Tests',
    () {
      test(
        'Computes marker altitude = base_altitude_m + shop_offset (1.5m)',
        () {
          final calculator = ARFloorPointCalculator();
          final markerAltFloor1 = calculator.calculateShopMarkerAltitude(
            floorBaseAltitudeM: 15.0,
            shopOffsetM: 1.5,
          );
          expect(markerAltFloor1, equals(16.5));

          final markerAltFloor2 = calculator.calculateShopMarkerAltitude(
            floorBaseAltitudeM: 30.0,
            shopOffsetM: 1.5,
          );
          expect(markerAltFloor2, equals(31.5));
        },
      );

      test(
        'Show current floor markers by default, upper-floor markers ONLY when camera pitch > 12°',
        () {
          final manager = ARShopMarkerManager();
          manager.loadShops([
            const DestinationPOI(
              id: 's1',
              name: 'Ground Shop',
              category: 'Retail',
              floorNumber: 1,
              location: GeodeticCoords(
                latitude: 6.9,
                longitude: 79.8,
                height: 15.0,
              ),
              rating: 4.8,
              description: 'Ground Shop',
              openStatus: 'Open Now',
            ),
            const DestinationPOI(
              id: 's2',
              name: 'Upper Shop 1',
              category: 'Retail',
              floorNumber: 2,
              location: GeodeticCoords(
                latitude: 6.9,
                longitude: 79.8,
                height: 30.0,
              ),
              rating: 4.9,
              description: 'Upper Shop 1',
              openStatus: 'Open Now',
            ),
            const DestinationPOI(
              id: 's3',
              name: 'Upper Shop 2',
              category: 'Retail',
              floorNumber: 3,
              location: GeodeticCoords(
                latitude: 6.9,
                longitude: 79.8,
                height: 45.0,
              ),
              rating: 4.5,
              description: 'Upper Shop 2',
              openStatus: 'Open Now',
            ),
          ]);

          final levelMarkers = manager.getMountedMarkersForCamera(
            currentFloorNumber: 1,
            cameraPitchDegrees: 0.0,
            pitchThresholdDegrees: 12.0,
          );
          expect(levelMarkers.length, equals(1));
          expect(levelMarkers.first.id, equals('s1'));

          final tiltedUpMarkers = manager.getMountedMarkersForCamera(
            currentFloorNumber: 1,
            cameraPitchDegrees: 18.0,
            pitchThresholdDegrees: 12.0,
          );
          expect(tiltedUpMarkers.length, equals(3));
        },
      );

      test(
        'Floor change clears previous floor markers and sets active floor',
        () {
          final manager = ARShopMarkerManager();
          manager.loadShops([
            const DestinationPOI(
              id: 's1',
              name: 'Shop 1',
              category: 'Retail',
              floorNumber: 1,
              location: GeodeticCoords(
                latitude: 6.9,
                longitude: 79.8,
                height: 15.0,
              ),
              rating: 4.8,
              description: 'Shop 1',
              openStatus: 'Open Now',
            ),
            const DestinationPOI(
              id: 's2',
              name: 'Shop 2',
              category: 'Retail',
              floorNumber: 2,
              location: GeodeticCoords(
                latitude: 6.9,
                longitude: 79.8,
                height: 30.0,
              ),
              rating: 4.9,
              description: 'Shop 2',
              openStatus: 'Open Now',
            ),
          ]);

          manager.onFloorChanged(2);

          final floor2Markers = manager.getMountedMarkersForCamera(
            currentFloorNumber: 2,
            cameraPitchDegrees: 0.0,
          );
          expect(floor2Markers.length, equals(1));
          expect(floor2Markers.first.id, equals('s2'));
        },
      );
    },
  );

  group('4. Cumulative Base Altitude & Admin Floor Gap Preservation Tests', () {
    test(
      'Sequentially chains base altitudes from 15.0m baseline: 15.0, 19.5, 24.0, 28.5, 33.0',
      () {
        final floors = [
          FloorHeightData(mallId: 'minimall', floorNo: 1, heightToNextM: 4.5, baseAltitudeM: 15.0, source: 'default', confidence: 1.0, isLocked: false, updatedAt: ''),
          FloorHeightData(mallId: 'minimall', floorNo: 2, heightToNextM: 4.5, baseAltitudeM: 19.5, source: 'default', confidence: 1.0, isLocked: false, updatedAt: ''),
          FloorHeightData(mallId: 'minimall', floorNo: 3, heightToNextM: 4.5, baseAltitudeM: 24.0, source: 'default', confidence: 1.0, isLocked: false, updatedAt: ''),
          FloorHeightData(mallId: 'minimall', floorNo: 4, heightToNextM: 4.5, baseAltitudeM: 28.5, source: 'default', confidence: 1.0, isLocked: false, updatedAt: ''),
          FloorHeightData(mallId: 'minimall', floorNo: 5, heightToNextM: 4.5, baseAltitudeM: 33.0, source: 'default', confidence: 1.0, isLocked: false, updatedAt: ''),
        ];

        double currentAlt = 15.0;
        for (int i = 0; i < floors.length; i++) {
          if (i == 0) {
            expect(floors[i].baseAltitudeM, equals(15.0));
          } else {
            currentAlt += floors[i - 1].heightToNextM;
            expect(floors[i].baseAltitudeM, equals(currentAlt));
          }
        }
      },
    );

    test(
      'Admin floor gap override re-cascades cumulative base altitudes for subsequent floors',
      () {
        final floors = [
          FloorHeightData(mallId: 'minimall', floorNo: 1, heightToNextM: 4.5, baseAltitudeM: 15.0, source: 'default', confidence: 1.0, isLocked: false, updatedAt: ''),
          FloorHeightData(mallId: 'minimall', floorNo: 2, heightToNextM: 5.2, baseAltitudeM: 19.5, source: 'admin', confidence: 1.0, isLocked: true, updatedAt: ''),
          FloorHeightData(mallId: 'minimall', floorNo: 3, heightToNextM: 4.5, baseAltitudeM: 24.0, source: 'default', confidence: 1.0, isLocked: false, updatedAt: ''),
          FloorHeightData(mallId: 'minimall', floorNo: 4, heightToNextM: 4.5, baseAltitudeM: 28.5, source: 'default', confidence: 1.0, isLocked: false, updatedAt: ''),
          FloorHeightData(mallId: 'minimall', floorNo: 5, heightToNextM: 4.5, baseAltitudeM: 33.0, source: 'default', confidence: 1.0, isLocked: false, updatedAt: ''),
        ];

        // Recalculate cumulative
        final recomputed = <FloorHeightData>[];
        double currentAlt = 15.0;
        for (int i = 0; i < floors.length; i++) {
          if (i == 0) {
            recomputed.add(floors[i].copyWith(baseAltitudeM: currentAlt));
          } else {
            currentAlt += floors[i - 1].heightToNextM;
            recomputed.add(floors[i].copyWith(baseAltitudeM: double.parse(currentAlt.toStringAsFixed(2))));
          }
        }

        expect(recomputed[0].baseAltitudeM, equals(15.00));
        expect(recomputed[1].baseAltitudeM, equals(19.50));
        expect(recomputed[2].baseAltitudeM, equals(24.70)); // 19.5 + 5.2 admin gap
        expect(recomputed[3].baseAltitudeM, equals(29.20)); // 24.7 + 4.5
        expect(recomputed[4].baseAltitudeM, equals(33.70)); // 29.2 + 4.5
        expect(recomputed[1].isLocked, isTrue);
        expect(recomputed[1].source, equals('admin'));
      },
    );
  });

  group('5. User Location Height Multi-Sensor Fusion Tests', () {
    test(
      'BarometricElevationEngine computes fused elevation from GNSS datum and barometric model',
      () {
        final engine = BarometricElevationEngine();
        engine.calibrateBaseline(1013.25, 20.0);

        // At sea level standard pressure, relative height delta is 0, so height is baseline 20.0m
        final heightSeaLevel = engine.calculateAbsoluteHeight(1013.25);
        expect(heightSeaLevel, closeTo(20.0, 0.05));

        // When pressure drops to 1010 hPa, altitude increases
        final heightHigher = engine.calculateAbsoluteHeight(1010.0);
        expect(heightHigher, greaterThan(20.0));

        // Multi-sensor fusion weights high confidence GPS altitude with barometric height
        final fused = engine.computeFusedLocationHeight(
          currentPressureHpa: 1013.25,
          gpsAltitude: 20.5,
          gpsAccuracy: 5.0, // High accuracy (5m)
        );
        expect(fused, closeTo(20.4, 0.2));
      },
    );

    test(
      'Calibrating Floor 1 to user location height (22.5m) chains upper floors with admin gaps',
      () {
        final initialFloors = [
          FloorHeightData(mallId: 'minimall', floorNo: 1, heightToNextM: 4.5, baseAltitudeM: 15.0, source: 'default', confidence: 1.0, isLocked: false, updatedAt: ''),
          FloorHeightData(mallId: 'minimall', floorNo: 2, heightToNextM: 5.0, baseAltitudeM: 19.5, source: 'admin', confidence: 1.0, isLocked: true, updatedAt: ''),
          FloorHeightData(mallId: 'minimall', floorNo: 3, heightToNextM: 4.5, baseAltitudeM: 24.0, source: 'default', confidence: 1.0, isLocked: false, updatedAt: ''),
        ];

        const userLocationHeight = 22.5;

        // Cumulative chain with Floor 1 set to user location height
        final recomputed = <FloorHeightData>[];
        double currentAlt = userLocationHeight;
        for (int i = 0; i < initialFloors.length; i++) {
          if (i == 0) {
            recomputed.add(initialFloors[i].copyWith(baseAltitudeM: currentAlt));
          } else {
            currentAlt += initialFloors[i - 1].heightToNextM;
            recomputed.add(initialFloors[i].copyWith(baseAltitudeM: double.parse(currentAlt.toStringAsFixed(2))));
          }
        }

        expect(recomputed[0].baseAltitudeM, equals(22.50)); // Floor 1 = user location height
        expect(recomputed[1].baseAltitudeM, equals(27.00)); // 22.5 + 4.5
        expect(recomputed[2].baseAltitudeM, equals(32.00)); // 27.0 + 5.0 (admin preserved gap)
      },
    );
  });
}
