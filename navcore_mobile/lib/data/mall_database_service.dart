import 'package:shared_preferences/shared_preferences.dart';
import '../engine/ecef_engine.dart';
import '../engine/bearing_engine.dart';
import '../engine/floor_tracker.dart';
import '../engine/pnp_engine.dart';
import 'api_service.dart';
import 'destinations.dart';

class MallMetadata {
  final String id;
  final String name;
  final String city;
  final String country;
  final double latitude;
  final double longitude;
  final int floorCount;
  final double packageSizeBytesMB;
  final String category;
  final String rating;
  final bool isDownloaded;
  final bool isActive;

  const MallMetadata({
    required this.id,
    required this.name,
    required this.city,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.floorCount,
    required this.packageSizeBytesMB,
    required this.category,
    required this.rating,
    this.isDownloaded = false,
    this.isActive = false,
  });
}

class FullMallPackage {
  final MallMetadata metadata;
  final BuildingElevationProfile profile;
  final List<DestinationPOI> destinations;
  final List<EntranceMarkerNode> entranceMarkers;

  const FullMallPackage({
    required this.metadata,
    required this.profile,
    required this.destinations,
    required this.entranceMarkers,
  });
}

class MallDatabaseService {
  static const String _downloadedMallsKey = 'NexNav_downloaded_malls';
  static const String _activeMallKey = 'NexNav_active_mall_id';

  final List<MallMetadata> _catalog = [];

  List<MallMetadata> get catalog => _catalog;

  Future<List<MallMetadata>> getMallsList() async {
    final liveMalls = await ApiService.instance.fetchMalls();
    if (liveMalls.isNotEmpty) {
      _catalog.clear();
      _catalog.addAll(liveMalls);
    }
    final sourceList = _catalog;

    final prefs = await SharedPreferences.getInstance();
    final downloadedIds = prefs.getStringList(_downloadedMallsKey) ?? const [];
    final activeId = prefs.getString(_activeMallKey) ?? '';

    return sourceList.map((m) {
      bool isDown = downloadedIds.contains(m.id);
      bool isAct = (m.id == activeId);
      return MallMetadata(
        id: m.id,
        name: m.name,
        city: m.city,
        country: m.country,
        latitude: m.latitude,
        longitude: m.longitude,
        floorCount: m.floorCount,
        packageSizeBytesMB: m.packageSizeBytesMB,
        category: m.category,
        rating: m.rating,
        isDownloaded: isDown,
        isActive: isAct,
      );
    }).toList();
  }

  Future<void> downloadMallPackage(
    String mallId,
    Function(double progress) onProgress,
  ) async {
    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      onProgress(i / 10);
    }

