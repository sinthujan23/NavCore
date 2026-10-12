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
    this.floorGap = 4.5,
    this.floorCount = 5,
    this.venueType = 'Shopping & Retail Complex',
  });
}

class GeocodingService {
  /// Reverse geocodes coordinates to real venue details using free OpenStreetMap Nominatim.
  /// Automatically resolves Place Name, City, Country, Venue ID, calibrated ground altitude,
  /// and calculates real architectural floor gaps based on the location and building taxonomy.
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

        // ------------------------------------------------------------------
        // Dynamic Floor Gap Calculation based on Location & Architectural Taxonomy
        // ------------------------------------------------------------------
        double calculatedFloorGap = 4.5;
        int calculatedFloorCount = 5;
        String venueType = 'Commercial Complex';

        // 1. Direct OpenStreetMap architectural tags if available
        if (extratags['height'] != null && extratags['building:levels'] != null) {
          final rawH = double.tryParse(
              extratags['height'].toString().replaceAll(RegExp(r'[^0-9.]'), ''));
          final rawL = int.tryParse(
              extratags['building:levels'].toString().replaceAll(RegExp(r'[^0-9]'), ''));
          if (rawH != null && rawL != null && rawL > 0 && rawH > rawL) {
            calculatedFloorGap = double.parse((rawH / rawL).toStringAsFixed(1));
            calculatedFloorCount = rawL.clamp(1, 10);
          }
        } else if (extratags['building:levels'] != null) {
          final rawL = int.tryParse(
              extratags['building:levels'].toString().replaceAll(RegExp(r'[^0-9]'), ''));
          if (rawL != null && rawL > 0) {
            calculatedFloorCount = rawL.clamp(1, 10);
          }
        }

        // 2. Architectural inference from venue place metadata & categories
        final suburb = (address['suburb'] ?? '').toString();
        final placeLower =
            '$placeName $suburb $city ${data['category'] ?? ''} ${data['type'] ?? ''}'
                .toLowerCase();

        if (placeLower.contains('airport') ||
            placeLower.contains('terminal') ||
            placeLower.contains('station')) {
          calculatedFloorGap = 5.5;
          calculatedFloorCount = 4;
          venueType = 'Transit Hub / Concourse';
        } else if (placeLower.contains('mall') ||
            placeLower.contains('atrium') ||
            placeLower.contains('galleria') ||
            placeLower.contains('plaza')) {
          calculatedFloorGap = 4.8;
          calculatedFloorCount = 5;
          venueType = 'Premier Retail Mall';
        } else if (placeLower.contains('supermarket') ||
            placeLower.contains('store') ||
            placeLower.contains('market') ||
            placeLower.contains('bazaar')) {
          calculatedFloorGap = 4.2;
          calculatedFloorCount = 3;
          venueType = 'Commercial Marketplace';
        } else if (placeLower.contains('tower') ||
            placeLower.contains('office') ||
            placeLower.contains('corporate') ||
            placeLower.contains('tech')) {
          calculatedFloorGap = 3.8;
          calculatedFloorCount = 7;
          venueType = 'Corporate Office Tower';
        } else if (placeLower.contains('park') || placeLower.contains('garage')) {
          calculatedFloorGap = 3.2;
          calculatedFloorCount = 4;
          venueType = 'Multi-Level Structure';
        } else {
          // Standard regional architectural standards
          if ((latitude - 6.927).abs() < 0.20 && (longitude - 79.86).abs() < 0.20) {
            calculatedFloorGap = 4.8;
            calculatedFloorCount = 5;
            venueType = 'Urban Retail Complex';
          } else if ((latitude - 8.58).abs() < 0.25 &&
              (longitude - 81.22).abs() < 0.25) {
            calculatedFloorGap = 4.5;
            calculatedFloorCount = 4;
            venueType = 'Coastal Commercial Center';
          } else {
            calculatedFloorGap = 4.5;
            calculatedFloorCount = 5;
            venueType = 'Shopping & Retail Complex';
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

    // Offline / Network Fallback based on coordinate proximities
    return _fallbackGeocode(latitude, longitude, calibratedAlt);
  }

  static ReverseGeocodeResult _fallbackGeocode(
    double lat,
    double lon,
    double calibratedAlt,
  ) {
    String city = 'Local City';
    String country = 'Sri Lanka';
    double fallbackFloorGap = 4.5;
    int fallbackFloorCount = 5;
    String fallbackVenueType = 'Commercial Mall';

    // Sri Lanka regions
    if ((lat - 8.58).abs() < 0.35 && (lon - 81.22).abs() < 0.35) {
      city = 'Trincomalee';
      fallbackFloorGap = 4.5;
      fallbackFloorCount = 4;
      fallbackVenueType = 'Coastal Commercial Center';
    } else if ((lat - 6.927).abs() < 0.25 && (lon - 79.86).abs() < 0.25) {
      city = 'Colombo';
      fallbackFloorGap = 4.8;
      fallbackFloorCount = 6;
      fallbackVenueType = 'Premier Shopping Mall';
    } else if ((lat - 7.29).abs() < 0.25 && (lon - 80.63).abs() < 0.25) {
      city = 'Kandy';
      fallbackFloorGap = 4.5;
      fallbackFloorCount = 5;
      fallbackVenueType = 'Multi-Tier Mall';
    } else if ((lat - 6.05).abs() < 0.25 && (lon - 80.21).abs() < 0.25) {
      city = 'Galle';
      fallbackFloorGap = 4.2;
      fallbackFloorCount = 3;
      fallbackVenueType = 'Historic Commercial Center';
    } else if ((lat - 9.66).abs() < 0.25 && (lon - 80.01).abs() < 0.25) {
      city = 'Jaffna';
      fallbackFloorGap = 4.2;
      fallbackFloorCount = 4;
      fallbackVenueType = 'Regional Commercial Mall';
    } else {
      city = 'Trincomalee';
      fallbackFloorGap = 4.5;
      fallbackFloorCount = 5;
      fallbackVenueType = 'Indoor Navigation Complex';
    }

    return ReverseGeocodeResult(
      placeName: '',
      city: city,
      country: country,
      suggestedVenueId: '',
      latitude: lat,
      longitude: lon,
      groundAltitude: calibratedAlt,
      floorGap: fallbackFloorGap,
      floorCount: fallbackFloorCount,
      venueType: fallbackVenueType,
    );
  }
}
