-- =========================================================================
-- NexNav NavCore Server Database Dump
-- Compatible with PostgreSQL, SQLite3, and MySQL
-- Generated At: 2026-10-12T16:04:00.000Z
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
-- Data Inserts (Users only, clean state without dummy venues)
-- =========================================================================

-- 1. Users
INSERT INTO users (id, email, password, name, role, created_at) VALUES ('usr-admin-01', 'admin@nexnav.com', 'admin123', 'System Administrator', 'admin', '2026-10-01T00:00:00.000Z');
INSERT INTO users (id, email, password, name, role, created_at) VALUES ('usr-regular-01', 'user@nexnav.com', 'user123', 'NexNav Shopper', 'user', '2026-10-01T00:00:00.000Z');
