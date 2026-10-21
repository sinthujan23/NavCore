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

  DestinationPOI copyWith({
    String? id,
    String? name,
    String? category,
    int? floorNumber,
    double? rating,
    GeodeticCoords? location,
    String? description,
    String? openStatus,
    String? openingHours,
    String? imageUrl,
    String? mallId,
  }) {
    return DestinationPOI(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      floorNumber: floorNumber ?? this.floorNumber,
      rating: rating ?? this.rating,
      location: location ?? this.location,
      description: description ?? this.description,
      openStatus: openStatus ?? this.openStatus,
      openingHours: openingHours ?? this.openingHours,
      imageUrl: imageUrl ?? this.imageUrl,
      mallId: mallId ?? this.mallId,
    );
  }

  double get latitude => location.latitude;
  double get longitude => location.longitude;

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
      floorNumber:
          (json['floorNumber'] ?? json['floor_number'] as num?)?.toInt() ?? 1,
      rating: (json['rating'] as num?)?.toDouble() ?? 4.8,
      location: GeodeticCoords(
        latitude:
            (json['latitude'] ?? json['location']?['latitude'] as num?)
                ?.toDouble() ??
            0.0,
        longitude:
            (json['longitude'] ?? json['location']?['longitude'] as num?)
                ?.toDouble() ??
            0.0,
        height:
            (json['height'] ?? json['location']?['height'] as num?)
                ?.toDouble() ??
            0.0,
      ),
      description: json['description'] as String? ?? '',
      openStatus:
          json['openStatus'] ?? json['open_status'] as String? ?? 'Open Now',
      openingHours: json['openingHours'] ?? json['opening_hours'] as String?,
      imageUrl: json['imageUrl'] ?? json['image_url'] as String?,
      mallId: json['mallId'] as String?,
    );
  }

  /// Image URL from database. Returns intelligent category/name match if not specified.
  String get effectiveImageUrl {
    if (imageUrl != null) {
      final clean = imageUrl!.trim();
      if (clean.isNotEmpty &&
          clean != 'null' &&
          clean != 'undefined' &&
          clean != 'none') {
        return clean;
      }
    }
    return _resolveFallbackImage();
  }

  String _resolveFallbackImage() {
    final n = name.toLowerCase();
    final c = category.toUpperCase();

    if (n.contains('dress') ||
        n.contains('cloth') ||
        n.contains('fashion') ||
        n.contains('zara') ||
        n.contains('shopy') ||
        n.contains('zeero') ||
        c.contains('FASHION') ||
        c.contains('RETAIL')) {
      if (n.contains('dress')) {
        return 'assets/images/shops/kelly_felder_designer_lounge.jpg';
      }
      if (n.contains('cotton')) {
        return 'assets/images/shops/cotton_collection.jpg';
      }
      return 'assets/images/shops/odel_flagship_store.jpg';
    }
    if (n.contains('com') ||
        n.contains('hard') ||
        n.contains('tech') ||
        n.contains('apple') ||
        n.contains('phone') ||
        n.contains('mobile') ||
        c.contains('TECH') ||
        c.contains('ELECTRONICS')) {
      if (n.contains('apple') || n.contains('abans')) {
        return 'assets/images/shops/abans_elite_apple_lg_store.jpg';
      }
      return 'assets/images/shops/samsung_smart_experience_zone.jpg';
    }
    if (n.contains('coffee') ||
        n.contains('cafe') ||
        n.contains('tea') ||
        n.contains('pizza') ||
        n.contains('food') ||
        n.contains('burger') ||
        n.contains('bar') ||
        n.contains('pub') ||
        n.contains('lounge') ||
        c.contains('FOOD') ||
        c.contains('DRINK')) {
      if (n.contains('tea') || n.contains('dilmah') || n.contains('bar') || n.contains('lounge')) {
        return 'assets/images/shops/dilmah_tea_lounge.jpg';
      }
      if (n.contains('coffee') || n.contains('barista') || n.contains('coffe')) {
        return 'assets/images/shops/barista_ceylon_espresso_bar.jpg';
      }
      if (n.contains('taco') || n.contains('bell')) {
        return 'assets/images/shops/taco_bell_sri_lanka.jpg';
      }
      return 'assets/images/shops/food_studio_ceylon_court.jpg';
    }
    if (n.contains('cinema') ||
        n.contains('movie') ||
        n.contains('game') ||
        c.contains('ENTERTAINMENT')) {
      return 'assets/images/shops/pvr_scope_cinemas_imax.jpg';
    }
    if (n.contains('car') ||
        n.contains('wash') ||
        n.contains('park') ||
        n.contains('valet')) {
      return 'assets/images/shops/b1_auto_car_wash.jpg';
    }
    if (n.contains('super') || n.contains('keells') || n.contains('mart')) {
      return 'assets/images/shops/keells_super_hypermarket.jpg';
    }
    if (n.contains('spa') || n.contains('ayurveda')) {
      return 'assets/images/shops/spa_ceylon_luxury_ayurveda.jpg';
    }
    return 'assets/images/shops/odel_flagship_store.jpg';
  }

  /// Clean status text without time details (e.g. "Open" or "Closed")
  String get statusOnly {
    final raw = openStatus.trim();
    if (raw.isEmpty) return 'Open';
    final lower = raw.toLowerCase();
    if (lower.contains('closed') || lower.contains('close')) {
      return 'Closed';
    }
    if (lower.contains('open')) {
      return 'Open';
    }
    if (raw.contains(':')) {
      final prefix = raw.split(':')[0].trim();
      if (prefix.isNotEmpty) return prefix;
    }
    return raw;
  }

  /// Whether the destination is currently open
  bool get isOpen => !statusOnly.toLowerCase().contains('close');

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
