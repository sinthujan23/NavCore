-- =========================================================================
-- NexNav NavCore Server Database Dump
-- Compatible with PostgreSQL, SQLite3, and MySQL
-- Generated At: 2026-10-12T15:45:00.000Z
-- =========================================================================

-- Drop tables if exists (clean restore)
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

-- =========================================================================
-- Data Inserts
-- =========================================================================

-- 1. Users
INSERT INTO users (id, email, password, name, role, created_at) VALUES ('usr-admin-01', 'admin@nexnav.com', 'admin123', 'System Administrator', 'admin', '2026-10-01T00:00:00.000Z');
INSERT INTO users (id, email, password, name, role, created_at) VALUES ('usr-regular-01', 'user@nexnav.com', 'user123', 'NexNav Shopper', 'user', '2026-10-01T00:00:00.000Z');
INSERT INTO users (id, email, password, name, role, created_at) VALUES ('usr-tester-01', 'tester@nexnav.com', 'test123', 'AR Field QA Tester', 'user', '2026-10-01T00:00:00.000Z');

-- 2. Malls
INSERT INTO malls (id, name, city, country, latitude, longitude, floor_count, package_size_bytes_mb, category, rating, is_downloaded, is_active, entrance_base_anchor_height, floor_gap_meters) VALUES ('mall-one-galle-face', 'One Galle Face Mall & Tower', 'Colombo', 'Sri Lanka', 6.927079, 79.845612, 5, 14.2, 'Premier Oceanfront Mall', '4.9 ★', TRUE, TRUE, 45.0, 5.0);
INSERT INTO malls (id, name, city, country, latitude, longitude, floor_count, package_size_bytes_mb, category, rating, is_downloaded, is_active, entrance_base_anchor_height, floor_gap_meters) VALUES ('mall-colombo-city-centre', 'Colombo City Centre (CCC)', 'Colombo', 'Sri Lanka', 6.91672, 79.85501, 5, 18.5, 'Luxury Shopping & Lifestyle', '4.8 ★', TRUE, FALSE, 35.0, 4.8);
INSERT INTO malls (id, name, city, country, latitude, longitude, floor_count, package_size_bytes_mb, category, rating, is_downloaded, is_active, entrance_base_anchor_height, floor_gap_meters) VALUES ('mall-havelock-city', 'Havelock City Mall', 'Colombo', 'Sri Lanka', 6.88502, 79.86603, 5, 16.8, 'Lifestyle & Retail Hub', '4.8 ★', TRUE, FALSE, 30.0, 4.5);
INSERT INTO malls (id, name, city, country, latitude, longitude, floor_count, package_size_bytes_mb, category, rating, is_downloaded, is_active, entrance_base_anchor_height, floor_gap_meters) VALUES ('mall-kandy-city-centre', 'Kandy City Centre (KCC)', 'Kandy', 'Sri Lanka', 7.29362, 80.63503, 5, 15.1, 'Heritage Commercial Complex', '4.7 ★', TRUE, FALSE, 500.0, 4.5);
INSERT INTO malls (id, name, city, country, latitude, longitude, floor_count, package_size_bytes_mb, category, rating, is_downloaded, is_active, entrance_base_anchor_height, floor_gap_meters) VALUES ('mall-marino-mall', 'Marino Mall & Entertainment', 'Colombo', 'Sri Lanka', 6.89781, 79.85472, 5, 12.4, 'Tech & Waterfront Mall', '4.6 ★', TRUE, FALSE, 25.0, 4.5);

