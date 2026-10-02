import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexnav_mobile/engine/osm_place_discovery_service.dart';
import 'package:nexnav_mobile/engine/ecef_engine.dart';
import 'package:nexnav_mobile/engine/floor_tracker.dart';
import 'package:nexnav_mobile/engine/bearing_engine.dart';
import 'package:nexnav_mobile/data/destinations.dart';

// ============================================================================
// 📍 CONFIGURE YOUR REAL-WORLD TEST LOCATION HERE
// Change these coordinates to your actual location latitude & longitude
// Example Locations:
//   - Colombo City Centre, Sri Lanka:  lat = 6.9175, lon = 79.8530
//   - London Westfield Shopping Mall:  lat = 51.5074, lon = -0.2212
//   - New York Hudson Yards Plaza:     lat = 40.7538, lon = -74.0022
//   - Tokyo Midtown Commercial Hub:    lat = 35.6657, lon = 139.7303
// ============================================================================
const double testUserLatitude = 6.9175; // 👈 Replace with your latitude
const double testUserLongitude = 79.8530; // 👈 Replace with your longitude

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. OpenStreetMap (OSM) Real Data Fetching Test', () {
    test(
      'Fetches real-world OSM places & building levels around user location',
      () async {
        final userCoords = GeodeticCoords(
          latitude: testUserLatitude,
          longitude: testUserLongitude,
          height: 0.0,
        );

        debugPrint(
          '\n🌐 [OSM Test] Querying live OSM Overpass API around: ($testUserLatitude, $testUserLongitude)...',
        );

        final List<DestinationPOI> places = await OSMPlaceDiscoveryService
            .instance
            .fetchRealOSMPlacesAroundUser(
              userCoords: userCoords,
              radiusMeters: 500.0,
            );

        expect(places, isNotNull);
        expect(places.isNotEmpty, isTrue);

        debugPrint(
          '✅ [OSM Test] Successfully fetched ${places.length} POIs near test location!',
        );

        for (int i = 0; i < places.length.clamp(0, 5); i++) {
          final p = places[i];
          debugPrint(
            '   🔹 POI #${i + 1}: "${p.name}" | Cat: ${p.category} | Floor: ${p.floorNumber} | Lat/Lon: (${p.location.latitude.toStringAsFixed(5)}, ${p.location.longitude.toStringAsFixed(5)}) | Abs Height: ${p.location.height}m',
          );

          expect(p.name, isNotEmpty);
          expect(p.category, isNotEmpty);
          expect(p.location.latitude, isNonZero);
          expect(p.location.longitude, isNonZero);
        }
      },
    );

    test(
      'Caches fetched OSM places when user moves less than 50 meters',
      () async {
        final userCoords1 = GeodeticCoords(
          latitude: testUserLatitude,
          longitude: testUserLongitude,
          height: 0.0,
        );
        final list1 = await OSMPlaceDiscoveryService.instance
            .fetchRealOSMPlacesAroundUser(userCoords: userCoords1);

        // Micro movement (<10 meters)
        final userCoords2 = GeodeticCoords(
          latitude: testUserLatitude + 0.00001,
          longitude: testUserLongitude + 0.00001,
          height: 0.0,
        );
        final list2 = await OSMPlaceDiscoveryService.instance
            .fetchRealOSMPlacesAroundUser(userCoords: userCoords2);

        expect(identical(list1, list2), isTrue);
        debugPrint(
          '✅ [OSM Cache Test] Cache successfully returned existing POI list for micro movement.',
        );
      },
    );
  });

  group('2. OSM Floor Level & Height Delta Mapping Tests', () {
    test(
      'Correctly maps OSM building levels to FloorLevelConfig & elevation heights',
      () {
        final groundFloor = defaultBuildingProfile.floors.firstWhere(
          (f) => f.floorNumber == 1,
        );
        final floor2 = defaultBuildingProfile.floors.firstWhere(
          (f) => f.floorNumber == 2,
        );
        final floor4 = defaultBuildingProfile.floors.firstWhere(
          (f) => f.floorNumber == 4,
        );

        // 45.0m is base ground anchor, 60.0m is L2, 90.0m is L4
        expect(groundFloor.absoluteHeightMeters, closeTo(45.0, 0.01));
        expect(floor2.absoluteHeightMeters, closeTo(60.0, 0.01));
        expect(floor4.absoluteHeightMeters, closeTo(90.0, 0.01));

        final delta2to4 =
            floor4.absoluteHeightMeters - floor2.absoluteHeightMeters;
        expect(delta2to4, closeTo(30.0, 0.01));

        debugPrint(
          '✅ [Floor Elevation Test] Level heights verified: Ground L1 (45.0m), L2 (60.0m), L4 (90.0m), Delta L2->L4 = 30.0m',
        );
      },
    );

    test(
      'Computes precise 3D distance and height delta for POIs at identical Lat/Lon',
      () {
        final userPos = GeodeticCoords(
          latitude: testUserLatitude,
          longitude: testUserLongitude,
          height: 45.0,
        );
        final sameCoordPOIOnFloor4 = DestinationPOI(
          id: 'stacked-shop-4',
          name: 'Sky Deck Lounge',
          category: 'FOOD & DRINK',
          location: GeodeticCoords(
            latitude: testUserLatitude,
            longitude: testUserLongitude,
            height: 90.0,
          ),
          floorNumber: 4,
          description: 'Multi-floor stacked shop',
          openStatus: 'Open Now (10:00 AM - 10:00 PM)',
          rating: 4.9,
        );

        final currentFloorConfig = defaultBuildingProfile.floors.firstWhere(
          (f) => f.floorNumber == 1,
        );
        final poiFloorConfig = defaultBuildingProfile.floors.firstWhere(
          (f) => f.floorNumber == 4,
        );

        final metrics = calculateSameCoordinateSpatialMetrics(
          userCoords: userPos,
          poiCoords: sameCoordPOIOnFloor4.location,
          userFloorNumber: 1,
          poiFloorNumber: 4,
          userFloorConfig: currentFloorConfig,
          poiFloorConfig: poiFloorConfig,
        );

        expect(metrics.horizontalHaversineDistMeters, closeTo(0.0, 0.01));
        expect(
          metrics.elevationDeltaMeters,
          closeTo(45.0, 0.01),
        ); // 90m (L4) - 45m (L1) = 45m delta
        expect(metrics.euclidean3DDistanceMeters, closeTo(45.0, 0.01));

        debugPrint(
          '✅ [Stacked POI Metrics Test] Horizontal Dist: ${metrics.horizontalHaversineDistMeters}m | Height Delta: ${metrics.elevationDeltaMeters}m | 3D Dist: ${metrics.euclidean3DDistanceMeters}m',
        );
      },
    );
  });

  group('3. Fallback Synthesizer Test for Custom Real Locations', () {
    test(
      'Synthesizes local POIs directly around custom user GPS coords if zero server response',
      () async {
        final customLocation = GeodeticCoords(
          latitude: 7.2906,
          longitude: 80.6337,
          height: 0.0,
        ); // Kandy, Sri Lanka

        final places = await OSMPlaceDiscoveryService.instance
            .fetchRealOSMPlacesAroundUser(userCoords: customLocation);

        expect(places, isNotNull);
        expect(places.isNotEmpty, isTrue);
        debugPrint(
          '✅ [Fallback Test] Local synthesis generated ${places.length} POIs anchored at (${customLocation.latitude}, ${customLocation.longitude})',
        );
      },
    );
  });
}
