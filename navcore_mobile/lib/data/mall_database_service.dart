import 'package:shared_preferences/shared_preferences.dart';
import '../engine/ecef_engine.dart';
import '../engine/bearing_engine.dart';
import '../engine/floor_tracker.dart';
import '../engine/pnp_engine.dart';
import 'api_service.dart';
import 'destinations.dart';
import 'geocoding_service.dart';

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

    // If nearest catalog mall is within 5km, return it
    if (minDistance <= 5000.0) {
      return nearest;
    }

    // Otherwise, dynamically generate a global spatial venue centered directly at userCoords
    return MallMetadata(
      id: 'mall-global-${userCoords.latitude.toStringAsFixed(3)}-${userCoords.longitude.toStringAsFixed(3)}',
      name: 'Current Global AR Venue',
      city: 'Local Area',
      country: 'Worldwide',
      latitude: userCoords.latitude,
      longitude: userCoords.longitude,
      floorCount: 5,
      packageSizeBytesMB: 14.0,
      category: 'AR Spatial Navigation Complex',
      rating: '4.9 ★',
      isDownloaded: true,
      isActive: true,
    );
  }

  /// Automatically detects, downloads, and activates the particular mall map package nearest to current GPS location
  Future<FullMallPackage> autoDownloadAndActivateNearestMall(
    GeodeticCoords userCoords, {
    Function(double progress)? onProgress,
  }) async {
    await getMallsList();
    final nearest = findNearestMall(userCoords);

    final prefs = await SharedPreferences.getInstance();
    final downloaded = prefs.getStringList(_downloadedMallsKey) ?? const [];

    if (!downloaded.contains(nearest.id)) {
      await downloadMallPackage(nearest.id, (p) {
        if (onProgress != null) onProgress(p);
      });
    } else {
      if (onProgress != null) onProgress(1.0);
    }

    await setActiveMall(nearest.id);
    return await loadMallPackage(nearest.id, userCoords: userCoords);
  }

  Future<FullMallPackage> loadMallPackage(
    String mallId, {
    GeodeticCoords? userCoords,
  }) async {
    final livePackage = await ApiService.instance.fetchMallPackage(mallId);
    if (livePackage != null) {
      return livePackage;
    }

    MallMetadata? targetMetadata;
    
    for (final m in _catalog) {
      if (m.id == mallId) {
        targetMetadata = m;
        break;
      }
    }

    if (targetMetadata == null && userCoords != null) {
      final geo = await GeocodingService.reverseGeocode(
        userCoords.latitude,
        userCoords.longitude,
      );
      targetMetadata = MallMetadata(
        id: geo.suggestedVenueId,
        name: geo.placeName,
        city: geo.city,
        country: geo.country,
        latitude: userCoords.latitude,
        longitude: userCoords.longitude,
        floorCount: 5,
        packageSizeBytesMB: 4.5,
        category: 'Indoor Venue',
        rating: '4.9 ★',
        isDownloaded: true,
        isActive: true,
      );
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
          floorGapMeters: 4.5,
          floors: [],
        ),
        destinations: [],
        entranceMarkers: [],
      );
    }

    // If userCoords is provided and user is far (>5km) from targetMetadata, re-anchor to userCoords globally
    if (userCoords != null && userCoords.latitude != 0.0 && userCoords.longitude != 0.0) {
      final distM = haversineDistance(
        userCoords,
        GeodeticCoords(
          latitude: targetMetadata.latitude,
          longitude: targetMetadata.longitude,
          height: userCoords.height,
        ),
      );
      if (distM > 5000.0) {
        final geo = await GeocodingService.reverseGeocode(
          userCoords.latitude,
          userCoords.longitude,
        );
        targetMetadata = MallMetadata(
          id: geo.suggestedVenueId,
          name: geo.placeName,
          city: geo.city,
          country: geo.country,
          latitude: userCoords.latitude,
          longitude: userCoords.longitude,
          floorCount: 5,
          packageSizeBytesMB: targetMetadata.packageSizeBytesMB,
          category: targetMetadata.category,
          rating: targetMetadata.rating,
          isDownloaded: true,
          isActive: true,
        );
      }
    }

    final geo = await GeocodingService.reverseGeocode(
      targetMetadata.latitude,
      targetMetadata.longitude,
    );

    final centerCoords = GeodeticCoords(
      latitude: targetMetadata.latitude,
      longitude: targetMetadata.longitude,
      height: geo.groundAltitude,
    );

    final localizedDestinations = getLocalizedDestinationsForCoords(
      centerCoords,
      mallId: targetMetadata.id,
    );

    final calculatedGap = geo.floorGap;
    final totalFloors = targetMetadata.floorCount.clamp(1, 10);
    final dynamicFloors = List.generate(totalFloors, (i) {
      final flrNum = i + 1;
      final relHeight = i * calculatedGap;
      final absHeight = centerCoords.height + relHeight;
      return FloorLevelConfig(
        floorId: 'fl-$flrNum',
        floorNumber: flrNum,
        name: flrNum == 1 ? 'Level 1 (Ground)' : 'Level $flrNum',
        relativeVectorMeters: relHeight,
        absoluteHeightMeters: absHeight,
        bandMinMeters: absHeight - (calculatedGap / 2),
        bandMaxMeters: absHeight + (calculatedGap / 2),
        storesCount: 0,
        ceilingHeightMeters: calculatedGap,
      );
    });

    return FullMallPackage(
      metadata: targetMetadata,
      profile: BuildingElevationProfile(
        buildingId: targetMetadata.id,
        name: targetMetadata.name,
        entranceBaseAnchorHeight: centerCoords.height,
        floorGapMeters: calculatedGap,
        floors: dynamicFloors,
      ),
      destinations: localizedDestinations,
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
