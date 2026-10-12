const express = require('express');
const router = express.Router();
const db = require('../db/dataStore');

/**
 * GET /api/parking/:mallId/slots
 */
router.get('/:mallId/slots', (req, res) => {
  const mallId = req.params.mallId;
  const slots = db.filter('parkingSlots', s => s.mallId === mallId);
  return res.json(slots);
});

/**
 * PUT /api/parking/slots/:id
 * Updates parking slot occupancy status
 */
router.put('/slots/:id', (req, res) => {
  const slotId = req.params.id;
  const { status } = req.body;

  const updated = db.update(
    'parkingSlots',
    s => s.id === slotId,
    s => ({ ...s, status: status || s.status })
  );

  if (!updated) {
    return res.status(404).json({ error: 'Parking slot not found' });
  }

  return res.json(updated);
});

/**
 * GET /api/parking/:mallId/vehicle/:userId
 */
router.get('/:mallId/vehicle/:userId', (req, res) => {
  const { userId } = req.params;
  const vehicles = db.get('vehicleLocations') || {};
  const vehicle = vehicles[userId];

  if (!vehicle) {
    return res.status(404).json({ error: 'No parked vehicle record found for this user' });
  }

  return res.json(vehicle);
});

/**
 * POST /api/parking/:mallId/vehicle
 */
router.post('/:mallId/vehicle', (req, res) => {
  const body = req.body;
  const userId = body.userId || 'usr-default';

  const vehicleRecord = {
    userId,
    vehicleId: body.vehicleId || 'veh-default',
    slotId: body.slotId,
    floorId: body.floorId || 'B1',
    floorName: body.floorName || 'Basement Level B1',
    latitude: Number(body.latitude),
    longitude: Number(body.longitude),
    height: Number(body.height || 0.0),
    timestamp: new Date().toISOString(),
    status: 'parked',
    licensePlate: body.licensePlate || 'WP CAB-8821',
    notes: body.notes || null,
  };

  const vehicles = db.get('vehicleLocations') || {};
  vehicles[userId] = vehicleRecord;
  db.set('vehicleLocations', vehicles);

  // Mark the slot as occupied
  if (body.slotId) {
    db.update('parkingSlots', s => s.id === body.slotId, s => ({ ...s, status: 'occupied' }));
  }

  return res.status(201).json(vehicleRecord);
});

/**
 * DELETE /api/parking/:mallId/vehicle/:userId
 */
router.delete('/:mallId/vehicle/:userId', (req, res) => {
  const { userId } = req.params;
  const vehicles = db.get('vehicleLocations') || {};
  const current = vehicles[userId];

  if (current && current.slotId) {
    // Free the slot
    db.update('parkingSlots', s => s.id === current.slotId, s => ({ ...s, status: 'free' }));
  }

  delete vehicles[userId];
  db.set('vehicleLocations', vehicles);

  return res.json({ message: 'Parked vehicle location cleared successfully' });
});

module.exports = router;
