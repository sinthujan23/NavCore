import 'package:shared_preferences/shared_preferences.dart';
import '../engine/ecef_engine.dart';
import '../engine/bearing_engine.dart';
import '../engine/floor_tracker.dart';
import '../engine/pnp_engine.dart';
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

  final List<MallMetadata> _catalog = [
    const MallMetadata(
      id: 'mall-one-galle-face',
      name: 'One Galle Face Mall & Tower',
      city: 'Colombo',
      country: 'Sri Lanka',
      latitude: 6.927079,
      longitude: 79.845612,
      floorCount: 5,
      packageSizeBytesMB: 14.2,
      category: 'Premier Oceanfront Mall',
      rating: '4.9 ★',
      isDownloaded: true,
      isActive: true,
    ),
    const MallMetadata(
      id: 'mall-colombo-city-centre',
      name: 'Colombo City Centre (CCC)',
      city: 'Colombo',
      country: 'Sri Lanka',
      latitude: 6.916720,
      longitude: 79.855010,
      floorCount: 5,
      packageSizeBytesMB: 18.5,
      category: 'Luxury Shopping & Lifestyle',
      rating: '4.8 ★',
      isDownloaded: true,
      isActive: false,
    ),
    const MallMetadata(
      id: 'mall-havelock-city',
      name: 'Havelock City Mall',
      city: 'Colombo',
      country: 'Sri Lanka',
      latitude: 6.885020,
      longitude: 79.866030,
      floorCount: 5,
      packageSizeBytesMB: 16.8,
      category: 'Lifestyle & Retail Hub',
      rating: '4.8 ★',
    ),
    const MallMetadata(
      id: 'mall-kandy-city-centre',
      name: 'Kandy City Centre (KCC)',
      city: 'Kandy',
      country: 'Sri Lanka',
      latitude: 7.293620,
      longitude: 80.635030,
      floorCount: 5,
      packageSizeBytesMB: 15.1,
      category: 'Heritage Commercial Complex',
      rating: '4.7 ★',
    ),
    const MallMetadata(
      id: 'mall-marino-mall',
      name: 'Marino Mall & Entertainment',
      city: 'Colombo',
      country: 'Sri Lanka',
      latitude: 6.897810,
      longitude: 79.854720,
      floorCount: 5,
      packageSizeBytesMB: 12.4,
      category: 'Tech & Waterfront Mall',
      rating: '4.6 ★',
    ),
  ];

  List<MallMetadata> get catalog => _catalog;

  Future<List<MallMetadata>> getMallsList() async {
    final prefs = await SharedPreferences.getInstance();
    final downloadedIds =
        prefs.getStringList(_downloadedMallsKey) ??
        ['mall-one-galle-face', 'mall-colombo-city-centre'];
    final activeId = prefs.getString(_activeMallKey) ?? 'mall-one-galle-face';

    return _catalog.map((m) {
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
    List<String> downloaded =
        prefs.getStringList(_downloadedMallsKey) ?? ['mall-one-galle-face'];
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
  /// Preserves relative spatial layout while anchoring the venue to any global location.
  List<DestinationPOI> getLocalizedDestinationsForCoords(
    GeodeticCoords centerCoords, {
    String mallId = 'mall-global',
  }) {
    const baseLat = 6.927079;
    const baseLon = 79.845612;

    final deltaLat = centerCoords.latitude - baseLat;
    final deltaLon = centerCoords.longitude - baseLon;

    return mockDestinations.map((poi) {
      return DestinationPOI(
        id: '$mallId-${poi.id}',
        name: poi.name,
        category: poi.category,
        floorNumber: poi.floorNumber,
        rating: poi.rating,
        location: GeodeticCoords(
          latitude: poi.location.latitude + deltaLat,
          longitude: poi.location.longitude + deltaLon,
          height: poi.location.height,
        ),
        description: poi.description,
        openStatus: poi.openStatus,
        imageUrl: poi.imageUrl,
      );
    }).toList();
  }

  /// Finds the nearest mall in the catalog or dynamically resolves a venue for any global user location
  MallMetadata findNearestMall(GeodeticCoords userCoords) {
    if (userCoords.latitude == 0.0 && userCoords.longitude == 0.0) {
      return _catalog.isNotEmpty ? _catalog.first : const MallMetadata(
        id: 'mall-one-galle-face',
        name: 'One Galle Face Mall & Tower',
        city: 'Colombo',
        country: 'Sri Lanka',
        latitude: 6.927079,
        longitude: 79.845612,
        floorCount: 5,
        packageSizeBytesMB: 14.2,
        category: 'Premier Oceanfront Mall',
        rating: '4.9 ★',
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
    final nearest = findNearestMall(userCoords);

    final prefs = await SharedPreferences.getInstance();
    final downloaded =
        prefs.getStringList(_downloadedMallsKey) ?? ['mall-one-galle-face'];

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
    MallMetadata? targetMetadata;
    
    for (final m in _catalog) {
      if (m.id == mallId) {
        targetMetadata = m;
        break;
      }
    }

    if (targetMetadata == null && userCoords != null) {
      targetMetadata = MallMetadata(
        id: mallId,
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

    targetMetadata ??= _catalog.first;

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
        targetMetadata = MallMetadata(
          id: targetMetadata.id,
          name: targetMetadata.name == _catalog.first.name ? 'Current Global AR Venue' : targetMetadata.name,
          city: targetMetadata.city,
          country: targetMetadata.country,
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

    final centerCoords = GeodeticCoords(
      latitude: targetMetadata.latitude,
      longitude: targetMetadata.longitude,
      height: 45.0,
    );

    final localizedDestinations = getLocalizedDestinationsForCoords(
      centerCoords,
      mallId: targetMetadata.id,
    );

    return FullMallPackage(
      metadata: targetMetadata,
      profile: BuildingElevationProfile(
        buildingId: targetMetadata.id,
        name: targetMetadata.name,
        entranceBaseAnchorHeight: 45.0,
        floorGapMeters: 5.0,
        floors: defaultBuildingProfile.floors,
      ),
      destinations: localizedDestinations,
      entranceMarkers: [
        EntranceMarkerNode(
          markerId: 'mrk-${targetMetadata.id}-01',
          buildingId: targetMetadata.id,
          name: '${targetMetadata.name} Main Gate 1',
          latitude: targetMetadata.latitude,
          longitude: targetMetadata.longitude,
          baseHeight: 45.0,
          physicalWidthMeters: 0.25,
          physicalHeightMeters: 0.25,
        ),
        EntranceMarkerNode(
          markerId: 'mrk-${targetMetadata.id}-02',
          buildingId: targetMetadata.id,
          name: '${targetMetadata.name} North Elevator Pillar',
          latitude: targetMetadata.latitude + 0.0001,
          longitude: targetMetadata.longitude + 0.0001,
          baseHeight: 50.0,
          physicalWidthMeters: 0.25,
          physicalHeightMeters: 0.25,
        ),
      ],
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
