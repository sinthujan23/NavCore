require('dotenv').config();
const express = require('express');
const cors = require('cors');

const authRoutes = require('./routes/auth.routes');
const mallsRoutes = require('./routes/malls.routes');
const destinationsRoutes = require('./routes/destinations.routes');
const floorsRoutes = require('./routes/floors.routes');
const parkingRoutes = require('./routes/parking.routes');

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(cors());
app.use(express.json({ limit: '20mb' }));
app.use(express.urlencoded({ limit: '20mb', extended: true }));

// Request logging in development
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

const db = require('./db/dataStore');

// Favicon handler
app.get('/favicon.ico', (req, res) => {
  res.type('image/svg+xml');
  res.send(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#2563EB"/><path d="M16 6L24 22H8L16 6Z" fill="#FFFFFF"/><circle cx="16" cy="18" r="2.5" fill="#2563EB"/></svg>`);
});

// Root Landing & API Status Dashboard
app.get('/', (req, res) => {
  if (req.accepts('html')) {
    const mallsCount = (db.get('malls') || []).length;
    const destsCount = (db.get('destinations') || []).length;
    const floorsCount = (db.get('floorHeights') || []).length;
    const parkingCount = (db.get('parkingSlots') || []).length;

    return res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>NexNav NavCore • Backend Server</title>
  <link rel="icon" type="image/svg+xml" href="/favicon.ico">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600;700&family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #0B0F19;
      --card-bg: rgba(17, 24, 39, 0.75);
      --card-border: rgba(255, 255, 255, 0.08);
      --accent: #2563EB;
      --accent-glow: rgba(37, 99, 235, 0.35);
      --success: #10B981;
      --text: #F8FAFC;
      --text-muted: #94A3B8;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: radial-gradient(circle at 50% 0%, #1E293B 0%, var(--bg) 70%);
      color: var(--text);
      font-family: 'Plus Jakarta Sans', sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .container {
      max-width: 860px;
      width: 100%;
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 24px;
      backdrop-filter: blur(20px);
      box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5), 0 0 60px var(--accent-glow);
      padding: 36px;
    }
    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 28px;
      flex-wrap: wrap;
      gap: 16px;
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 14px;
    }
    .logo {
      width: 44px;
      height: 44px;
      background: linear-gradient(135deg, #3B82F6, #1D4ED8);
      border-radius: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 8px 16px var(--accent-glow);
    }
    .logo svg { width: 24px; height: 24px; fill: white; }
    h1 { font-size: 24px; font-weight: 800; letter-spacing: -0.5px; }
    .subtitle { font-size: 13px; color: var(--text-muted); margin-top: 2px; }
    .status-badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      background: rgba(16, 185, 129, 0.12);
      border: 1px solid rgba(16, 185, 129, 0.3);
      padding: 6px 14px;
      border-radius: 999px;
      color: var(--success);
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.5px;
    }
    .pulse-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--success);
      box-shadow: 0 0 10px var(--success);
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.5; transform: scale(0.85); }
    }
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 14px;
      margin-bottom: 30px;
    }
    .stat-card {
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid var(--card-border);
      border-radius: 16px;
      padding: 16px 20px;
    }
    .stat-label { font-size: 11px; font-weight: 700; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.8px; }
    .stat-val { font-size: 26px; font-weight: 800; color: #FFFFFF; margin-top: 4px; font-family: 'JetBrains Mono', monospace; }
    .section-title {
      font-size: 13px;
      font-weight: 800;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 1px;
      margin-bottom: 12px;
    }
    .endpoints-list {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .endpoint-item {
      display: flex;
      justify-content: space-between;
      align-items: center;
      background: rgba(255, 255, 255, 0.02);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 12px 16px;
      text-decoration: none;
      color: inherit;
      transition: all 0.2s;
    }
    .endpoint-item:hover {
      background: rgba(37, 99, 235, 0.1);
      border-color: rgba(37, 99, 235, 0.4);
      transform: translateX(4px);
    }
    .endpoint-left {
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .method-tag {
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      font-weight: 800;
      padding: 3px 8px;
      border-radius: 6px;
      background: rgba(59, 130, 246, 0.15);
      color: #60A5FA;
    }
    .endpoint-path {
      font-family: 'JetBrains Mono', monospace;
      font-size: 13px;
      color: #E2E8F0;
    }
    .endpoint-desc {
      font-size: 12px;
      color: var(--text-muted);
    }
    .footer {
      margin-top: 28px;
      padding-top: 20px;
      border-top: 1px solid var(--card-border);
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 12px;
      color: var(--text-muted);
      flex-wrap: wrap;
      gap: 12px;
    }
    .credentials-badge {
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid var(--card-border);
      padding: 4px 10px;
      border-radius: 8px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="brand">
        <div class="logo">
          <svg viewBox="0 0 24 24"><path d="M12 2L19 21L12 17L5 21L12 2Z"/></svg>
        </div>
        <div>
          <h1>NexNav NavCore</h1>
          <div class="subtitle">Indoor Navigation & Spatial Positioning REST API</div>
        </div>
      </div>
      <div class="status-badge">
        <span class="pulse-dot"></span>
        SYSTEM ONLINE
      </div>
    </div>

    <div class="stats-grid">
      <div class="stat-card">
        <div class="stat-label">Active Venues</div>
        <div class="stat-val">${mallsCount}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Stores / POIs</div>
        <div class="stat-val">${destsCount}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Floor Profiles</div>
        <div class="stat-val">${floorsCount}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Parking Stalls</div>
        <div class="stat-val">${parkingCount}</div>
      </div>
    </div>

    <div class="section-title">Live REST API Endpoints</div>
    <div class="endpoints-list">
      <a href="/api/health" class="endpoint-item" target="_blank">
        <div class="endpoint-left">
          <span class="method-tag">GET</span>
          <span class="endpoint-path">/api/health</span>
        </div>
        <span class="endpoint-desc">Server health, uptime & service status</span>
      </a>
      <a href="/api/malls" class="endpoint-item" target="_blank">
        <div class="endpoint-left">
          <span class="method-tag">GET</span>
          <span class="endpoint-path">/api/malls</span>
        </div>
        <span class="endpoint-desc">Catalog of shopping centers & venues</span>
      </a>
      <a href="/api/destinations" class="endpoint-item" target="_blank">
        <div class="endpoint-left">
          <span class="method-tag">GET</span>
          <span class="endpoint-path">/api/destinations</span>
        </div>
        <span class="endpoint-desc">All destination POIs and indoor shops</span>
      </a>
      <a href="/api/floors/mall-one-galle-face" class="endpoint-item" target="_blank">
        <div class="endpoint-left">
          <span class="method-tag">GET</span>
          <span class="endpoint-path">/api/floors/mall-one-galle-face</span>
        </div>
        <span class="endpoint-desc">Floor elevation vectors & heights</span>
      </a>
      <a href="/api/parking/mall-one-galle-face/slots" class="endpoint-item" target="_blank">
        <div class="endpoint-left">
          <span class="method-tag">GET</span>
          <span class="endpoint-path">/api/parking/mall-one-galle-face/slots</span>
        </div>
        <span class="endpoint-desc">Basement parking stalls & availability</span>
      </a>
    </div>

    <div class="footer">
      <div>Connected Client: <span class="credentials-badge">Flutter NexNav Mobile</span></div>
      <div>Admin: <span class="credentials-badge">admin@nexnav.com / Admin@1234</span></div>
    </div>
  </div>
</body>
</html>`);
  }

  return res.json({
    service: 'NexNav NavCore Backend REST API',
    status: 'online',
    version: '1.0.0',
    health: '/api/health',
    endpoints: ['/api/auth', '/api/malls', '/api/destinations', '/api/floors', '/api/parking'],
  });
});

// Health check
app.get('/api/health', (req, res) => {
  res.json({
    status: 'online',
    service: 'NexNav NavCore Backend REST API',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
  });
});

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/malls', mallsRoutes);
app.use('/api/destinations', destinationsRoutes);
app.use('/api/floors', floorsRoutes);
app.use('/api/parking', parkingRoutes);

// 404 Handler
app.use((req, res) => {
  res.status(404).json({ error: `Route not found: ${req.method} ${req.originalUrl}` });
});

// Global Error Handler
app.use((err, req, res, next) => {
  console.error('[Server Error]', err);
  res.status(500).json({ error: 'Internal Server Error', message: err.message });
});

// Start listening
app.listen(PORT, '0.0.0.0', () => {
  console.log('================================================================');
  console.log(`🚀 NexNav NavCore Backend REST API running at:`);
  console.log(`   - Local:    http://localhost:${PORT}`);
  console.log(`   - Network:  http://0.0.0.0:${PORT}`);
  console.log(`   - Health:   http://localhost:${PORT}/api/health`);
  console.log('================================================================');
});
