import 'dart:async';
import '../engine/floor_tracker.dart';
import 'api_service.dart';
import 'destinations.dart';
import 'floor_height_model.dart';

/// NexNav Backend API Hook Layer Specification
/// Provides REST abstraction for fetching building floor plans, shop POIs, and floor height calculations.

class MallApiShopFilter {
  final String buildingId;
  final int floorNumber;
  final double userLatitude;
  final double userLongitude;
  final double radiusMeters;

  const MallApiShopFilter({
    required this.buildingId,
    required this.floorNumber,
    required this.userLatitude,
    required this.userLongitude,
    this.radiusMeters = 500.0,
  });
}

abstract class MallBackendApi {
  Future<BuildingElevationProfile> fetchBuildingProfile(String buildingId);
  Future<List<DestinationPOI>> fetchShopsForFloor(MallApiShopFilter filter);
  Future<List<FloorHeightData>> fetchFloorHeights(String mallId);
  Future<List<FloorHeightData>> triggerFloorHeightCalculation(
    String mallId, {
    double? lat,
    double? lon,
    double? barometerPressureHpa,
    double? liveAltitudeM,
    double? floorGapM,
  });
  Future<FloorHeightData> updateFloorHeight(
    String mallId,
    int floorNo, {
    double? heightToNextM,
    bool? isLocked,
    double? baseAltitudeM,
  });
  Future<List<FloorHeightData>> addFloor(
    String mallId,
    int floorNo,
    double heightToNextM,
  );
  Future<List<FloorHeightData>> deleteFloor(String mallId, int floorNo);
  Future<List<FloorHeightData>> resetAllFloors(String mallId);
}

/// Production REST API Implementation with Local Fallback Hook
class RestMallBackendApi implements MallBackendApi {
  final String baseUrl;
  final bool useOfflineFallback;

  // Local state cache for offline database fallback
  final Map<String, List<FloorHeightData>> _localHeightsCache = {};

  RestMallBackendApi({
    String? baseUrl,
    this.useOfflineFallback = false,
  }) : baseUrl = baseUrl ?? ApiService.defaultBaseUrl;

  @override
  Future<BuildingElevationProfile> fetchBuildingProfile(
    String buildingId,
  ) async {
    final pkg = await ApiService.instance.fetchMallPackage(buildingId);
    if (pkg != null) {
      return pkg.profile;
    }
    return defaultBuildingProfile;
  }

  @override
  Future<List<DestinationPOI>> fetchShopsForFloor(
    MallApiShopFilter filter,
  ) async {
    final live = await ApiService.instance.fetchDestinations(
      mallId: filter.buildingId,
      floorNumber: filter.floorNumber,
    );
    return live;
  }

  List<FloorHeightData> _getOrCreateDefaultHeights(String mallId) {
    return _localHeightsCache[mallId] ?? <FloorHeightData>[];
  }

  @override
  Future<List<FloorHeightData>> fetchFloorHeights(String mallId) async {
    final live = await ApiService.instance.fetchFloorHeights(mallId);
    _localHeightsCache[mallId] = live;
    return live;
  }

  @override
  Future<List<FloorHeightData>> triggerFloorHeightCalculation(
    String mallId, {
    double? lat,
    double? lon,
    double? barometerPressureHpa,
    double? liveAltitudeM,
    double? floorGapM,
  }) async {
    final live = await ApiService.instance.calculateFloorHeights(
      mallId,
      lat: lat,
      lon: lon,
      barometerPressureHpa: barometerPressureHpa,
      liveAltitudeM: liveAltitudeM,
      floorGapM: floorGapM,
    );
    if (live.isNotEmpty) {
      _localHeightsCache[mallId] = live;
      return live;
    }

    final currentList = List<FloorHeightData>.from(_getOrCreateDefaultHeights(mallId));
    currentList.sort((a, b) => a.floorNo.compareTo(b.floorNo));
    final updatedList = <FloorHeightData>[];
    double cumulativeAlt = currentList.isNotEmpty && currentList.first.baseAltitudeM > 0
        ? currentList.first.baseAltitudeM
        : 8.5;

    for (int i = 0; i < currentList.length; i++) {
      final item = currentList[i];
      double h = item.heightToNextM;
      String src = item.source;
      double conf = item.confidence;
      final isAdmin = item.isLocked || item.source == 'admin';

      if (!isAdmin) {
        src = 'barometer';
        conf = barometerPressureHpa != null ? 0.95 : 0.85;
      }

      updatedList.add(
        item.copyWith(
          baseAltitudeM: cumulativeAlt,
          source: src,
          confidence: conf,
          isLocked: isAdmin,
          updatedAt: DateTime.now().toIso8601String(),
        ),
      );

      cumulativeAlt += h;
    }

    _localHeightsCache[mallId] = updatedList;
    return updatedList;
  }