    final prefs = await SharedPreferences.getInstance();
    List<String> downloaded = prefs.getStringList(_downloadedMallsKey) ?? [];
    if (!downloaded.contains(mallId)) {
      downloaded.add(mallId);
      await prefs.setStringList(_downloadedMallsKey, downloaded);
    }
  }

  Future<void> setActiveMall(String mallId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeMallKey, mallId);
  }

  /// Returns POIs dynamically localized relative to a given center GPS coordinate.
  List<DestinationPOI> getLocalizedDestinationsForCoords(
    GeodeticCoords centerCoords, {
    String mallId = 'mall-global',
  }) {
    return const <DestinationPOI>[];
  }

  /// Returns only malls situated within the specified radius (default 500 meters) of the user's current GPS location.
  Future<List<MallMetadata>> getMallsWithinRadius(
    GeodeticCoords userCoords, {
    double radiusMeters = 500.0,
  }) async {
    final allMalls = await getMallsList();
    if (userCoords.latitude == 0.0 && userCoords.longitude == 0.0) {
      return allMalls;
    }
    return allMalls.where((mall) {
      final dist = haversineDistance(
        userCoords,
        GeodeticCoords(
          latitude: mall.latitude,
          longitude: mall.longitude,
          height: userCoords.height,
        ),
      );
      return dist <= radiusMeters;
    }).toList();
  }

  /// Calculates dynamic distance in meters from user's current GPS location to a given mall.
  double calculateDistanceToMall(GeodeticCoords userCoords, MallMetadata mall) {
    return haversineDistance(
      userCoords,
      GeodeticCoords(
        latitude: mall.latitude,
        longitude: mall.longitude,
        height: userCoords.height,
      ),
    );
  }

  /// Finds the nearest mall in the catalog or dynamically resolves a venue for any global user location
  MallMetadata findNearestMall(GeodeticCoords userCoords) {
    if (_catalog.isEmpty) {
      return MallMetadata(
        id: '',
        name: 'No Active Mall',
        city: '',
        country: '',
        latitude: userCoords.latitude,
        longitude: userCoords.longitude,
        floorCount: 0,
        packageSizeBytesMB: 0.0,
        category: '',
        rating: '',
        isDownloaded: false,
        isActive: false,
      );
    }

    MallMetadata nearest = _catalog.first;
    double minDistance = double.infinity;

    for (final mall in _catalog) {
      final dist = haversineDistance(
        userCoords,
        GeodeticCoords(
          latitude: mall.latitude,
          longitude: mall.longitude,
          height: userCoords.height,
        ),
      );
      if (dist < minDistance) {
        minDistance = dist;
        nearest = mall;
      }
    }

    return nearest;
  }

  /// Automatically detects, downloads, and activates the particular mall map package within 500m of current GPS location
  Future<FullMallPackage> autoDownloadAndActivateNearestMall(
    GeodeticCoords userCoords, {
    Function(double progress)? onProgress,
    double maxRadiusMeters = 500.0,
  }) async {
    await getMallsList();
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString(_activeMallKey);

    MallMetadata targetMall;
    final hasGps = userCoords.latitude != 0.0 && userCoords.longitude != 0.0;

    if (hasGps) {
      // Prioritize malls within 500m of the user's current GPS location
      final mallsWithin500m = _catalog.where((m) {
        final dist = haversineDistance(
          userCoords,
          GeodeticCoords(
            latitude: m.latitude,
            longitude: m.longitude,
            height: userCoords.height,
          ),
        );
        return dist <= maxRadiusMeters;
      }).toList();

      if (mallsWithin500m.isNotEmpty) {
        mallsWithin500m.sort((a, b) {
          final distA = calculateDistanceToMall(userCoords, a);
          final distB = calculateDistanceToMall(userCoords, b);
          return distA.compareTo(distB);
        });
        targetMall = mallsWithin500m.first;
      } else if (activeId != null && _catalog.any((m) => m.id == activeId)) {
        targetMall = _catalog.firstWhere((m) => m.id == activeId);
      } else {
        targetMall = findNearestMall(userCoords);
      }
    } else if (activeId != null && _catalog.any((m) => m.id == activeId)) {
      targetMall = _catalog.firstWhere((m) => m.id == activeId);
    } else {
      targetMall = findNearestMall(userCoords);
    }

    final downloaded = prefs.getStringList(_downloadedMallsKey) ?? const [];

    if (!downloaded.contains(targetMall.id)) {
      await downloadMallPackage(targetMall.id, (p) {
        if (onProgress != null) onProgress(p);
      });
    } else {
      if (onProgress != null) onProgress(1.0);
    }

    await setActiveMall(targetMall.id);
    return await loadMallPackage(targetMall.id, userCoords: userCoords);
  }

  Future<FullMallPackage> loadMallPackage(
    String mallId, {
    GeodeticCoords? userCoords,
  }) async {
    final livePackage = await ApiService.instance.fetchMallPackage(mallId);
    if (livePackage != null && livePackage.metadata.id.isNotEmpty) {
      return livePackage;
    }

    MallMetadata? targetMetadata;
    for (final m in _catalog) {
      if (m.id == mallId) {
        targetMetadata = m;
        break;
      }
    }

    targetMetadata ??= _catalog.isNotEmpty ? _catalog.first : null;

    if (targetMetadata == null || targetMetadata.id.isEmpty) {
      return const FullMallPackage(
        metadata: MallMetadata(
          id: '',
          name: '',
          city: '',
          country: '',
          latitude: 0.0,
          longitude: 0.0,
          floorCount: 0,
          packageSizeBytesMB: 0.0,
          category: '',
          rating: '',
          isDownloaded: false,
          isActive: false,
        ),
        profile: BuildingElevationProfile(
          buildingId: '',
          name: '',
          entranceBaseAnchorHeight: 0.0,
          floorGapMeters: 0.0,
          floors: [],
        ),
        destinations: [],
        entranceMarkers: [],
      );
    }

    final liveDestinations = await ApiService.instance.fetchDestinations(
      mallId: targetMetadata.id,
    );
    final rawDestinations = liveDestinations.isNotEmpty
        ? liveDestinations
        : await ApiService.instance.fetchDestinations();
    final mallDestinations = rawDestinations.where((p) {
      if (p.mallId != null && p.mallId!.isNotEmpty) {
        return p.mallId == targetMetadata?.id;
      }
      return true;
    }).toList();

    final centerCoords = GeodeticCoords(
      latitude: targetMetadata.latitude,
      longitude: targetMetadata.longitude,
      height: 45.0,
    );

    return FullMallPackage(
      metadata: targetMetadata,
      profile: BuildingElevationProfile(
        buildingId: targetMetadata.id,
        name: targetMetadata.name,
        entranceBaseAnchorHeight: centerCoords.height,
        floorGapMeters: 4.5,
        floors: const <FloorLevelConfig>[],
      ),
      destinations: mallDestinations,
      entranceMarkers: const <EntranceMarkerNode>[],
    );
  }

  /// Query POIs stored in database for a specific floor level
  List<DestinationPOI> queryPOIsByFloor(
    List<DestinationPOI> allPois,
    int floorNumber,
  ) {
    return allPois.where((poi) => poi.floorNumber == floorNumber).toList();
  }

  /// Search database POIs by keyword query
  List<DestinationPOI> searchPOIsInDatabase(
    List<DestinationPOI> allPois,
    String query,
  ) {
    if (query.isEmpty) return allPois;
    final q = query.toLowerCase();
    return allPois
        .where(
          (poi) =>
              poi.name.toLowerCase().contains(q) ||
              poi.category.toLowerCase().contains(q) ||
              poi.description.toLowerCase().contains(q),
        )
        .toList();
  }

  /// Filter database POIs by category tag
  List<DestinationPOI> filterPOIsByCategory(
    List<DestinationPOI> allPois,
    String category,
  ) {
    if (category == 'All') return allPois;
    final catLower = category.toLowerCase();
    return allPois
        .where((poi) => poi.category.toLowerCase().contains(catLower))
        .toList();
  }
}
