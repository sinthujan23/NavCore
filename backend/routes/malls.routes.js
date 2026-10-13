const express = require('express');
const router = express.Router();
const db = require('../db/dataStore');
const { requireAdmin } = require('../middleware/auth');

/**
 * GET /api/malls
 * Returns the full catalog of malls
 */
router.get('/', (req, res) => {
  const malls = db.get('malls');
  return res.json(malls);
});

/**
 * GET /api/malls/:id
 * Returns metadata for a specific mall
 */
router.get('/:id', (req, res) => {
  const mall = db.find('malls', m => m.id === req.params.id);
  if (!mall) {
    return res.status(404).json({ error: 'Mall not found' });
  }
  return res.json(mall);
});

/**
 * GET /api/malls/:id/package
 * Returns complete map package: metadata, elevation profile, destinations, entrance markers
 */
router.get('/:id/package', (req, res) => {
  const mallId = req.params.id;
  const mall = db.find('malls', m => m.id === mallId);

  if (!mall) {
    return res.status(404).json({ error: 'Mall not found' });
  }

  const allDestinations = db.filter('destinations', d => d.mallId === mallId);
  const floorHeights = db.filter('floorHeights', f => f.mallId === mallId);
  const entranceMarkers = db.filter('entranceMarkers', e => e.buildingId === mallId);

  // Generate dynamic floor levels from floor heights
  const floors = floorHeights.map(h => {
    const isBasement = h.floorNo < 0;
    const floorId = isBasement ? `B${Math.abs(h.floorNo)}` : `F${h.floorNo}`;
    const floorName = isBasement
      ? `Basement B${Math.abs(h.floorNo)}`
      : (h.floorNo === 1 ? 'Ground Floor F1' : `Upper Floor F${h.floorNo}`);
    const storesCount = allDestinations.filter(d => d.floorNumber === h.floorNo).length;

    return {
      floorId,
      floorNumber: h.floorNo,
      name: floorName,
      relativeVectorMeters: h.heightToNextM,
      absoluteHeightMeters: h.baseAltitudeM,
      bandMinMeters: h.baseAltitudeM - 2.5,
      bandMaxMeters: h.baseAltitudeM + 2.5,
      storesCount,
    };
  }).sort((a, b) => a.absoluteHeightMeters - b.absoluteHeightMeters);

  const profile = {
    buildingId: mall.id,
    name: mall.name,
    entranceBaseAnchorHeight: mall.entranceBaseAnchorHeight !== undefined ? Number(mall.entranceBaseAnchorHeight) : 0.0,
    floorGapMeters: mall.floorGapMeters !== undefined ? Number(mall.floorGapMeters) : 4.5,
    floors,
  };

  return res.json({
    metadata: mall,
    profile,
    destinations: allDestinations,
    entranceMarkers,
  });
});

/**
 * POST /api/malls
 * Admin: Add a new mall to the catalog
 */
router.post('/', requireAdmin, (req, res) => {
  const body = req.body;
  if (!body.id || !body.name || body.latitude === undefined || body.longitude === undefined) {
    return res.status(400).json({ error: 'Missing required mall fields: id, name, latitude, longitude' });
  }

  const existing = db.find('malls', m => m.id === body.id);
  if (existing) {
    return res.status(409).json({ error: 'Mall with this ID already exists' });
  }

  const newMall = {
    id: body.id,
    name: body.name,
    city: body.city || 'Local Area',
    country: body.country || 'Sri Lanka',
    latitude: Number(body.latitude),
    longitude: Number(body.longitude),
    floorCount: Number(body.floorCount) || 5,
    packageSizeBytesMB: Number(body.packageSizeBytesMB) || 4.8,
    category: body.category || 'Indoor Venue',
    rating: body.rating || '4.8 ★',
    isDownloaded: true,
    isActive: false,
    entranceBaseAnchorHeight: body.entranceBaseAnchorHeight !== undefined ? Number(body.entranceBaseAnchorHeight) : 0.0,
    floorGapMeters: body.floorGapMeters !== undefined ? Number(body.floorGapMeters) : 4.5,
  };

  db.insert('malls', newMall);

  // Auto-generate floor heights for the newly created venue
  const floorCount = newMall.floorCount || 3;
  let currentAlt = newMall.entranceBaseAnchorHeight || 15.0;
  for (let fn = 1; fn <= floorCount; fn++) {
    db.insert('floorHeights', {
      mallId: newMall.id,
      floorNo: fn,
      heightToNextM: newMall.floorGapMeters || 4.5,
      baseAltitudeM: currentAlt,
      source: 'admin',
      confidence: 1.0,
      isLocked: false,
      updatedAt: new Date().toISOString(),
    });
    currentAlt += (newMall.floorGapMeters || 4.5);
  }

  return res.status(201).json(newMall);
});

