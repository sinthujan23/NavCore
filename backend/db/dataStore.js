const fs = require('fs');
const path = require('path');

const DB_FILE = path.join(__dirname, '..', 'data', 'db.json');

// Ensure data directory exists
const dataDir = path.dirname(DB_FILE);
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

// Initial seed data with production-ready venues, POIs, floors, and credentials
const seedData = {
  users: [
    {
      id: 'usr-admin-01',
      email: 'admin@nexnav.com',
      password: 'Admin@1234',
      name: 'System Administrator',
      role: 'admin',
      isVerified: true,
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

class DataStore {
  constructor() {
    this.data = this._load();
    this._ensureCollections();
  }

  _ensureCollections() {
    if (!this.data) this.data = {};
    if (!Array.isArray(this.data.users)) this.data.users = [];
    if (!Array.isArray(this.data.malls)) this.data.malls = [];
    if (!Array.isArray(this.data.entranceMarkers)) this.data.entranceMarkers = [];
    if (!Array.isArray(this.data.floorHeights)) this.data.floorHeights = [];
    if (!Array.isArray(this.data.destinations)) this.data.destinations = [];
    if (!Array.isArray(this.data.parkingSlots)) this.data.parkingSlots = [];
    if (!Array.isArray(this.data.verificationCodes)) this.data.verificationCodes = [];
    if (!this.data.vehicleLocations || typeof this.data.vehicleLocations !== 'object') {
      this.data.vehicleLocations = {};
    }
  }

  _load() {
    try {
      if (fs.existsSync(DB_FILE)) {
        const raw = fs.readFileSync(DB_FILE, 'utf-8');
        const parsed = JSON.parse(raw);
        if (parsed.users && parsed.users.length > 0 && parsed.malls && parsed.malls.length > 0) {
          return parsed;
        }
      }
    } catch (err) {
      console.error('[DataStore] Error reading db.json, falling back to dump/seed:', err.message);
    }

    // Attempt restoring from database dump file if present (for clean cloud deployments)
    const DUMP_FILE = path.join(__dirname, '..', 'data', 'db.dump.json');
    const DUMP_ALIAS = path.join(__dirname, '..', 'data', 'dump.json');
    for (const dPath of [DUMP_FILE, DUMP_ALIAS]) {
      try {
        if (fs.existsSync(dPath)) {
          const rawDump = fs.readFileSync(dPath, 'utf-8');
          const parsedDump = JSON.parse(rawDump);
          if (parsedDump.users && parsedDump.users.length > 0) {
            this._save(parsedDump);
            return parsedDump;
          }
        }
      } catch (_) { }
    }

    this._save(seedData);
    return JSON.parse(JSON.stringify(seedData));
  }

  _save(newData) {
    try {
      const content = JSON.stringify(newData, null, 2);
      fs.writeFileSync(DB_FILE, content, 'utf-8');

      // Also permanently sync to dump files so all creates, updates, and deletes persist across server reloads
      const DUMP_FILE = path.join(__dirname, '..', 'data', 'db.dump.json');
      const DUMP_ALIAS = path.join(__dirname, '..', 'data', 'dump.json');
      try {
        fs.writeFileSync(DUMP_FILE, content, 'utf-8');
      } catch (_) { }
      try {
        fs.writeFileSync(DUMP_ALIAS, content, 'utf-8');
      } catch (_) { }
    } catch (err) {
      console.error('[DataStore] Error saving database:', err.message);
    }
  }

  get(collection) {
    this._ensureCollections();
    return this.data[collection] || [];
  }

  set(collection, items) {
    this._ensureCollections();
    this.data[collection] = items;
    this._save(this.data);
  }

  find(collection, predicate) {
    const list = this.get(collection);
    return list.find(predicate);
  }

  filter(collection, predicate) {
    const list = this.get(collection);
    return list.filter(predicate);
  }

  insert(collection, item) {
    this._ensureCollections();
    if (!Array.isArray(this.data[collection])) {
      this.data[collection] = [];
    }
    this.data[collection].push(item);
    this._save(this.data);
    return item;
  }

  // Alias for insert
  push(collection, item) {
    return this.insert(collection, item);
  }

  update(collection, predicate, updater) {
    this._ensureCollections();
    if (!Array.isArray(this.data[collection])) {
      this.data[collection] = [];
    }
    const list = this.data[collection];
    const index = list.findIndex(predicate);
    if (index !== -1) {
      const updated = updater(list[index]);
      list[index] = updated;
      this._save(this.data);
      return updated;
    }
    return null;
  }

  updateAll(collection, predicate, updater) {
    this._ensureCollections();
    if (!Array.isArray(this.data[collection])) {
      this.data[collection] = [];
    }
    const list = this.data[collection];
    let updatedCount = 0;
    for (let i = 0; i < list.length; i++) {
      if (predicate(list[i])) {
        list[i] = updater(list[i]);
        updatedCount++;
      }
    }
    if (updatedCount > 0) {
      this._save(this.data);
    }
    return updatedCount;
  }

  delete(collection, predicate) {
    this._ensureCollections();
    if (!Array.isArray(this.data[collection])) {
      this.data[collection] = [];
    }
    const list = this.data[collection];
    const filtered = list.filter(item => !predicate(item));
    this.data[collection] = filtered;
    this._save(this.data);
    return filtered;
  }

  // Alias for delete
  remove(collection, predicate) {
    return this.delete(collection, predicate);
  }
}

module.exports = new DataStore();
