const fs = require('fs');
const path = require('path');

const BACKEND_DATA_DIR = path.join(__dirname, '..', 'data');
const DB_JSON_PATH = path.join(BACKEND_DATA_DIR, 'db.json');
const DB_DUMP_PATH = path.join(BACKEND_DATA_DIR, 'db.dump.json');
const DUMP_ALIAS_PATH = path.join(BACKEND_DATA_DIR, 'dump.json');
const DUMP_SQL_PATH = path.join(BACKEND_DATA_DIR, 'dump.sql');

const MOBILE_DATA_DIR = path.join(__dirname, '..', '..', 'navcore_mobile', 'assets', 'data');
const MOBILE_DB_JSON_PATH = path.join(MOBILE_DATA_DIR, 'db.json');

function cleanUsersDatabase() {
  console.log('====================================================');
  console.log('🧹 NexNav NavCore: Database User Data Purge Utility');
  console.log('====================================================\n');

  // 1. Process backend/data/db.json
  if (!fs.existsSync(DB_JSON_PATH)) {
    console.error(`❌ Database file not found at: ${DB_JSON_PATH}`);
    return;
  }

  let dbData;
  try {
    const raw = fs.readFileSync(DB_JSON_PATH, 'utf-8');
    dbData = JSON.parse(raw);
  } catch (err) {
    console.error(`❌ Failed to parse ${DB_JSON_PATH}:`, err.message);
    return;
  }

  const allUsers = Array.isArray(dbData.users) ? dbData.users : [];
  const initialUserCount = allUsers.length;

  // Filter users: KEEP ONLY ADMINS
  const adminUsers = allUsers.filter(u => u.role === 'admin');
  const removedUsers = allUsers.filter(u => u.role !== 'admin');
  const adminIds = new Set(adminUsers.map(u => u.id));
  const adminEmails = new Set(adminUsers.map(u => (u.email || '').toLowerCase()));

  console.log(`Initial total users in database: ${initialUserCount}`);
  console.log(`Preserved Admin users count:     ${adminUsers.length}`);
  console.log(`Non-admin users to purge:       ${removedUsers.length}`);

  if (removedUsers.length > 0) {
    console.log('\nPurged non-admin users:');
    removedUsers.forEach(u => console.log(`  - [ID: ${u.id}] ${u.email} (${u.name || 'Unnamed'})`));
  } else {
    console.log('\n(No non-admin users found in active db.json)');
  }

  // Update users collection
  dbData.users = adminUsers;

  // Clean vehicleLocations for non-admin users
  let vehicleLocationsBefore = 0;
  let vehicleLocationsAfter = 0;
  if (dbData.vehicleLocations && typeof dbData.vehicleLocations === 'object') {
    const origKeys = Object.keys(dbData.vehicleLocations);
    vehicleLocationsBefore = origKeys.length;
    const cleanedVehicleLocations = {};
    for (const [userId, loc] of Object.entries(dbData.vehicleLocations)) {
      if (adminIds.has(userId)) {
        cleanedVehicleLocations[userId] = loc;
      }
    }
    dbData.vehicleLocations = cleanedVehicleLocations;
    vehicleLocationsAfter = Object.keys(cleanedVehicleLocations).length;
    console.log(`Vehicle locations: reduced from ${vehicleLocationsBefore} to ${vehicleLocationsAfter}`);
  }

  // Clean verificationCodes for non-admin users
  if (Array.isArray(dbData.verificationCodes)) {
    const codesBefore = dbData.verificationCodes.length;
    dbData.verificationCodes = dbData.verificationCodes.filter(c => 
      adminEmails.has((c.email || '').toLowerCase())
    );
    const codesAfter = dbData.verificationCodes.length;
    console.log(`Verification OTP codes: reduced from ${codesBefore} to ${codesAfter}`);
  }

  // Save to db.json
  const formattedJson = JSON.stringify(dbData, null, 2);
  fs.writeFileSync(DB_JSON_PATH, formattedJson, 'utf-8');
  console.log(`\n✅ Saved cleaned database to: ${DB_JSON_PATH}`);

  // Save to db.dump.json and dump.json
  if (fs.existsSync(DB_DUMP_PATH)) {
    fs.writeFileSync(DB_DUMP_PATH, formattedJson, 'utf-8');
    console.log(`✅ Synced dump file: ${DB_DUMP_PATH}`);
  }
  if (fs.existsSync(DUMP_ALIAS_PATH)) {
    fs.writeFileSync(DUMP_ALIAS_PATH, formattedJson, 'utf-8');
    console.log(`✅ Synced alias dump file: ${DUMP_ALIAS_PATH}`);
  }

  // 2. Also clean navcore_mobile/assets/data/db.json if it exists
  if (fs.existsSync(MOBILE_DB_JSON_PATH)) {
    try {
      const mobileRaw = fs.readFileSync(MOBILE_DB_JSON_PATH, 'utf-8');
      const mobileData = JSON.parse(mobileRaw);
      if (Array.isArray(mobileData.users)) {
        const mobBefore = mobileData.users.length;
        mobileData.users = mobileData.users.filter(u => u.role === 'admin');
        const mobAfter = mobileData.users.length;
        fs.writeFileSync(MOBILE_DB_JSON_PATH, JSON.stringify(mobileData, null, 2), 'utf-8');
        console.log(`✅ Cleaned mobile bundled assets: ${MOBILE_DB_JSON_PATH} (Users: ${mobBefore} -> ${mobAfter})`);
      }
    } catch (e) {
      console.warn('⚠️ Could not update mobile asset db.json:', e.message);
    }
  }

  // 3. Re-run SQL dump generator from seed.js if available
  try {
    const seedScript = require('./seed');
    console.log('✅ Triggered seed dump sync for SQL and data tables.');
  } catch (_) {
    // Alternatively write dump.sql directly
  }

  console.log('\n====================================================');
  console.log('🎉 Database User Purge Completed Successfully!');
  console.log('Remaining Administrator(s):');
  adminUsers.forEach(admin => {
    console.log(`  ★ ${admin.name} <${admin.email}> [ID: ${admin.id}]`);
  });
  console.log('====================================================\n');
}

cleanUsersDatabase();
