const express = require('express');
const router = express.Router();
const db = require('../db/dataStore');
const { requireAdmin } = require('../middleware/auth');

/**
 * GET /api/floors/:mallId
 * Returns all floor height profiles for a given mall
 */
router.get('/:mallId', (req, res) => {
  const mallId = (req.params.mallId || '').trim();
  const lowerMallId = mallId.toLowerCase();
  let list = db.filter('floorHeights', f => {
    const fMall = (f.mallId || '').trim().toLowerCase();
    return fMall === lowerMallId ||
      fMall === lowerMallId.replace(/^mall-/, '') ||
      lowerMallId === fMall.replace(/^mall-/, '') ||
      (fMall.length > 0 && (fMall.includes(lowerMallId) || lowerMallId.includes(fMall)));
  });

  // If no floors exist in DB yet for this mall, automatically populate standard floors from mall metadata
  if (list.length === 0) {
    const mall = db.find('malls', m => {
      const mMall = (m.id || '').trim().toLowerCase();
      return mMall === lowerMallId ||
        mMall === lowerMallId.replace(/^mall-/, '') ||
        lowerMallId === mMall.replace(/^mall-/, '') ||
        (mMall.length > 0 && (mMall.includes(lowerMallId) || lowerMallId.includes(mMall)));
    });
    if (mall) {
      const floorCount = Number(mall.floorCount) || 3;
      const gap = Number(mall.floorGapMeters) || 3.8;
      const lat = Number(mall.latitude || 0);
      const lon = Number(mall.longitude || 0);
      let locAlt = 8.5;
      if (lat && lon) {
        if (Math.abs(lat - 8.5) < 0.6 && Math.abs(lon - 81.2) < 0.6) locAlt = 8.5;
        else if (Math.abs(lat - 6.9) < 0.5 && Math.abs(lon - 79.8) < 0.5) locAlt = 7.2;
        else if (Math.abs(lat - 7.3) < 0.5 && Math.abs(lon - 80.6) < 0.5) locAlt = 485.0;
        else if (Math.abs(lat - 6.0) < 0.5 && Math.abs(lon - 80.2) < 0.5) locAlt = 10.0;
        else if (Math.abs(lat - 9.6) < 0.5 && Math.abs(lon - 80.0) < 0.5) locAlt = 5.5;
      }
      let currentAlt = Number(mall.entranceBaseAnchorHeight) || locAlt;
      for (let fn = 1; fn <= floorCount; fn++) {
        const newFloor = {
          mallId: mall.id,
          floorNo: fn,
          heightToNextM: gap,
          baseAltitudeM: parseFloat(currentAlt.toFixed(2)),
          source: 'default',
          confidence: 1.0,
          isLocked: false,
          updatedAt: new Date().toISOString(),
        };
        db.insert('floorHeights', newFloor);
        list.push(newFloor);
        currentAlt += gap;
      }
    }
  }

  list.sort((a, b) => a.floorNo - b.floorNo);
  return res.json(list);
});

/**
 * Helper: Recalculates cumulative base altitudes for all floors of a mall.
 * Preserves admin-added gaps and locked floors.
 */
function recalculateMallAltitudes(mallId) {
  const lowerMallId = (mallId || '').trim().toLowerCase();
  let mallFloors = db.filter('floorHeights', f => (f.mallId || '').trim().toLowerCase() === lowerMallId);
  if (mallFloors.length === 0) return [];

  mallFloors.sort((a, b) => a.floorNo - b.floorNo);

  const mall = db.find('malls', m => (m.id || '').trim().toLowerCase() === lowerMallId);
  const entranceAnchor = (mall && Number(mall.entranceBaseAnchorHeight)) || 8.5;

  let currentAlt = (mallFloors[0] && mallFloors[0].floorNo === 1 && mallFloors[0].baseAltitudeM !== undefined && mallFloors[0].baseAltitudeM > 0)
    ? Number(mallFloors[0].baseAltitudeM)
    : entranceAnchor;

  const updated = mallFloors.map((f, idx) => {
    if (idx === 0) {
      currentAlt = (f.baseAltitudeM !== undefined && f.baseAltitudeM > 0) ? Number(f.baseAltitudeM) : entranceAnchor;
    } else {
      const prevGap = Number(mallFloors[idx - 1].heightToNextM) || 3.8;
      currentAlt += prevGap;
    }
    return {
      ...f,
      baseAltitudeM: parseFloat(currentAlt.toFixed(2)),
      updatedAt: new Date().toISOString(),
    };
  });

  const remaining = db.filter('floorHeights', f => (f.mallId || '').trim().toLowerCase() !== lowerMallId);
  db.set('floorHeights', [...remaining, ...updated]);
  return updated;
}

