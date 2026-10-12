const express = require('express');
const router = express.Router();
const db = require('../db/dataStore');
const { requireAdmin } = require('../middleware/auth');

/**
 * GET /api/destinations
 * Query params: mallId, floorNumber, category, search
 */
router.get('/', (req, res) => {
  const { mallId, floorNumber, category, search } = req.query;

  let results = db.get('destinations');

  if (mallId) {
    results = results.filter(d => d.mallId === mallId);
  }

  if (floorNumber !== undefined) {
    const fn = parseInt(floorNumber, 10);
    results = results.filter(d => d.floorNumber === fn);
  }

  if (category) {
    results = results.filter(d => d.category.toLowerCase() === category.toLowerCase());
  }

  if (search) {
    const q = search.toLowerCase();
    results = results.filter(d =>
      d.name.toLowerCase().includes(q) ||
      d.description.toLowerCase().includes(q) ||
      d.category.toLowerCase().includes(q)
    );
  }

  return res.json(results);
});

/**
 * GET /api/destinations/:id
 */
router.get('/:id', (req, res) => {
  const poi = db.find('destinations', d => d.id === req.params.id);
  if (!poi) {
    return res.status(404).json({ error: 'Destination POI not found' });
  }
  return res.json(poi);
});

/**
 * POST /api/destinations
 * Admin: Add new destination POI
 */
router.post('/', requireAdmin, (req, res) => {
  const body = req.body;

  if (!body.name || body.latitude === undefined || body.longitude === undefined) {
    return res.status(400).json({ error: 'Missing required POI fields: name, latitude, longitude' });
  }

  const malls = db.get('malls');
  const targetMallId = body.mallId || (malls.length > 0 ? malls[0].id : 'mall-default');

  const newPoi = {
    id: body.id || `poi-${Date.now()}`,
    mallId: targetMallId,
    name: body.name,
    category: body.category || 'SERVICES',
    floorNumber: body.floorNumber !== undefined ? Number(body.floorNumber) : 1,
    rating: body.rating !== undefined ? Number(body.rating) : 4.8,
    latitude: Number(body.latitude),
    longitude: Number(body.longitude),
    height: body.height !== undefined ? Number(body.height) : 15.0,
    description: body.description || '',
    openStatus: body.openStatus || 'Open Now',
    openingHours: body.openingHours || '10:00 AM - 10:00 PM',
    imageUrl: body.imageUrl || null,
  };

  db.insert('destinations', newPoi);
  return res.status(201).json(newPoi);
});

/**
 * PUT /api/destinations/:id
 * Admin: Update destination POI
 */
router.put('/:id', requireAdmin, (req, res) => {
  const poiId = req.params.id;
  const updated = db.update(
    'destinations',
    d => d.id === poiId,
    d => ({ ...d, ...req.body, id: poiId })
  );

  if (!updated) {
    return res.status(404).json({ error: 'Destination POI not found' });
  }
  return res.json(updated);
});

/**
 * DELETE /api/destinations/:id
 * Admin: Delete destination POI
 */
router.delete('/:id', requireAdmin, (req, res) => {
  const poiId = req.params.id;
  db.delete('destinations', d => d.id === poiId);
  return res.json({ message: `Destination ${poiId} deleted successfully` });
});

module.exports = router;
