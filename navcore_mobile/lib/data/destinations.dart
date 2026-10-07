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
  });

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

/// Entrance Anchor for One Galle Face Mall, Colombo, Sri Lanka
const entranceAnchor = GeodeticCoords(
  latitude: 6.927079,
  longitude: 79.845612,
  height: 45.0,
);

final mockDestinations = [
  // FLOOR -1 - Basement 1 Parking & Express Services (5 Items) - Height: 30.0m
  const DestinationPOI(
    id: 'poi-b1-01',
    name: 'B1 Executive Valet & Concierge',
    category: 'SERVICES',
    floorNumber: -1,
    rating: 4.9,
    location: GeodeticCoords(
      latitude: 6.927380,
      longitude: 79.845312,
      height: 30.0,
    ),
    description:
        'VIP valet drop-off, luggage storage, and premium parking concierge desk.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/b1_executive_valet_concierge.jpg',
  ),
  const DestinationPOI(
    id: 'poi-b1-02',
    name: 'Keells Express Supermarket B1',
    category: 'SERVICES',
    floorNumber: -1,
    rating: 4.8,
    location: GeodeticCoords(
      latitude: 6.927380,
      longitude: 79.845912,
      height: 30.0,
    ),
    description:
        'Express groceries, fresh takeaway snacks, cold beverages, and essentials.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/keells_express_supermarket_b1.jpg',
  ),
  const DestinationPOI(
    id: 'poi-b1-03',
    name: 'B1 Eco EV Fast-Charging Hub',
    category: 'TECH & ELECTRONICS',
    floorNumber: -1,
    rating: 4.9,
    location: GeodeticCoords(
      latitude: 6.926780,
      longitude: 79.845312,
      height: 30.0,
    ),
    description:
        'High-speed 120kW DC EV chargers for Tesla, Hyundai, Nissan & BYD vehicles.',
    openStatus: '24/7',
    imageUrl: 'assets/images/shops/b1_eco_ev_charging_hub.jpg',
  ),
  const DestinationPOI(
    id: 'poi-b1-04',
    name: 'B1 Auto Car Wash & Detailing',
    category: 'SERVICES',
    floorNumber: -1,
    rating: 4.7,
    location: GeodeticCoords(
      latitude: 6.926780,
      longitude: 79.845912,
      height: 30.0,
    ),
    description:
        'Eco-friendly waterless car wash, interior vacuuming & ceramic coating.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/b1_auto_car_wash.jpg',
  ),
  const DestinationPOI(
    id: 'poi-b1-05',
    name: 'B1 Luggage Lockers & Express Counter',
    category: 'SERVICES',
    floorNumber: -1,
    rating: 4.8,
    location: GeodeticCoords(
      latitude: 6.927480,
      longitude: 79.845612,
      height: 30.0,
    ),
    description:
        'Automated smart luggage lockers, parcel pickup, and courier services.',
    openStatus: '24/7',
    imageUrl: 'assets/images/shops/b1_luggage_lockers.jpg',
  ),

  // FLOOR 1 - Ground Floor & Ceylon Atrium (5 Items) - Height: 45.0m
  const DestinationPOI(
    id: 'poi-101',
    name: 'Odel Flagship Department Store',
    category: 'RETAIL & FASHION',
    floorNumber: 1,
    rating: 4.9,
    location: GeodeticCoords(
      latitude: 6.927430,
      longitude: 79.845612,
      height: 45.0,
    ),
    description: 'Premier Sri Lankan lifestyle, fashion & department store.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/odel_flagship_store.jpg',
  ),
  const DestinationPOI(
    id: 'poi-102',
    name: 'Concierge & Information Desk',
    category: 'SERVICES',
    floorNumber: 1,
    rating: 5.0,
    location: GeodeticCoords(
      latitude: 6.927330,
      longitude: 79.845862,
      height: 45.0,
    ),
    description:
        'Sri Lanka tourist assistance, mall guide & lost property services.',
    openStatus: '24/7',
    imageUrl: 'assets/images/shops/concierge_information_desk.jpg',
  ),
  const DestinationPOI(
    id: 'poi-103',
    name: 'Spa Ceylon Luxury Ayurveda',
    category: 'SERVICES',
    floorNumber: 1,
    rating: 4.9,
    location: GeodeticCoords(
      latitude: 6.927079,
      longitude: 79.845962,
      height: 45.0,
    ),
    description:
        'Royal Sri Lankan Ayurveda wellness, essential oils & skincare.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/spa_ceylon_luxury_ayurveda.jpg',
  ),
  const DestinationPOI(
    id: 'poi-104',
    name: 'Dilmah Tea Lounge & t-Bar',
    category: 'FOOD & DRINK',
    floorNumber: 1,
    rating: 4.8,
    location: GeodeticCoords(
      latitude: 6.926830,
      longitude: 79.845862,
      height: 45.0,
    ),
    description:
        'Handpicked single-origin Ceylon tea tasting, mocktails & high tea.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/dilmah_tea_lounge.jpg',
  ),
  const DestinationPOI(
    id: 'poi-105',
    name: 'Keells Super Hypermarket',
    category: 'SERVICES',
    floorNumber: 1,
    rating: 4.7,
    location: GeodeticCoords(
      latitude: 6.926730,
      longitude: 79.845612,
      height: 45.0,
    ),
    description:
        'Gourmet groceries, fresh Sri Lankan produce, bakery & spices.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/keells_super_hypermarket.jpg',
  ),

  // FLOOR 2 - Fashion & Apparel (5 Items) - Height: 60.0m
  const DestinationPOI(
    id: 'poi-201',
    name: 'Cotton Collection',
    category: 'RETAIL & FASHION',
    floorNumber: 2,
    rating: 4.6,
    location: GeodeticCoords(
      latitude: 6.926830,
      longitude: 79.845362,
      height: 60.0,
    ),
    description:
        'Casual island wear, linen garments, tropical resort fashion & accessories.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/cotton_collection.jpg',
  ),
  const DestinationPOI(
    id: 'poi-202',
    name: 'Kelly Felder Designer Lounge',
    category: 'RETAIL & FASHION',
    floorNumber: 2,
    rating: 4.8,
    location: GeodeticCoords(
      latitude: 6.927079,
      longitude: 79.845262,
      height: 60.0,
    ),
    description:
        'Chic Sri Lankan womenswear, evening attire, and designer handbags.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/kelly_felder_designer_lounge.jpg',
  ),
  const DestinationPOI(
    id: 'poi-203',
    name: 'House of Fashion Outlet',
    category: 'RETAIL & FASHION',
    floorNumber: 2,
    rating: 4.7,
    location: GeodeticCoords(
      latitude: 6.927330,
      longitude: 79.845362,
      height: 60.0,
    ),
    description:
        'Extensive selection of international trends and local Sri Lankan apparel.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/house_of_fashion_outlet.jpg',
  ),
  const DestinationPOI(
    id: 'poi-204',
    name: 'Barefoot Ceylon Handwoven Gallery',
    category: 'RETAIL & FASHION',
    floorNumber: 2,
    rating: 4.9,
    location: GeodeticCoords(
      latitude: 6.927480,
      longitude: 79.845612,
      height: 60.0,
    ),
    description:
        'Vibrant handwoven Sri Lankan textiles, books, toys, and artisanal crafts.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/barefoot_ceylon_handwoven.jpg',
  ),
  const DestinationPOI(
    id: 'poi-205',
    name: 'Hugo Boss & Luxury Apparel',
    category: 'RETAIL & FASHION',
    floorNumber: 2,
    rating: 4.8,
    location: GeodeticCoords(
      latitude: 6.927079,
      longitude: 79.846012,
      height: 60.0,
    ),
    description:
        'Premium luxury suits, formal wear, leather shoes & accessories.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/hugo_boss_luxury_apparel.jpg',
  ),

  // FLOOR 3 - Tech & Electronics Hub (5 Items) - Height: 75.0m
  const DestinationPOI(
    id: 'poi-301',
    name: 'Singer Mega Experience Center',
    category: 'TECH & ELECTRONICS',
    floorNumber: 3,
    rating: 4.8,
    location: GeodeticCoords(
      latitude: 6.927380,
      longitude: 79.845912,
      height: 75.0,
    ),
    description:
        'Smart TVs, home electronics, laptops, and consumer technology.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/singer_mega_experience_center.jpg',
  ),
  const DestinationPOI(
    id: 'poi-302',
    name: 'Abans Elite Apple & LG Store',
    category: 'TECH & ELECTRONICS',
    floorNumber: 3,
    rating: 4.9,
    location: GeodeticCoords(
      latitude: 6.926780,
      longitude: 79.845912,
      height: 75.0,
    ),
    description:
        'Authorized Apple products, iPhones, MacBooks, and LG smart devices.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/abans_elite_apple_lg_store.jpg',
  ),
  const DestinationPOI(
    id: 'poi-303',
    name: 'Dialog Axiata Experience Centre',
    category: 'TECH & ELECTRONICS',
    floorNumber: 3,
    rating: 4.8,
    location: GeodeticCoords(
      latitude: 6.926680,
      longitude: 79.845612,
      height: 75.0,
    ),
    description:
        '5G SIM connections, eSIM activation, fiber broadband & IoT gadgets.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/dialog_axiata_experience_centre.jpg',
  ),
  const DestinationPOI(
    id: 'poi-304',
    name: 'Mobitel & SLT Broadband Lounge',
    category: 'TECH & ELECTRONICS',
    floorNumber: 3,
    rating: 4.7,
    location: GeodeticCoords(
      latitude: 6.926780,
      longitude: 79.845312,
      height: 75.0,
    ),
    description:
        'National telecom service desk, fiber routers, and mobile accessories.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/mobitel_slt_broadband_lounge.jpg',
  ),
  const DestinationPOI(
    id: 'poi-305',
    name: 'Samsung Smart Experience Zone',
    category: 'TECH & ELECTRONICS',
    floorNumber: 3,
    rating: 4.9,
    location: GeodeticCoords(
      latitude: 6.927079,
      longitude: 79.845212,
      height: 75.0,
    ),
    description:
        'Galaxy smartphones, tablets, smartwatches & home appliance displays.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/samsung_smart_experience_zone.jpg',
  ),

  // FLOOR 4 - Food Court & Dining Layer (5 Items) - Height: 90.0m
  const DestinationPOI(
    id: 'poi-401',
    name: 'Food Studio Ceylon Court',
    category: 'FOOD & DRINK',
    floorNumber: 4,
    rating: 4.9,
    location: GeodeticCoords(
      latitude: 6.927380,
      longitude: 79.845312,
      height: 90.0,
    ),
    description:
        'Fresh Kottu Roti, Jaffna Crab Curry, Egg Hoppers & Ceylon street food.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/food_studio_ceylon_court.jpg',
  ),
  const DestinationPOI(
    id: 'poi-402',
    name: 'Ministry of Crab Express',
    category: 'FOOD & DRINK',
    floorNumber: 4,
    rating: 5.0,
    location: GeodeticCoords(
      latitude: 6.927530,
      longitude: 79.845612,
      height: 90.0,
    ),
    description:
        'World-renowned Sri Lankan giant lagoon crab & Garlic Chili Prawns.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/ministry_of_crab_express.jpg',
  ),
  const DestinationPOI(
    id: 'poi-403',
    name: 'Barista Ceylon Espresso Bar',
    category: 'FOOD & DRINK',
    floorNumber: 4,
    rating: 4.7,
    location: GeodeticCoords(
      latitude: 6.927380,
      longitude: 79.845962,
      height: 90.0,
    ),
    description:
        'Artisanal local coffees, iced lattes, fresh pastries, and savories.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/barista_ceylon_espresso_bar.jpg',
  ),
  const DestinationPOI(
    id: 'poi-404',
    name: 'Taco Bell Sri Lanka',
    category: 'FOOD & DRINK',
    floorNumber: 4,
    rating: 4.6,
    location: GeodeticCoords(
      latitude: 6.927079,
      longitude: 79.846062,
      height: 90.0,
    ),
    description:
        'Mexican inspired burritos, crunchy tacos, and spicy Sri Lankan sauces.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/taco_bell_sri_lanka.jpg',
  ),
  const DestinationPOI(
    id: 'poi-405',
    name: 'PVR / Scope Cinemas IMAX OGF',
    category: 'ENTERTAINMENT',
    floorNumber: 4,
    rating: 5.0,
    location: GeodeticCoords(
      latitude: 6.926680,
      longitude: 79.845962,
      height: 90.0,
    ),
    description:
        'Premium 3D IMAX screen, Dolby Atmos surround sound & luxury recliners.',
    openStatus: 'OPEN NOW',
    imageUrl: 'assets/images/shops/pvr_scope_cinemas_imax.jpg',
  ),
];
