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
  }

  _load() {
    try {
      if (fs.existsSync(DB_FILE)) {
        const raw = fs.readFileSync(DB_FILE, 'utf-8');
        return JSON.parse(raw);
      }
    } catch (err) {
      console.error('[DataStore] Error reading db.json, falling back to seed:', err.message);
    }
    this._save(seedData);
    return JSON.parse(JSON.stringify(seedData));
  }

  _save(newData) {
    try {
      fs.writeFileSync(DB_FILE, JSON.stringify(newData, null, 2), 'utf-8');
    } catch (err) {
      console.error('[DataStore] Error saving db.json:', err.message);
    }
  }

  get(collection) {
    return this.data[collection] || [];
  }

  set(collection, items) {
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
    if (!this.data[collection]) {
      this.data[collection] = [];
    }
    this.data[collection].push(item);
    this._save(this.data);
    return item;
  }

  update(collection, predicate, updater) {
    const list = this.get(collection);
    const index = list.findIndex(predicate);
    if (index !== -1) {
      const updated = updater(list[index]);
      list[index] = updated;
      this._save(this.data);
      return updated;
    }
    return null;
  }

  delete(collection, predicate) {
    const list = this.get(collection);
    const filtered = list.filter(item => !predicate(item));
    this.data[collection] = filtered;
    this._save(this.data);
    return filtered;
  }
}

module.exports = new DataStore();
