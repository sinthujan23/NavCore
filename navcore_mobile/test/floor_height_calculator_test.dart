import 'package:flutter_test/flutter_test.dart';
import 'package:nexnav_mobile/data/destinations.dart';
import 'package:nexnav_mobile/data/floor_height_model.dart';
import 'package:nexnav_mobile/engine/ar_pose_engine.dart';
import 'package:nexnav_mobile/engine/barometer_floor_sampler.dart';
import 'package:nexnav_mobile/engine/ecef_engine.dart';
import 'package:nexnav_mobile/engine/real_sensor_service.dart';

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
}
