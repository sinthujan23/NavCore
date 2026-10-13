import '../engine/ecef_engine.dart';

class DestinationPOI {
  final String id;
  final String name;
  final String category;
  final int floorNumber;
  final double rating;
  final GeodeticCoords location;
  final String description;
  final String openStatus;
  final String? openingHours;
  final String? imageUrl;
  final String? mallId;

  const DestinationPOI({
    required this.id,
    required this.name,
    required this.category,
    required this.floorNumber,
    required this.rating,
    required this.location,
    required this.description,
    required this.openStatus,
    this.openingHours,
    this.imageUrl,
    this.mallId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'floorNumber': floorNumber,
        'rating': rating,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'height': location.height,
        'description': description,
        'openStatus': openStatus,
        'openingHours': openingHours,
        'imageUrl': imageUrl,
        'mallId': mallId,
      };

  factory DestinationPOI.fromJson(Map<String, dynamic> json) {
    return DestinationPOI(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? 'SERVICES',
      floorNumber: (json['floorNumber'] ?? json['floor_number'] as num?)?.toInt() ?? 1,
      rating: (json['rating'] as num?)?.toDouble() ?? 4.8,
      location: GeodeticCoords(
        latitude: (json['latitude'] ?? json['location']?['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (json['longitude'] ?? json['location']?['longitude'] as num?)?.toDouble() ?? 0.0,
        height: (json['height'] ?? json['location']?['height'] as num?)?.toDouble() ?? 0.0,
      ),
      description: json['description'] as String? ?? '',
      openStatus: json['openStatus'] ?? json['open_status'] as String? ?? 'Open Now',
      openingHours: json['openingHours'] ?? json['opening_hours'] as String?,
      imageUrl: json['imageUrl'] ?? json['image_url'] as String?,
      mallId: json['mallId'] as String?,
    );
  }

  /// Image URL from database. Returns empty string if not provided in database.
  String get effectiveImageUrl {
    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      return imageUrl!;
    }
    return '';
  }

  /// Opening hours from database. Returns openStatus or default if not specified.
  String get effectiveOpeningHours {
    if (openingHours != null && openingHours!.trim().isNotEmpty) {
      return openingHours!;
    }
    if (openStatus.trim().isNotEmpty) {
      return openStatus;
    }
    return 'Hours not specified';
  }
}

/// Neutral initial reference coordinates (re-anchored to live user GPS)
const entranceAnchor = GeodeticCoords(
  latitude: 0.0,
  longitude: 0.0,
  height: 0.0,
);


