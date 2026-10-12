import 'dart:convert';
import '../engine/ecef_engine.dart';
import '../engine/floor_tracker.dart';
import 'api_service.dart';
import 'destinations.dart';

class BuildingConfig {
  final String buildingId;
  final String name;
  final String city;
  final GeodeticCoords centerAnchor;
  final List<FloorLevelConfig> floors;
  final List<DestinationPOI> pois;
  final List<ReferenceMarker> markers;

  const BuildingConfig({
    required this.buildingId,
    required this.name,
    required this.city,
    required this.centerAnchor,
    required this.floors,
    required this.pois,
    required this.markers,
  });
}

class ReferenceMarker {
  final String markerId;
  final String name;
  final int floorNumber;
  final GeodeticCoords position;
  final double physicalWidthMeters;
  final double physicalHeightMeters;
  final String qrCodeData;

  const ReferenceMarker({
    required this.markerId,
    required this.name,
    required this.floorNumber,
    required this.position,
    required this.physicalWidthMeters,
    required this.physicalHeightMeters,
    required this.qrCodeData,
  });
}

class BuildingDataService {
  BuildingConfig? _cachedConfig;

  Future<BuildingConfig> loadBuildingConfig({
    String buildingId = '',
  }) async {
    if (_cachedConfig != null && _cachedConfig!.buildingId == buildingId) {
      return _cachedConfig!;
    }

    // Attempt to load from live API service if buildingId provided
    if (buildingId.isNotEmpty) {
      try {
        final pkg = await ApiService.instance.fetchMallPackage(buildingId);
        if (pkg != null) {
          _cachedConfig = BuildingConfig(
            buildingId: pkg.metadata.id,
            name: pkg.metadata.name,
            city: pkg.metadata.city,
            centerAnchor: GeodeticCoords(
              latitude: pkg.metadata.latitude,
              longitude: pkg.metadata.longitude,
              height: 0.0,
            ),
            floors: pkg.profile.floors,
            pois: pkg.destinations,
            markers: const [],
          );
          return _cachedConfig!;
        }
      } catch (_) {}
    }

    _cachedConfig = BuildingConfig(
      buildingId: buildingId,
      name: buildingId.isEmpty ? 'Venue' : buildingId,
      city: '',
      centerAnchor: const GeodeticCoords(
        latitude: 0.0,
        longitude: 0.0,
        height: 0.0,
      ),
      floors: const [],
      pois: const [],
      markers: const [],
    );

    return _cachedConfig!;
  }

  /// Exports building configuration to standalone JSON format for offline storage
  String exportConfigToJson(BuildingConfig config) {
    return jsonEncode({
      'buildingId': config.buildingId,
      'name': config.name,
      'city': config.city,
      'poiCount': config.pois.length,
      'markerCount': config.markers.length,
    });
  }
}
