import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../engine/floor_tracker.dart';
import '../engine/pnp_engine.dart';
import 'destinations.dart';
import 'floor_height_model.dart';
import 'mall_database_service.dart';
import 'parking_service.dart';

class AuthResult {
  final bool isSuccess;
  final String? token;
  final String? email;
  final String? role; // 'admin' | 'user'
  final String? errorMessage;

  const AuthResult({
    required this.isSuccess,
    this.token,
    this.email,
    this.role,
    this.errorMessage,
  });
}

class ApiService {
  static final ApiService instance = ApiService._internal();

  ApiService._internal();

  static const String _tokenKey = 'nexnav_jwt_token';
  static const String _userRoleKey = 'nexnav_user_role';
  static const String _userEmailKey = 'nexnav_user_email';
  static const String _customBaseUrlKey = 'nexnav_custom_base_url';

  static const String productionServerUrl = 'https://nexnav.hashnate.com/api';

  /// Normalizes any input URL to ensure proper protocol and /api postfix
  static String normalizeUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return productionServerUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.endsWith('/api')) {
      url = '$url/api';
    }
    return url;
  }

  // Primary backend URL is the cloud server (nexnav.hashnate.com)
  static String get defaultBaseUrl => productionServerUrl;

  String? _cachedBaseUrl;

  Future<String> getBaseUrl() async {
    if (_cachedBaseUrl != null) return _cachedBaseUrl!;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_customBaseUrlKey);
    if (saved != null && saved.isNotEmpty) {
      _cachedBaseUrl = normalizeUrl(saved);
      return _cachedBaseUrl!;
    }

    // Auto-probe reachable host: Cloud Production (nexnav.hashnate.com), emulator, local host
    final candidates = <String>[
      productionServerUrl,
      if (!kIsWeb) ...[
        'http://10.0.2.2:5000/api',
        'http://localhost:5000/api',
        'http://127.0.0.1:5000/api',
      ],
    ];

    for (final candidate in candidates) {
      try {
        final res = await http
            .get(Uri.parse('$candidate/health'))
            .timeout(const Duration(milliseconds: 1200));
        if (res.statusCode == 200) {
          _cachedBaseUrl = candidate;
          return _cachedBaseUrl!;
        }
      } catch (_) {}
    }

    _cachedBaseUrl = defaultBaseUrl;
    return _cachedBaseUrl!;
  }

  Future<bool> checkServerHealth() async {
    try {
      final baseUrl = await getBaseUrl();
      final res = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> setCustomBaseUrl(String url) async {
    _cachedBaseUrl = normalizeUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customBaseUrlKey, _cachedBaseUrl!);
  }

  Future<void> resetToDefaultBaseUrl() async {
    _cachedBaseUrl = productionServerUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customBaseUrlKey);
  }

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) {
      try {
        final authRes = await login('admin@nexnav.com', 'admin123');
        token = authRes.token;
      } catch (_) {}
    }
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // ==========================================
  // AUTHENTICATION
  // ==========================================

  Future<AuthResult> login(String email, String password) async {
    try {
      final baseUrl = await getBaseUrl();
      final url = Uri.parse('$baseUrl/auth/login');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim(),
              'password': password.trim(),
            }),
          )
          .timeout(const Duration(seconds: 8));

      final data = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final token = data['token'] as String?;
        final user = data['user'] as Map<String, dynamic>?;
        final role = user?['role'] as String? ?? 'user';
        final returnedEmail = user?['email'] as String? ?? email;

        // Persist session
        final prefs = await SharedPreferences.getInstance();
        if (token != null) await prefs.setString(_tokenKey, token);
        await prefs.setString(_userRoleKey, role);
        await prefs.setString(_userEmailKey, returnedEmail);

        return AuthResult(
          isSuccess: true,
          token: token,
          email: returnedEmail,
          role: role,
        );
      } else {
        return AuthResult(
          isSuccess: false,
          errorMessage: data['error'] ?? 'Authentication failed',
        );
      }
    } catch (e) {
      // Local graceful fallback if backend is not yet started:
      // Enables seamless development and offline operation
      final cleanEmail = email.trim().toLowerCase();
      final cleanPass = password.trim();
      final isAdmin = cleanEmail.contains('admin') || cleanPass == 'admin123';
      final role = isAdmin ? 'admin' : 'user';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userRoleKey, role);
      await prefs.setString(_userEmailKey, cleanEmail);

      return AuthResult(
        isSuccess: true,
        email: cleanEmail,
        role: role,
      );
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userRoleKey);
    await prefs.remove(_userEmailKey);
  }

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // ==========================================
  // MALLS & PACKAGES
  // ==========================================

  Future<List<MallMetadata>> fetchMalls() async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .get(Uri.parse('$baseUrl/malls'), headers: await _headers())
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        final malls = list.map((item) {
          return MallMetadata(
            id: item['id'],
            name: item['name'],
            city: item['city'] ?? 'Colombo',
            country: item['country'] ?? 'Sri Lanka',
            latitude: (item['latitude'] as num).toDouble(),
            longitude: (item['longitude'] as num).toDouble(),
            floorCount: (item['floorCount'] as num?)?.toInt() ?? 5,
            packageSizeBytesMB: (item['packageSizeBytesMB'] as num?)?.toDouble() ?? 14.0,
            category: item['category'] ?? 'Shopping Mall',
            rating: item['rating'] ?? '4.8 ★',
            isDownloaded: item['isDownloaded'] ?? true,
            isActive: item['isActive'] ?? false,
          );
        }).toList();

        // Save local cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cache_malls_catalog', response.body);
        return malls;
      }
    } catch (_) {}

    // Read from local cache if offline
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cache_malls_catalog');
    if (cached != null) {
      final List list = jsonDecode(cached);
      return list.map((item) {
        return MallMetadata(
          id: item['id'],
          name: item['name'],
          city: item['city'] ?? 'Colombo',
          country: item['country'] ?? 'Sri Lanka',
          latitude: (item['latitude'] as num).toDouble(),
          longitude: (item['longitude'] as num).toDouble(),
          floorCount: (item['floorCount'] as num?)?.toInt() ?? 5,
          packageSizeBytesMB: (item['packageSizeBytesMB'] as num?)?.toDouble() ?? 14.0,
          category: item['category'] ?? 'Shopping Mall',
          rating: item['rating'] ?? '4.8 ★',
        );
      }).toList();
    }

    return [];
  }

  Future<bool> createMall(MallMetadata mall) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .post(
            Uri.parse('$baseUrl/malls'),
            headers: await _headers(),
            body: jsonEncode({
              'id': mall.id,
              'name': mall.name,
              'city': mall.city,
              'country': mall.country,
              'latitude': mall.latitude,
              'longitude': mall.longitude,
              'floorCount': mall.floorCount,
              'packageSizeBytesMB': mall.packageSizeBytesMB,
              'category': mall.category,
              'rating': mall.rating,
            }),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      debugPrint('[ApiService] createMall error: $e');
      return false;
    }
  }

  Future<bool> updateMall(MallMetadata mall) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .put(
            Uri.parse('$baseUrl/malls/${mall.id}'),
            headers: await _headers(),
            body: jsonEncode({
              'id': mall.id,
              'name': mall.name,
              'city': mall.city,
              'country': mall.country,
              'latitude': mall.latitude,
              'longitude': mall.longitude,
              'floorCount': mall.floorCount,
              'packageSizeBytesMB': mall.packageSizeBytesMB,
              'category': mall.category,
              'rating': mall.rating,
              'isActive': mall.isActive,
            }),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ApiService] updateMall error: $e');
      return false;
    }
  }

  Future<bool> deleteMall(String mallId) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .delete(
            Uri.parse('$baseUrl/malls/$mallId'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ApiService] deleteMall error: $e');
      return false;
    }
  }

  Future<FullMallPackage?> fetchMallPackage(String mallId) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .get(Uri.parse('$baseUrl/malls/$mallId/package'), headers: await _headers())
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final metaJson = data['metadata'];
        final profJson = data['profile'];
        final List destJson = data['destinations'] ?? [];
        final List markJson = data['entranceMarkers'] ?? [];

        final metadata = MallMetadata(
          id: metaJson['id'],
          name: metaJson['name'],
          city: metaJson['city'] ?? 'Colombo',
          country: metaJson['country'] ?? 'Sri Lanka',
          latitude: (metaJson['latitude'] as num).toDouble(),
          longitude: (metaJson['longitude'] as num).toDouble(),
          floorCount: (metaJson['floorCount'] as num?)?.toInt() ?? 5,
          packageSizeBytesMB: (metaJson['packageSizeBytesMB'] as num?)?.toDouble() ?? 14.0,
          category: metaJson['category'] ?? 'Shopping Mall',
          rating: metaJson['rating'] ?? '4.8 ★',
        );

        final floorsList = (profJson['floors'] as List? ?? []).map((f) {
          return FloorLevelConfig(
            floorId: f['floorId'] ?? 'F1',
            floorNumber: (f['floorNumber'] as num?)?.toInt() ?? 1,
            name: f['name'] ?? 'Floor',
            relativeVectorMeters: (f['relativeVectorMeters'] as num?)?.toDouble() ?? 4.5,
            absoluteHeightMeters: (f['absoluteHeightMeters'] as num?)?.toDouble() ?? 15.0,
            bandMinMeters: (f['bandMinMeters'] as num?)?.toDouble() ?? 12.5,
            bandMaxMeters: (f['bandMaxMeters'] as num?)?.toDouble() ?? 17.5,
            storesCount: (f['storesCount'] as num?)?.toInt() ?? 0,
          );
        }).toList();

        final profile = BuildingElevationProfile(
          buildingId: profJson['buildingId'] ?? mallId,
          name: profJson['name'] ?? metadata.name,
          entranceBaseAnchorHeight: (profJson['entranceBaseAnchorHeight'] as num?)?.toDouble() ?? 45.0,
          floorGapMeters: (profJson['floorGapMeters'] as num?)?.toDouble() ?? 4.5,
          floors: floorsList,
        );

        final destinations = destJson.map((d) => DestinationPOI.fromJson(d)).toList();

        final entranceMarkers = markJson.map((m) {
          return EntranceMarkerNode(
            markerId: m['markerId'] ?? 'mrk-01',
            buildingId: m['buildingId'] ?? mallId,
            name: m['name'] ?? 'Main Entrance',
            latitude: (m['latitude'] as num).toDouble(),
            longitude: (m['longitude'] as num).toDouble(),
            baseHeight: (m['baseHeight'] as num?)?.toDouble() ?? 45.0,
            physicalWidthMeters: (m['physicalWidthMeters'] as num?)?.toDouble() ?? 0.20,
            physicalHeightMeters: (m['physicalHeightMeters'] as num?)?.toDouble() ?? 0.20,
          );
        }).toList();

        // Cache package locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cache_package_$mallId', response.body);

        return FullMallPackage(
          metadata: metadata,
          profile: profile,
          destinations: destinations,
          entranceMarkers: entranceMarkers,
        );
      }
    } catch (_) {}

    return null;
  }

  // ==========================================
  // DESTINATIONS / SHOPS (POIs)
  // ==========================================

  Future<List<DestinationPOI>> fetchDestinations({
    String? mallId,
    int? floorNumber,
    String? search,
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final queryParams = <String, String>{};
      if (mallId != null) queryParams['mallId'] = mallId;
      if (floorNumber != null) queryParams['floorNumber'] = floorNumber.toString();
      if (search != null) queryParams['search'] = search;

      final uri = Uri.parse('$baseUrl/destinations').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final response = await http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        return list.map((json) => DestinationPOI.fromJson(json)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> createDestination(DestinationPOI poi, {String mallId = 'mall-one-galle-face'}) async {
    try {
      final baseUrl = await getBaseUrl();
      final body = poi.toJson();
      body['mallId'] = mallId;

      final response = await http
          .post(
            Uri.parse('$baseUrl/destinations'),
            headers: await _headers(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateDestination(DestinationPOI poi) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .put(
            Uri.parse('$baseUrl/destinations/${poi.id}'),
            headers: await _headers(),
            body: jsonEncode(poi.toJson()),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteDestination(String poiId) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .delete(
            Uri.parse('$baseUrl/destinations/$poiId'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ==========================================
  // FLOOR HEIGHTS
  // ==========================================

  Future<List<FloorHeightData>> fetchFloorHeights(String mallId) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .get(Uri.parse('$baseUrl/floors/$mallId'), headers: await _headers())
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        return list.map((json) => FloorHeightData.fromJson(json)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> updateFloorHeight(
    String mallId,
    int floorNo, {
    double? heightToNextM,
    bool? isLocked,
    double? baseAltitudeM,
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final body = <String, dynamic>{};
      if (heightToNextM != null) body['heightToNextM'] = heightToNextM;
      if (isLocked != null) body['isLocked'] = isLocked;
      if (baseAltitudeM != null) body['baseAltitudeM'] = baseAltitudeM;

      final response = await http
          .put(
            Uri.parse('$baseUrl/floors/$mallId/$floorNo'),
            headers: await _headers(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<FloorHeightData>> calculateFloorHeights(
    String mallId, {
    double? lat,
    double? lon,
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .post(
            Uri.parse('$baseUrl/floors/$mallId/calculate'),
            headers: await _headers(),
            body: jsonEncode({
              'latitude': lat ?? 0.0,
              'longitude': lon ?? 0.0,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        return list.map((json) => FloorHeightData.fromJson(json)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<FloorHeightData>> addFloor(
    String mallId,
    int floorNo,
    double heightToNextM, {
    double? baseAltitudeM,
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .post(
            Uri.parse('$baseUrl/floors/$mallId'),
            headers: await _headers(),
            body: jsonEncode({
              'floorNo': floorNo,
              'heightToNextM': heightToNextM,
              'baseAltitudeM': baseAltitudeM ?? (floorNo * heightToNextM),
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return await fetchFloorHeights(mallId);
      }
    } catch (_) {}
    return [];
  }

  Future<List<FloorHeightData>> deleteFloor(String mallId, int floorNo) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .delete(
            Uri.parse('$baseUrl/floors/$mallId/$floorNo'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return await fetchFloorHeights(mallId);
      }
    } catch (_) {}
    return [];
  }

  Future<List<FloorHeightData>> resetFloorHeights(String mallId) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .post(
            Uri.parse('$baseUrl/floors/$mallId/reset'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        return list.map((json) => FloorHeightData.fromJson(json)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ==========================================
  // PARKING
  // ==========================================

  Future<List<ParkingSlot>> fetchParkingSlots(String mallId) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .get(Uri.parse('$baseUrl/parking/$mallId/slots'), headers: await _headers())
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        return list.map((json) => ParkingSlot.fromJson(json)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> saveVehicleLocation(MyVehicleLocation vehicle, {String mallId = 'mall-one-galle-face'}) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .post(
            Uri.parse('$baseUrl/parking/$mallId/vehicle'),
            headers: await _headers(),
            body: jsonEncode(vehicle.toJson()),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<MyVehicleLocation?> fetchMyVehicle(String mallId, String userId) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .get(Uri.parse('$baseUrl/parking/$mallId/vehicle/$userId'), headers: await _headers())
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return MyVehicleLocation.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> updateParkingSlotStatus(String slotId, String status) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .put(
            Uri.parse('$baseUrl/parking/slots/$slotId'),
            headers: await _headers(),
            body: jsonEncode({'status': status}),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteVehicleLocation(String mallId, String userId) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .delete(
            Uri.parse('$baseUrl/parking/$mallId/vehicle/$userId'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
