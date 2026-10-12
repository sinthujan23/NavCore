import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ReverseGeocodeResult {
  final String placeName;
  final String city;
  final String country;
  final String suggestedVenueId;
  final double latitude;
  final double longitude;
  final double groundAltitude;
  final double floorGap;
  final int floorCount;
  final String venueType;

  const ReverseGeocodeResult({
    required this.placeName,
    required this.city,
    required this.country,
    required this.suggestedVenueId,
    required this.latitude,
    required this.longitude,
    required this.groundAltitude,
    this.floorGap = 0.0,
    this.floorCount = 0,
    this.venueType = 'Indoor Venue',
  });
}

class GeocodingService {
  /// Reverse geocodes coordinates to real venue details using free OpenStreetMap Nominatim.
  /// Automatically resolves Place Name, City, Country, Venue ID, and calibrated ground altitude.
  /// Floor counts and floor gaps are NOT fabricated and remain 0 unless explicitly configured.
  static Future<ReverseGeocodeResult> reverseGeocode(
    double latitude,
    double longitude, {
    double? rawAltitude,
  }) async {
    // Calibrate altitude: GPS ellipsoidal height in low-geoid areas can be negative (e.g. -84m in Indian Ocean).
    // In building indoor coordinates, base ground floor elevation is normalized to 0.0m or real MSL.
    double calibratedAlt = 0.0;
    if (rawAltitude != null && rawAltitude > 0.0 && rawAltitude < 4000.0) {
      calibratedAlt = double.parse(rawAltitude.toStringAsFixed(1));
    }

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$latitude&lon=$longitude&zoom=18&addressdetails=1&extratags=1',
      );

      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'NexNavSpatialNavigator/1.0 (contact@nexnav.app)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final Map<String, dynamic> address =
            data['address'] as Map<String, dynamic>? ?? {};
        final Map<String, dynamic> extratags =
            data['extratags'] as Map<String, dynamic>? ?? {};

        final country = (address['country'] as String?)?.trim() ?? 'Sri Lanka';
        final rawCity = (address['town'] ??
                address['city'] ??
                address['municipality'] ??
                address['suburb'] ??
                address['city_district'] ??
                address['county'] ??
                address['state_district'] ??
                address['state'] ??
                'Trincomalee')
            .toString()
            .trim();
        final city = rawCity
            .replaceAll(RegExp(r'\s+(District|Division|Province|Council)', caseSensitive: false), '')
            .trim();

        // Check ONLY actual named commercial / mall / retail establishments (NEVER a road)
        final namedBuilding = (address['mall'] ??
                address['department_store'] ??
                address['supermarket'] ??
                address['shopping_centre'] ??
                address['retail'] ??
                address['commercial'] ??
                address['building'] ??
                address['shop'] ??
                address['amenity'] ??
                '')
            .toString()
            .trim();

        String placeName = '';
        if (namedBuilding.isNotEmpty &&
            namedBuilding.toLowerCase() != 'yes' &&
            namedBuilding.toLowerCase() != 'no' &&
            namedBuilding.toLowerCase() != 'building' &&
            namedBuilding.toLowerCase() != 'commercial') {
          placeName = namedBuilding;
        }

        final cleanSlug = placeName
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-|-$'), '');
        final suggestedId = cleanSlug.isNotEmpty ? 'mall-$cleanSlug' : '';

        // Only parse real architectural tags if explicitly available in OSM
        double calculatedFloorGap = 0.0;
        int calculatedFloorCount = 0;
        String venueType = 'Indoor Venue';

        if (extratags['height'] != null && extratags['building:levels'] != null) {
          final rawH = double.tryParse(
              extratags['height'].toString().replaceAll(RegExp(r'[^0-9.]'), ''));
          final rawL = int.tryParse(
              extratags['building:levels'].toString().replaceAll(RegExp(r'[^0-9]'), ''));
          if (rawH != null && rawL != null && rawL > 0 && rawH > rawL) {
            calculatedFloorGap = double.parse((rawH / rawL).toStringAsFixed(1));
            calculatedFloorCount = rawL.clamp(0, 50);
          }
        } else if (extratags['building:levels'] != null) {
          final rawL = int.tryParse(
              extratags['building:levels'].toString().replaceAll(RegExp(r'[^0-9]'), ''));
          if (rawL != null && rawL > 0) {
            calculatedFloorCount = rawL.clamp(0, 50);
          }
        }

        return ReverseGeocodeResult(
          placeName: placeName,
          city: city,
          country: country,
          suggestedVenueId: suggestedId,
          latitude: latitude,
          longitude: longitude,
          groundAltitude: calibratedAlt,
          floorGap: calculatedFloorGap,
          floorCount: calculatedFloorCount,
          venueType: venueType,
        );
      }
    } catch (e) {
      debugPrint('[GeocodingService] Reverse geocode network fallback: $e');
    }

    // Offline / Network Fallback (does not add fake floors or gaps)
    return _fallbackGeocode(latitude, longitude, calibratedAlt);
  }

  static ReverseGeocodeResult _fallbackGeocode(
    double lat,
    double lon,
    double calibratedAlt,
  ) {
    String city = 'Local City';
    String country = 'Sri Lanka';

    // Sri Lanka regions for city name lookup only
    if ((lat - 8.58).abs() < 0.35 && (lon - 81.22).abs() < 0.35) {
      city = 'Trincomalee';
    } else if ((lat - 6.927).abs() < 0.25 && (lon - 79.86).abs() < 0.25) {
      city = 'Colombo';
    } else if ((lat - 7.29).abs() < 0.25 && (lon - 80.63).abs() < 0.25) {
      city = 'Kandy';
    } else if ((lat - 6.05).abs() < 0.25 && (lon - 80.21).abs() < 0.25) {
      city = 'Galle';
    } else if ((lat - 9.66).abs() < 0.25 && (lon - 80.01).abs() < 0.25) {
      city = 'Jaffna';
    } else {
      city = 'Trincomalee';
    }

    return ReverseGeocodeResult(
      placeName: '',
      city: city,
      country: country,
      suggestedVenueId: '',
      latitude: lat,
      longitude: lon,
      groundAltitude: calibratedAlt,
      floorGap: 0.0,
      floorCount: 0,
      venueType: 'Indoor Venue',
    );
  }
}
