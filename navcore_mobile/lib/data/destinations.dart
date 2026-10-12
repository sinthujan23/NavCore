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

  /// Helper to return a guaranteed high-quality suitable image URL for the shop
  String get effectiveImageUrl {
    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      return imageUrl!;
    }
    return getFallbackShopImage(name, category);
  }

  /// Helper to return realistic opening hours (e.g. "10:00 AM - 10:00 PM")
  String get effectiveOpeningHours {
    if (openingHours != null && openingHours!.trim().isNotEmpty) {
      return openingHours!;
    }
    final n = name.toLowerCase();
    final c = category.toLowerCase();
    if (openStatus == '24/7' || n.contains('ev') || n.contains('locker') || n.contains('concierge') || n.contains('valet')) {
      return '24 Hours Open';
    }
    if (n.contains('keells') || n.contains('supermarket')) {
      return '08:00 AM - 10:00 PM';
    }
    if (c.contains('food') || n.contains('coffee') || n.contains('tea') || n.contains('barista') || n.contains('dilmah')) {
      return '08:30 AM - 11:00 PM';
    }
    if (n.contains('cinema') || n.contains('pvr') || n.contains('imax')) {
      return '10:00 AM - 11:30 PM';
    }
    return '10:00 AM - 10:00 PM';
  }
}

/// Dynamic fallback resolver based on shop category and keywords
String getFallbackShopImage(String name, String category) {
  final n = name.toLowerCase();
  final c = category.toLowerCase();

  if (n.contains('coffee') || n.contains('barista') || n.contains('espresso')) {
    return 'assets/images/shops/barista_ceylon_espresso_bar.jpg';
  }
  if (n.contains('tea') || n.contains('dilmah')) {
    return 'assets/images/shops/dilmah_tea_lounge.jpg';
  }
  if (n.contains('crab') || n.contains('seafood')) {
    return 'assets/images/shops/ministry_of_crab_express.jpg';
  }
  if (n.contains('taco') || n.contains('burrito') || n.contains('mexican')) {
    return 'assets/images/shops/taco_bell_sri_lanka.jpg';
  }
  if (c.contains('food') || n.contains('food') || n.contains('dining') || n.contains('court')) {
    return 'assets/images/shops/food_studio_ceylon_court.jpg';
  }
  if (n.contains('cinema') || n.contains('imax') || n.contains('pvr') || c.contains('entertainment')) {
    return 'assets/images/shops/pvr_scope_cinemas_imax.jpg';
  }
  if (n.contains('apple') || n.contains('abans')) {
    return 'assets/images/shops/abans_elite_apple_lg_store.jpg';
  }
  if (n.contains('samsung')) {
    return 'assets/images/shops/samsung_smart_experience_zone.jpg';
  }
  if (n.contains('singer')) {
    return 'assets/images/shops/singer_mega_experience_center.jpg';
  }
  if (n.contains('dialog')) {
    return 'assets/images/shops/dialog_axiata_experience_centre.jpg';
  }
  if (n.contains('mobitel')) {
    return 'assets/images/shops/mobitel_slt_broadband_lounge.jpg';
  }
  if (n.contains('odel')) {
    return 'assets/images/shops/odel_flagship_store.jpg';
  }
  if (n.contains('hugo')) {
    return 'assets/images/shops/hugo_boss_luxury_apparel.jpg';
  }
  if (n.contains('cotton')) {
    return 'assets/images/shops/cotton_collection.jpg';
  }
  if (n.contains('kelly')) {
    return 'assets/images/shops/kelly_felder_designer_lounge.jpg';
  }
  if (n.contains('barefoot')) {
    return 'assets/images/shops/barefoot_ceylon_handwoven.jpg';
  }
  if (n.contains('house of fashion') || n.contains('fashion')) {
    return 'assets/images/shops/house_of_fashion_outlet.jpg';
  }
  if (n.contains('supermarket') || n.contains('hypermarket') || n.contains('keells')) {
    return 'assets/images/shops/keells_super_hypermarket.jpg';
  }
  if (n.contains('spa') || n.contains('ayurveda')) {
    return 'assets/images/shops/spa_ceylon_luxury_ayurveda.jpg';
  }
  if (n.contains('ev') || n.contains('charging')) {
    return 'assets/images/shops/b1_eco_ev_charging_hub.jpg';
  }
  if (n.contains('wash') || n.contains('car')) {
    return 'assets/images/shops/b1_auto_car_wash.jpg';
  }
  if (n.contains('valet') || n.contains('concierge') || n.contains('info')) {
    return 'assets/images/shops/concierge_information_desk.jpg';
  }
  if (n.contains('lockers')) {
    return 'assets/images/shops/b1_luggage_lockers.jpg';
  }

  return 'assets/images/shops/odel_flagship_store.jpg';
}

/// Neutral initial reference coordinates (re-anchored to live user GPS)
const entranceAnchor = GeodeticCoords(
  latitude: 0.0,
  longitude: 0.0,
  height: 0.0,
);

final List<DestinationPOI> mockDestinations = <DestinationPOI>[];

