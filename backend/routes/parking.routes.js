const express = require('express');
const router = express.Router();
const db = require('../db/dataStore');

/**
 * GET /api/parking/:mallId/slots
 */
router.get('/:mallId/slots', (req, res) => {
  const reqMall = (req.params.mallId || '').trim().toLowerCase();
  const slots = db.filter('parkingSlots', s => {
    const sMall = (s.mallId || '').trim().toLowerCase();
    return sMall === reqMall ||
           sMall === reqMall.replace(/^mall-/, '') ||
           reqMall === sMall.replace(/^mall-/, '');
  });
  return res.json(slots);
});

/**
 * POST /api/parking/:mallId/slots
 * Creates a single parking slot
 */
router.post('/:mallId/slots', (req, res) => {
  const mallId = req.params.mallId;
  const body = req.body;
  const newSlot = {
    id: body.id || `slot-${Date.now()}`,
    mallId,
    floorId: body.floorId || 'P',
    section: body.section || 'A',
    slotNumber: Number(body.slotNumber) || 1,
    status: body.status || 'free',
    latitude: Number(body.latitude) || 0.0,
    longitude: Number(body.longitude) || 0.0,
    height: Number(body.height) || 0.0,
    gridRow: Number(body.gridRow) || 0,
    gridCol: Number(body.gridCol) || 0,
    isEVCharging: Boolean(body.isEVCharging),
    isHandicapAccessible: Boolean(body.isHandicapAccessible),
    sensorId: body.sensorId || `SNS-${body.floorId || 'P'}-${body.section || 'A'}${body.slotNumber || 1}`,
    createdAt: new Date().toISOString()
  };

  const existingIndex = (db.get('parkingSlots') || []).findIndex(s => s.id === newSlot.id);
  if (existingIndex !== -1) {
    db.update('parkingSlots', s => s.id === newSlot.id, () => newSlot);
  } else {
    db.push('parkingSlots', newSlot);
  }
  return res.status(201).json(newSlot);
});

/**
 * POST /api/parking/:mallId/slots/bulk
 * Creates multiple parking slots (e.g., adding a panel/row of bays)
 */
router.post('/:mallId/slots/bulk', (req, res) => {
  const mallId = req.params.mallId;
  const slotsList = req.body.slots || [];
  const added = [];
  for (const s of slotsList) {
    const newSlot = {
      id: s.id || `slot-${Date.now()}-${Math.random().toString(36).substr(2, 4)}`,
      mallId,
      floorId: s.floorId || 'P',
      section: s.section || 'A',
      slotNumber: Number(s.slotNumber) || 1,
      status: s.status || 'free',
      latitude: Number(s.latitude) || 0.0,
      longitude: Number(s.longitude) || 0.0,
      height: Number(s.height) || 0.0,
      gridRow: Number(s.gridRow) || 0,
      gridCol: Number(s.gridCol) || 0,
      isEVCharging: Boolean(s.isEVCharging),
      isHandicapAccessible: Boolean(s.isHandicapAccessible),
      sensorId: s.sensorId || `SNS-${s.floorId || 'GF'}-${s.section || 'A'}${s.slotNumber || 1}`,
      createdAt: new Date().toISOString()
    };
    const existingIndex = (db.get('parkingSlots') || []).findIndex(x => x.id === newSlot.id);
    if (existingIndex !== -1) {
      db.update('parkingSlots', x => x.id === newSlot.id, () => newSlot);
    } else {
      db.push('parkingSlots', newSlot);
    }
    added.push(newSlot);
  }
  return res.status(201).json(added);
});

/**
 * DELETE /api/parking/slots/:id
 * Deletes a parking slot
 */
router.delete('/slots/:id', (req, res) => {
  const slotId = req.params.id;
  const removed = db.remove('parkingSlots', s => s.id === slotId);
  if (!removed) {
    return res.status(404).json({ error: 'Parking slot not found' });
  }
  return res.json({ message: 'Parking slot deleted successfully' });
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
