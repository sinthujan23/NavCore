const express = require('express');
const router = express.Router();
const db = require('../db/dataStore');



/**
 * Helper to check if two slot definitions refer to the exact same stall
 */
const isMatchingSlot = (existingSlot, candidateSlot) => {
  const eId = (existingSlot.id || '').trim().toLowerCase();
  const cId = (candidateSlot.id || '').trim().toLowerCase();
  if (eId && cId && eId === cId) return true;

  // Compare normalized slot ID (e.g. 1-B1-A-01 vs 01-B1-A-01 or 1-B1-A01)
  const normEId = eId.replace(/^0+/, '').replace(/[^a-z0-9]/g, '');
  const normCId = cId.replace(/^0+/, '').replace(/[^a-z0-9]/g, '');
  if (normEId && normCId && normEId === normCId) return true;

  // Compare mall, floor, section, slotNumber
  const eMall = (existingSlot.mallId || '').trim().toLowerCase().replace(/^mall-/, '').replace(/^0+/, '');
  const cMall = (candidateSlot.mallId || '').trim().toLowerCase().replace(/^mall-/, '').replace(/^0+/, '');
  const eFloor = (existingSlot.floorId || '').trim().toUpperCase();
  const cFloor = (candidateSlot.floorId || '').trim().toUpperCase();
  const eSec = (existingSlot.section || '').trim().toUpperCase();
  const cSec = (candidateSlot.section || '').trim().toUpperCase();
  const eNum = Number(existingSlot.slotNumber) || 0;
  const cNum = Number(candidateSlot.slotNumber) || 0;

  if (eFloor === cFloor && eSec === cSec && eNum === cNum && (eMall === cMall || !eMall || !cMall)) {
    return true;
  }
  return false;
};