-- 3. Entrance Markers
INSERT INTO entrance_markers (marker_id, building_id, name, latitude, longitude, base_height, physical_width_meters, physical_height_meters, qr_code_data) VALUES ('mrk-ogf-01', 'mall-one-galle-face', 'One Galle Face Main Ocean Gate 1', 6.927079, 79.845612, 45.0, 0.25, 0.25, 'NEXNAV://MALL/mall-one-galle-face/MARKER/01');
INSERT INTO entrance_markers (marker_id, building_id, name, latitude, longitude, base_height, physical_width_meters, physical_height_meters, qr_code_data) VALUES ('mrk-ogf-02', 'mall-one-galle-face', 'One Galle Face North Elevator Pillar', 6.927179, 79.845712, 45.0, 0.25, 0.25, 'NEXNAV://MALL/mall-one-galle-face/MARKER/02');
INSERT INTO entrance_markers (marker_id, building_id, name, latitude, longitude, base_height, physical_width_meters, physical_height_meters, qr_code_data) VALUES ('mrk-ccc-01', 'mall-colombo-city-centre', 'CCC Main Atrium Gate', 6.91672, 79.85501, 35.0, 0.25, 0.25, 'NEXNAV://MALL/mall-colombo-city-centre/MARKER/01');
INSERT INTO entrance_markers (marker_id, building_id, name, latitude, longitude, base_height, physical_width_meters, physical_height_meters, qr_code_data) VALUES ('mrk-hvc-01', 'mall-havelock-city', 'Havelock City Boulevard West Gate', 6.88502, 79.86603, 30.0, 0.25, 0.25, 'NEXNAV://MALL/mall-havelock-city/MARKER/01');
INSERT INTO entrance_markers (marker_id, building_id, name, latitude, longitude, base_height, physical_width_meters, physical_height_meters, qr_code_data) VALUES ('mrk-kcc-01', 'mall-kandy-city-centre', 'KCC Heritage Plaza Gate 1', 7.29362, 80.63503, 500.0, 0.25, 0.25, 'NEXNAV://MALL/mall-kandy-city-centre/MARKER/01');
INSERT INTO entrance_markers (marker_id, building_id, name, latitude, longitude, base_height, physical_width_meters, physical_height_meters, qr_code_data) VALUES ('mrk-mar-01', 'mall-marino-mall', 'Marino Mall Galle Road Entrance', 6.89781, 79.85472, 25.0, 0.25, 0.25, 'NEXNAV://MALL/mall-marino-mall/MARKER/01');

-- 4. Floor Heights
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-one-galle-face', -1, 5.0, 40.0, 'admin', 1.0, TRUE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-one-galle-face', 1, 5.0, 45.0, 'admin', 1.0, TRUE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-one-galle-face', 2, 5.0, 50.0, 'admin', 1.0, TRUE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-one-galle-face', 3, 5.0, 55.0, 'admin', 1.0, TRUE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-one-galle-face', 4, 5.0, 60.0, 'admin', 1.0, TRUE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-colombo-city-centre', -1, 4.8, 30.2, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-colombo-city-centre', 1, 4.8, 35.0, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-colombo-city-centre', 2, 4.8, 39.8, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-colombo-city-centre', 3, 4.8, 44.6, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-colombo-city-centre', 4, 4.8, 49.4, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-havelock-city', -1, 4.5, 25.5, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-havelock-city', 1, 4.5, 30.0, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-havelock-city', 2, 4.5, 34.5, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-havelock-city', 3, 4.5, 39.0, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-havelock-city', 4, 4.5, 43.5, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-kandy-city-centre', 1, 4.5, 500.0, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-kandy-city-centre', 2, 4.5, 504.5, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-kandy-city-centre', 3, 4.5, 509.0, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-marino-mall', 1, 4.5, 25.0, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-marino-mall', 2, 4.5, 29.5, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');
INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES ('mall-marino-mall', 3, 4.5, 34.0, 'admin', 1.0, FALSE, '2026-10-01T00:00:00.000Z');

