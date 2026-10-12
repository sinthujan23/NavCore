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
