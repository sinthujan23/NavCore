/* ==========================================================================
   NAVCORE PRO ADMIN PANEL - CENTRALIZED REACTIVE STORE
   ========================================================================== */

const NavCoreStore = (function () {
  // State Subscribers
  const listeners = [];

  // Initial State Database
  let state = {
    auth: {
      isLoggedIn: localStorage.getItem('navcore_logged_in') === 'true',
      user: JSON.parse(localStorage.getItem('navcore_user_session') || 'null') || {
        name: 'Sinthujan A.',
        email: 'admin@navcore.io',
        role: 'Super Admin',
        avatar: 'SA'
      }
    },
    activeBuildingId: 'mall-one-galle-face',
    theme: 'dark',
    emergencyActive: false,
    emergencyReason: '',

    // Buildings & Venues Catalog
    buildings: [
      {
        id: 'mall-one-galle-face',
        name: 'One Galle Face Mall & Tower',
        city: 'Colombo',
        country: 'Sri Lanka',
        latitude: 6.927079,
        longitude: 79.845612,
        baseElevation: 45.0,
        compassHeading: 184.5,
        floorCount: 6,
        packageSizeBytesMB: 14.2,
        category: 'Premier Oceanfront Mall',
        rating: '4.9 ★',
        status: 'ACTIVE'
      },
      {
        id: 'mall-colombo-city-centre',
        name: 'Colombo City Centre (CCC)',
        city: 'Colombo',
        country: 'Sri Lanka',
        latitude: 6.916720,
        longitude: 79.855010,
        baseElevation: 38.0,
        compassHeading: 120.0,
        floorCount: 5,
        packageSizeBytesMB: 18.5,
        category: 'Luxury Shopping & Lifestyle',
        rating: '4.8 ★',
        status: 'ONLINE'
      },
      {
        id: 'mall-havelock-city',
        name: 'Havelock City Mall',
        city: 'Colombo',
        country: 'Sri Lanka',
        latitude: 6.885020,
        longitude: 79.866030,
        baseElevation: 25.0,
        compassHeading: 90.0,
        floorCount: 5,
        packageSizeBytesMB: 16.8,
        category: 'Lifestyle & Retail Hub',
        rating: '4.8 ★',
        status: 'ONLINE'
      },
      {
        id: 'mall-kandy-city-centre',
        name: 'Kandy City Centre (KCC)',
        city: 'Kandy',
        country: 'Sri Lanka',
        latitude: 7.293620,
        longitude: 80.635030,
        baseElevation: 500.0,
        compassHeading: 45.0,
        floorCount: 5,
        packageSizeBytesMB: 15.1,
        category: 'Heritage Commercial Complex',
        rating: '4.7 ★',
        status: 'ONLINE'
      },
      {
        id: 'mall-marino-mall',
        name: 'Marino Mall & Entertainment',
        city: 'Colombo',
        country: 'Sri Lanka',
        latitude: 6.897810,
        longitude: 79.854720,
        baseElevation: 18.0,
        compassHeading: 180.0,
        floorCount: 5,
        packageSizeBytesMB: 12.4,
        category: 'Tech & Waterfront Mall',
        rating: '4.6 ★',
        status: 'ONLINE'
      }
    ],

    // Floor Profiles for One Galle Face
    floors: [
      { number: -1, code: 'B1', name: 'Basement 1 - Parking & Express Services', heightMeters: 30.0, poiCount: 5, status: 'Active' },
      { number: 0, code: 'G', name: 'Ground Floor - Main Atrium & Luxury Fashion', heightMeters: 35.0, poiCount: 8, status: 'Active' },
      { number: 1, code: 'L1', name: 'Level 1 - High Fashion & Apparel Hub', heightMeters: 40.0, poiCount: 10, status: 'Active' },
      { number: 2, code: 'L2', name: 'Level 2 - Dining Promenade & Gourmet Food Studio', heightMeters: 45.0, poiCount: 9, status: 'Active' },
      { number: 3, code: 'L3', name: 'Level 3 - Tech, Electronics & PVR Cinemas', heightMeters: 50.0, poiCount: 7, status: 'Active' },
      { number: 4, code: 'L4', name: 'Level 4 - Executive Lounges & Sky Deck', heightMeters: 55.0, poiCount: 3, status: 'Active' }
    ],

    // Shops & POI Directory (Imported & expanded from destinations.dart)
    shops: [
      {
        id: 'poi-b1-01',
        name: 'B1 Executive Valet & Concierge',
        category: 'SERVICES',
        floorNumber: -1,
        rating: 4.9,
        latitude: 6.927380,
        longitude: 79.845312,
        height: 30.0,
        description: 'VIP valet drop-off, luggage storage, and premium parking concierge desk.',
        openStatus: 'OPEN NOW',
        imageUrl: 'https://images.unsplash.com/photo-1549399542-7e3f8b79c341?w=500&auto=format&fit=crop&q=60'
      },
      {
        id: 'poi-b1-02',
        name: 'Keells Express Supermarket B1',
        category: 'SERVICES',
        floorNumber: -1,
        rating: 4.8,
        latitude: 6.927380,
        longitude: 79.845912,
        height: 30.0,
        description: 'Express groceries, fresh takeaway snacks, cold beverages, and essentials.',
        openStatus: 'OPEN NOW',
        imageUrl: 'https://images.unsplash.com/photo-1578916171728-46686eac8d58?w=500&auto=format&fit=crop&q=60'
      },
      {
        id: 'poi-b1-03',
        name: 'B1 Eco EV Fast-Charging Hub',
        category: 'TECH & ELECTRONICS',
        floorNumber: -1,
        rating: 4.9,
        latitude: 6.926780,
        longitude: 79.845312,
        height: 30.0,
        description: 'High-speed 120kW DC EV chargers for Tesla, Hyundai, Nissan & BYD vehicles.',
        openStatus: '24/7',
        imageUrl: 'https://images.unsplash.com/photo-1563720223185-11003d516935?w=500&auto=format&fit=crop&q=60'
      },
      {
        id: 'poi-b1-04',
        name: 'B1 Auto Car Wash & Detailing',
        category: 'SERVICES',
        floorNumber: -1,
        rating: 4.7,
        latitude: 6.926780,
        longitude: 79.845912,
        height: 30.0,
        description: 'Eco-friendly waterless car wash, interior vacuuming & ceramic coating.',
        openStatus: 'OPEN NOW',
        imageUrl: 'https://images.unsplash.com/photo-1520340356584-f9917d1eea6f?w=500&auto=format&fit=crop&q=60'
      },
      {
        id: 'poi-g-01',
        name: 'Dilmah Ceylon Tea Lounge',
        category: 'DINING & CAFES',
        floorNumber: 0,
        rating: 4.9,
        latitude: 6.927079,
        longitude: 79.845612,
        height: 35.0,
        description: 'Artisanal single-origin tea pairings, high tea tiers, and fresh baked pastries.',
        openStatus: 'OPEN NOW',
        imageUrl: 'https://images.unsplash.com/photo-1576092768241-dec231879fc3?w=500&auto=format&fit=crop&q=60'
      },
      {
        id: 'poi-g-02',
        name: 'Odel Flagship Luxury Store',
        category: 'FASHION & APPAREL',
        floorNumber: 0,
        rating: 4.8,
        latitude: 6.927180,
        longitude: 79.845712,
        height: 35.0,
        description: 'Premium international designer apparel, perfumes, cosmetics, and leather accessories.',
        openStatus: 'OPEN NOW',
        imageUrl: 'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=500&auto=format&fit=crop&q=60'
      },
      {
        id: 'poi-g-03',
        name: 'Hugo Boss Luxury Lounge',
        category: 'FASHION & APPAREL',
        floorNumber: 0,
        rating: 4.9,
        latitude: 6.926980,
        longitude: 79.845512,
        height: 35.0,
        description: 'Tailored European menswear, suits, timepieces, and luxury leather footwear.',
        openStatus: 'OPEN NOW',
        imageUrl: 'https://images.unsplash.com/photo-1594938298603-c8148c4dae35?w=500&auto=format&fit=crop&q=60'
      },
      {
        id: 'poi-g-04',
        name: 'Spa Ceylon Luxury Ayurveda',
        category: 'HEALTH & BEAUTY',
        floorNumber: 0,
        rating: 4.9,
        latitude: 6.927280,
        longitude: 79.845412,
        height: 35.0,
        description: 'Royal Ceylon wellness oils, aromatherapy, herbal skin care, and luxury gifts.',
        openStatus: 'OPEN NOW',
        imageUrl: 'https://images.unsplash.com/photo-1608248597260-84a1421f1d1f?w=500&auto=format&fit=crop&q=60'
      },
      {
        id: 'poi-l2-01',
        name: 'Ministry of Crab Express',
        category: 'DINING & CAFES',
        floorNumber: 2,
        rating: 4.9,
        latitude: 6.927080,
        longitude: 79.845412,
        height: 45.0,
        description: 'World-famous lagoon crab dishes, garlic chilli prawn bowls, and gourmet seafood.',
        openStatus: 'OPEN NOW',
        imageUrl: 'https://images.unsplash.com/photo-1559742811-822863646df1?w=500&auto=format&fit=crop&q=60'
      },
      {
        id: 'poi-l2-02',
        name: 'Food Studio Ceylon Court',
        category: 'DINING & CAFES',
        floorNumber: 2,
        rating: 4.7,
        latitude: 6.927280,
        longitude: 79.845712,
        height: 45.0,
        description: 'Multi-cuisine food hall featuring authentic Sri Lankan, Thai, Japanese & Italian counters.',
        openStatus: 'OPEN NOW',
        imageUrl: 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=500&auto=format&fit=crop&q=60'
      },
      {
        id: 'poi-l3-01',
        name: 'PVR Scope Cinemas IMAX 3D',
        category: 'ENTERTAINMENT',
        floorNumber: 3,
        rating: 4.9,
        latitude: 6.927180,
        longitude: 79.845812,
        height: 50.0,
        description: 'Ultra-HD IMAX laser projector theater, Dolby Atmos audio, recliner seating & popcorn bar.',
        openStatus: 'OPEN NOW',
        imageUrl: 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=500&auto=format&fit=crop&q=60'
      },
      {
        id: 'poi-l3-02',
        name: 'Abans Elite Apple & LG Store',
        category: 'TECH & ELECTRONICS',
        floorNumber: 3,
        rating: 4.8,
        latitude: 6.926880,
        longitude: 79.845412,
        height: 50.0,
        description: 'Authorized Apple reseller featuring iPhone, MacBook Pro, iPad, and LG OLED displays.',
        openStatus: 'OPEN NOW',
        imageUrl: 'https://images.unsplash.com/photo-1531297484001-80022131f5a1?w=500&auto=format&fit=crop&q=60'
      }
    ],

    // Smart Parking Matrix (40 Spots in Basement B1 Deck)
    parkingSpots: Array.from({ length: 40 }, (_, i) => {
      const idNumber = String(i + 1).padStart(3, '0');
      let status = 'vacant';
      let type = 'standard';
      
      if (i % 3 === 0) status = 'occupied';
      if (i % 7 === 0) status = 'reserved';
      if (i >= 32) {
        type = 'ev';
        status = i % 2 === 0 ? 'occupied' : 'vacant';
      }

      return {
        id: `B1-${idNumber}`,
        zone: i < 20 ? 'Zone A (West)' : 'Zone B (East)',
        status: status, // vacant, occupied, reserved
        type: type, // standard, ev, handicap, valet
        licensePlate: status === 'occupied' ? `CAB-${Math.floor(1000 + Math.random() * 9000)}` : null,
        durationMins: status === 'occupied' ? Math.floor(15 + Math.random() * 180) : 0
      };
    }),

    // ALPR License Plate Recognition Logs
    alprLogs: [
      { id: 'ALPR-901', plate: 'CAB-4912', spotId: 'B1-003', entryTime: '10:14 AM', vehicle: 'Toyota Prius (White)', feeLKR: 500 },
      { id: 'ALPR-902', plate: 'WP-CBD-8821', spotId: 'B1-034', entryTime: '09:45 AM', vehicle: 'Tesla Model Y (Black EV)', feeLKR: 900 },
      { id: 'ALPR-903', plate: 'CAD-1120', spotId: 'B1-007', entryTime: '10:32 AM', vehicle: 'BMW X5 (Blue)', feeLKR: 250 },
      { id: 'ALPR-904', plate: 'K-6712', spotId: 'B1-012', entryTime: '08:20 AM', vehicle: 'Honda Vezel (Grey)', feeLKR: 750 },
      { id: 'ALPR-905', plate: 'WP-CAR-9901', spotId: 'B1-018', entryTime: '10:48 AM', vehicle: 'Mercedes Benz E-Class', feeLKR: 250 }
    ],

    // AR Spatial Reference Markers & Beacons
    markers: [
      {
        id: 'REF-ENTRANCE-01',
        name: 'North Main Atrium Entrance Poster Anchor',
        floorNumber: 0,
        latitude: 6.927079,
        longitude: 79.845612,
        height: 1.65,
        widthMeters: 0.25,
        qrCodeData: 'NexNav:REF-ENTRANCE-01:6.927079:79.845612:45.0',
        lastCalibrated: '2026-09-28'
      },
      {
        id: 'REF-B1-VALET-02',
        name: 'Basement 1 Valet Elevator Pillar Anchor',
        floorNumber: -1,
        latitude: 6.927380,
        longitude: 79.845312,
        height: 1.50,
        widthMeters: 0.30,
        qrCodeData: 'NexNav:REF-B1-VALET-02:6.927380:79.845312:30.0',
        lastCalibrated: '2026-09-25'
      },
      {
        id: 'REF-FOODCOURT-03',
        name: 'Level 2 Food Studio Entrance Column',
        floorNumber: 2,
        latitude: 6.927280,
        longitude: 79.845712,
        height: 1.70,
        widthMeters: 0.25,
        qrCodeData: 'NexNav:REF-FOODCOURT-03:6.927280:79.845712:45.0',
        lastCalibrated: '2026-09-29'
      },
      {
        id: 'REF-CINEMA-04',
        name: 'Level 3 IMAX Ticket Counter Wall Anchor',
        floorNumber: 3,
        latitude: 6.927180,
        longitude: 79.845812,
        height: 1.80,
        widthMeters: 0.25,
        qrCodeData: 'NexNav:REF-CINEMA-04:6.927180:79.845812:50.0',
        lastCalibrated: '2026-09-22'
      }
    ],

    // Wayfinding Indoor Node Graph Nodes & Links
    nodes: [
      { id: 'node-g-ent', name: 'Ground Entrance Anchor', floor: 0, x: 100, y: 350, type: 'entrance' },
      { id: 'node-g-atrium', name: 'Central Atrium Hub', floor: 0, x: 300, y: 250, type: 'hub' },
      { id: 'node-g-dilmah', name: 'Dilmah Tea Lounge Door', floor: 0, x: 450, y: 150, type: 'poi' },
      { id: 'node-g-odel', name: 'Odel Flagship Entrance', floor: 0, x: 450, y: 380, type: 'poi' },
      { id: 'node-g-elev-1', name: 'North Elevator Bank A', floor: 0, x: 250, y: 100, type: 'elevator' },
      { id: 'node-g-esca-up', name: 'Escalator L1 Up', floor: 0, x: 380, y: 250, type: 'escalator' },
      { id: 'node-g-exit-1', name: 'North Emergency Exit', floor: 0, x: 50, y: 100, type: 'exit' }
    ],
    edges: [
      { from: 'node-g-ent', to: 'node-g-atrium', distMeters: 18.5, wheelchair: true },
      { from: 'node-g-atrium', to: 'node-g-dilmah', distMeters: 12.0, wheelchair: true },
      { from: 'node-g-atrium', to: 'node-g-odel', distMeters: 14.2, wheelchair: true },
      { from: 'node-g-atrium', to: 'node-g-esca-up', distMeters: 8.0, wheelchair: false },
      { from: 'node-g-atrium', to: 'node-g-elev-1', distMeters: 15.0, wheelchair: true },
      { from: 'node-g-ent', to: 'node-g-exit-1', distMeters: 10.0, wheelchair: true }
    ],

    // Active Connected Mobile App Sessions Telemetry
    activeSessions: [
      { id: 'SESS-801', user: 'Mobile User #491', device: 'Apple iPhone 15 Pro', trackingEngine: 'ECEF + PnP Visual Pose', floor: 'Level 2 Dining', lat: 6.927281, lon: 79.845715, battery: '84%', fps: 60, status: 'NAVIGATING' },
      { id: 'SESS-802', user: 'Mobile User #112', device: 'Samsung Galaxy S24 Ultra', trackingEngine: 'ECEF + BLE Beacon', floor: 'Basement 1 Parking', lat: 6.927382, lon: 79.845314, battery: '92%', fps: 58, status: 'PARKING_LOCK' },
      { id: 'SESS-803', user: 'Mobile User #309', device: 'Google Pixel 8 Pro', trackingEngine: 'VPS Camera Marker', floor: 'Ground Floor Atrium', lat: 6.927081, lon: 79.845615, battery: '67%', fps: 60, status: 'IDLE_EXPLORING' },
      { id: 'SESS-804', user: 'Mobile User #771', device: 'Xiaomi 14 Ultra', trackingEngine: 'ECEF Geodetic GPS', floor: 'Level 3 Cinema', lat: 6.927182, lon: 79.845815, battery: '45%', fps: 54, status: 'NAVIGATING' }
    ],

    // API Keys
    apiKeys: [
      { id: 'key-prod-01', name: 'Mobile App iOS/Android Prod Client', key: 'nx_live_9f8a319d0a28b4c7e', created: '2026-08-15', status: 'ACTIVE' },
      { id: 'key-dev-02', name: 'Local Dev Debugging Key', key: 'nx_test_118a829f0011b22aa', created: '2026-09-01', status: 'ACTIVE' }
    ]
  };

  // State Change Notification
  function notify() {
    listeners.forEach(fn => fn(state));
  }

  return {
    subscribe: function (fn) {
      listeners.push(fn);
      fn(state);
    },
    getState: function () {
      return state;
    },
    
    // Building Actions
    setActiveBuilding: function (buildingId) {
      state.activeBuildingId = buildingId;
      notify();
    },
    
    // Shop / POI Actions
    addShop: function (newShop) {
      state.shops.unshift(newShop);
      notify();
    },
    updateShop: function (id, updatedData) {
      const idx = state.shops.findIndex(s => s.id === id);
      if (idx !== -1) {
        state.shops[idx] = { ...state.shops[idx], ...updatedData };
        notify();
      }
    },
    deleteShop: function (id) {
      state.shops = state.shops.filter(s => s.id !== id);
      notify();
    },

    // Parking Spot State Toggle
    toggleParkingSpot: function (spotId) {
      const idx = state.parkingSpots.findIndex(p => p.id === spotId);
      if (idx !== -1) {
        const current = state.parkingSpots[idx].status;
        const next = current === 'vacant' ? 'occupied' : (current === 'occupied' ? 'reserved' : 'vacant');
        state.parkingSpots[idx].status = next;
        state.parkingSpots[idx].licensePlate = next === 'occupied' ? `CAB-${Math.floor(1000 + Math.random() * 9000)}` : null;
        notify();
      }
    },

    // AR Reference Marker Actions
    addMarker: function (marker) {
      state.markers.unshift(marker);
      notify();
    },
    deleteMarker: function (id) {
      state.markers = state.markers.filter(m => m.id !== id);
      notify();
    },

    // Wayfinding Node Actions
    addNode: function (node) {
      state.nodes.push(node);
      notify();
    },

    // Emergency Evacuation Override
    setEmergency: function (active, reason = '') {
      state.emergencyActive = active;
      state.emergencyReason = reason;
      notify();
    },

    // Auth Management
    login: function (email, password, role = 'Super Admin', name = '') {
      let avatar = 'SA';
      let userName = name || (email ? email.split('@')[0] : 'Admin User');
      if (role === 'Super Admin') { avatar = 'SA'; if (!name) userName = 'Sinthujan A.'; }
      else if (role === 'Venue Operations Manager') { avatar = 'VM'; if (!name) userName = 'Sarah Jenkins'; }
      else if (role === 'Security & Emergency Officer') { avatar = 'SO'; if (!name) userName = 'Cmdr. Dave Miller'; }

      state.auth = {
        isLoggedIn: true,
        user: {
          email: email || 'admin@navcore.io',
          name: userName,
          role: role,
          avatar: avatar
        }
      };

      try {
        localStorage.setItem('navcore_logged_in', 'true');
        localStorage.setItem('navcore_user_session', JSON.stringify(state.auth.user));
      } catch (e) {
        console.warn('LocalStorage error', e);
      }

      notify();
      return state.auth.user;
    },

    logout: function () {
      state.auth = {
        isLoggedIn: false,
        user: null
      };

      try {
        localStorage.removeItem('navcore_logged_in');
        localStorage.removeItem('navcore_user_session');
      } catch (e) {
        console.warn('LocalStorage error', e);
      }

      notify();
    },

    isLoggedIn: function () {
      return state.auth ? state.auth.isLoggedIn : false;
    },

    getUser: function () {
      return state.auth ? state.auth.user : null;
    }
  };
})();
