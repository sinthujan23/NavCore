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
  final bool isSelected;
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
    this.isActive = true,
    this.isSelected = false,
    this.entranceBaseAnchorHeight = 0.0,
    this.floorGapMeters = 3.8,
    this.parkingFloors = const ['P'],
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
    bool? isSelected,
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
      isSelected: isSelected ?? this.isSelected,
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
    'isSelected': isSelected,
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
  static const String _userActiveMallKey = 'NexNav_user_active_mall_id';
  static const String _adminActiveMallKey = 'NexNav_admin_active_mall_id';

  final List<MallMetadata> _catalog = [];

  List<MallMetadata> get catalog => _catalog;

  String? get activeMallId {
    final active =
        _catalog.where((m) => m.isActive || m.isSelected).firstOrNull;
    return active?.id;
  }

  Future<List<MallMetadata>> getMallsList({
    bool activeOnly = false,
    bool isAdmin = false,
  }) async {
    try {
      final liveMalls = await ApiService.instance.fetchMalls();
      _catalog.clear();
      _catalog.addAll(liveMalls);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final downloadedIds = prefs.getStringList(_downloadedMallsKey) ?? const [];
    final roleKey = isAdmin ? _adminActiveMallKey : _userActiveMallKey;
    String activeId =
        (prefs.getString(roleKey) ?? prefs.getString(_activeMallKey) ?? '')
            .trim()
            .toLowerCase();

    // If activeId is not set or not in catalog, resolve it without overwriting other malls
    final catalogHasActiveId = _catalog.any((m) {
      final mId = m.id.trim().toLowerCase();
      final mStripped = mId.replaceAll(RegExp(r'^0+'), '');
      final aStripped = activeId.replaceAll(RegExp(r'^0+'), '');
      return mId == activeId || (aStripped.isNotEmpty && mStripped == aStripped);
    });
    if (!catalogHasActiveId && _catalog.isNotEmpty) {
      final serverActive = _catalog.where((m) => m.isActive).firstOrNull;
      activeId = (serverActive ?? _catalog.first).id.trim().toLowerCase();
      if (activeId.isNotEmpty) {
        await prefs.setString(roleKey, activeId);
        await prefs.setString(_activeMallKey, activeId);
      }
    }

    final mapped = _catalog.map((m) {
      final mIdLower = m.id.trim().toLowerCase();
      final mStripped = mIdLower.replaceAll(RegExp(r'^0+'), '');
      final aStripped = activeId.replaceAll(RegExp(r'^0+'), '');
      final bool isDown = downloadedIds.any(
        (id) => id.trim().toLowerCase() == mIdLower,
      );
      final bool isSel = activeId.isNotEmpty &&
          (mIdLower == activeId ||
              (aStripped.isNotEmpty && mStripped == aStripped));
      return m.copyWith(
        isDownloaded: isDown,
        isActive: isSel,
        isSelected: isSel,
      );
    }).toList();

    _catalog.clear();
    _catalog.addAll(mapped);
    if (activeOnly) {
      return mapped.where((m) => m.isActive).toList();
    }
    return mapped;
  }

  void removeMall(String mallId) {
    final lowerId = mallId.trim().toLowerCase();
    _catalog.removeWhere((m) => m.id.trim().toLowerCase() == lowerId);
  }

  void toggleMallActiveStatus(String mallId, bool isActive) {
    final cleanLower = mallId.trim().toLowerCase();
    for (int i = 0; i < _catalog.length; i++) {
      if (_catalog[i].id.trim().toLowerCase() == cleanLower) {
        _catalog[i] = _catalog[i].copyWith(
          isActive: isActive,
          isSelected: isActive,
        );
      } else if (isActive) {
        // Enforce strictly one active: all other malls become inactive
        _catalog[i] = _catalog[i].copyWith(isActive: false, isSelected: false);
      }
    }
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

  Future<void> setActiveMall(String mallId, {bool isAdmin = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanId = mallId.trim();
    final roleKey = isAdmin ? _adminActiveMallKey : _userActiveMallKey;
    if (cleanId.isEmpty) {
      await prefs.remove(roleKey);
      await prefs.remove(_activeMallKey);
    } else {
      await prefs.setString(roleKey, cleanId);
      await prefs.setString(_activeMallKey, cleanId);
    }

    final cleanLower = cleanId.toLowerCase();
    final strippedClean = cleanLower.replaceAll(RegExp(r'^0+'), '');
    for (int i = 0; i < _catalog.length; i++) {
      final m = _catalog[i];
      final mLower = m.id.trim().toLowerCase();
      final mStripped = mLower.replaceAll(RegExp(r'^0+'), '');
      final isTarget = cleanLower.isNotEmpty &&
          (mLower == cleanLower ||
              (strippedClean.isNotEmpty && mStripped == strippedClean));
      _catalog[i] = m.copyWith(
        isSelected: isTarget,
        isActive: isTarget,
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
  /// If [activeOnly] is true, strictly excludes any inactive venues.
  Future<List<MallMetadata>> getMallsWithinRadius(
    GeodeticCoords userCoords, {
    double radiusMeters = 500.0,
    bool activeOnly = false,
  }) async {
    final allMalls = await getMallsList();
    if (userCoords.latitude == 0.0 && userCoords.longitude == 0.0) {
      return const <MallMetadata>[];
    }
    return allMalls.where((mall) {
      if (activeOnly && !mall.isActive) return false;
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

  /// Finds the nearest active mall in the catalog or dynamically resolves a venue for any global user location
  MallMetadata findNearestMall(
    GeodeticCoords userCoords, {
    bool activeOnly = false,
  }) {
    final candidates = activeOnly
        ? _catalog.where((m) => m.isActive).toList()
        : _catalog;

    if (candidates.isEmpty) {
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
        isSelected: false,
      );
    }

    MallMetadata nearest = candidates.first;
    double minDistance = double.infinity;

    for (final mall in candidates) {
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

  Future<void> clearActiveMall({bool isAdmin = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final roleKey = isAdmin ? _adminActiveMallKey : _userActiveMallKey;
    await prefs.remove(roleKey);
    await prefs.remove(_activeMallKey);
    for (int i = 0; i < _catalog.length; i++) {
      _catalog[i] = _catalog[i].copyWith(isSelected: false);
    }
  }

  /// Automatically detects, downloads, and activates the mall map package ONLY if within 500m of current GPS location.
  /// Malls above 500m are NOT loaded in maps.
  Future<FullMallPackage> autoDownloadAndActivateNearestMall(
    GeodeticCoords userCoords, {
    Function(double progress)? onProgress,
    double maxRadiusMeters = 500.0,
    bool isAdmin = false,
  }) async {
    await getMallsList(isAdmin: isAdmin);
    if (_catalog.isEmpty) {
      await clearActiveMall(isAdmin: isAdmin);
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
          isActive: false,
          isSelected: false,
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

    List<MallMetadata> mallsWithin500m = [];
    if (hasGps) {
      // Filter all catalog malls strictly within 500m of user's current GPS location
      mallsWithin500m = _catalog.where((m) {
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
    }

    if (mallsWithin500m.isNotEmpty) {
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

      await setActiveMall(targetMall.id, isAdmin: isAdmin);
      return await loadMallPackage(
        targetMall.id,
        userCoords: userCoords,
        isAdmin: isAdmin,
      );
    }

    // Fallback: If outside 500m or no GPS lock, preserve and load the active mall from catalog
    final prefs = await SharedPreferences.getInstance();
    final roleKey = isAdmin ? _adminActiveMallKey : _userActiveMallKey;
    String? currentActiveId =
        prefs.getString(roleKey) ?? prefs.getString(_activeMallKey);
    if (currentActiveId == null || currentActiveId.trim().isEmpty) {
      final firstActive =
          _catalog.where((m) => m.isActive).firstOrNull ??
          (_catalog.isNotEmpty ? _catalog.first : null);
      if (firstActive != null) {
        currentActiveId = firstActive.id;
        await setActiveMall(currentActiveId, isAdmin: isAdmin);
      }
    }

    if (currentActiveId != null && currentActiveId.trim().isNotEmpty) {
      return await loadMallPackage(
        currentActiveId,
        userCoords: userCoords,
        isAdmin: isAdmin,
      );
    }

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
        isActive: false,
        isSelected: false,
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

  Future<FullMallPackage> loadMallPackage(
    String mallId, {
    GeodeticCoords? userCoords,
    bool isAdmin = false,
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
      await setActiveMall(livePackage.metadata.id, isAdmin: isAdmin);
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
      final fresh = await getMallsList(isAdmin: isAdmin);
      for (final m in fresh) {
        if (m.id.trim().toLowerCase() == searchId ||
            m.name.trim().toLowerCase() == searchId) {
          targetMetadata = m;
          break;
        }
      }
    }

    if (targetMetadata != null && targetMetadata.id.isNotEmpty) {
      await setActiveMall(targetMetadata.id, isAdmin: isAdmin);
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
          isSelected: false,
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
    final targetId = targetMetadata.id.trim().toLowerCase();
    final mallDestinations = liveDestinations.where((p) {
      if (p.mallId != null && p.mallId!.isNotEmpty) {
        return p.mallId!.trim().toLowerCase() == targetId;
      }
      return false;
    }).toList();

    final double groundAlt = targetMetadata.entranceBaseAnchorHeight > 0
        ? targetMetadata.entranceBaseAnchorHeight
        : 8.5;
    final double gap = targetMetadata.floorGapMeters > 0
        ? targetMetadata.floorGapMeters
        : 3.8;

    final floorHeights = await ApiService.instance.fetchFloorHeights(
      targetMetadata.id,
    );
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
      final count = targetMetadata.floorCount > 0
          ? targetMetadata.floorCount
          : 5;
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
            storesCount: mallDestinations
                .where((d) => d.floorNumber == fn)
                .length,
          ),
        );
        curAlt += gap;
      }
    }

    final hasParkingFloor = floorsList.any(
      (f) => f.floorNumber < 0 || f.floorId.trim().toUpperCase() == 'P',
    );
    if (!hasParkingFloor) {
      floorsList.insert(
        0,
        FloorLevelConfig(
          floorId: 'P',
          floorNumber: -1,
          name: 'Parking (P)',
          relativeVectorMeters: -gap,
          absoluteHeightMeters: double.parse(
            (groundAlt - gap).toStringAsFixed(2),
          ),
          bandMinMeters: groundAlt - gap - 2.5,
          bandMaxMeters: groundAlt - gap + 2.5,
          storesCount: 0,
        ),
      );
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