  @override
  Future<FloorHeightData> updateFloorHeight(
    String mallId,
    int floorNo, {
    double? heightToNextM,
    bool? isLocked,
    double? baseAltitudeM,
  }) async {
    final success = await ApiService.instance.updateFloorHeight(
      mallId,
      floorNo,
      heightToNextM: heightToNextM,
      isLocked: isLocked,
      baseAltitudeM: baseAltitudeM,
    );
    if (success) {
      final updated = await ApiService.instance.fetchFloorHeights(mallId);
      if (updated.isNotEmpty) {
        _localHeightsCache[mallId] = updated;
        final match = updated.firstWhere((f) => f.floorNo == floorNo, orElse: () => updated.first);
        return match;
      }
    }

    final currentList = _getOrCreateDefaultHeights(mallId);
    final idx = currentList.indexWhere((f) => f.floorNo == floorNo);
    if (idx >= 0) {
      final old = currentList[idx];
      final updated = old.copyWith(
        heightToNextM: heightToNextM ?? old.heightToNextM,
        baseAltitudeM: baseAltitudeM ?? old.baseAltitudeM,
        isLocked: isLocked ?? (heightToNextM != null || baseAltitudeM != null ? true : old.isLocked),
        source: (heightToNextM != null || baseAltitudeM != null) ? 'admin' : old.source,
        confidence: 1.0,
        updatedAt: DateTime.now().toIso8601String(),
      );

      currentList[idx] = updated;
      currentList.sort((a, b) => a.floorNo.compareTo(b.floorNo));

      double cumulativeAlt = currentList.first.baseAltitudeM > 0 ? currentList.first.baseAltitudeM : 8.5;
      for (int i = 0; i < currentList.length; i++) {
        currentList[i] = currentList[i].copyWith(baseAltitudeM: cumulativeAlt);
        cumulativeAlt += currentList[i].heightToNextM;
      }

      _localHeightsCache[mallId] = currentList;
      return currentList.firstWhere((f) => f.floorNo == floorNo, orElse: () => currentList[idx]);
    }

    throw Exception('Floor $floorNo not found in mall $mallId');
  }

  @override
  Future<List<FloorHeightData>> addFloor(
    String mallId,
    int floorNo,
    double heightToNextM,
  ) async {
    final live = await ApiService.instance.addFloor(mallId, floorNo, heightToNextM);
    if (live.isNotEmpty) {
      _localHeightsCache[mallId] = live;
      return live;
    }

    final currentList = List<FloorHeightData>.from(
      _getOrCreateDefaultHeights(mallId),
    );
    currentList.removeWhere((f) => f.floorNo == floorNo);
    currentList.add(
      FloorHeightData(
        mallId: mallId,
        floorNo: floorNo,
        heightToNextM: heightToNextM,
        baseAltitudeM: 0.0,
        source: 'admin',
        confidence: 1.0,
        isLocked: true,
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
    currentList.sort((a, b) => a.floorNo.compareTo(b.floorNo));

    double cumulativeAlt = currentList.first.baseAltitudeM > 0 ? currentList.first.baseAltitudeM : 8.5;
    for (int i = 0; i < currentList.length; i++) {
      currentList[i] = currentList[i].copyWith(baseAltitudeM: cumulativeAlt);
      cumulativeAlt += currentList[i].heightToNextM;
    }

    _localHeightsCache[mallId] = currentList;
    return currentList;
  }

  @override
  Future<List<FloorHeightData>> deleteFloor(String mallId, int floorNo) async {
    final live = await ApiService.instance.deleteFloor(mallId, floorNo);
    _localHeightsCache[mallId] = live;
    return live;
  }

  @override
  Future<List<FloorHeightData>> resetAllFloors(String mallId) async {
    final live = await ApiService.instance.resetFloorHeights(mallId);
    if (live.isNotEmpty) {
      _localHeightsCache[mallId] = live;
      return live;
    }

    final currentList = List<FloorHeightData>.from(
      _getOrCreateDefaultHeights(mallId),
    );
    final updatedList = <FloorHeightData>[];
    double cumulativeAlt = 0.0;

    for (int i = 0; i < currentList.length; i++) {
      final item = currentList[i];
      final updated = item.copyWith(
        source: 'default',
        confidence: 0.5,
        isLocked: false,
        baseAltitudeM: cumulativeAlt,
        updatedAt: DateTime.now().toIso8601String(),
      );
      updatedList.add(updated);
      cumulativeAlt += updated.heightToNextM;
    }

    _localHeightsCache[mallId] = updatedList;
    return updatedList;
  }
}
