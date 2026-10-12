const fs = require('fs');
const path = require('path');

const DATA_DIR = path.join(__dirname, '..', 'data');
const DB_JSON_PATH = path.join(DATA_DIR, 'db.json');
const DUMP_JSON_PATH = path.join(DATA_DIR, 'db.dump.json');
const DUMP_SQL_PATH = path.join(DATA_DIR, 'dump.sql');

if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// Master Seed / Production Database Dataset
const masterDatabase = {
  users: [
    {
      id: 'usr-admin-01',
      email: 'admin@nexnav.com',
      password: 'admin123',
      name: 'System Administrator',
      role: 'admin',
      createdAt: '2026-10-01T00:00:00.000Z',
    },
    {
      id: 'usr-regular-01',
      email: 'user@nexnav.com',
      password: 'user123',
      name: 'NexNav Shopper',
      role: 'user',
      createdAt: '2026-10-01T00:00:00.000Z',
    },
    {
      id: 'usr-tester-01',
      email: 'tester@nexnav.com',
      password: 'test123',
      name: 'AR Field QA Tester',
      role: 'user',
      createdAt: '2026-10-01T00:00:00.000Z',
    },
  ],
  malls: [
    {
      id: 'mall-one-galle-face',
      name: 'One Galle Face Mall & Tower',
      city: 'Colombo',
      country: 'Sri Lanka',
      latitude: 6.927079,
      longitude: 79.845612,
      floorCount: 5,
      packageSizeBytesMB: 14.2,
      category: 'Premier Oceanfront Mall',
      rating: '4.9 ★',
      isDownloaded: true,
      isActive: true,
      entranceBaseAnchorHeight: 45.0,
      floorGapMeters: 5.0,
    },
    {
      id: 'mall-colombo-city-centre',
      name: 'Colombo City Centre (CCC)',
      city: 'Colombo',
      country: 'Sri Lanka',
      latitude: 6.916720,
      longitude: 79.855010,
      floorCount: 5,
      packageSizeBytesMB: 18.5,
      category: 'Luxury Shopping & Lifestyle',
      rating: '4.8 ★',
      isDownloaded: true,
      isActive: false,
      entranceBaseAnchorHeight: 35.0,
      floorGapMeters: 4.8,
    },
    {
      id: 'mall-havelock-city',
      name: 'Havelock City Mall',
      city: 'Colombo',
      country: 'Sri Lanka',
      latitude: 6.885020,
      longitude: 79.866030,
      floorCount: 5,
      packageSizeBytesMB: 16.8,
      category: 'Lifestyle & Retail Hub',
      rating: '4.8 ★',
      isDownloaded: true,
      isActive: false,
      entranceBaseAnchorHeight: 30.0,
      floorGapMeters: 4.5,
    },
    {
      id: 'mall-kandy-city-centre',
      name: 'Kandy City Centre (KCC)',
      city: 'Kandy',
      country: 'Sri Lanka',
      latitude: 7.293620,
      longitude: 80.635030,
      floorCount: 5,
      packageSizeBytesMB: 15.1,
      category: 'Heritage Commercial Complex',
      rating: '4.7 ★',
      isDownloaded: true,
      isActive: false,
      entranceBaseAnchorHeight: 500.0,
      floorGapMeters: 4.5,
    },
    {
      id: 'mall-marino-mall',
      name: 'Marino Mall & Entertainment',
      city: 'Colombo',
      country: 'Sri Lanka',
      latitude: 6.897810,
      longitude: 79.854720,
      floorCount: 5,
      packageSizeBytesMB: 12.4,
      category: 'Tech & Waterfront Mall',
      rating: '4.6 ★',
      isDownloaded: true,
      isActive: false,
      entranceBaseAnchorHeight: 25.0,
      floorGapMeters: 4.5,
    },
  ],
  entranceMarkers: [
    {
      markerId: 'mrk-ogf-01',
      buildingId: 'mall-one-galle-face',
      name: 'One Galle Face Main Ocean Gate 1',
      latitude: 6.927079,
      longitude: 79.845612,
      baseHeight: 45.0,
      physicalWidthMeters: 0.25,
      physicalHeightMeters: 0.25,
      qrCodeData: 'NEXNAV://MALL/mall-one-galle-face/MARKER/01',
    },
    {
      markerId: 'mrk-ogf-02',
      buildingId: 'mall-one-galle-face',
      name: 'One Galle Face North Elevator Pillar',
      latitude: 6.927179,
      longitude: 79.845712,
      baseHeight: 45.0,
      physicalWidthMeters: 0.25,
      physicalHeightMeters: 0.25,
      qrCodeData: 'NEXNAV://MALL/mall-one-galle-face/MARKER/02',
    },
    {
      markerId: 'mrk-ccc-01',
      buildingId: 'mall-colombo-city-centre',
      name: 'Colombo City Centre Main Atrium Gate',
      latitude: 6.916720,
      longitude: 79.855010,
      baseHeight: 35.0,
      physicalWidthMeters: 0.25,
      physicalHeightMeters: 0.25,
      qrCodeData: 'NEXNAV://MALL/mall-colombo-city-centre/MARKER/01',
    },
    {
      markerId: 'mrk-hvc-01',
      buildingId: 'mall-havelock-city',
      name: 'Havelock City Boulevard West Gate',
      latitude: 6.885020,
      longitude: 79.866030,
      baseHeight: 30.0,
      physicalWidthMeters: 0.25,
      physicalHeightMeters: 0.25,
      qrCodeData: 'NEXNAV://MALL/mall-havelock-city/MARKER/01',
    },
    {
      markerId: 'mrk-kcc-01',
      buildingId: 'mall-kandy-city-centre',
      name: 'KCC Heritage Plaza Gate 1',
      latitude: 7.293620,
      longitude: 80.635030,
      baseHeight: 500.0,
      physicalWidthMeters: 0.25,
      physicalHeightMeters: 0.25,
      qrCodeData: 'NEXNAV://MALL/mall-kandy-city-centre/MARKER/01',
    },
    {
      markerId: 'mrk-mar-01',
      buildingId: 'mall-marino-mall',
      name: 'Marino Mall Galle Road Entrance',
      latitude: 6.897810,
      longitude: 79.854720,
      baseHeight: 25.0,
      physicalWidthMeters: 0.25,
      physicalHeightMeters: 0.25,
      qrCodeData: 'NEXNAV://MALL/mall-marino-mall/MARKER/01',
    },
  ],
  floorHeights: [
    // One Galle Face Floors
    {
      mallId: 'mall-one-galle-face',
      floorNo: -1,
      heightToNextM: 5.0,
      baseAltitudeM: 40.0,
      source: 'admin',
      confidence: 1.0,
      isLocked: true,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-one-galle-face',
      floorNo: 1,
      heightToNextM: 5.0,
      baseAltitudeM: 45.0,
      source: 'admin',
      confidence: 1.0,
      isLocked: true,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-one-galle-face',
      floorNo: 2,
      heightToNextM: 5.0,
      baseAltitudeM: 50.0,
      source: 'admin',
      confidence: 1.0,
      isLocked: true,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-one-galle-face',
      floorNo: 3,
      heightToNextM: 5.0,
      baseAltitudeM: 55.0,
      source: 'admin',
      confidence: 1.0,
      isLocked: true,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-one-galle-face',
      floorNo: 4,
      heightToNextM: 5.0,
      baseAltitudeM: 60.0,
      source: 'admin',
      confidence: 1.0,
      isLocked: true,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    // Colombo City Centre Floors
    {
      mallId: 'mall-colombo-city-centre',
      floorNo: -1,
      heightToNextM: 4.8,
      baseAltitudeM: 30.2,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-colombo-city-centre',
      floorNo: 1,
      heightToNextM: 4.8,
      baseAltitudeM: 35.0,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-colombo-city-centre',
      floorNo: 2,
      heightToNextM: 4.8,
      baseAltitudeM: 39.8,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-colombo-city-centre',
      floorNo: 3,
      heightToNextM: 4.8,
      baseAltitudeM: 44.6,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-colombo-city-centre',
      floorNo: 4,
      heightToNextM: 4.8,
      baseAltitudeM: 49.4,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    // Havelock City Floors
    {
      mallId: 'mall-havelock-city',
      floorNo: -1,
      heightToNextM: 4.5,
      baseAltitudeM: 25.5,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-havelock-city',
      floorNo: 1,
      heightToNextM: 4.5,
      baseAltitudeM: 30.0,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-havelock-city',
      floorNo: 2,
      heightToNextM: 4.5,
      baseAltitudeM: 34.5,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-havelock-city',
      floorNo: 3,
      heightToNextM: 4.5,
      baseAltitudeM: 39.0,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-havelock-city',
      floorNo: 4,
      heightToNextM: 4.5,
      baseAltitudeM: 43.5,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    // Kandy City Centre Floors
    {
      mallId: 'mall-kandy-city-centre',
      floorNo: 1,
      heightToNextM: 4.5,
      baseAltitudeM: 500.0,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-kandy-city-centre',
      floorNo: 2,
      heightToNextM: 4.5,
      baseAltitudeM: 504.5,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-kandy-city-centre',
      floorNo: 3,
      heightToNextM: 4.5,
      baseAltitudeM: 509.0,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    // Marino Mall Floors
    {
      mallId: 'mall-marino-mall',
      floorNo: 1,
      heightToNextM: 4.5,
      baseAltitudeM: 25.0,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-marino-mall',
      floorNo: 2,
      heightToNextM: 4.5,
      baseAltitudeM: 29.5,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
    {
      mallId: 'mall-marino-mall',
      floorNo: 3,
      heightToNextM: 4.5,
      baseAltitudeM: 34.0,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: '2026-10-01T00:00:00.000Z',
    },
  ],
  destinations: [
    // ==========================================
    // ONE GALLE FACE MALL (OGF) POIS
    // ==========================================
    // B1 - Basement 1
    {
      id: 'poi-b1-01',
      mallId: 'mall-one-galle-face',
      name: 'B1 Executive Valet & Concierge',
      category: 'SERVICES',
      floorNumber: -1,
      rating: 4.9,
      latitude: 6.927380,
      longitude: 79.845312,
      height: 40.0,
      description: 'VIP valet drop-off, luggage storage, and premium parking concierge desk.',
      openStatus: 'OPEN NOW',
      openingHours: '24 Hours Open',
      imageUrl: 'assets/images/shops/b1_executive_valet_concierge.jpg',
    },
    {
      id: 'poi-b1-02',
      mallId: 'mall-one-galle-face',
      name: 'Keells Express Supermarket B1',
      category: 'SERVICES',
      floorNumber: -1,
      rating: 4.8,
      latitude: 6.927380,
      longitude: 79.845912,
      height: 40.0,
      description: 'Express groceries, fresh takeaway snacks, cold beverages, and essentials.',
      openStatus: 'OPEN NOW',
      openingHours: '08:00 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/keells_express_supermarket_b1.jpg',
    },
    {
      id: 'poi-b1-03',
      mallId: 'mall-one-galle-face',
      name: 'B1 Eco EV Fast-Charging Hub',
      category: 'TECH & ELECTRONICS',
      floorNumber: -1,
      rating: 4.9,
      latitude: 6.926780,
      longitude: 79.845312,
      height: 40.0,
      description: 'High-speed 120kW DC EV chargers for Tesla, Hyundai, Nissan & BYD vehicles.',
      openStatus: '24/7',
      openingHours: '24 Hours Open',
      imageUrl: 'assets/images/shops/b1_eco_ev_charging_hub.jpg',
    },
    {
      id: 'poi-b1-04',
      mallId: 'mall-one-galle-face',
      name: 'B1 Auto Car Wash & Detailing',
      category: 'SERVICES',
      floorNumber: -1,
      rating: 4.7,
      latitude: 6.926780,
      longitude: 79.845912,
      height: 40.0,
      description: 'Eco-friendly waterless car wash, interior vacuuming & ceramic coating.',
      openStatus: 'OPEN NOW',
      openingHours: '09:00 AM - 08:00 PM',
      imageUrl: 'assets/images/shops/b1_auto_car_wash.jpg',
    },
    {
      id: 'poi-b1-05',
      mallId: 'mall-one-galle-face',
      name: 'B1 Luggage Lockers & Express Counter',
      category: 'SERVICES',
      floorNumber: -1,
      rating: 4.8,
      latitude: 6.927480,
      longitude: 79.845612,
      height: 40.0,
      description: 'Automated smart luggage lockers, parcel pickup, and courier services.',
      openStatus: '24/7',
      openingHours: '24 Hours Open',
      imageUrl: 'assets/images/shops/b1_luggage_lockers.jpg',
    },

    // F1 - Ground Floor
    {
      id: 'poi-101',
      mallId: 'mall-one-galle-face',
      name: 'Odel Flagship Department Store',
      category: 'RETAIL & FASHION',
      floorNumber: 1,
      rating: 4.9,
      latitude: 6.927430,
      longitude: 79.845612,
      height: 45.0,
      description: 'Premier Sri Lankan lifestyle, fashion & department store.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/odel_flagship_store.jpg',
    },
    {
      id: 'poi-102',
      mallId: 'mall-one-galle-face',
      name: 'Concierge & Information Desk',
      category: 'SERVICES',
      floorNumber: 1,
      rating: 5.0,
      latitude: 6.927330,
      longitude: 79.845862,
      height: 45.0,
      description: 'Sri Lanka tourist assistance, mall guide & lost property services.',
      openStatus: '24/7',
      openingHours: '24 Hours Open',
      imageUrl: 'assets/images/shops/concierge_information_desk.jpg',
    },
    {
      id: 'poi-103',
      mallId: 'mall-one-galle-face',
      name: 'Spa Ceylon Luxury Ayurveda',
      category: 'SERVICES',
      floorNumber: 1,
      rating: 4.9,
      latitude: 6.927079,
      longitude: 79.845962,
      height: 45.0,
      description: 'Royal Sri Lankan Ayurveda wellness, essential oils & skincare.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/spa_ceylon_luxury_ayurveda.jpg',
    },
    {
      id: 'poi-104',
      mallId: 'mall-one-galle-face',
      name: 'Dilmah Tea Lounge & t-Bar',
      category: 'FOOD & DRINK',
      floorNumber: 1,
      rating: 4.8,
      latitude: 6.926830,
      longitude: 79.845862,
      height: 45.0,
      description: 'Handpicked single-origin Ceylon tea tasting, mocktails & high tea.',
      openStatus: 'OPEN NOW',
      openingHours: '08:30 AM - 11:00 PM',
      imageUrl: 'assets/images/shops/dilmah_tea_lounge.jpg',
    },
    {
      id: 'poi-105',
      mallId: 'mall-one-galle-face',
      name: 'Keells Super Hypermarket',
      category: 'SERVICES',
      floorNumber: 1,
      rating: 4.7,
      latitude: 6.926730,
      longitude: 79.845612,
      height: 45.0,
      description: 'Gourmet groceries, fresh Sri Lankan produce, bakery & spices.',
      openStatus: 'OPEN NOW',
      openingHours: '08:00 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/keells_super_hypermarket.jpg',
    },

    // F2 - Fashion & Apparel
    {
      id: 'poi-201',
      mallId: 'mall-one-galle-face',
      name: 'Cotton Collection',
      category: 'RETAIL & FASHION',
      floorNumber: 2,
      rating: 4.6,
      latitude: 6.926830,
      longitude: 79.845362,
      height: 50.0,
      description: 'Casual island wear, linen garments, tropical resort fashion & accessories.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/cotton_collection.jpg',
    },
    {
      id: 'poi-202',
      mallId: 'mall-one-galle-face',
      name: 'Kelly Felder Designer Lounge',
      category: 'RETAIL & FASHION',
      floorNumber: 2,
      rating: 4.8,
      latitude: 6.927079,
      longitude: 79.845262,
      height: 50.0,
      description: 'Chic Sri Lankan womenswear, evening attire, and designer handbags.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/kelly_felder_designer_lounge.jpg',
    },
    {
      id: 'poi-203',
      mallId: 'mall-one-galle-face',
      name: 'House of Fashion Outlet',
      category: 'RETAIL & FASHION',
      floorNumber: 2,
      rating: 4.7,
      latitude: 6.927330,
      longitude: 79.845362,
      height: 50.0,
      description: 'Extensive selection of international trends and local Sri Lankan apparel.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/house_of_fashion_outlet.jpg',
    },
    {
      id: 'poi-204',
      mallId: 'mall-one-galle-face',
      name: 'Barefoot Ceylon Handwoven Gallery',
      category: 'RETAIL & FASHION',
      floorNumber: 2,
      rating: 4.9,
      latitude: 6.927480,
      longitude: 79.845612,
      height: 50.0,
      description: 'Vibrant handwoven Sri Lankan textiles, books, toys, and artisanal crafts.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/barefoot_ceylon_handwoven.jpg',
    },
    {
      id: 'poi-205',
      mallId: 'mall-one-galle-face',
      name: 'Hugo Boss & Luxury Apparel',
      category: 'RETAIL & FASHION',
      floorNumber: 2,
      rating: 4.8,
      latitude: 6.927079,
      longitude: 79.846012,
      height: 50.0,
      description: 'Premium luxury suits, formal wear, leather shoes & accessories.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/hugo_boss_luxury_apparel.jpg',
    },

    // F3 - Tech & Electronics
    {
      id: 'poi-301',
      mallId: 'mall-one-galle-face',
      name: 'Singer Mega Experience Center',
      category: 'TECH & ELECTRONICS',
      floorNumber: 3,
      rating: 4.8,
      latitude: 6.927380,
      longitude: 79.845912,
      height: 55.0,
      description: 'Smart TVs, home electronics, laptops, and consumer technology.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/singer_mega_experience_center.jpg',
    },
    {
      id: 'poi-302',
      mallId: 'mall-one-galle-face',
      name: 'Abans Elite Apple & LG Store',
      category: 'TECH & ELECTRONICS',
      floorNumber: 3,
      rating: 4.9,
      latitude: 6.926780,
      longitude: 79.845912,
      height: 55.0,
      description: 'Authorized Apple products, iPhones, MacBooks, and LG smart devices.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/abans_elite_apple_lg_store.jpg',
    },
    {
      id: 'poi-303',
      mallId: 'mall-one-galle-face',
      name: 'Dialog Axiata Experience Centre',
      category: 'TECH & ELECTRONICS',
      floorNumber: 3,
      rating: 4.8,
      latitude: 6.926680,
      longitude: 79.845612,
      height: 55.0,
      description: '5G SIM connections, eSIM activation, fiber broadband & IoT gadgets.',
      openStatus: 'OPEN NOW',
      openingHours: '09:30 AM - 09:30 PM',
      imageUrl: 'assets/images/shops/dialog_axiata_experience_centre.jpg',
    },
    {
      id: 'poi-304',
      mallId: 'mall-one-galle-face',
      name: 'Mobitel & SLT Broadband Lounge',
      category: 'TECH & ELECTRONICS',
      floorNumber: 3,
      rating: 4.7,
      latitude: 6.926780,
      longitude: 79.845312,
      height: 55.0,
      description: 'National telecom service desk, fiber routers, and mobile accessories.',
      openStatus: 'OPEN NOW',
      openingHours: '09:30 AM - 09:30 PM',
      imageUrl: 'assets/images/shops/mobitel_slt_broadband_lounge.jpg',
    },
    {
      id: 'poi-305',
      mallId: 'mall-one-galle-face',
      name: 'Samsung Smart Experience Zone',
      category: 'TECH & ELECTRONICS',
      floorNumber: 3,
      rating: 4.9,
      latitude: 6.927079,
      longitude: 79.845212,
      height: 55.0,
      description: 'Galaxy smartphones, tablets, smartwatches & home appliance displays.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/samsung_smart_experience_zone.jpg',
    },

    // F4 - Food Court & Entertainment
    {
      id: 'poi-401',
      mallId: 'mall-one-galle-face',
      name: 'Food Studio Ceylon Court',
      category: 'FOOD & DRINK',
      floorNumber: 4,
      rating: 4.9,
      latitude: 6.927380,
      longitude: 79.845312,
      height: 60.0,
      description: 'Fresh Kottu Roti, Jaffna Crab Curry, Egg Hoppers & Ceylon street food.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 11:00 PM',
      imageUrl: 'assets/images/shops/food_studio_ceylon_court.jpg',
    },
    {
      id: 'poi-402',
      mallId: 'mall-one-galle-face',
      name: 'Ministry of Crab Express',
      category: 'FOOD & DRINK',
      floorNumber: 4,
      rating: 5.0,
      latitude: 6.927530,
      longitude: 79.845612,
      height: 60.0,
      description: 'World-renowned Sri Lankan giant lagoon crab & Garlic Chili Prawns.',
      openStatus: 'OPEN NOW',
      openingHours: '11:00 AM - 11:00 PM',
      imageUrl: 'assets/images/shops/ministry_of_crab_express.jpg',
    },
    {
      id: 'poi-403',
      mallId: 'mall-one-galle-face',
      name: 'Barista Ceylon Espresso Bar',
      category: 'FOOD & DRINK',
      floorNumber: 4,
      rating: 4.7,
      latitude: 6.927380,
      longitude: 79.845962,
      height: 60.0,
      description: 'Artisanal local coffees, iced lattes, fresh pastries, and savories.',
      openStatus: 'OPEN NOW',
      openingHours: '08:00 AM - 11:00 PM',
      imageUrl: 'assets/images/shops/barista_ceylon_espresso_bar.jpg',
    },
    {
      id: 'poi-404',
      mallId: 'mall-one-galle-face',
      name: 'Taco Bell Sri Lanka',
      category: 'FOOD & DRINK',
      floorNumber: 4,
      rating: 4.6,
      latitude: 6.927079,
      longitude: 79.846062,
      height: 60.0,
      description: 'Mexican inspired burritos, crunchy tacos, and spicy Sri Lankan sauces.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 11:00 PM',
      imageUrl: 'assets/images/shops/taco_bell_sri_lanka.jpg',
    },
    {
      id: 'poi-405',
      mallId: 'mall-one-galle-face',
      name: 'PVR / Scope Cinemas IMAX OGF',
      category: 'ENTERTAINMENT',
      floorNumber: 4,
      rating: 5.0,
      latitude: 6.926680,
      longitude: 79.845962,
      height: 60.0,
      description: 'Premium 3D IMAX screen, Dolby Atmos surround sound & luxury recliners.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 11:30 PM',
      imageUrl: 'assets/images/shops/pvr_scope_cinemas_imax.jpg',
    },

    // ==========================================
    // COLOMBO CITY CENTRE (CCC) POIS
    // ==========================================
    {
      id: 'poi-ccc-01',
      mallId: 'mall-colombo-city-centre',
      name: 'Scope Cinemas Multiplex CCC',
      category: 'ENTERTAINMENT',
      floorNumber: 3,
      rating: 4.9,
      latitude: 6.916820,
      longitude: 79.855110,
      height: 44.6,
      description: '6-screen world-class multiplex with Dolby Surround and VIP dining.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 11:30 PM',
      imageUrl: 'assets/images/shops/pvr_scope_cinemas_imax.jpg',
    },
    {
      id: 'poi-ccc-02',
      mallId: 'mall-colombo-city-centre',
      name: 'Food Studio Overlooking Beira Lake',
      category: 'FOOD & DRINK',
      floorNumber: 3,
      rating: 4.8,
      latitude: 6.916620,
      longitude: 79.854910,
      height: 44.6,
      description: 'Scenic international culinary court with panoramic Beira Lake views.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 10:30 PM',
      imageUrl: 'assets/images/shops/food_studio_ceylon_court.jpg',
    },
    {
      id: 'poi-ccc-03',
      mallId: 'mall-colombo-city-centre',
      name: 'Apple Care & FutureWorld CCC',
      category: 'TECH & ELECTRONICS',
      floorNumber: 2,
      rating: 4.9,
      latitude: 6.916720,
      longitude: 79.855210,
      height: 39.8,
      description: 'Apple Premium Reseller and official service center.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 09:30 PM',
      imageUrl: 'assets/images/shops/abans_elite_apple_lg_store.jpg',
    },

    // ==========================================
    // HAVELOCK CITY MALL POIS
    // ==========================================
    {
      id: 'poi-hvc-01',
      mallId: 'mall-havelock-city',
      name: 'Cargills Food City Gourmet Flagship',
      category: 'SERVICES',
      floorNumber: 1,
      rating: 4.8,
      latitude: 6.885120,
      longitude: 79.866130,
      height: 30.0,
      description: 'Premium organic supermarket, delicatessen, imported cheeses & wines.',
      openStatus: 'OPEN NOW',
      openingHours: '08:00 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/keells_super_hypermarket.jpg',
    },
    {
      id: 'poi-hvc-02',
      mallId: 'mall-havelock-city',
      name: 'Scope Cinemas Havelock IMAX',
      category: 'ENTERTAINMENT',
      floorNumber: 4,
      rating: 4.9,
      latitude: 6.885220,
      longitude: 79.865930,
      height: 43.5,
      description: 'Sri Lankas newest laser projection IMAX theatre.',
      openStatus: 'OPEN NOW',
      openingHours: '10:00 AM - 11:30 PM',
      imageUrl: 'assets/images/shops/pvr_scope_cinemas_imax.jpg',
    },

    // ==========================================
    // KANDY CITY CENTRE (KCC) POIS
    // ==========================================
    {
      id: 'poi-kcc-01',
      mallId: 'mall-kandy-city-centre',
      name: 'World of Outdoor & Adventure KCC',
      category: 'RETAIL & FASHION',
      floorNumber: 2,
      rating: 4.7,
      latitude: 7.293720,
      longitude: 80.635130,
      height: 504.5,
      description: 'Hiking gear, mountain footwear, outdoor clothing and camping essentials.',
      openStatus: 'OPEN NOW',
      openingHours: '09:30 AM - 08:30 PM',
      imageUrl: 'assets/images/shops/cotton_collection.jpg',
    },

    // ==========================================
    // MARINO MALL POIS
    // ==========================================
    {
      id: 'poi-mar-01',
      mallId: 'mall-marino-mall',
      name: 'VR Interactive Theme Zone',
      category: 'ENTERTAINMENT',
      floorNumber: 3,
      rating: 4.8,
      latitude: 6.897910,
      longitude: 79.854820,
      height: 34.0,
      description: 'Futuristic 9D VR simulators, motion racing rigs & laser tag arena.',
      openStatus: 'OPEN NOW',
      openingHours: '10:30 AM - 10:00 PM',
      imageUrl: 'assets/images/shops/pvr_scope_cinemas_imax.jpg',
    },
  ],
  parkingSlots: [
    // One Galle Face Basement B1 Parking Slots
    {
      id: 'A-01',
      mallId: 'mall-one-galle-face',
      floorId: 'B1',
      section: 'A',
      slotNumber: 1,
      status: 'free',
      latitude: 6.926880,
      longitude: 79.845412,
      height: 40.0,
      gridRow: 0,
      gridCol: 0,
      isEVCharging: true,
      isHandicapAccessible: false,
      sensorId: 'snr-ogf-b1-a01',
    },
    {
      id: 'A-02',
      mallId: 'mall-one-galle-face',
      floorId: 'B1',
      section: 'A',
      slotNumber: 2,
      status: 'free',
      latitude: 6.926880,
      longitude: 79.845432,
      height: 40.0,
      gridRow: 0,
      gridCol: 1,
      isEVCharging: true,
      isHandicapAccessible: false,
      sensorId: 'snr-ogf-b1-a02',
    },
    {
      id: 'A-03',
      mallId: 'mall-one-galle-face',
      floorId: 'B1',
      section: 'A',
      slotNumber: 3,
      status: 'occupied',
      latitude: 6.926880,
      longitude: 79.845452,
      height: 40.0,
      gridRow: 0,
      gridCol: 2,
      isEVCharging: false,
      isHandicapAccessible: false,
      sensorId: 'snr-ogf-b1-a03',
    },
    {
      id: 'A-04',
      mallId: 'mall-one-galle-face',
      floorId: 'B1',
      section: 'A',
      slotNumber: 4,
      status: 'free',
      latitude: 6.926880,
      longitude: 79.845472,
      height: 40.0,
      gridRow: 0,
      gridCol: 3,
      isEVCharging: false,
      isHandicapAccessible: true,
      sensorId: 'snr-ogf-b1-a04',
    },
    {
      id: 'B-01',
      mallId: 'mall-one-galle-face',
      floorId: 'B1',
      section: 'B',
      slotNumber: 1,
      status: 'free',
      latitude: 6.926930,
      longitude: 79.845412,
      height: 40.0,
      gridRow: 1,
      gridCol: 0,
      isEVCharging: false,
      isHandicapAccessible: false,
      sensorId: 'snr-ogf-b1-b01',
    },
    {
      id: 'B-02',
      mallId: 'mall-one-galle-face',
      floorId: 'B1',
      section: 'B',
      slotNumber: 2,
      status: 'reserved',
      latitude: 6.926930,
      longitude: 79.845432,
      height: 40.0,
      gridRow: 1,
      gridCol: 1,
      isEVCharging: false,
      isHandicapAccessible: false,
      sensorId: 'snr-ogf-b1-b02',
    },
    {
      id: 'B-03',
      mallId: 'mall-one-galle-face',
      floorId: 'B1',
      section: 'B',
      slotNumber: 3,
      status: 'free',
      latitude: 6.926930,
      longitude: 79.845452,
      height: 40.0,
      gridRow: 1,
      gridCol: 2,
      isEVCharging: false,
      isHandicapAccessible: false,
      sensorId: 'snr-ogf-b1-b03',
    },
    {
      id: 'B-04',
      mallId: 'mall-one-galle-face',
      floorId: 'B1',
      section: 'B',
      slotNumber: 4,
      status: 'free',
      latitude: 6.926930,
      longitude: 79.845472,
      height: 40.0,
      gridRow: 1,
      gridCol: 3,
      isEVCharging: false,
      isHandicapAccessible: true,
      sensorId: 'snr-ogf-b1-b04',
    },

    // One Galle Face Ground VIP Surface Parking Slots
    {
      id: 'P-01',
      mallId: 'mall-one-galle-face',
      floorId: 'GF',
      section: 'P',
      slotNumber: 1,
      status: 'free',
      latitude: 6.927179,
      longitude: 79.845712,
      height: 45.0,
      gridRow: 0,
      gridCol: 0,
      isEVCharging: true,
      isHandicapAccessible: true,
      sensorId: 'snr-ogf-gf-p01',
    },
    {
      id: 'P-02',
      mallId: 'mall-one-galle-face',
      floorId: 'GF',
      section: 'P',
      slotNumber: 2,
      status: 'occupied',
      latitude: 6.927179,
      longitude: 79.845732,
      height: 45.0,
      gridRow: 0,
      gridCol: 1,
      isEVCharging: false,
      isHandicapAccessible: false,
      sensorId: 'snr-ogf-gf-p02',
    },
  ],
  vehicleLocations: {
    'usr-regular-01': {
      userId: 'usr-regular-01',
      vehicleId: 'veh-user-01',
      slotId: 'A-03',
      floorId: 'B1',
      floorName: 'Basement Level B1',
      latitude: 6.926880,
      longitude: 79.845452,
      height: 40.0,
      timestamp: '2026-10-12T08:30:00.000Z',
      status: 'parked',
      licensePlate: 'WP CAB-8821',
      notes: 'Parked in Bay A-03 near Entrance Lift Core 2',
    },
  },
};

/**
 * Generates SQL DDL + DML dump string compatible with PostgreSQL / MySQL / SQLite
 */
function generateSqlDump(data) {
  let sql = `-- =========================================================================
-- NexNav NavCore Server Database Dump
-- Compatible with PostgreSQL, SQLite3, and MySQL
-- Generated At: ${new Date().toISOString()}
-- =========================================================================

-- Drop tables if exists
DROP TABLE IF EXISTS vehicle_locations;
DROP TABLE IF EXISTS parking_slots;
DROP TABLE IF EXISTS destinations;
DROP TABLE IF EXISTS floor_heights;
DROP TABLE IF EXISTS entrance_markers;
DROP TABLE IF EXISTS malls;
DROP TABLE IF EXISTS users;

-- -------------------------------------------------------------------------
-- 1. Table: users
-- -------------------------------------------------------------------------
CREATE TABLE users (
  id VARCHAR(64) PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,
  name VARCHAR(255) NOT NULL,
  role VARCHAR(32) NOT NULL DEFAULT 'user',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------------------
-- 2. Table: malls
-- -------------------------------------------------------------------------
CREATE TABLE malls (
  id VARCHAR(64) PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  city VARCHAR(128) NOT NULL,
  country VARCHAR(128) NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  floor_count INT NOT NULL DEFAULT 5,
  package_size_bytes_mb DOUBLE PRECISION DEFAULT 10.0,
  category VARCHAR(128),
  rating VARCHAR(32),
  is_downloaded BOOLEAN DEFAULT TRUE,
  is_active BOOLEAN DEFAULT FALSE,
  entrance_base_anchor_height DOUBLE PRECISION DEFAULT 0.0,
  floor_gap_meters DOUBLE PRECISION DEFAULT 4.5
);

-- -------------------------------------------------------------------------
-- 3. Table: entrance_markers
-- -------------------------------------------------------------------------
CREATE TABLE entrance_markers (
  marker_id VARCHAR(64) PRIMARY KEY,
  building_id VARCHAR(64) REFERENCES malls(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  base_height DOUBLE PRECISION NOT NULL,
  physical_width_meters DOUBLE PRECISION DEFAULT 0.25,
  physical_height_meters DOUBLE PRECISION DEFAULT 0.25,
  qr_code_data TEXT
);

-- -------------------------------------------------------------------------
-- 4. Table: floor_heights
-- -------------------------------------------------------------------------
CREATE TABLE floor_heights (
  id SERIAL PRIMARY KEY,
  mall_id VARCHAR(64) REFERENCES malls(id) ON DELETE CASCADE,
  floor_no INT NOT NULL,
  height_to_next_m DOUBLE PRECISION NOT NULL,
  base_altitude_m DOUBLE PRECISION NOT NULL,
  source VARCHAR(64) DEFAULT 'admin',
  confidence DOUBLE PRECISION DEFAULT 1.0,
  is_locked BOOLEAN DEFAULT FALSE,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(mall_id, floor_no)
);

-- -------------------------------------------------------------------------
-- 5. Table: destinations (POIs)
-- -------------------------------------------------------------------------
CREATE TABLE destinations (
  id VARCHAR(64) PRIMARY KEY,
  mall_id VARCHAR(64) REFERENCES malls(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  category VARCHAR(128) NOT NULL,
  floor_number INT NOT NULL,
  rating DOUBLE PRECISION DEFAULT 4.8,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  height DOUBLE PRECISION NOT NULL,
  description TEXT,
  open_status VARCHAR(64) DEFAULT 'OPEN NOW',
  opening_hours VARCHAR(128),
  image_url TEXT
);

-- -------------------------------------------------------------------------
-- 6. Table: parking_slots
-- -------------------------------------------------------------------------
CREATE TABLE parking_slots (
  id VARCHAR(64) PRIMARY KEY,
  mall_id VARCHAR(64) REFERENCES malls(id) ON DELETE CASCADE,
  floor_id VARCHAR(32) NOT NULL,
  section VARCHAR(32) NOT NULL,
  slot_number INT NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'free',
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  height DOUBLE PRECISION NOT NULL,
  grid_row INT NOT NULL,
  grid_col INT NOT NULL,
  is_ev_charging BOOLEAN DEFAULT FALSE,
  is_handicap_accessible BOOLEAN DEFAULT FALSE,
  sensor_id VARCHAR(64)
);

-- -------------------------------------------------------------------------
-- 7. Table: vehicle_locations
-- -------------------------------------------------------------------------
CREATE TABLE vehicle_locations (
  user_id VARCHAR(64) PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  vehicle_id VARCHAR(64) NOT NULL,
  slot_id VARCHAR(64),
  floor_id VARCHAR(32) NOT NULL,
  floor_name VARCHAR(128),
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  height DOUBLE PRECISION NOT NULL,
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  status VARCHAR(32) DEFAULT 'parked',
  license_plate VARCHAR(64),
  notes TEXT
);

`;

  const esc = (val) => {
    if (val === null || val === undefined) return 'NULL';
    if (typeof val === 'boolean') return val ? 'TRUE' : 'FALSE';
    if (typeof val === 'number') return val;
    return `'${String(val).replace(/'/g, "''")}'`;
  };

  // Insert Users
  sql += `\n-- Insert Users\n`;
  for (const u of data.users) {
    sql += `INSERT INTO users (id, email, password, name, role, created_at) VALUES (${esc(u.id)}, ${esc(u.email)}, ${esc(u.password)}, ${esc(u.name)}, ${esc(u.role)}, ${esc(u.createdAt)});\n`;
  }

  // Insert Malls
  sql += `\n-- Insert Malls\n`;
  for (const m of data.malls) {
    sql += `INSERT INTO malls (id, name, city, country, latitude, longitude, floor_count, package_size_bytes_mb, category, rating, is_downloaded, is_active, entrance_base_anchor_height, floor_gap_meters) VALUES (${esc(m.id)}, ${esc(m.name)}, ${esc(m.city)}, ${esc(m.country)}, ${esc(m.latitude)}, ${esc(m.longitude)}, ${esc(m.floorCount)}, ${esc(m.packageSizeBytesMB)}, ${esc(m.category)}, ${esc(m.rating)}, ${esc(m.isDownloaded)}, ${esc(m.isActive)}, ${esc(m.entranceBaseAnchorHeight)}, ${esc(m.floorGapMeters)});\n`;
  }

  // Insert Entrance Markers
  sql += `\n-- Insert Entrance Markers\n`;
  for (const em of data.entranceMarkers) {
    sql += `INSERT INTO entrance_markers (marker_id, building_id, name, latitude, longitude, base_height, physical_width_meters, physical_height_meters, qr_code_data) VALUES (${esc(em.markerId)}, ${esc(em.buildingId)}, ${esc(em.name)}, ${esc(em.latitude)}, ${esc(em.longitude)}, ${esc(em.baseHeight)}, ${esc(em.physicalWidthMeters)}, ${esc(em.physicalHeightMeters)}, ${esc(em.qrCodeData)});\n`;
  }

  // Insert Floor Heights
  sql += `\n-- Insert Floor Heights\n`;
  for (const fh of data.floorHeights) {
    sql += `INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES (${esc(fh.mallId)}, ${esc(fh.floorNo)}, ${esc(fh.heightToNextM)}, ${esc(fh.baseAltitudeM)}, ${esc(fh.source)}, ${esc(fh.confidence)}, ${esc(fh.isLocked)}, ${esc(fh.updatedAt)});\n`;
  }

  // Insert Destinations
  sql += `\n-- Insert Destinations (POIs)\n`;
  for (const d of data.destinations) {
    sql += `INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES (${esc(d.id)}, ${esc(d.mallId)}, ${esc(d.name)}, ${esc(d.category)}, ${esc(d.floorNumber)}, ${esc(d.rating)}, ${esc(d.latitude)}, ${esc(d.longitude)}, ${esc(d.height)}, ${esc(d.description)}, ${esc(d.openStatus)}, ${esc(d.openingHours)}, ${esc(d.imageUrl)});\n`;
  }

  // Insert Parking Slots
  sql += `\n-- Insert Parking Slots\n`;
  for (const ps of data.parkingSlots) {
    sql += `INSERT INTO parking_slots (id, mall_id, floor_id, section, slot_number, status, latitude, longitude, height, grid_row, grid_col, is_ev_charging, is_handicap_accessible, sensor_id) VALUES (${esc(ps.id)}, ${esc(ps.mallId)}, ${esc(ps.floorId)}, ${esc(ps.section)}, ${esc(ps.slotNumber)}, ${esc(ps.status)}, ${esc(ps.latitude)}, ${esc(ps.longitude)}, ${esc(ps.height)}, ${esc(ps.gridRow)}, ${esc(ps.gridCol)}, ${esc(ps.isEVCharging)}, ${esc(ps.isHandicapAccessible)}, ${esc(ps.sensorId)});\n`;
  }

  // Insert Vehicle Locations
  sql += `\n-- Insert Vehicle Locations\n`;
  for (const [userId, vl] of Object.entries(data.vehicleLocations)) {
    sql += `INSERT INTO vehicle_locations (user_id, vehicle_id, slot_id, floor_id, floor_name, latitude, longitude, height, timestamp, status, license_plate, notes) VALUES (${esc(userId)}, ${esc(vl.vehicleId)}, ${esc(vl.slotId)}, ${esc(vl.floorId)}, ${esc(vl.floorName)}, ${esc(vl.latitude)}, ${esc(vl.longitude)}, ${esc(vl.height)}, ${esc(vl.timestamp)}, ${esc(vl.status)}, ${esc(vl.licensePlate)}, ${esc(vl.notes)});\n`;
  }

  return sql;
}

function run() {
  const args = process.argv.slice(2);
  const isDumpMode = args.includes('--dump');

  let activeData = masterDatabase;

  // If dumping from current live db.json
  if (isDumpMode && fs.existsSync(DB_JSON_PATH)) {
    try {
      const live = JSON.parse(fs.readFileSync(DB_JSON_PATH, 'utf-8'));
      if (live.users && live.users.length > 0 && live.malls && live.malls.length > 0) {
        activeData = live;
        console.log('[Seed CLI] Exporting snapshot from live db.json...');
      }
    } catch (e) {
      console.warn('[Seed CLI] Warning parsing existing db.json, using master dataset:', e.message);
    }
  }

  // 1. Write backend/data/db.json
  fs.writeFileSync(DB_JSON_PATH, JSON.stringify(activeData, null, 2), 'utf-8');
  console.log(`[Seed CLI] Successfully updated active database file: ${DB_JSON_PATH}`);

  // 2. Write backend/data/db.dump.json (master JSON dump)
  fs.writeFileSync(DUMP_JSON_PATH, JSON.stringify(activeData, null, 2), 'utf-8');
  console.log(`[Seed CLI] Successfully wrote JSON database dump: ${DUMP_JSON_PATH}`);

  // Also write backend/data/dump.json as convenience alias
  const aliasDumpPath = path.join(DATA_DIR, 'dump.json');
  fs.writeFileSync(aliasDumpPath, JSON.stringify(activeData, null, 2), 'utf-8');

  // 3. Write backend/data/dump.sql (SQL DDL/DML dump)
  const sqlContent = generateSqlDump(activeData);
  fs.writeFileSync(DUMP_SQL_PATH, sqlContent, 'utf-8');
  console.log(`[Seed CLI] Successfully wrote SQL database dump: ${DUMP_SQL_PATH}`);

  console.log('\n--- Database Dump Summary ---');
  console.log(`Users:            ${activeData.users.length}`);
  console.log(`Malls:            ${activeData.malls.length}`);
  console.log(`Entrance Markers: ${activeData.entranceMarkers.length}`);
  console.log(`Floor Heights:    ${activeData.floorHeights.length}`);
  console.log(`Destinations:     ${activeData.destinations.length}`);
  console.log(`Parking Slots:    ${activeData.parkingSlots.length}`);
  console.log(`Vehicle Records:  ${Object.keys(activeData.vehicleLocations).length}`);
  console.log('-----------------------------\n');
}

run();