const normalizeSlotId = (id) => {
  if (!id) return '';
  let s = (typeof id === 'string' ? id : (id.id || id.slotId || '')).trim().toLowerCase();
  s = s.replace(/^parking-/, '').replace(/^mall-/, '');
  const parts = s.split(/[-_#]/).map(p => p.replace(/^0+/, '')).filter(Boolean);
  return parts.length ? parts.join('-') : s;
};

const isMatchingSlotId = (slot, targetId) => {
  if (!slot || !targetId) return false;
  const sRaw = (typeof slot === 'string' ? slot : (slot.id || slot.slotId || '')).trim().toLowerCase();
  const tRaw = (typeof targetId === 'string' ? targetId : (targetId.id || targetId.slotId || '')).trim().toLowerCase();
  let sId = sRaw.replace(/^parking-/, '');
  let tId = tRaw.replace(/^parking-/, '');
  if (sId === tId) return true;

  const cleanS = sId.replace(/^mall-/, '');
  const cleanT = tId.replace(/^mall-/, '');
  if (cleanS === cleanT) return true;

  const normS = normalizeSlotId(cleanS);
  const normT = normalizeSlotId(cleanT);
  if (normS.length > 0 && normS === normT) return true;

  const alphaS = cleanS.replace(/[^a-z0-9]/g, '');
  const alphaT = cleanT.replace(/[^a-z0-9]/g, '');
  if (alphaS.length > 0 && alphaS === alphaT) return true;

  const stripZeroS = alphaS.replace(/^0+/, '');
  const stripZeroT = alphaT.replace(/^0+/, '');
  if (stripZeroS.length > 0 && stripZeroS === stripZeroT) return true;

  if (typeof slot === 'object' && slot !== null) {
    const sFloor = (slot.floorId || '').trim().toUpperCase();
    const sSec = (slot.section || '').trim().toUpperCase();
    const sNum = Number(slot.slotNumber) || 0;
    if (sFloor && sSec && sNum > 0) {
      const match = cleanT.match(/([a-z0-9]+)[-_#]([a-z])[-_#]?([0-9]+)$/i);
      if (match) {
        const tFloor = match[1].toUpperCase();
        const tSec = match[2].toUpperCase();
        const tNum = Number(match[3]) || 0;
        if (sFloor === tFloor && sSec === tSec && sNum === tNum) return true;
      }
    }
  }

  return false;
};

const deduplicateSlotsList = (slots) => {
  const seen = new Set();
  const seenPos = new Set();
  const deduped = [];
  const vehicles = db.get('vehicleLocations') || {};
  const occupiedSlots = new Set(
    Object.values(vehicles)
      .filter(v => v.status === 'parked' && v.slotId)
      .map(v => (v.slotId || '').trim().toLowerCase())
  );

  for (const s of slots) {
    const sId = (s.id || '').trim().toLowerCase();
    const posKey = `${(s.floorId || '').trim().toUpperCase()}#${(s.section || '').trim().toUpperCase()}#${Number(s.slotNumber) || 0}`;
    if (!seen.has(sId) && !seenPos.has(posKey)) {
      seen.add(sId);
      seenPos.add(posKey);
      // Synchronize status with active parked vehicle record if present
      const slotCopy = { ...s };
      if (occupiedSlots.has(sId) || Array.from(occupiedSlots).some(occ => isMatchingSlotId(s, occ))) {
        slotCopy.status = 'occupied';
      }
      deduped.push(slotCopy);
    }
  }
  return deduped;
};

/**
 * GET /api/parking/slots
 * Returns all deduplicated parking slots synchronized with active vehicle occupancies
 */
router.get('/slots', (req, res) => {
  const slots = db.get('parkingSlots') || [];
  return res.json(deduplicateSlotsList(slots));
});

/**
 * GET /api/parking/:mallId/slots
 */
router.get('/:mallId/slots', (req, res) => {
  const reqMall = (req.params.mallId || '').trim().toLowerCase();
  const allSlots = db.get('parkingSlots') || [];
  if (!reqMall || reqMall === 'all') {
    return res.json(deduplicateSlotsList(allSlots));
  }
  const cleanReqMall = reqMall.replace(/^mall-/, '');
  const normReqMall = cleanReqMall.replace(/^0+/, '') || cleanReqMall;

  // Find mall in DB to match against mall name as well
  const malls = db.get('malls') || [];
  const targetMall = malls.find(m => {
    const mId = (m.id || '').trim().toLowerCase();
    const mName = (m.name || '').trim().toLowerCase();
    const cleanMId = mId.replace(/^mall-/, '');
    const normMId = cleanMId.replace(/^0+/, '') || cleanMId;
    return mId === reqMall ||
      cleanMId === cleanReqMall ||
      normMId === normReqMall ||
      mName === reqMall ||
      mName.replace(/[^a-z0-9]+/g, '-') === cleanReqMall;
  });
  const targetMallId = targetMall ? (targetMall.id || '').trim().toLowerCase() : '';
  const cleanTargetMallId = targetMallId.replace(/^mall-/, '');
  const normTargetMallId = cleanTargetMallId.replace(/^0+/, '') || cleanTargetMallId;

  const slots = allSlots.filter(s => {
    const sMall = (s.mallId || '').trim().toLowerCase();
    const cleanSMall = sMall.replace(/^mall-/, '');
    const normSMall = cleanSMall.replace(/^0+/, '') || cleanSMall;
    const sId = (s.id || '').trim().toLowerCase();

    return sMall === reqMall ||
      cleanSMall === cleanReqMall ||
      normSMall === normReqMall ||
      (targetMallId && (sMall === targetMallId || cleanSMall === cleanTargetMallId || normSMall === normTargetMallId)) ||
      sId.startsWith(`${cleanReqMall}-`) ||
      sId.startsWith(`${normReqMall}-`) ||
      (cleanTargetMallId && sId.startsWith(`${cleanTargetMallId}-`));
  });
  return res.json(deduplicateSlotsList(slots));
});

/**
 * Helper to handle bulk creation
 */
const handleBulkCreateSlots = (mallId, req, res) => {
  const cleanMall = (mallId || '1').replace(/^mall-/, '');
  const slotsList = Array.isArray(req.body)
    ? req.body
    : (Array.isArray(req.body.slots) ? req.body.slots : []);
  const added = [];

  for (const s of slotsList) {
    const slotId = s.id || `${cleanMall}-${s.floorId || 'P'}-${s.section || 'A'}${s.slotNumber || Date.now()}-${Math.random().toString(36).substr(2, 4)}`;
    const newSlot = {
      id: slotId,
      mallId: s.mallId || mallId || cleanMall,
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
      sensorId: s.sensorId || `SNS-${cleanMall}-${s.floorId || 'GF'}-${s.section || 'A'}${s.slotNumber || 1}`,
      createdAt: s.createdAt || new Date().toISOString()
    };
    const currentSlots = db.get('parkingSlots') || [];
    const existingIndex = currentSlots.findIndex(x => isMatchingSlot(x, newSlot));
    if (existingIndex !== -1) {
      const matchId = currentSlots[existingIndex].id;
      db.update('parkingSlots', x => x.id === matchId, () => ({ ...newSlot, id: matchId }));
      added.push({ ...newSlot, id: matchId });
    } else {
      db.push('parkingSlots', newSlot);
      added.push(newSlot);
    }
  }
  console.log(`[Parking] Bulk added/updated ${added.length} slots for mall ${mallId}`);
  return res.status(201).json(added);
};

/**
 * POST /api/parking/slots/bulk
 * POST /api/parking/:mallId/slots/bulk
 */
router.post('/slots/bulk', (req, res) => {
  const mallId = req.body.mallId || (Array.isArray(req.body) && req.body.length > 0 ? req.body[0].mallId : '') || '1';
  return handleBulkCreateSlots(mallId, req, res);
});

router.post('/:mallId/slots/bulk', (req, res) => {
  const mallId = req.params.mallId || req.body.mallId || '1';
  return handleBulkCreateSlots(mallId, req, res);
});

/**
 * POST /api/parking/slots
 * POST /api/parking/:mallId/slots
 * Creates or updates a single parking slot
 */
const handleCreateSlot = (req, res) => {
  const mallId = req.params.mallId || req.body.mallId || '1';
  const body = req.body;
  const cleanMall = mallId.replace(/^mall-/, '');
  const slotId = body.id || `${cleanMall}-${body.floorId || 'P'}-${body.section || 'A'}${body.slotNumber || Date.now()}`;
  const newSlot = {
    id: slotId,
    mallId: mallId,
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
    sensorId: body.sensorId || `SNS-${cleanMall}-${body.floorId || 'P'}-${body.section || 'A'}${body.slotNumber || 1}`,
    createdAt: body.createdAt || new Date().toISOString()
  };

  const currentSlots = db.get('parkingSlots') || [];
  const existingIndex = currentSlots.findIndex(s => isMatchingSlot(s, newSlot));
  if (existingIndex !== -1) {
    const matchId = currentSlots[existingIndex].id;
    db.update('parkingSlots', s => s.id === matchId, () => ({ ...newSlot, id: matchId }));
    console.log(`[Parking] Updated existing slot ${matchId} for mall ${mallId} (status: ${newSlot.status})`);
    return res.status(200).json({ ...newSlot, id: matchId });
  } else {
    db.push('parkingSlots', newSlot);
    console.log(`[Parking] Stored slot ${slotId} for mall ${mallId} (status: ${newSlot.status})`);
    return res.status(201).json(newSlot);
  }
};

router.post('/slots', handleCreateSlot);
router.post('/:mallId/slots', handleCreateSlot);

/**
 * DELETE /api/parking/slots/:id
 * DELETE /api/parking/:mallId/slots/:id
 * Deletes a parking slot
 */
const handleDeleteSlot = (req, res) => {
  const slotId = (req.params.id || '').trim().toLowerCase();
  db.remove('parkingSlots', s => isMatchingSlotId(s, slotId));
  db.remove('destinations', d => isMatchingSlotId(d, slotId) || isMatchingSlotId({ id: (d.id || '').replace(/^parking-/, '') }, slotId));

  // If a vehicle was parked at this deleted slot, remove the vehicle record
  const vehicles = db.get('vehicleLocations') || {};
  let vehicleChanged = false;
  for (const [uId, v] of Object.entries(vehicles)) {
    if (v.slotId && isMatchingSlotId({ id: v.slotId }, slotId)) {
      delete vehicles[uId];
      vehicleChanged = true;
    }
  }
  if (vehicleChanged) {
    db.set('vehicleLocations', vehicles);
  }

  console.log(`[Parking] Deleted slot ${req.params.id}`);
  return res.json({ message: 'Parking slot deleted successfully' });
};

/**
 * DELETE /api/parking/:mallId/slots
 * DELETE /api/parking/slots
 * Clears parking slots for a mall
 */
const handleClearAllSlots = (req, res) => {
  const reqMall = (req.params.mallId || (req.body && req.body.mallId) || (req.query && req.query.mallId) || '').trim().toLowerCase().replace(/^mall-/, '');
  const normReqMall = reqMall.replace(/^0+/, '') || reqMall;

  const vehicles = db.get('vehicleLocations') || {};
  const occupiedSlotIds = new Set(
    Object.values(vehicles).filter(v => v.status === 'parked' && v.slotId).map(v => v.slotId.trim().toLowerCase())
  );

  db.remove('parkingSlots', s => {
    const sMall = (s.mallId || '').trim().toLowerCase().replace(/^mall-/, '');
    const normSMall = sMall.replace(/^0+/, '') || sMall;
    const sId = (s.id || '').trim().toLowerCase();
    const matchesMall = !reqMall || reqMall === 'all' || sMall === reqMall || sMall === normReqMall || normSMall === reqMall || normSMall === normReqMall || sId.startsWith(`${reqMall}-`) || sId.startsWith(`${normReqMall}-`);
    if (!matchesMall) return false;
    const isOccupied = s.status === 'occupied' || occupiedSlotIds.has(sId) || Array.from(occupiedSlotIds).some(occ => isMatchingSlotId(s, occ));
    return !isOccupied;
  });

  db.remove('destinations', d => {
    const isPark = d.category === 'PARKING' || d.category === 'PARKING_SLOT' || d.category === 'PARKING_BAY' || (d.description || '').includes('PARKING_META|') || (d.id || '').startsWith('parking-');
    if (!isPark) return false;
    const dMall = (d.mallId || '').trim().toLowerCase().replace(/^mall-/, '');
    const normDMall = dMall.replace(/^0+/, '') || dMall;
    const dId = (d.id || '').trim().toLowerCase();
    const matchesMall = !reqMall || reqMall === 'all' || dMall === reqMall || dMall === normReqMall || normDMall === reqMall || normDMall === normReqMall || dId.startsWith(`${reqMall}-`) || dId.startsWith(`${normReqMall}-`);
    if (!matchesMall) return false;
    const isOccupied = (d.openStatus || '').toLowerCase() === 'occupied' || occupiedSlotIds.has(dId) || Array.from(occupiedSlotIds).some(occ => isMatchingSlotId(d, occ));
    return !isOccupied;
  });

  console.log(`[Parking] Cleared parking slots for mall ${reqMall || 'all'}`);
  return res.json({ message: `Cleared parking slots for mall ${reqMall || 'all'}` });
};

router.delete('/slots', handleClearAllSlots);
router.delete('/:mallId/slots', handleClearAllSlots);
router.delete('/slots/:id', handleDeleteSlot);
router.delete('/:mallId/slots/:id', handleDeleteSlot);

/**
 * PUT /api/parking/slots/:id
 * PUT /api/parking/:mallId/slots/:id
 * Updates parking slot occupancy status and metadata
 */
const handleUpdateSlot = (req, res) => {
  const slotId = (req.params.id || '').trim().toLowerCase();
  const body = req.body || {};

  const updatedCount = db.updateAll(
    'parkingSlots',
    s => isMatchingSlotId(s, slotId),
    s => ({
      ...s,
      ...body,
      status: body.status || s.status,
      id: s.id, // preserve original id casing
    })
  );

  // Synchronize destination openStatus if present in destinations
  if (body.status) {
    db.updateAll(
      'destinations',
      d => isMatchingSlotId(d, slotId) || isMatchingSlotId({ id: (d.id || '').replace(/^parking-/, '') }, slotId),
      d => ({ ...d, openStatus: body.status })
    );
  }

  // If status is explicitly set to free, remove any parked vehicle records in this slot
  if (body.status === 'free') {
    const vehicles = db.get('vehicleLocations') || {};
    let vehicleChanged = false;
    for (const [uId, v] of Object.entries(vehicles)) {
      if (v.slotId && isMatchingSlotId({ id: v.slotId }, slotId)) {
        delete vehicles[uId];
        vehicleChanged = true;
      }
    }
    if (vehicleChanged) {
      db.set('vehicleLocations', vehicles);
    }
  }

  if (updatedCount === 0) {
    // If not found in memory, insert it as new slot so it isn't lost
    const fallbackSlot = {
      id: req.params.id,
      mallId: body.mallId || req.params.mallId || '1',
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
      sensorId: body.sensorId || `SNS-${req.params.id}`,
      createdAt: new Date().toISOString()
    };
    db.push('parkingSlots', fallbackSlot);
    console.log(`[Parking] Created new slot via PUT: ${req.params.id} (status: ${fallbackSlot.status})`);
    return res.json(fallbackSlot);
  }

  const updatedSlots = (db.get('parkingSlots') || []).filter(s => isMatchingSlotId(s, slotId));
  console.log(`[Parking] Updated slot ${req.params.id} -> status: ${body.status || 'updated'}`);
  return res.json(updatedSlots[0] || { id: req.params.id, status: body.status });
};

router.put('/slots/:id', handleUpdateSlot);
router.put('/:mallId/slots/:id', handleUpdateSlot);

/**
 * GET /api/parking/:mallId/vehicles
 * GET /api/parking/vehicles
 * Returns all active parked vehicles
 */
const handleGetVehicles = (req, res) => {
  const reqMall = (req.params.mallId || '').trim().toLowerCase().replace(/^mall-/, '');
  const normReqMall = reqMall.replace(/^0+/, '') || reqMall;
  const vehicles = db.get('vehicleLocations') || {};
  const list = Object.values(vehicles).filter(v => v.status === 'parked');
  if (!reqMall || reqMall === 'all') {
    return res.json(list);
  }
  const filtered = list.filter(v => {
    const vMall = (v.mallId || '').trim().toLowerCase().replace(/^mall-/, '');
    const normVMall = vMall.replace(/^0+/, '') || vMall;
    const vSlot = (v.slotId || '').trim().toLowerCase().replace(/^parking-/, '').replace(/^mall-/, '');
    const normVSlot = vSlot.replace(/^0+/, '');
    return vMall === reqMall ||
      vMall === normReqMall ||
      normVMall === reqMall ||
      normVMall === normReqMall ||
      vSlot.startsWith(`${reqMall}-`) ||
      vSlot.startsWith(`${normReqMall}-`) ||
      normVSlot.startsWith(`${normReqMall}-`) ||
      !vMall;
  });
  return res.json(filtered);
};

router.get('/vehicles', handleGetVehicles);
router.get('/:mallId/vehicles', handleGetVehicles);

/**
 * GET /api/parking/:mallId/vehicle/:userId
 * GET /api/parking/vehicle/:userId
 */
const handleGetVehicleForUser = (req, res) => {
  const { userId } = req.params;
  const vehicles = db.get('vehicleLocations') || {};
  const vehicle = vehicles[userId];

  if (!vehicle) {
    return res.status(404).json({ error: 'No parked vehicle record found for this user' });
  }

  return res.json(vehicle);
};

router.get('/vehicle/:userId', handleGetVehicleForUser);
router.get('/:mallId/vehicle/:userId', handleGetVehicleForUser);

/**
 * POST /api/parking/:mallId/vehicle
 * POST /api/parking/vehicle
 */
const handleParkVehicle = (req, res) => {
  const body = req.body || {};
  const userId = body.userId || 'usr-default';
  const mallId = (req.params.mallId || body.mallId || (body.slotId && body.slotId.includes('-') ? body.slotId.split('-')[0] : '1')).replace(/^mall-/, '');

  const vehicleRecord = {
    userId,
    vehicleId: body.vehicleId || 'veh-default',
    slotId: body.slotId,
    mallId,
    floorId: body.floorId || 'P',
    floorName: body.floorName || 'Basement Level B1',
    latitude: Number(body.latitude) || 0.0,
    longitude: Number(body.longitude) || 0.0,
    height: Number(body.height || 0.0),
    timestamp: new Date().toISOString(),
    status: 'parked',
    licensePlate: body.licensePlate || 'WP CAB-8821',
    notes: body.notes || null,
  };

  const vehicles = db.get('vehicleLocations') || {};
  vehicles[userId] = vehicleRecord;
  db.set('vehicleLocations', vehicles);

  // Mark all matching slot instances as occupied in parkingSlots and destinations
  if (body.slotId) {
    const updatedCount = db.updateAll(
      'parkingSlots',
      s => isMatchingSlotId(s, body.slotId),
      s => ({ ...s, status: 'occupied' })
    );

    // If slot didn't exist in parkingSlots yet, insert it as occupied!
    if (updatedCount === 0) {
      const parts = (body.slotId || '').split('-');
      const floorId = body.floorId || (parts.length >= 2 ? parts[1] : 'P');
      const section = parts.length >= 3 ? parts[2] : 'A';
      const slotNum = Number(parts.length >= 4 ? parts[3] : 1) || 1;
      db.push('parkingSlots', {
        id: body.slotId,
        mallId,
        floorId,
        section,
        slotNumber: slotNum,
        status: 'occupied',
        latitude: Number(body.latitude) || 0.0,
        longitude: Number(body.longitude) || 0.0,
        height: Number(body.height || 0.0),
        gridRow: 0,
        gridCol: 0,
        isEVCharging: false,
        isHandicapAccessible: false,
        sensorId: `SNS-${body.slotId}`,
        createdAt: new Date().toISOString(),
      });
    }

    db.updateAll(
      'destinations',
      d => isMatchingSlotId(d, body.slotId) || isMatchingSlotId({ id: (d.id || '').replace(/^parking-/, '') }, body.slotId),
      d => ({ ...d, openStatus: 'occupied' })
    );
    console.log(`[Parking] Marked slot ${body.slotId} as OCCUPIED by user ${userId} (mall: ${mallId})`);
  }

  return res.status(201).json(vehicleRecord);
};

router.post('/vehicle', handleParkVehicle);
router.post('/:mallId/vehicle', handleParkVehicle);

/**
 * DELETE /api/parking/:mallId/vehicle/:userId
 * DELETE /api/parking/vehicle/:userId
 */
const handleUnparkVehicle = (req, res) => {
  const { userId } = req.params;
  const vehicles = db.get('vehicleLocations') || {};
  let current = vehicles[userId];
  let matchedUserKey = userId;

  if (!current) {
    for (const [uId, v] of Object.entries(vehicles)) {
      if (uId.toLowerCase() === (userId || '').toLowerCase() ||
          (v.slotId && isMatchingSlotId({ id: v.slotId }, userId))) {
        current = v;
        matchedUserKey = uId;
        break;
      }
    }
  }

  if (current && current.slotId) {
    // Free all matching slot instances in parkingSlots and destinations
    db.updateAll('parkingSlots', s => isMatchingSlotId(s, current.slotId), s => ({ ...s, status: 'free' }));
    db.updateAll(
      'destinations',
      d => isMatchingSlotId(d, current.slotId) || isMatchingSlotId({ id: (d.id || '').replace(/^parking-/, '') }, current.slotId),
      d => ({ ...d, openStatus: 'free' })
    );
    console.log(`[Parking] Freed slot ${current.slotId} from user ${matchedUserKey}`);
  }

  delete vehicles[matchedUserKey];
  db.set('vehicleLocations', vehicles);

  return res.json({ message: 'Parked vehicle location cleared successfully' });
};

router.delete('/vehicle/:userId', handleUnparkVehicle);
router.delete('/:mallId/vehicle/:userId', handleUnparkVehicle);

/**
 * DELETE /api/parking/vehicles
 * DELETE /api/parking/:mallId/vehicles
 * Clears all active vehicle pins for a given mall venue (or all malls)
 */
const handleClearAllVehicles = (req, res) => {
  const reqMall = (req.params.mallId || req.body.mallId || '').trim().toLowerCase().replace(/^mall-/, '');
  const normReqMall = reqMall.replace(/^0+/, '') || reqMall;
  const vehicles = db.get('vehicleLocations') || {};
  let removedCount = 0;

  if (!reqMall || reqMall === 'all') {
    db.set('vehicleLocations', {});
    db.updateAll('parkingSlots', () => true, s => ({ ...s, status: 'free' }));
    db.updateAll('destinations', d => d.category === 'PARKING', d => ({ ...d, openStatus: 'free' }));
    console.log('[Parking] Cleared all vehicles across all venues');
    return res.json({ message: 'All vehicle pins cleared across all venues' });
  }

  for (const [uId, v] of Object.entries(vehicles)) {
    const vMall = (v.mallId || '').trim().toLowerCase().replace(/^mall-/, '');
    const normVMall = vMall.replace(/^0+/, '') || vMall;
    const vSlot = (v.slotId || '').trim().toLowerCase().replace(/^parking-/, '').replace(/^mall-/, '');
    const normVSlot = vSlot.replace(/^0+/, '');

    const matches = vMall === reqMall ||
      vMall === normReqMall ||
      normVMall === reqMall ||
      normVMall === normReqMall ||
      vSlot.startsWith(`${reqMall}-`) ||
      vSlot.startsWith(`${normReqMall}-`) ||
      normVSlot.startsWith(`${normReqMall}-`);

    if (matches) {
      if (v.slotId) {
        db.updateAll('parkingSlots', s => isMatchingSlotId(s, v.slotId), s => ({ ...s, status: 'free' }));
        db.updateAll('destinations', d => isMatchingSlotId(d, v.slotId) || isMatchingSlotId({ id: (d.id || '').replace(/^parking-/, '') }, v.slotId), d => ({ ...d, openStatus: 'free' }));
      }
      delete vehicles[uId];
      removedCount++;
    }
  }

  db.set('vehicleLocations', vehicles);
  console.log(`[Parking] Cleared ${removedCount} vehicle pins for mall ${reqMall}`);
  return res.json({ message: `Cleared ${removedCount} vehicle pins for mall ${reqMall}` });
};

router.delete('/vehicles', handleClearAllVehicles);
router.delete('/:mallId/vehicles', handleClearAllVehicles);

/**
 * POST/PUT /api/parking/slots/reset-free
 * POST/PUT /api/parking/:mallId/slots/reset-free
 */
const handleResetSlotsToFree = (req, res) => {
  const reqMall = (req.params.mallId || req.body.mallId || '').trim().toLowerCase().replace(/^mall-/, '');
  const normReqMall = reqMall.replace(/^0+/, '') || reqMall;

  db.updateAll('parkingSlots', s => {
    if (!reqMall || reqMall === 'all') return true;
    const sMall = (s.mallId || '').trim().toLowerCase().replace(/^mall-/, '');
    const normSMall = sMall.replace(/^0+/, '') || sMall;
    const sId = (s.id || '').trim().toLowerCase().replace(/^parking-/, '');
    return sMall === reqMall || sMall === normReqMall || normSMall === reqMall || normSMall === normReqMall || sId.startsWith(`${reqMall}-`) || sId.startsWith(`${normReqMall}-`);
  }, s => ({ ...s, status: 'free' }));

  return res.json({ message: 'All parking stalls reset to free' });
};

router.post('/slots/reset-free', handleResetSlotsToFree);
router.post('/:mallId/slots/reset-free', handleResetSlotsToFree);
router.put('/slots/reset-free', handleResetSlotsToFree);
router.put('/:mallId/slots/reset-free', handleResetSlotsToFree);

module.exports = router;