/**
 * PUT /api/floors/:mallId/:floorNo
 * Admin: Update a specific floor's height or lock state.
 * Automatically recalculates cumulative base altitudes for all upper floors.
 */
router.put('/:mallId/:floorNo', requireAdmin, (req, res) => {
  const mallId = (req.params.mallId || '').trim();
  const lowerMallId = mallId.toLowerCase();
  const floorNo = parseInt(req.params.floorNo, 10);
  const { heightToNextM, isLocked, baseAltitudeM, confidence, source } = req.body;

  let updated = db.update(
    'floorHeights',
    f => (f.mallId || '').trim().toLowerCase() === lowerMallId && f.floorNo === floorNo,
    f => ({
      ...f,
      heightToNextM: heightToNextM !== undefined ? Number(heightToNextM) : f.heightToNextM,
      isLocked: isLocked !== undefined ? Boolean(isLocked) : true,
      baseAltitudeM: baseAltitudeM !== undefined ? Number(baseAltitudeM) : f.baseAltitudeM,
      confidence: confidence !== undefined ? Number(confidence) : 1.0,
      source: source || 'admin',
      updatedAt: new Date().toISOString(),
    })
  );

  if (!updated) {
    const newFloor = {
      mallId,
      floorNo,
      heightToNextM: heightToNextM !== undefined ? Number(heightToNextM) : 3.8,
      baseAltitudeM: baseAltitudeM !== undefined ? Number(baseAltitudeM) : 8.5,
      isLocked: isLocked !== undefined ? Boolean(isLocked) : true,
      confidence: confidence !== undefined ? Number(confidence) : 1.0,
      source: source || 'admin',
      updatedAt: new Date().toISOString(),
    };
    db.insert('floorHeights', newFloor);
    updated = newFloor;
  }

  // Recalculate cumulative base altitudes for all floors based on admin added gap
  const fullList = recalculateMallAltitudes(mallId);
  const match = fullList.find(f => f.floorNo === floorNo) || updated;
  return res.json(match);
});

/**
 * POST /api/floors/:mallId
 * Admin: Add a new floor and cascade cumulative base altitude
 */
router.post('/:mallId', requireAdmin, (req, res) => {
  const mallId = (req.params.mallId || '').trim();
  const lowerMallId = mallId.toLowerCase();
  const { floorNo, heightToNextM, baseAltitudeM } = req.body;

  if (floorNo === undefined) {
    return res.status(400).json({ error: 'floorNo is required' });
  }

  const fn = Number(floorNo);
  const existing = db.find(
    'floorHeights',
    f => (f.mallId || '').trim().toLowerCase() === lowerMallId && f.floorNo === fn
  );
  if (existing) {
    return res.status(409).json({ error: `Floor ${fn} already exists for this mall` });
  }

  const newFloor = {
    mallId,
    floorNo: fn,
    heightToNextM: heightToNextM !== undefined ? Number(heightToNextM) : 3.8,
    baseAltitudeM: baseAltitudeM !== undefined ? Number(baseAltitudeM) : 8.5,
    source: 'admin',
    confidence: 1.0,
    isLocked: true,
    updatedAt: new Date().toISOString(),
  };

  db.insert('floorHeights', newFloor);
  const fullList = recalculateMallAltitudes(mallId);
  const match = fullList.find(f => f.floorNo === fn) || newFloor;
  return res.status(201).json(match);
});