/**
 * PUT /api/malls/:id
 * Admin: Update mall information
 */
router.put('/:id', requireAdmin, (req, res) => {
  const mallId = req.params.id;
  const updated = db.update('malls', m => m.id === mallId, m => ({ ...m, ...req.body, id: mallId }));
  if (!updated) {
    return res.status(404).json({ error: 'Mall not found' });
  }
  return res.json(updated);
});

/**
 * DELETE /api/malls/:id
 * Admin: Delete a mall
 */
router.delete('/:id', requireAdmin, (req, res) => {
  const mallId = (req.params.id || '').trim();
  const lowerId = mallId.toLowerCase();

  db.delete('malls', m => (m.id || '').trim().toLowerCase() === lowerId);
  db.delete('destinations', d => (d.mallId || '').trim().toLowerCase() === lowerId);
  db.delete('floorHeights', f => (f.mallId || '').trim().toLowerCase() === lowerId);
  db.delete('entranceMarkers', e => (e.buildingId || '').trim().toLowerCase() === lowerId);
  db.delete('parkingSlots', s => (s.mallId || '').trim().toLowerCase() === lowerId);

  return res.json({ message: `Mall ${mallId} and all associated records deleted permanently` });
});

/**
 * POST /api/malls/:id/markers
 * Admin: Add an entrance reference marker
 */
router.post('/:id/markers', requireAdmin, (req, res) => {
  const mallId = req.params.id;
  const body = req.body;

  if (!body.name || body.latitude === undefined || body.longitude === undefined) {
    return res.status(400).json({ error: 'Missing marker fields: name, latitude, longitude' });
  }

  const marker = {
    markerId: body.markerId || `mrk-${Date.now()}`,
    buildingId: mallId,
    name: body.name,
    latitude: Number(body.latitude),
    longitude: Number(body.longitude),
    baseHeight: Number(body.baseHeight !== undefined ? body.baseHeight : 0.0),
    physicalWidthMeters: Number(body.physicalWidthMeters || 0.20),
    physicalHeightMeters: Number(body.physicalHeightMeters || 0.20),
    qrCodeData: body.qrCodeData || null,
    createdAt: new Date().toISOString(),
  };

  db.insert('entranceMarkers', marker);
  return res.status(201).json(marker);
});

/**
 * PUT /api/malls/markers/:markerId
 * Admin: Update an entrance marker
 */
router.put('/markers/:markerId', requireAdmin, (req, res) => {
  const markerId = req.params.markerId;
  const updated = db.update(
    'entranceMarkers',
    m => m.markerId === markerId,
    m => ({ ...m, ...req.body, markerId })
  );

  if (!updated) {
    return res.status(404).json({ error: 'Entrance marker not found' });
  }
  return res.json(updated);
});

/**
 * DELETE /api/malls/markers/:markerId
 * Admin: Delete an entrance marker
 */
router.delete('/markers/:markerId', requireAdmin, (req, res) => {
  const markerId = req.params.markerId;
  db.delete('entranceMarkers', m => m.markerId === markerId);
  return res.json({ message: `Entrance marker ${markerId} deleted permanently` });
});

module.exports = router;
