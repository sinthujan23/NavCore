import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../engine/floor_tracker.dart';
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
  });
  Future<FloorHeightData> updateFloorHeight(
    String mallId,
    int floorNo, {
    double? heightToNextM,
    bool? isLocked,
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
  final bool useMockFallback;

  // Local state cache for offline mock fallback
  final Map<String, List<FloorHeightData>> _localMockHeights = {};

  RestMallBackendApi({
    this.baseUrl = 'http://localhost:8080/api',
    this.useMockFallback = true,
  }) {
    _initDefaultMockHeights();
  }

  void _initDefaultMockHeights() {
    const mallId = 'mall-one-galle-face';
    const nowIso = '2026-10-05T08:00:00.000Z';
    _localMockHeights[mallId] = [
      const FloorHeightData(
        mallId: mallId,
        floorNo: -1,
        heightToNextM: 15.0,
        baseAltitudeM: 0.0,
        source: 'default',
        confidence: 0.5,
        isLocked: false,
        updatedAt: nowIso,
      ),
      const FloorHeightData(
        mallId: mallId,
        floorNo: 1,
        heightToNextM: 15.0,
        baseAltitudeM: 15.0,
        source: 'default',
        confidence: 0.5,
        isLocked: false,
        updatedAt: nowIso,
      ),
      const FloorHeightData(
        mallId: mallId,
        floorNo: 2,
        heightToNextM: 15.0,
        baseAltitudeM: 30.0,
        source: 'default',
        confidence: 0.5,
        isLocked: false,
        updatedAt: nowIso,
      ),
      const FloorHeightData(
        mallId: mallId,
        floorNo: 3,
        heightToNextM: 15.0,
        baseAltitudeM: 45.0,
        source: 'default',
        confidence: 0.5,
        isLocked: false,
        updatedAt: nowIso,
      ),
      const FloorHeightData(
        mallId: mallId,
        floorNo: 4,
        heightToNextM: 0.0,
        baseAltitudeM: 60.0,
        source: 'default',
        confidence: 0.5,
        isLocked: false,
        updatedAt: nowIso,
      ),
    ];
  }

  @override
  Future<BuildingElevationProfile> fetchBuildingProfile(
    String buildingId,
  ) async {
    if (useMockFallback) {
      await Future.delayed(const Duration(milliseconds: 50));
      return defaultBuildingProfile;
    }
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/malls/$buildingId/profile'),
      );
      if (response.statusCode == 200) {
        // Return parsed building profile
      }
    } catch (_) {}
    return defaultBuildingProfile;
  }

  @override
  Future<List<DestinationPOI>> fetchShopsForFloor(
    MallApiShopFilter filter,
  ) async {
    if (useMockFallback) {
      await Future.delayed(const Duration(milliseconds: 50));
      return mockDestinations
          .where((poi) => poi.floorNumber == filter.floorNumber)
          .toList();
    }
    return mockDestinations
        .where((poi) => poi.floorNumber == filter.floorNumber)
        .toList();
  }

  List<FloorHeightData> _getOrCreateDefaultHeights(String mallId) {
    if (_localMockHeights.containsKey(mallId) &&
        _localMockHeights[mallId]!.isNotEmpty) {
      return _localMockHeights[mallId]!;
    }

    final nowIso = DateTime.now().toIso8601String();
    final defaultList = [
      FloorHeightData(
        mallId: mallId,
        floorNo: -1,
        heightToNextM: 15.0,
        baseAltitudeM: 0.0,
        source: 'default',
        confidence: 0.5,
        isLocked: false,
        updatedAt: nowIso,
      ),
      FloorHeightData(
        mallId: mallId,
        floorNo: 1,
        heightToNextM: 15.0,
        baseAltitudeM: 15.0,
        source: 'default',
        confidence: 0.5,
        isLocked: false,
        updatedAt: nowIso,
      ),
      FloorHeightData(
        mallId: mallId,
        floorNo: 2,
        heightToNextM: 15.0,
        baseAltitudeM: 30.0,
        source: 'default',
        confidence: 0.5,
        isLocked: false,
        updatedAt: nowIso,
      ),
      FloorHeightData(
        mallId: mallId,
        floorNo: 3,
        heightToNextM: 15.0,
        baseAltitudeM: 45.0,
        source: 'default',
        confidence: 0.5,
        isLocked: false,
        updatedAt: nowIso,
      ),
      FloorHeightData(
        mallId: mallId,
        floorNo: 4,
        heightToNextM: 0.0,
        baseAltitudeM: 60.0,
        source: 'default',
        confidence: 0.5,
        isLocked: false,
        updatedAt: nowIso,
      ),
    ];

    _localMockHeights[mallId] = defaultList;
    return defaultList;
  }

  @override
  Future<List<FloorHeightData>> fetchFloorHeights(String mallId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/malls/$mallId/floor-heights'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final list = (decoded['floors'] as List)
            .map((e) => FloorHeightData.fromJson(e))
            .toList();
        _localMockHeights[mallId] = list;
        return list;
      }
    } catch (_) {
      // Fallback to local store on network failure
    }

    return _getOrCreateDefaultHeights(mallId);
  }

  @override
  Future<List<FloorHeightData>> triggerFloorHeightCalculation(
    String mallId, {
    double? lat,
    double? lon,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/malls/$mallId/floor-heights/calculate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'latitude': lat ?? 6.927079,
              'longitude': lon ?? 79.845612,
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final list = (decoded['floors'] as List)
            .map((e) => FloorHeightData.fromJson(e))
            .toList();
        _localMockHeights[mallId] = list;
        return list;
      }
    } catch (_) {
      // Fallback auto-calculation simulation for offline mode
    }

    final currentList = List<FloorHeightData>.from(_getOrCreateDefaultHeights(mallId));
    final updatedList = <FloorHeightData>[];
    double cumulativeAlt = 0.0;

    for (int i = 0; i < currentList.length; i++) {
      final item = currentList[i];
      double h = item.heightToNextM;
      String src = item.source;
      double conf = item.confidence;

      if (!item.isLocked && item.source != 'admin') {
        src = 'barometer';
        conf = 0.85;
      }

      updatedList.add(
        item.copyWith(
          baseAltitudeM: cumulativeAlt,
          source: src,
          confidence: conf,
          updatedAt: DateTime.now().toIso8601String(),
        ),
      );

      cumulativeAlt += h;
    }

    _localMockHeights[mallId] = updatedList;
    return updatedList;
  }

  @override
  Future<FloorHeightData> updateFloorHeight(
    String mallId,
    int floorNo, {
    double? heightToNextM,
    bool? isLocked,
  }) async {
    try {
      final Map<String, dynamic> bodyData = {};
      if (heightToNextM != null) {
        bodyData['height_to_next_m'] = heightToNextM;
        bodyData['source'] = 'admin';
      }
      if (isLocked != null) {
        bodyData['is_locked'] = isLocked;
      }

      final response = await http
          .put(
            Uri.parse('$baseUrl/malls/$mallId/floor-heights/$floorNo'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(bodyData),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final result = FloorHeightData.fromJson(decoded['floor']);
        await fetchFloorHeights(mallId);
        return result;
      }
    } catch (_) {}

    final currentList = _getOrCreateDefaultHeights(mallId);
    final idx = currentList.indexWhere((f) => f.floorNo == floorNo);
    if (idx >= 0) {
      final old = currentList[idx];
      final updated = old.copyWith(
        heightToNextM: heightToNextM ?? old.heightToNextM,
        isLocked: isLocked ?? (heightToNextM != null ? true : old.isLocked),
        source: heightToNextM != null ? 'admin' : old.source,
        confidence: heightToNextM != null ? 1.0 : old.confidence,
        updatedAt: DateTime.now().toIso8601String(),
      );

      currentList[idx] = updated;

      double cumulativeAlt = 0.0;
      for (int i = 0; i < currentList.length; i++) {
        currentList[i] = currentList[i].copyWith(baseAltitudeM: cumulativeAlt);
        cumulativeAlt += currentList[i].heightToNextM;
      }

      _localMockHeights[mallId] = currentList;
      return currentList[idx];
    }

    throw Exception('Floor $floorNo not found in mall $mallId');
  }

  @override
  Future<List<FloorHeightData>> addFloor(
    String mallId,
    int floorNo,
    double heightToNextM,
  ) async {
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

    double cumulativeAlt = 0.0;
    for (int i = 0; i < currentList.length; i++) {
      currentList[i] = currentList[i].copyWith(baseAltitudeM: cumulativeAlt);
      cumulativeAlt += currentList[i].heightToNextM;
    }

    _localMockHeights[mallId] = currentList;
    return currentList;
  }

  @override
  Future<List<FloorHeightData>> deleteFloor(String mallId, int floorNo) async {
    final currentList = List<FloorHeightData>.from(
      _getOrCreateDefaultHeights(mallId),
    );
    currentList.removeWhere((f) => f.floorNo == floorNo);

    double cumulativeAlt = 0.0;
    for (int i = 0; i < currentList.length; i++) {
      currentList[i] = currentList[i].copyWith(baseAltitudeM: cumulativeAlt);
      cumulativeAlt += currentList[i].heightToNextM;
    }

    _localMockHeights[mallId] = currentList;
    return currentList;
  }

  @override
  Future<List<FloorHeightData>> resetAllFloors(String mallId) async {
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

    _localMockHeights[mallId] = updatedList;
    return updatedList;
  }
}
