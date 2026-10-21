const fs = require('fs');
const path = require('path');

const DATA_DIR = path.join(__dirname, '..', 'data');
const DB_JSON_PATH = path.join(DATA_DIR, 'db.json');
const DUMP_JSON_PATH = path.join(DATA_DIR, 'db.dump.json');
const ALIAS_DUMP_PATH = path.join(DATA_DIR, 'dump.json');
const DUMP_SQL_PATH = path.join(DATA_DIR, 'dump.sql');

if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// Clean Seed / Production Initial Database Dataset (Without dummy venues)
const masterDatabase = {
  users: [
    {
      id: 'usr-admin-01',
      email: 'admin@nexnav.com',
      password: 'Admin@1234',
      name: 'System Administrator',
      role: 'admin',
      createdAt: '2026-10-01T00:00:00.000Z',
    },
  ],
  malls: [],
  entranceMarkers: [],
  floorHeights: [],
  destinations: [],
  parkingSlots: [],
  vehicleLocations: {},
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
`;

  const esc = (val) => {
    if (val === null || val === undefined) return 'NULL';
    if (typeof val === 'boolean') return val ? 'TRUE' : 'FALSE';
    if (typeof val === 'number') return val;
    return `'${String(val).replace(/'/g, "''")}'`;
  };

  // Insert Users
  sql += `\n-- 1. Users\n`;
  for (const u of (data.users || [])) {
    sql += `INSERT INTO users (id, email, password, name, role, created_at) VALUES (${esc(u.id)}, ${esc(u.email)}, ${esc(u.password)}, ${esc(u.name)}, ${esc(u.role)}, ${esc(u.createdAt)});\n`;
  }

  // Insert Malls (if any)
  if (data.malls && data.malls.length > 0) {
    sql += `\n-- 2. Malls\n`;
    for (const m of data.malls) {
      sql += `INSERT INTO malls (id, name, city, country, latitude, longitude, floor_count, package_size_bytes_mb, category, rating, is_downloaded, is_active, entrance_base_anchor_height, floor_gap_meters) VALUES (${esc(m.id)}, ${esc(m.name)}, ${esc(m.city)}, ${esc(m.country)}, ${esc(m.latitude)}, ${esc(m.longitude)}, ${esc(m.floorCount)}, ${esc(m.packageSizeBytesMB)}, ${esc(m.category)}, ${esc(m.rating)}, ${esc(m.isDownloaded)}, ${esc(m.isActive)}, ${esc(m.entranceBaseAnchorHeight)}, ${esc(m.floorGapMeters)});\n`;
    }
  }

  // Insert Entrance Markers (if any)
  if (data.entranceMarkers && data.entranceMarkers.length > 0) {
    sql += `\n-- 3. Entrance Markers\n`;
    for (const em of data.entranceMarkers) {
      sql += `INSERT INTO entrance_markers (marker_id, building_id, name, latitude, longitude, base_height, physical_width_meters, physical_height_meters, qr_code_data) VALUES (${esc(em.markerId)}, ${esc(em.buildingId)}, ${esc(em.name)}, ${esc(em.latitude)}, ${esc(em.longitude)}, ${esc(em.baseHeight)}, ${esc(em.physicalWidthMeters)}, ${esc(em.physicalHeightMeters)}, ${esc(em.qrCodeData)});\n`;
    }
  }

  // Insert Floor Heights (if any)
  if (data.floorHeights && data.floorHeights.length > 0) {
    sql += `\n-- 4. Floor Heights\n`;
    for (const fh of data.floorHeights) {
      sql += `INSERT INTO floor_heights (mall_id, floor_no, height_to_next_m, base_altitude_m, source, confidence, is_locked, updated_at) VALUES (${esc(fh.mallId)}, ${esc(fh.floorNo)}, ${esc(fh.heightToNextM)}, ${esc(fh.baseAltitudeM)}, ${esc(fh.source)}, ${esc(fh.confidence)}, ${esc(fh.isLocked)}, ${esc(fh.updatedAt)});\n`;
    }
  }

  // Insert Destinations (if any)
  if (data.destinations && data.destinations.length > 0) {
    sql += `\n-- 5. Destinations (POIs)\n`;
    for (const d of data.destinations) {
      sql += `INSERT INTO destinations (id, mall_id, name, category, floor_number, rating, latitude, longitude, height, description, open_status, opening_hours, image_url) VALUES (${esc(d.id)}, ${esc(d.mallId)}, ${esc(d.name)}, ${esc(d.category)}, ${esc(d.floorNumber)}, ${esc(d.rating)}, ${esc(d.latitude)}, ${esc(d.longitude)}, ${esc(d.height)}, ${esc(d.description)}, ${esc(d.openStatus)}, ${esc(d.openingHours)}, ${esc(d.imageUrl)});\n`;
    }
  }

  // Insert Parking Slots (if any)
  if (data.parkingSlots && data.parkingSlots.length > 0) {
    sql += `\n-- 6. Parking Slots\n`;
    for (const ps of data.parkingSlots) {
      sql += `INSERT INTO parking_slots (id, mall_id, floor_id, section, slot_number, status, latitude, longitude, height, grid_row, grid_col, is_ev_charging, is_handicap_accessible, sensor_id) VALUES (${esc(ps.id)}, ${esc(ps.mallId)}, ${esc(ps.floorId)}, ${esc(ps.section)}, ${esc(ps.slotNumber)}, ${esc(ps.status)}, ${esc(ps.latitude)}, ${esc(ps.longitude)}, ${esc(ps.height)}, ${esc(ps.gridRow)}, ${esc(ps.gridCol)}, ${esc(ps.isEVCharging)}, ${esc(ps.isHandicapAccessible)}, ${esc(ps.sensorId)});\n`;
    }
  }

  // Insert Vehicle Locations (if any)
  if (data.vehicleLocations && Object.keys(data.vehicleLocations).length > 0) {
    sql += `\n-- 7. Vehicle Locations\n`;
    for (const [userId, vl] of Object.entries(data.vehicleLocations)) {
      sql += `INSERT INTO vehicle_locations (user_id, vehicle_id, slot_id, floor_id, floor_name, latitude, longitude, height, timestamp, status, license_plate, notes) VALUES (${esc(userId)}, ${esc(vl.vehicleId)}, ${esc(vl.slotId)}, ${esc(vl.floorId)}, ${esc(vl.floorName)}, ${esc(vl.latitude)}, ${esc(vl.longitude)}, ${esc(vl.height)}, ${esc(vl.timestamp)}, ${esc(vl.status)}, ${esc(vl.licensePlate)}, ${esc(vl.notes)});\n`;
    }
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
      if (live.users && live.users.length > 0) {
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

  // 3. Write alias dump.json
  fs.writeFileSync(ALIAS_DUMP_PATH, JSON.stringify(activeData, null, 2), 'utf-8');

  // 4. Write backend/data/dump.sql (SQL DDL/DML dump)
  const sqlContent = generateSqlDump(activeData);
  fs.writeFileSync(DUMP_SQL_PATH, sqlContent, 'utf-8');
  console.log(`[Seed CLI] Successfully wrote SQL database dump: ${DUMP_SQL_PATH}`);

  console.log('\n--- Database Dump Summary ---');
  console.log(`Users:            ${(activeData.users || []).length}`);
  console.log(`Malls:            ${(activeData.malls || []).length}`);
  console.log(`Entrance Markers: ${(activeData.entranceMarkers || []).length}`);
  console.log(`Floor Heights:    ${(activeData.floorHeights || []).length}`);
  console.log(`Destinations:     ${(activeData.destinations || []).length}`);
  console.log(`Parking Slots:    ${(activeData.parkingSlots || []).length}`);
  console.log(`Vehicle Records:  ${Object.keys(activeData.vehicleLocations || {}).length}`);
  console.log('-----------------------------\n');
}

run();
