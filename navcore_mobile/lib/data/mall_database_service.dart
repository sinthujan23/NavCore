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
  final double entranceBaseAnchorHeight;
  final double floorGapMeters;
  final List<String> parkingFloors;

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
    this.entranceBaseAnchorHeight = 0.0,
    this.floorGapMeters = 3.8,
    this.parkingFloors = const ['Floor 1'],
  });

  MallMetadata copyWith({
    String? id,
    String? name,
    String? city,
    String? country,
    double? latitude,
    double? longitude,
    int? floorCount,
    double? packageSizeBytesMB,
    String? category,
    String? rating,
    bool? isDownloaded,
    bool? isActive,
    double? entranceBaseAnchorHeight,
    double? floorGapMeters,
    List<String>? parkingFloors,
  }) {
    return MallMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      city: city ?? this.city,
      country: country ?? this.country,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      floorCount: floorCount ?? this.floorCount,
      packageSizeBytesMB: packageSizeBytesMB ?? this.packageSizeBytesMB,
      category: category ?? this.category,
      rating: rating ?? this.rating,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      isActive: isActive ?? this.isActive,
      entranceBaseAnchorHeight:
          entranceBaseAnchorHeight ?? this.entranceBaseAnchorHeight,
      floorGapMeters: floorGapMeters ?? this.floorGapMeters,
      parkingFloors: parkingFloors ?? this.parkingFloors,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'city': city,
    'country': country,
    'latitude': latitude,
    'longitude': longitude,
    'floorCount': floorCount,
    'packageSizeBytesMB': packageSizeBytesMB,
    'category': category,
    'rating': rating,
    'isDownloaded': isDownloaded,
    'isActive': isActive,
    'entranceBaseAnchorHeight': entranceBaseAnchorHeight,
    'floorGapMeters': floorGapMeters,
    'parkingFloors': parkingFloors,
  };
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
    try {
      final liveMalls = await ApiService.instance.fetchMalls();
      _catalog.clear();
      _catalog.addAll(liveMalls);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final downloadedIds = prefs.getStringList(_downloadedMallsKey) ?? const [];
    final activeId = (prefs.getString(_activeMallKey) ?? '').trim().toLowerCase();

    final mapped = _catalog.map((m) {
      final mIdLower = m.id.trim().toLowerCase();
      bool isDown = downloadedIds.any((id) => id.trim().toLowerCase() == mIdLower);
      bool isAct = (mIdLower == activeId && activeId.isNotEmpty);
      return m.copyWith(
        isDownloaded: isDown,
        isActive: isAct,
      );
    }).toList();

    _catalog.clear();
    _catalog.addAll(mapped);
    return mapped;
  }

  void removeMall(String mallId) {
    final lowerId = mallId.trim().toLowerCase();
    _catalog.removeWhere((m) => m.id.trim().toLowerCase() == lowerId);
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
    final cleanId = mallId.trim();
    if (cleanId.isEmpty) {
      await prefs.remove(_activeMallKey);
    } else {
      await prefs.setString(_activeMallKey, cleanId);
    }

    final cleanLower = cleanId.toLowerCase();
    for (int i = 0; i < _catalog.length; i++) {
      final m = _catalog[i];
      final isAct = cleanLower.isNotEmpty && (m.id.trim().toLowerCase() == cleanLower);
      _catalog[i] = MallMetadata(
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
        isDownloaded: m.isDownloaded,
        isActive: isAct,
      );
    }
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
      return const <MallMetadata>[];
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

  Future<void> clearActiveMall() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeMallKey);
    for (int i = 0; i < _catalog.length; i++) {
      final m = _catalog[i];
      _catalog[i] = MallMetadata(
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
        isDownloaded: m.isDownloaded,
        isActive: false,
      );
    }
  }

  /// Automatically detects, downloads, and activates the mall map package ONLY if within 500m of current GPS location.
  /// Malls above 500m are NOT loaded in maps.
  Future<FullMallPackage> autoDownloadAndActivateNearestMall(
    GeodeticCoords userCoords, {
    Function(double progress)? onProgress,
    double maxRadiusMeters = 500.0,
  }) async {
    await getMallsList();
    if (_catalog.isEmpty) {
      await clearActiveMall();
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

    final hasGps = userCoords.latitude != 0.0 && userCoords.longitude != 0.0;

    if (!hasGps) {
      // Without valid GPS location, do not auto-load any mall map
      await clearActiveMall();
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

    // Filter ONLY malls strictly within 500m of user's current GPS location
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

    // Above 500m malls are NOT loaded in maps!
    if (mallsWithin500m.isEmpty) {
      await clearActiveMall();
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

    // Sort by distance to find the closest mall within 500m
    mallsWithin500m.sort((a, b) {
      final distA = calculateDistanceToMall(userCoords, a);
      final distB = calculateDistanceToMall(userCoords, b);
      return distA.compareTo(distB);
    });
    final targetMall = mallsWithin500m.first;

    final prefs = await SharedPreferences.getInstance();
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
    if (mallId.trim().isEmpty) {
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

    final livePackage = await ApiService.instance.fetchMallPackage(mallId);
    if (livePackage != null && livePackage.metadata.id.isNotEmpty) {
      if (userCoords != null &&
          userCoords.latitude != 0.0 &&
          userCoords.longitude != 0.0) {
        final dist = haversineDistance(
          userCoords,
          GeodeticCoords(
            latitude: livePackage.metadata.latitude,
            longitude: livePackage.metadata.longitude,
            height: userCoords.height,
          ),
        );
        if (dist > 500.0) {
          // Mall is > 500m away: strictly do not load map!
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
      }
      await setActiveMall(livePackage.metadata.id);
      return livePackage;
    }

    MallMetadata? targetMetadata;
    final searchId = mallId.trim().toLowerCase();
    for (final m in _catalog) {
      if (m.id.trim().toLowerCase() == searchId ||
          m.name.trim().toLowerCase() == searchId) {
        targetMetadata = m;
        break;
      }
    }

    if (targetMetadata == null) {
      final fresh = await getMallsList();
      for (final m in fresh) {
        if (m.id.trim().toLowerCase() == searchId ||
            m.name.trim().toLowerCase() == searchId) {
          targetMetadata = m;
          break;
        }
      }
    }

    if (targetMetadata != null && targetMetadata.id.isNotEmpty) {
      if (userCoords != null &&
          userCoords.latitude != 0.0 &&
          userCoords.longitude != 0.0) {
        final dist = calculateDistanceToMall(userCoords, targetMetadata);
        if (dist > 500.0) {
          // Mall is > 500m away: strictly do not load map!
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
      }
      await setActiveMall(targetMetadata.id);
    }

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

    final double groundAlt = targetMetadata.entranceBaseAnchorHeight > 0
        ? targetMetadata.entranceBaseAnchorHeight
        : 8.5;
    final double gap = targetMetadata.floorGapMeters > 0
        ? targetMetadata.floorGapMeters
        : 3.8;

    final floorHeights = await ApiService.instance.fetchFloorHeights(targetMetadata.id);
    List<FloorLevelConfig> floorsList = floorHeights.map((fh) {
      final fn = fh.floorNo;
      final baseAlt = fh.baseAltitudeM;
      final heightNext = fh.heightToNextM > 0 ? fh.heightToNextM : gap;
      return FloorLevelConfig(
        floorId: 'F$fn',
        floorNumber: fn,
        name: fn < 0
            ? 'Basement B${fn.abs()}'
            : (fn == 0 ? 'Ground Floor' : 'Floor $fn'),
        relativeVectorMeters: heightNext,
        absoluteHeightMeters: baseAlt,
        bandMinMeters: baseAlt - 2.5,
        bandMaxMeters: baseAlt + 2.5,
        storesCount: mallDestinations.where((d) => d.floorNumber == fn).length,
      );
    }).toList();

    if (floorsList.isEmpty) {
      final count = targetMetadata.floorCount > 0 ? targetMetadata.floorCount : 5;
      double curAlt = groundAlt;
      for (int fn = 1; fn <= count; fn++) {
        floorsList.add(
          FloorLevelConfig(
            floorId: 'F$fn',
            floorNumber: fn,
            name: fn == 1 ? 'Ground Floor' : 'Floor $fn',
            relativeVectorMeters: gap,
            absoluteHeightMeters: double.parse(curAlt.toStringAsFixed(2)),
            bandMinMeters: curAlt - 2.5,
            bandMaxMeters: curAlt + 2.5,
            storesCount: mallDestinations.where((d) => d.floorNumber == fn).length,
          ),
        );
        curAlt += gap;
      }
    }

    return FullMallPackage(
      metadata: targetMetadata,
      profile: BuildingElevationProfile(
        buildingId: targetMetadata.id,
        name: targetMetadata.name,
        entranceBaseAnchorHeight: groundAlt,
        floorGapMeters: gap,
        floors: floorsList,
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