/**
 * DELETE /api/floors/:mallId/:floorNo
 * Admin: Delete a floor and recalculate remaining floor altitudes
 */
router.delete('/:mallId/:floorNo', requireAdmin, (req, res) => {
  const mallId = (req.params.mallId || '').trim();
  const lowerMallId = mallId.toLowerCase();
  const floorNo = parseInt(req.params.floorNo, 10);

  db.delete('floorHeights', f => (f.mallId || '').trim().toLowerCase() === lowerMallId && f.floorNo === floorNo);
  const fullList = recalculateMallAltitudes(mallId);

  // Update mall's floorCount in catalog
  db.update('malls', m => (m.id || '').trim().toLowerCase() === lowerMallId, m => ({ ...m, floorCount: fullList.length }));

  return res.json({
    message: `Floor ${floorNo} removed for mall ${mallId}`,
    remainingFloors: fullList.length,
    floors: fullList,
  });
});

/**
 * DELETE /api/floors/:mallId
 * Admin: Delete all floors for a mall
 */
router.delete('/:mallId', requireAdmin, (req, res) => {
  const mallId = (req.params.mallId || '').trim();
  const lowerMallId = mallId.toLowerCase();

  db.delete('floorHeights', f => (f.mallId || '').trim().toLowerCase() === lowerMallId);

  // Update mall's floorCount in catalog
  db.update('malls', m => (m.id || '').trim().toLowerCase() === lowerMallId, m => ({ ...m, floorCount: 0 }));

  return res.json({
    message: `All floors removed for mall ${mallId}`,
    remainingFloors: 0,
    floors: [],
  });
});

/**
 * POST /api/floors/:mallId/calculate
 * Triggers real-time barometric and structural height estimation.
 * Strictly preserves admin-added floor gaps (isLocked == true or source == 'admin').
 * Cumulatively calculates base altitudes based on floor gaps.
 */
