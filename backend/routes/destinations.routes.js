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
    const qm = (mallId || '').trim().toLowerCase();
    if (qm !== 'all' && qm.length > 0) {
      results = results.filter(d => {
        const dm = (d.mallId || '').trim().toLowerCase();
        if (!dm) return true;
        return dm === qm ||
          dm === qm.replace(/^mall-/, '') ||
          qm === dm.replace(/^mall-/, '') ||
          dm.includes(qm) ||
          qm.includes(dm);
      });
    }
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

  // Deduplicate before returning
  const seenIds = new Set();
  const seenKeys = new Set();
  const deduped = [];
  for (const d of results) {
    const dId = (d.id || '').trim().toLowerCase();
    const dMall = (d.mallId || '').trim().toLowerCase().replace(/^mall-/, '').replace(/^0+/, '');
    const key = `${(d.name || '').trim().toLowerCase()}#${d.floorNumber}#${dMall}`;
    if (!seenIds.has(dId) && !seenKeys.has(key)) {
      if (dId) seenIds.add(dId);
      seenKeys.add(key);
      deduped.push(d);
    }
  }

  return res.json(deduped);
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
  const targetFloor = body.floorNumber !== undefined ? Number(body.floorNumber) : 1;

  // Prevent duplicate creation: check by id or (mallId + trimmed lowercased name + floorNumber)
  const normTargetMall = (targetMallId || '').trim().toLowerCase().replace(/^mall-/, '').replace(/^0+/, '');
  const existing = db.find('destinations', d => {
    const dId = (d.id || '').trim().toLowerCase();
    const bId = (body.id || '').trim().toLowerCase();
    if (bId && dId === bId) return true;
    const dMall = (d.mallId || '').trim().toLowerCase().replace(/^mall-/, '').replace(/^0+/, '');
    const dName = (d.name || '').trim().toLowerCase();
    const bName = (body.name || '').trim().toLowerCase();
    return (dMall === normTargetMall || !dMall || !normTargetMall) &&
      dName === bName &&
      Number(d.floorNumber) === targetFloor;
  });

  if (existing) {
    const updated = db.update(
      'destinations',
      d => d.id === existing.id,
      d => ({
        ...d,
        name: body.name,
        category: body.category || d.category,
        rating: body.rating !== undefined ? Number(body.rating) : d.rating,
        latitude: Number(body.latitude),
        longitude: Number(body.longitude),
        height: body.height !== undefined ? Number(body.height) : d.height,
        description: body.description || d.description,
        openStatus: body.openStatus || d.openStatus,
        openingHours: body.openingHours || d.openingHours,
        imageUrl: body.imageUrl !== undefined ? body.imageUrl : d.imageUrl,
      })
    );
    return res.status(200).json(updated || existing);
  }

  const newPoi = {
    id: body.id || `poi-${Date.now()}`,
    mallId: targetMallId,
    name: body.name,
    category: body.category || 'SERVICES',
    floorNumber: targetFloor,
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

const normalizeSlotId = (id) => {
  if (!id) return '';
  let s = (typeof id === 'string' ? id : (id.id || id.slotId || '')).trim().toLowerCase();
  s = s.replace(/^parking-/, '');
  const parts = s.split(/[-_#]/).map(p => p.replace(/^0+/, '')).filter(Boolean);
  return parts.length ? parts.join('-') : s;
};

const isMatchingPoiId = (item, targetId) => {
  if (!item || !targetId) return false;
  const dId = (item.id || '').trim().toLowerCase();
  const tId = targetId.trim().toLowerCase();
  if (dId === tId) return true;
  const cleanD = dId.replace(/^parking-/, '');
  const cleanT = tId.replace(/^parking-/, '');
  if (cleanD === cleanT) return true;
  const normD = normalizeSlotId(cleanD);
  const normT = normalizeSlotId(cleanT);
  return normD.length > 0 && normD === normT;
};

/**
 * PUT /api/destinations/:id
 * Admin: Update destination POI
 */
router.put('/:id', requireAdmin, (req, res) => {
  const poiId = req.params.id;
  const updated = db.update(
    'destinations',
    d => isMatchingPoiId(d, poiId),
    d => ({ ...d, ...req.body, id: d.id })
  );

  // Synchronize slot status if this destination represents a parking bay
  if (req.body.openStatus) {
    const slotStatus = req.body.openStatus.toLowerCase() === 'occupied'
      ? 'occupied'
      : (req.body.openStatus.toLowerCase() === 'reserved' ? 'reserved' : 'free');
    db.updateAll(
      'parkingSlots',
      s => isMatchingPoiId(s, poiId),
      s => ({ ...s, status: slotStatus })
    );
  }

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
  const poiId = (req.params.id || '').trim();
  db.delete('destinations', d => isMatchingPoiId(d, poiId));
  db.delete('parkingSlots', s => isMatchingPoiId(s, poiId));

  // If a vehicle was parked at this slot, remove it
  const vehicles = db.get('vehicleLocations') || {};
  let changed = false;
  for (const [uId, v] of Object.entries(vehicles)) {
    if (v.slotId && isMatchingPoiId({ id: v.slotId }, poiId)) {
      delete vehicles[uId];
      changed = true;
    }
  }
  if (changed) {
    db.set('vehicleLocations', vehicles);
  }

  return res.json({ message: `Destination ${poiId} deleted successfully` });
});

module.exports = router;
