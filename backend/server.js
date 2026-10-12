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
app.use(express.json());

// Request logging in development
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
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
