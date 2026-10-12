const express = require('express');
const router = express.Router();
const db = require('../db/dataStore');
const { requireAdmin } = require('../middleware/auth');

/**
 * GET /api/floors/:mallId
 * Returns all floor height profiles for a given mall
 */
router.get('/:mallId', (req, res) => {
  const mallId = req.params.mallId;
  const list = db.filter('floorHeights', f => f.mallId === mallId);
  list.sort((a, b) => a.floorNo - b.floorNo);
  return res.json(list);
});

/**
 * PUT /api/floors/:mallId/:floorNo
 * Admin: Update a specific floor's height or lock state
 */
router.put('/:mallId/:floorNo', requireAdmin, (req, res) => {
  const mallId = req.params.mallId;
  const floorNo = parseInt(req.params.floorNo, 10);
  const { heightToNextM, isLocked, baseAltitudeM, confidence, source } = req.body;

  const updated = db.update(
    'floorHeights',
    f => f.mallId === mallId && f.floorNo === floorNo,
    f => ({
      ...f,
      heightToNextM: heightToNextM !== undefined ? Number(heightToNextM) : f.heightToNextM,
      isLocked: isLocked !== undefined ? Boolean(isLocked) : f.isLocked,
      baseAltitudeM: baseAltitudeM !== undefined ? Number(baseAltitudeM) : f.baseAltitudeM,
      confidence: confidence !== undefined ? Number(confidence) : f.confidence,
      source: source || 'admin',
      updatedAt: new Date().toISOString(),
    })
  );

  if (!updated) {
    return res.status(404).json({ error: 'Floor record not found' });
  }

  return res.json(updated);
});

/**
 * POST /api/floors/:mallId
 * Admin: Add a new floor
 */
router.post('/:mallId', requireAdmin, (req, res) => {
  const mallId = req.params.mallId;
  const { floorNo, heightToNextM, baseAltitudeM } = req.body;

  if (floorNo === undefined) {
    return res.status(400).json({ error: 'floorNo is required' });
  }

  const fn = Number(floorNo);
  const existing = db.find('floorHeights', f => f.mallId === mallId && f.floorNo === fn);
  if (existing) {
    return res.status(409).json({ error: `Floor ${fn} already exists for this mall` });
  }

  const newFloor = {
    mallId,
    floorNo: fn,
    heightToNextM: heightToNextM !== undefined ? Number(heightToNextM) : 15.0,
    baseAltitudeM: baseAltitudeM !== undefined ? Number(baseAltitudeM) : (fn * 15.0),
    source: 'admin',
    confidence: 1.0,
    isLocked: false,
    updatedAt: new Date().toISOString(),
  };

  db.insert('floorHeights', newFloor);
  return res.status(201).json(newFloor);
});

/**
 * DELETE /api/floors/:mallId/:floorNo
 * Admin: Delete a floor
 */
router.delete('/:mallId/:floorNo', requireAdmin, (req, res) => {
  const mallId = req.params.mallId;
  const floorNo = parseInt(req.params.floorNo, 10);

  db.delete('floorHeights', f => f.mallId === mallId && f.floorNo === floorNo);
  return res.json({ message: `Floor ${floorNo} removed for mall ${mallId}` });
});

/**
 * POST /api/floors/:mallId/calculate
 * Triggers barometric and structural height estimation
 */
router.post('/:mallId/calculate', (req, res) => {
  const mallId = req.params.mallId;
  const floors = db.filter('floorHeights', f => f.mallId === mallId);

  // Auto-calculate cumulative base altitudes
  let currentAltitude = 0.0;
  floors.sort((a, b) => a.floorNo - b.floorNo);

  const updated = floors.map((f, idx) => {
    if (idx === 0) {
      currentAltitude = f.baseAltitudeM || 0.0;
    } else {
      currentAltitude += floors[idx - 1].heightToNextM || 15.0;
    }
    return {
      ...f,
      baseAltitudeM: currentAltitude,
      updatedAt: new Date().toISOString(),
    };
  });

  // Save back to db
  const remaining = db.filter('floorHeights', f => f.mallId !== mallId);
  db.set('floorHeights', [...remaining, ...updated]);

  return res.json(updated);
});

/**
 * POST /api/floors/:mallId/reset
 * Resets floors to default floor gap intervals (4.5m)
 */
router.post('/:mallId/reset', requireAdmin, (req, res) => {
  const mallId = req.params.mallId;
  const floors = db.filter('floorHeights', f => f.mallId === mallId);
  floors.sort((a, b) => a.floorNo - b.floorNo);

  const updated = floors.map(f => {
    const defaultGap = 4.5;
    const baseAlt = f.floorNo * defaultGap;
    return {
      ...f,
      heightToNextM: defaultGap,
      baseAltitudeM: baseAlt,
      source: 'default',
      confidence: 1.0,
      isLocked: false,
      updatedAt: new Date().toISOString(),
    };
  });

  const remaining = db.filter('floorHeights', f => f.mallId !== mallId);
  db.set('floorHeights', [...remaining, ...updated]);
  return res.json(updated);
});

module.exports = router;