-- 5. Destinations (POIs)
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-b1-01', 'mall-one-galle-face', 'B1 Executive Valet & Concierge', 'SERVICES', -1, 4.9, 6.92738, 79.845312, 40.0, 'VIP valet drop-off, luggage storage, and premium parking concierge desk.', 'OPEN NOW', '24 Hours Open', 'assets/images/shops/b1_executive_valet_concierge.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-b1-02', 'mall-one-galle-face', 'Keells Express Supermarket B1', 'SERVICES', -1, 4.8, 6.92738, 79.845912, 40.0, 'Express groceries, fresh takeaway snacks, cold beverages, and essentials.', 'OPEN NOW', '08:00 AM - 10:00 PM', 'assets/images/shops/keells_express_supermarket_b1.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-b1-03', 'mall-one-galle-face', 'B1 Eco EV Fast-Charging Hub', 'TECH & ELECTRONICS', -1, 4.9, 6.92678, 79.845312, 40.0, 'High-speed 120kW DC EV chargers for Tesla, Hyundai, Nissan & BYD vehicles.', '24/7', '24 Hours Open', 'assets/images/shops/b1_eco_ev_charging_hub.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-b1-04', 'mall-one-galle-face', 'B1 Auto Car Wash & Detailing', 'SERVICES', -1, 4.7, 6.92678, 79.845912, 40.0, 'Eco-friendly waterless car wash, interior vacuuming & ceramic coating.', 'OPEN NOW', '09:00 AM - 08:00 PM', 'assets/images/shops/b1_auto_car_wash.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-b1-05', 'mall-one-galle-face', 'B1 Luggage Lockers & Express Counter', 'SERVICES', -1, 4.8, 6.92748, 79.845612, 40.0, 'Automated smart luggage lockers, parcel pickup, and courier services.', '24/7', '24 Hours Open', 'assets/images/shops/b1_luggage_lockers.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-101', 'mall-one-galle-face', 'Odel Flagship Department Store', 'RETAIL & FASHION', 1, 4.9, 6.92743, 79.845612, 45.0, 'Premier Sri Lankan lifestyle, fashion & department store.', 'OPEN NOW', '10:00 AM - 10:00 PM', 'assets/images/shops/odel_flagship_store.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-102', 'mall-one-galle-face', 'Concierge & Information Desk', 'SERVICES', 1, 5.0, 6.92733, 79.845862, 45.0, 'Sri Lanka tourist assistance, mall guide & lost property services.', '24/7', '24 Hours Open', 'assets/images/shops/concierge_information_desk.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-103', 'mall-one-galle-face', 'Spa Ceylon Luxury Ayurveda', 'SERVICES', 1, 4.9, 6.927079, 79.845962, 45.0, 'Royal Sri Lankan Ayurveda wellness, essential oils & skincare.', 'OPEN NOW', '10:00 AM - 10:00 PM', 'assets/images/shops/spa_ceylon_luxury_ayurveda.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-104', 'mall-one-galle-face', 'Dilmah Tea Lounge & t-Bar', 'FOOD & DRINK', 1, 4.8, 6.92683, 79.845862, 45.0, 'Handpicked single-origin Ceylon tea tasting, mocktails & high tea.', 'OPEN NOW', '08:30 AM - 11:00 PM', 'assets/images/shops/dilmah_tea_lounge.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-105', 'mall-one-galle-face', 'Keells Super Hypermarket', 'SERVICES', 1, 4.7, 6.92673, 79.845612, 45.0, 'Gourmet groceries, fresh Sri Lankan produce, bakery & spices.', 'OPEN NOW', '08:00 AM - 10:00 PM', 'assets/images/shops/keells_super_hypermarket.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-201', 'mall-one-galle-face', 'Cotton Collection', 'RETAIL & FASHION', 2, 4.6, 6.92683, 79.845362, 50.0, 'Casual island wear, linen garments, tropical resort fashion & accessories.', 'OPEN NOW', '10:00 AM - 10:00 PM', 'assets/images/shops/cotton_collection.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-202', 'mall-one-galle-face', 'Kelly Felder Designer Lounge', 'RETAIL & FASHION', 2, 4.8, 6.927079, 79.845262, 50.0, 'Chic Sri Lankan womenswear, evening attire, and designer handbags.', 'OPEN NOW', '10:00 AM - 10:00 PM', 'assets/images/shops/kelly_felder_designer_lounge.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-203', 'mall-one-galle-face', 'House of Fashion Outlet', 'RETAIL & FASHION', 2, 4.7, 6.92733, 79.845362, 50.0, 'Extensive selection of international trends and local Sri Lankan apparel.', 'OPEN NOW', '10:00 AM - 10:00 PM', 'assets/images/shops/house_of_fashion_outlet.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-204', 'mall-one-galle-face', 'Barefoot Ceylon Handwoven Gallery', 'RETAIL & FASHION', 2, 4.9, 6.92748, 79.845612, 50.0, 'Vibrant handwoven Sri Lankan textiles, books, toys, and artisanal crafts.', 'OPEN NOW', '10:00 AM - 10:00 PM', 'assets/images/shops/barefoot_ceylon_handwoven.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-205', 'mall-one-galle-face', 'Hugo Boss & Luxury Apparel', 'RETAIL & FASHION', 2, 4.8, 6.927079, 79.846012, 50.0, 'Premium luxury suits, formal wear, leather shoes & accessories.', 'OPEN NOW', '10:00 AM - 10:00 PM', 'assets/images/shops/hugo_boss_luxury_apparel.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-301', 'mall-one-galle-face', 'Singer Mega Experience Center', 'TECH & ELECTRONICS', 3, 4.8, 6.92738, 79.845912, 55.0, 'Smart TVs, home electronics, laptops, and consumer technology.', 'OPEN NOW', '10:00 AM - 10:00 PM', 'assets/images/shops/singer_mega_experience_center.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-302', 'mall-one-galle-face', 'Abans Elite Apple & LG Store', 'TECH & ELECTRONICS', 3, 4.9, 6.92678, 79.845912, 55.0, 'Authorized Apple products, iPhones, MacBooks, and LG smart devices.', 'OPEN NOW', '10:00 AM - 10:00 PM', 'assets/images/shops/abans_elite_apple_lg_store.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-303', 'mall-one-galle-face', 'Dialog Axiata Experience Centre', 'TECH & ELECTRONICS', 3, 4.8, 6.92668, 79.845612, 55.0, '5G SIM connections, eSIM activation, fiber broadband & IoT gadgets.', 'OPEN NOW', '09:30 AM - 09:30 PM', 'assets/images/shops/dialog_axiata_experience_centre.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-304', 'mall-one-galle-face', 'Mobitel & SLT Broadband Lounge', 'TECH & ELECTRONICS', 3, 4.7, 6.92678, 79.845312, 55.0, 'National telecom service desk, fiber routers, and mobile accessories.', 'OPEN NOW', '09:30 AM - 09:30 PM', 'assets/images/shops/mobitel_slt_broadband_lounge.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-305', 'mall-one-galle-face', 'Samsung Smart Experience Zone', 'TECH & ELECTRONICS', 3, 4.9, 6.927079, 79.845212, 55.0, 'Galaxy smartphones, tablets, smartwatches & home appliance displays.', 'OPEN NOW', '10:00 AM - 10:00 PM', 'assets/images/shops/samsung_smart_experience_zone.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-401', 'mall-one-galle-face', 'Food Studio Ceylon Court', 'FOOD & DRINK', 4, 4.9, 6.92738, 79.845312, 60.0, 'Fresh Kottu Roti, Jaffna Crab Curry, Egg Hoppers & Ceylon street food.', 'OPEN NOW', '10:00 AM - 11:00 PM', 'assets/images/shops/food_studio_ceylon_court.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-402', 'mall-one-galle-face', 'Ministry of Crab Express', 'FOOD & DRINK', 4, 5.0, 6.92753, 79.845612, 60.0, 'World-renowned Sri Lankan giant lagoon crab & Garlic Chili Prawns.', 'OPEN NOW', '11:00 AM - 11:00 PM', 'assets/images/shops/ministry_of_crab_express.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-403', 'mall-one-galle-face', 'Barista Ceylon Espresso Bar', 'FOOD & DRINK', 4, 4.7, 6.92738, 79.845962, 60.0, 'Artisanal local coffees, iced lattes, fresh pastries, and savories.', 'OPEN NOW', '08:00 AM - 11:00 PM', 'assets/images/shops/barista_ceylon_espresso_bar.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-404', 'mall-one-galle-face', 'Taco Bell Sri Lanka', 'FOOD & DRINK', 4, 4.6, 6.927079, 79.846062, 60.0, 'Mexican inspired burritos, crunchy tacos, and spicy Sri Lankan sauces.', 'OPEN NOW', '10:00 AM - 11:00 PM', 'assets/images/shops/taco_bell_sri_lanka.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-405', 'mall-one-galle-face', 'PVR / Scope Cinemas IMAX OGF', 'ENTERTAINMENT', 4, 5.0, 6.92668, 79.845962, 60.0, 'Premium 3D IMAX screen, Dolby Atmos surround sound & luxury recliners.', 'OPEN NOW', '10:00 AM - 11:30 PM', 'assets/images/shops/pvr_scope_cinemas_imax.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-ccc-01', 'mall-colombo-city-centre', 'Scope Cinemas Multiplex CCC', 'ENTERTAINMENT', 3, 4.9, 6.91682, 79.85511, 44.6, '6-screen world-class multiplex with Dolby Surround and VIP dining.', 'OPEN NOW', '10:00 AM - 11:30 PM', 'assets/images/shops/pvr_scope_cinemas_imax.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-ccc-02', 'mall-colombo-city-centre', 'Food Studio Overlooking Beira Lake', 'FOOD & DRINK', 3, 4.8, 6.91662, 79.85491, 44.6, 'Scenic international culinary court with panoramic Beira Lake views.', 'OPEN NOW', '10:00 AM - 10:30 PM', 'assets/images/shops/food_studio_ceylon_court.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-ccc-03', 'mall-colombo-city-centre', 'Apple Care & FutureWorld CCC', 'TECH & ELECTRONICS', 2, 4.9, 6.91672, 79.85521, 39.8, 'Apple Premium Reseller and official service center.', 'OPEN NOW', '10:00 AM - 09:30 PM', 'assets/images/shops/abans_elite_apple_lg_store.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-hvc-01', 'mall-havelock-city', 'Cargills Food City Gourmet Flagship', 'SERVICES', 1, 4.8, 6.88512, 79.86613, 30.0, 'Premium organic supermarket, delicatessen, imported cheeses & wines.', 'OPEN NOW', '08:00 AM - 10:00 PM', 'assets/images/shops/keells_super_hypermarket.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-hvc-02', 'mall-havelock-city', 'Scope Cinemas Havelock IMAX', 'ENTERTAINMENT', 4, 4.9, 6.88522, 79.86593, 43.5, 'Sri Lankas newest laser projection IMAX theatre.', 'OPEN NOW', '10:00 AM - 11:30 PM', 'assets/images/shops/pvr_scope_cinemas_imax.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-kcc-01', 'mall-kandy-city-centre', 'World of Outdoor & Adventure KCC', 'RETAIL & FASHION', 2, 4.7, 7.29372, 80.63513, 504.5, 'Hiking gear, mountain footwear, outdoor clothing and camping essentials.', 'OPEN NOW', '09:30 AM - 08:30 PM', 'assets/images/shops/cotton_collection.jpg');
INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES ('poi-mar-01', 'mall-marino-mall', 'VR Interactive Theme Zone', 'ENTERTAINMENT', 3, 4.8, 6.89791, 79.85482, 34.0, 'Futuristic 9D VR simulators, motion racing rigs & laser tag arena.', 'OPEN NOW', '10:30 AM - 10:00 PM', 'assets/images/shops/pvr_scope_cinemas_imax.jpg');

