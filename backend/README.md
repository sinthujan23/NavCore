# NexNav NavCore — Backend REST API Server

Production-grade, modular Node.js & Express REST API server powering the NexNav Zero-Hardware Indoor AR Navigation Flutter mobile client.

## 🚀 Quick Start

### 1. Install Dependencies
```bash
cd backend
npm install
```

### 2. Start the Server
```bash
# Run in production mode:
npm start

# Run with hot reload (Node 18+):
npm run dev
```

The server binds to `0.0.0.0:5000` (accessible from both localhost and mobile devices on your local Wi-Fi or Android emulator via `10.0.2.2:5000`).

---

## 📡 API Endpoints

### 🔐 Authentication (`/api/auth`)
- `POST /api/auth/login` — Login with email & password (returns JWT Bearer token & role: `admin` / `user`)
- `POST /api/auth/register` — Create new user or admin account
- `GET /api/auth/me` — Verify token and fetch profile

**Default Pre-Seeded Accounts:**
- **Admin**: `admin@nexnav.com` / `admin123` (Admin Portal access)
- **User**: `user@nexnav.com` / `user123` (Shopper AR Navigation access)

### 🏬 Malls & Venues (`/api/malls`)
- `GET /api/malls` — List all venues/malls
- `GET /api/malls/:id` — Get single mall metadata
- `GET /api/malls/:id/package` — Fetch complete map package (elevation profile, floors, POIs, entrance markers)
- `POST /api/malls` — *(Admin)* Add new mall
- `PUT /api/malls/:id` — *(Admin)* Update mall details
- `DELETE /api/malls/:id` — *(Admin)* Remove mall

### 📍 Destinations / POIs (`/api/destinations`)
- `GET /api/destinations` — Search POIs (filter by `mallId`, `floorNumber`, `category`, `search`)
- `GET /api/destinations/:id` — Fetch single shop POI
- `POST /api/destinations` — *(Admin)* Add POI
- `PUT /api/destinations/:id` — *(Admin)* Update POI
- `DELETE /api/destinations/:id` — *(Admin)* Remove POI

### 📐 Floor Heights & Calibration (`/api/floors`)
- `GET /api/floors/:mallId` — Get all floor heights & base altitudes
- `PUT /api/floors/:mallId/:floorNo` — *(Admin)* Update floor height & lock status
- `POST /api/floors/:mallId` — *(Admin)* Add floor
- `DELETE /api/floors/:mallId/:floorNo` — *(Admin)* Delete floor
- `POST /api/floors/:mallId/calculate` — Trigger barometric/structural altitude recalculation

### 🚗 Parking & Stalls (`/api/parking`)
- `GET /api/parking/:mallId/slots` — List all parking slots (EV, handicap, occupancy status)
- `PUT /api/parking/slots/:id` — Update slot occupancy (`free`, `occupied`, `reserved`)
- `GET /api/parking/:mallId/vehicle/:userId` — Get user's saved parked car location
- `POST /api/parking/:mallId/vehicle` — Save parked car location
- `DELETE /api/parking/:mallId/vehicle/:userId` — Clear parked car location

---

## 💾 Database Dump & Production Deployment

The backend includes complete, pre-configured database dumps ready for instant server deployment (Render, Railway, AWS, DigitalOcean, Docker, VPS, etc.).

### 📁 Database Dump Artifacts
| File | Format | Purpose |
|------|--------|---------|
| [`data/db.dump.json`](file:///e:/Hasnet%20Projects/NavCore/backend/data/db.dump.json) | JSON Document Dump | Complete dataset dump for Node.js engine with all malls, POIs, floors, and users. |
| [`data/dump.json`](file:///e:/Hasnet%20Projects/NavCore/backend/data/dump.json) | JSON Document Dump | Standard alias of `db.dump.json` for cloud deployment platforms. |
| [`data/db.json`](file:///e:/Hasnet%20Projects/NavCore/backend/data/db.json) | Active Live DB | The operational database file used by `dataStore.js` at runtime. |
| [`data/dump.sql`](file:///e:/Hasnet%20Projects/NavCore/backend/data/dump.sql) | Relational SQL Dump | PostgreSQL, SQLite3 & MySQL compatible DDL + DML dump for relational cloud DBs. |

### 🛠 Database Commands
```bash
# Re-seed or restore active database from master dump:
npm run db:seed

# Export current live database state to dump files:
npm run db:dump
```

### 🚀 Deploying to Cloud (e.g., Render, Railway, VPS, Docker)
1. **Push to Git**: Ensure `backend/data/db.dump.json` and `backend/data/db.json` are committed.
2. **Environment Variables**:
   ```env
   PORT=5000
   JWT_SECRET=your_super_secret_production_key_here
   NODE_ENV=production
   ```
3. **Build & Start Command**:
   - Build: `npm install`
   - Start: `npm start` (or `npm run db:seed && npm start` to guarantee fresh seeded state)
4. The server automatically initializes with all 5 pre-configured venues, 30+ POIs, multi-level floor height profiles, and parking stall sensors.