router.post('/:mallId/calculate', (req, res) => {
  const mallId = (req.params.mallId || '').trim();
  const lowerMallId = mallId.toLowerCase();
  const { barometerPressureHpa, liveAltitudeM, groundBaselineAlt, latitude, longitude, gpsAltitudeM, floorGapM } = req.body || {};

  let floors = db.filter('floorHeights', f => (f.mallId || '').trim().toLowerCase() === lowerMallId);
  const mall = db.find('malls', m => (m.id || '').trim().toLowerCase() === lowerMallId);
  const userLocationAltitude = liveAltitudeM || gpsAltitudeM || groundBaselineAlt;

  const lat = Number(latitude || (mall && mall.latitude) || 0);
  const lon = Number(longitude || (mall && mall.longitude) || 0);
  let locationDefaultAltitude = 8.5;
  if (lat && lon) {
    if (Math.abs(lat - 8.5) < 0.6 && Math.abs(lon - 81.2) < 0.6) locationDefaultAltitude = 8.5;
    else if (Math.abs(lat - 6.9) < 0.5 && Math.abs(lon - 79.8) < 0.5) locationDefaultAltitude = 7.2;
    else if (Math.abs(lat - 7.3) < 0.5 && Math.abs(lon - 80.6) < 0.5) locationDefaultAltitude = 485.0;
    else if (Math.abs(lat - 6.0) < 0.5 && Math.abs(lon - 80.2) < 0.5) locationDefaultAltitude = 10.0;
    else if (Math.abs(lat - 9.6) < 0.5 && Math.abs(lon - 80.0) < 0.5) locationDefaultAltitude = 5.5;
  }

  const entranceAnchor = (userLocationAltitude && Number(userLocationAltitude) > 0)
    ? Number(userLocationAltitude)
    : ((mall && Number(mall.entranceBaseAnchorHeight)) || locationDefaultAltitude);
  const dynamicGap = Number(floorGapM) || Number(mall?.floorGapMeters) || 3.8;

  if (floors.length === 0) {
    const floorCount = Number(mall?.floorCount) || 3;
    for (let fn = 1; fn <= floorCount; fn++) {
      floors.push({
        mallId,
        floorNo: fn,
        heightToNextM: dynamicGap,
        baseAltitudeM: entranceAnchor,
        source: 'barometer',
        confidence: 0.9,
        isLocked: false,
        updatedAt: new Date().toISOString(),
      });
    }
  }

  floors.sort((a, b) => a.floorNo - b.floorNo);

  // Auto-calculate cumulative base altitudes based on user location & preserved admin floor gaps
  const firstFloorAdminLocked = floors[0] && (floors[0].isLocked === true || floors[0].source === 'admin');
  let currentAlt = firstFloorAdminLocked && floors[0].baseAltitudeM !== undefined && floors[0].baseAltitudeM > 0
    ? Number(floors[0].baseAltitudeM)
    : Number(entranceAnchor);

  const updated = floors.map((f, idx) => {
    // If admin added/locked this floor gap, strictly preserve it!
    const isExplicitlyLocked = f.isLocked === true;
    const gap = isExplicitlyLocked ? (Number(f.heightToNextM) || dynamicGap) : dynamicGap;
    const source = isExplicitlyLocked ? 'admin' : (userLocationAltitude ? 'gps_baro_fusion' : 'barometer');
    const confidence = isExplicitlyLocked ? 1.0 : (barometerPressureHpa ? 0.95 : 0.85);

    if (idx === 0) {
      currentAlt = (isExplicitlyLocked && f.baseAltitudeM !== undefined && f.baseAltitudeM > 0)
        ? Number(f.baseAltitudeM)
        : Number(entranceAnchor);
    } else {
      const prevLocked = floors[idx - 1].isLocked === true;
      const prevGap = prevLocked ? (Number(floors[idx - 1].heightToNextM) || dynamicGap) : dynamicGap;
      currentAlt += prevGap;
    }

    return {
      ...f,
      heightToNextM: gap,
      baseAltitudeM: parseFloat(currentAlt.toFixed(2)),
      source,
      confidence,
      isLocked: isAdminLocked,
      updatedAt: new Date().toISOString(),
    };
  });

  const remaining = db.filter('floorHeights', f => (f.mallId || '').trim().toLowerCase() !== lowerMallId);
  db.set('floorHeights', [...remaining, ...updated]);

  return res.json(updated);
});

/**
 * POST /api/floors/:mallId/reset
 * Resets floors to location-based standard intervals
 */
router.post('/:mallId/reset', requireAdmin, (req, res) => {
  const mallId = (req.params.mallId || '').trim();
  const lowerMallId = mallId.toLowerCase();
  const floors = db.filter('floorHeights', f => (f.mallId || '').trim().toLowerCase() === lowerMallId);
  floors.sort((a, b) => a.floorNo - b.floorNo);

  const mall = db.find('malls', m => (m.id || '').trim().toLowerCase() === lowerMallId);
  const entranceAnchor = (mall && Number(mall.entranceBaseAnchorHeight)) || 8.5;
  const defaultGap = Number(mall && mall.floorGapMeters) || 3.8;

  const updated = floors.map((f, idx) => {
    const baseAlt = entranceAnchor + (idx * defaultGap);
    return {
      ...f,
      heightToNextM: defaultGap,
      baseAltitudeM: parseFloat(baseAlt.toFixed(2)),
      source: 'default',
      confidence: 1.0,
      isLocked: false,
      updatedAt: new Date().toISOString(),
    };
  });

  const remaining = db.filter('floorHeights', f => (f.mallId || '').trim().toLowerCase() !== lowerMallId);
  db.set('floorHeights', [...remaining, ...updated]);
  return res.json(updated);
});

module.exports = router;