-- 6. Parking Slots
INSERT INTO parking_slots (id, mall_id, floor_id, section, slot_number, status, latitude, longitude, height, grid_row, grid_col, is_ev_charging, is_handicap_accessible, sensor_id) VALUES ('A-01', 'mall-one-galle-face', 'B1', 'A', 1, 'free', 6.92688, 79.845412, 40.0, 0, 0, TRUE, FALSE, 'snr-ogf-b1-a01');
INSERT INTO parking_slots (id, mall_id, floor_id, section, slot_number, status, latitude, longitude, height, grid_row, grid_col, is_ev_charging, is_handicap_accessible, sensor_id) VALUES ('A-02', 'mall-one-galle-face', 'B1', 'A', 2, 'free', 6.92688, 79.845432, 40.0, 0, 1, TRUE, FALSE, 'snr-ogf-b1-a02');
INSERT INTO parking_slots (id, mall_id, floor_id, section, slot_number, status, latitude, longitude, height, grid_row, grid_col, is_ev_charging, is_handicap_accessible, sensor_id) VALUES ('A-03', 'mall-one-galle-face', 'B1', 'A', 3, 'occupied', 6.92688, 79.845452, 40.0, 0, 2, FALSE, FALSE, 'snr-ogf-b1-a03');
INSERT INTO parking_slots (id, mall_id, floor_id, section, slot_number, status, latitude, longitude, height, grid_row, grid_col, is_ev_charging, is_handicap_accessible, sensor_id) VALUES ('A-04', 'mall-one-galle-face', 'B1', 'A', 4, 'free', 6.92688, 79.845472, 40.0, 0, 3, FALSE, TRUE, 'snr-ogf-b1-a04');
INSERT INTO parking_slots (id, mall_id, floor_id, section, slot_number, status, latitude, longitude, height, grid_row, grid_col, is_ev_charging, is_handicap_accessible, sensor_id) VALUES ('B-01', 'mall-one-galle-face', 'B1', 'B', 1, 'free', 6.92693, 79.845412, 40.0, 1, 0, FALSE, FALSE, 'snr-ogf-b1-b01');
INSERT INTO parking_slots (id, mall_id, floor_id, section, slot_number, status, latitude, longitude, height, grid_row, grid_col, is_ev_charging, is_handicap_accessible, sensor_id) VALUES ('B-02', 'mall-one-galle-face', 'B1', 'B', 2, 'reserved', 6.92693, 79.845432, 40.0, 1, 1, FALSE, FALSE, 'snr-ogf-b1-b02');
INSERT INTO parking_slots (id, mall_id, floor_id, section, slot_number, status, latitude, longitude, height, grid_row, grid_col, is_ev_charging, is_handicap_accessible, sensor_id) VALUES ('B-03', 'mall-one-galle-face', 'B1', 'B', 3, 'free', 6.92693, 79.845452, 40.0, 1, 2, FALSE, FALSE, 'snr-ogf-b1-b03');
INSERT INTO parking_slots (id, mall_id, floor_id, section, slot_number, status, latitude, longitude, height, grid_row, grid_col, is_ev_charging, is_handicap_accessible, sensor_id) VALUES ('B-04', 'mall-one-galle-face', 'B1', 'B', 4, 'free', 6.92693, 79.845472, 40.0, 1, 3, FALSE, TRUE, 'snr-ogf-b1-b04');
INSERT INTO parking_slots (id, mall_id, floor_id, section, slot_number, status, latitude, longitude, height, grid_row, grid_col, is_ev_charging, is_handicap_accessible, sensor_id) VALUES ('P-01', 'mall-one-galle-face', 'GF', 'P', 1, 'free', 6.927179, 79.845712, 45.0, 0, 0, TRUE, TRUE, 'snr-ogf-gf-p01');
INSERT INTO parking_slots (id, mall_id, floor_id, section, slot_number, status, latitude, longitude, height, grid_row, grid_col, is_ev_charging, is_handicap_accessible, sensor_id) VALUES ('P-02', 'mall-one-galle-face', 'GF', 'P', 2, 'occupied', 6.927179, 79.845732, 45.0, 0, 1, FALSE, FALSE, 'snr-ogf-gf-p02');

-- 7. Vehicle Locations
INSERT INTO vehicle_locations (user_id, vehicle_id, slot_id, floor_id, floor_name, latitude, longitude, height, timestamp, status, license_plate, notes) VALUES ('usr-regular-01', 'veh-user-01', 'A-03', 'B1', 'Basement Level B1', 6.92688, 79.845452, 40.0, '2026-10-12T08:30:00.000Z', 'parked', 'WP CAB-8821', 'Parked in Bay A-03 near Entrance Lift Core 2');
