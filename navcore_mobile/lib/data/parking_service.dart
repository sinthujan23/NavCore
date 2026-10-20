import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../engine/ecef_engine.dart';
import '../engine/bearing_engine.dart';
import 'api_service.dart';
import 'destinations.dart';

enum ParkingSlotStatus { free, occupied, reserved }

class ParkingSlot {
  final String id;
  final String mallId;
  final String floorId;
  final String section;
  final int slotNumber;
  ParkingSlotStatus status;
  final GeodeticCoords location;
  final int gridRow;
  final int gridCol;
  final bool isEVCharging;
  final bool isHandicapAccessible;
  final String sensorId;

  ParkingSlot({
    required this.id,
    this.mallId = '',
    required this.floorId,
    required this.section,
    required this.slotNumber,
    required this.status,
    required this.location,
    required this.gridRow,
    required this.gridCol,
    this.isEVCharging = false,
    this.isHandicapAccessible = false,
    required this.sensorId,
  });

  DestinationPOI toDestinationPOI() {
    int floorNum = 1;
    final clean = floorId.trim().toUpperCase();
    if (clean.startsWith('B')) {
      final digits = int.tryParse(clean.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
      floorNum = -digits;
    } else if (clean == 'GF' || clean == 'GROUND' || clean == 'G') {
      floorNum = 0;
    } else {
      final digits = int.tryParse(clean.replaceAll(RegExp(r'[^0-9]'), ''));
      if (digits != null) floorNum = digits;
    }
    return DestinationPOI(
      id: id,
      name: 'Parking Stall $id',
      category: 'PARKING',
      floorNumber: floorNum,
      rating: 4.8,
      location: location,
      description:
          'PARKING_META|floor:$floorId|sec:$section|num:$slotNumber|ev:$isEVCharging|handicap:$isHandicapAccessible|sensor:$sensorId',
      openStatus: status == ParkingSlotStatus.occupied ? 'occupied' : 'free',
      mallId: mallId.isNotEmpty ? mallId : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'mallId': mallId,
    'floorId': floorId,
    'section': section,
    'slotNumber': slotNumber,
    'status': status.name,
    'latitude': location.latitude,
    'longitude': location.longitude,
    'height': location.height,
    'gridRow': gridRow,
    'gridCol': gridCol,
    'isEVCharging': isEVCharging,
    'isHandicapAccessible': isHandicapAccessible,
    'sensorId': sensorId,
  };

  factory ParkingSlot.fromJson(Map<String, dynamic> json) => ParkingSlot(
    id: json['id'] ?? '',
    mallId: (json['mallId'] ?? '').toString(),
    floorId: json['floorId'] ?? 'P',
    section: json['section'] ?? 'A',
    slotNumber: json['slotNumber'] is num
        ? (json['slotNumber'] as num).toInt()
        : int.tryParse(json['slotNumber']?.toString() ?? '1') ?? 1,
    status: ParkingSlotStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => ParkingSlotStatus.free,
    ),
    location: GeodeticCoords(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      height: (json['height'] as num?)?.toDouble() ?? 0.0,
    ),
    gridRow: json['gridRow'] is num
        ? (json['gridRow'] as num).toInt()
        : int.tryParse(json['gridRow']?.toString() ?? '0') ?? 0,
    gridCol: json['gridCol'] is num
        ? (json['gridCol'] as num).toInt()
        : int.tryParse(json['gridCol']?.toString() ?? '0') ?? 0,
    isEVCharging: json['isEVCharging'] ?? false,
    isHandicapAccessible: json['isHandicapAccessible'] ?? false,
    sensorId: json['sensorId'] ?? '',
  );
}

class MyVehicleLocation {
  final String userId;
  final String vehicleId;
  final String slotId;
  final String floorId;
  final String floorName;
  final GeodeticCoords location;
  final DateTime timestamp;
  final String status; // "parked" | "removed"
  final String licensePlate;
  final String? notes;
  final String mallId;

  MyVehicleLocation({
    required this.userId,
    required this.slotId,
    required this.floorId,
    required this.floorName,
    required this.location,
    required this.timestamp,
    this.vehicleId = 'veh-default',
    this.status = 'parked',
    this.licensePlate = 'WP CAB-8821',
    this.notes,
    this.mallId = '',
  });

  DestinationPOI toDestinationPOI() {
    final int floorNum = floorId.contains('B2') ? -2 : -1;
    return DestinationPOI(
      id: slotId,
      name: 'My Parked Car ($slotId)',
      category: 'PARKING',
      floorNumber: floorNum,
      rating: 5.0,
      location: location,
      description: 'Your saved vehicle location at $floorName ($slotId)',
      openStatus: '24/7',
      mallId: mallId.isNotEmpty ? mallId : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'vehicleId': vehicleId,
    'slotId': slotId,
    'mallId': mallId,
    'floorId': floorId,
    'floorName': floorName,
    'latitude': location.latitude,
    'longitude': location.longitude,
    'height': location.height,
    'timestamp': timestamp.toIso8601String(),
    'status': status,
    'licensePlate': licensePlate,
    'notes': notes,
  };

  factory MyVehicleLocation.fromJson(Map<String, dynamic> json) {
    double lat = 0.0;
    if (json['latitude'] != null) {
      lat = (json['latitude'] is num)
          ? (json['latitude'] as num).toDouble()
          : double.tryParse(json['latitude'].toString()) ?? 0.0;
    }
    double lon = 0.0;
    if (json['longitude'] != null) {
      lon = (json['longitude'] is num)
          ? (json['longitude'] as num).toDouble()
          : double.tryParse(json['longitude'].toString()) ?? 0.0;
    }
    double height = 0.0;
    if (json['height'] != null) {
      height = (json['height'] is num)
          ? (json['height'] as num).toDouble()
          : double.tryParse(json['height'].toString()) ?? 0.0;
    }
    DateTime ts;
    try {
      ts = json['timestamp'] != null
          ? DateTime.parse(json['timestamp'].toString())
          : DateTime.now();
    } catch (_) {
      ts = DateTime.now();
    }

    final slot = (json['slotId'] ?? '').toString();
    var mall = (json['mallId'] ?? '').toString();
    if (mall.isEmpty && slot.contains('-')) {
      mall = slot.split('-').first;
    }

    return MyVehicleLocation(
      userId: (json['userId'] ?? 'user-001').toString(),
      vehicleId: (json['vehicleId'] ?? 'veh-default').toString(),
      slotId: slot,
      floorId: (json['floorId'] ?? 'P').toString(),
      floorName: (json['floorName'] ?? 'Basement Parking').toString(),
      location: GeodeticCoords(latitude: lat, longitude: lon, height: height),
      timestamp: ts,
      status: (json['status'] ?? 'parked').toString(),
      licensePlate: (json['licensePlate'] ?? 'WP CAB-8821').toString(),
      notes: json['notes']?.toString(),
      mallId: mall,
    );
  }
}

class ParkingService extends ChangeNotifier {
  static const String _vehicleStorageKeyPrefix = 'NexNav_my_vehicle_location_';

  static final ParkingService _instance = ParkingService._internal();
  factory ParkingService() => _instance;
  static ParkingService get instance => _instance;

  // Multi-mall slot store: normalized mallId -> (floorId -> List<ParkingSlot>)
  final Map<String, Map<String, List<ParkingSlot>>> _mallFloorSlots = {};
  final Map<String, List<ParkingSlot>> _floorSlots = {};
  final Set<String> _deletedSlotIds = {};
  final Set<String> _pendingCreationSlotIds = {};
  final Map<String, DateTime> _recentlyUpdatedSlots = {};
  final Map<String, ParkingSlotStatus> _optimisticStatuses = {};
  bool _isSyncing = false;
  String _activeMallId = '';

  ParkingSlot? findSlotById(String slotId) {
    final target = slotId.trim().toLowerCase();
    for (final map in [_floorSlots, ..._mallFloorSlots.values]) {
      for (final list in map.values) {
        for (final s in list) {
          if (isMatchingSlotId(s.id, target)) {
            return s;
          }
        }
      }
    }
    return null;
  }

  static String normalizeMallId(String id) {
    var clean = id.trim().toLowerCase();
    if (clean.startsWith('mall-')) {
      clean = clean.substring(5);
    }
    final stripped = clean.replaceAll(RegExp(r'^0+'), '');
    return stripped.isEmpty ? clean : stripped;
  }

  static String normalizeSlotId(String id) {
    var s = id.trim().toLowerCase();
    if (s.startsWith('parking-')) s = s.substring(8);
    if (s.startsWith('mall-')) s = s.substring(5);
    final parts = s
        .split(RegExp(r'[-_#]'))
        .map((p) => p.replaceFirst(RegExp(r'^0+'), ''))
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isNotEmpty ? parts.join('-') : s;
  }

  static bool isMatchingSlotId(String? idA, String? idB) {
    if (idA == null || idB == null) return false;
    var a = idA.trim().toLowerCase();
    var b = idB.trim().toLowerCase();
    if (a.isEmpty || b.isEmpty) return false;
    if (a.startsWith('parking-')) a = a.substring(8);
    if (b.startsWith('parking-')) b = b.substring(8);
    if (a == b) return true;

    final cleanA = a.startsWith('mall-') ? a.substring(5) : a;
    final cleanB = b.startsWith('mall-') ? b.substring(5) : b;
    if (cleanA == cleanB) return true;

    final normA = normalizeSlotId(cleanA);
    final normB = normalizeSlotId(cleanB);
    if (normA.isNotEmpty && normA == normB) return true;

    final alphaA = cleanA.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final alphaB = cleanB.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (alphaA.isNotEmpty && alphaA == alphaB) return true;

    final stripZeroA = alphaA.replaceFirst(RegExp(r'^0+'), '');
    final stripZeroB = alphaB.replaceFirst(RegExp(r'^0+'), '');
    if (stripZeroA.isNotEmpty && stripZeroA == stripZeroB) return true;

    return false;
  }

  void _syncLegacyFloorSlots(String normId) {
    if (_activeMallId.isEmpty || _activeMallId == normId) {
      _floorSlots.clear();
      final current = _mallFloorSlots[normId];
      if (current != null) {
        for (final entry in current.entries) {
          _floorSlots[entry.key] = List.from(entry.value);
        }
      }
    }
  }

  // Auth state tracking
  String _currentUserId = '';
  String _authToken = '';
  bool _isAuthenticated = false;

  // Per-user record repository store (simulating backend DB records: userId -> MyVehicleLocation)
  final Map<String, MyVehicleLocation> _userVehicleRecords = {};
  // All parked vehicles across all users in active venue: slotId -> MyVehicleLocation
  final Map<String, MyVehicleLocation> _allParkedVehicles = {};
  Timer? _sensorSimulationTimer;
  Timer? _liveSyncTimer;
  final StreamController<Map<String, List<ParkingSlot>>> _slotStreamController =
      StreamController<Map<String, List<ParkingSlot>>>.broadcast();

  bool _isLiveStreamActive = false;

  ParkingService._internal() {
    _loadVehicleFromStorage();
    _loadDeletedSlotIds();
  }

  Future<void> _loadDeletedSlotIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('NexNav_deleted_slot_ids');
      if (list != null) {
        _deletedSlotIds.addAll(list.map((e) => e.trim().toLowerCase()));
      }
    } catch (_) {}
  }

  String get currentUserId => _currentUserId;
  String get authToken => _authToken;
  bool get isAuthenticated => _isAuthenticated;
  MyVehicleLocation? get currentVehicleLocation =>
      fetchMyVehicleLocation(_currentUserId);
  bool get hasParkedVehicle => currentVehicleLocation != null;
  Map<String, MyVehicleLocation> get allParkedVehicles =>
      Map.unmodifiable(_allParkedVehicles);

  void clearAllParkedVehicles() {
    _allParkedVehicles.clear();
    _userVehicleRecords.clear();
    _slotStreamController.add(_floorSlots);
    notifyListeners();
  }

  MyVehicleLocation? getParkedVehicleForSlot(String slotId) {
    final target = slotId.trim().toLowerCase();
    for (final entry in _allParkedVehicles.entries) {
      if (isMatchingSlotId(entry.key, target) ||
          isMatchingSlotId(entry.value.slotId, target)) {
        return entry.value;
      }
    }
    for (final v in _userVehicleRecords.values) {
      if (v.status == 'parked' && isMatchingSlotId(v.slotId, target)) {
        return v;
      }
    }
    return null;
  }

  Stream<Map<String, List<ParkingSlot>>> get slotStream =>
      _slotStreamController.stream;
  bool get isLiveStreamActive => _isLiveStreamActive;

  /// Starts periodic background synchronization with backend server (1s for ultra-fast reaction)
  void startLiveSync({int intervalSeconds = 1}) {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      if (_activeMallId.isNotEmpty) {
        syncSlotsSilently(_activeMallId);
      }
    });
  }

  /// Stops periodic background sync
  void stopLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
  }

  /// Silent synchronization that fetches latest slots from backend without clearing on transient errors
  Future<void> syncSlotsSilently(String mallId) async {
    final cleanId = mallId.trim();
    if (cleanId.isEmpty || _isSyncing) return;
    _isSyncing = true;
    final normId = normalizeMallId(cleanId);

    try {
      final liveSlots = await ApiService.instance.fetchParkingSlots(cleanId);
      final remoteVehicles = await ApiService.instance.fetchAllParkedVehicles(
        cleanId,
      );
      _applyServerSlots(
        cleanId,
        normId,
        liveSlots,
        remoteVehicles: remoteVehicles,
      );
    } catch (e) {
      debugPrint('[ParkingService] Silent sync warning: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Authoritative filter to purge any legacy mock stalls from memory and cache.
  /// Never filters out legitimate user-created stalls like '1-P-A-01' or '1-P-A01'.
  static bool isLegacyMockSlot(String id) {
    final lower = id.trim().toLowerCase();
    return lower.startsWith('mock-') || lower.startsWith('dummy-');
  }

  /// Applies authoritative server slots to in-memory state and local cache
  void _applyServerSlots(
    String cleanId,
    String normId,
    List<ParkingSlot> liveSlots, {
    List<MyVehicleLocation> remoteVehicles = const [],
  }) {
    // 0. Update _allParkedVehicles with remoteVehicles & local records
    for (final v in remoteVehicles) {
      if (v.status == 'parked' && v.slotId.isNotEmpty) {
        final rawKey = v.slotId.trim().toLowerCase();
        final cleanKey = rawKey.replaceFirst(RegExp(r'^parking-'), '');
        final normKey = normalizeSlotId(cleanKey);
        _allParkedVehicles[rawKey] = v;
        _allParkedVehicles[cleanKey] = v;
        _allParkedVehicles[normKey] = v;
      } else {
        _allParkedVehicles.remove(v.slotId.trim().toLowerCase());
      }
    }
    for (final v in _userVehicleRecords.values) {
      if (v.status == 'parked' && v.slotId.isNotEmpty) {
        final rawKey = v.slotId.trim().toLowerCase();
        final cleanKey = rawKey.replaceFirst(RegExp(r'^parking-'), '');
        final normKey = normalizeSlotId(cleanKey);
        _allParkedVehicles[rawKey] = v;
        _allParkedVehicles[cleanKey] = v;
        _allParkedVehicles[normKey] = v;
      }
    }

    final newMap = <String, List<ParkingSlot>>{};
    final seenIds = <String>{};
    final seenPositions = <String>{};

    // 1. Authoritative server slots
    for (final slot in liveSlots) {
      if (isLegacyMockSlot(slot.id)) continue;
      final idLower = slot.id.trim().toLowerCase();
      if (_deletedSlotIds.contains(idLower)) continue;
      final cleanSlotId = idLower.replaceFirst(RegExp(r'^parking-'), '');
      final normSlotId = normalizeSlotId(cleanSlotId);

      final posKey =
          '${normalizeFloorId(slot.floorId)}#${slot.section.trim().toUpperCase()}#${slot.slotNumber}';
      if (seenIds.contains(idLower) || seenPositions.contains(posKey)) {
        continue;
      }
      seenIds.add(idLower);
      seenPositions.add(posKey);
      _pendingCreationSlotIds.remove(idLower);

      // Preserve recent optimistic status during grace period
      final optStatus =
          _optimisticStatuses[idLower] ??
          _optimisticStatuses[cleanSlotId] ??
          _optimisticStatuses[normSlotId];
      if (optStatus != null) {
        final lastUpdate =
            _recentlyUpdatedSlots[idLower] ??
            _recentlyUpdatedSlots[cleanSlotId];
        if (lastUpdate != null &&
            DateTime.now().difference(lastUpdate) <
                const Duration(seconds: 8)) {
          slot.status = optStatus;
        } else {
          _optimisticStatuses.remove(idLower);
        }
      }

      newMap.putIfAbsent(slot.floorId, () => []);
      newMap[slot.floorId]!.add(slot);
    }

    // 2. Preserve all locally existing/added stalls that were not deleted
    final localMap = _mallFloorSlots[normId] ?? _mallFloorSlots[cleanId] ?? {};
    for (final entry in localMap.entries) {
      for (final localSlot in entry.value) {
        if (isLegacyMockSlot(localSlot.id)) continue;
        final idLower = localSlot.id.trim().toLowerCase();
        if (_deletedSlotIds.contains(idLower)) continue;

        final posKey =
            '${normalizeFloorId(localSlot.floorId)}#${localSlot.section.trim().toUpperCase()}#${localSlot.slotNumber}';
        if (!seenIds.contains(idLower) && !seenPositions.contains(posKey)) {
          seenIds.add(idLower);
          seenPositions.add(posKey);
          newMap.putIfAbsent(localSlot.floorId, () => []);
          newMap[localSlot.floorId]!.add(localSlot);
        }
      }
    }

    // 3. Auto-lock stalls occupied by active parked vehicles (multi-user & remote sync)
    final allActiveVehicles = <MyVehicleLocation>{
      ...remoteVehicles.where(
        (v) => v.status == 'parked' && v.slotId.isNotEmpty,
      ),
      ..._allParkedVehicles.values.where(
        (v) => v.status == 'parked' && v.slotId.isNotEmpty,
      ),
      ..._userVehicleRecords.values.where(
        (v) => v.status == 'parked' && v.slotId.isNotEmpty,
      ),
    }.toList();

    for (final v in allActiveVehicles) {
      final vSlotNorm = v.slotId.trim().toLowerCase();
      final vSlotClean = vSlotNorm.replaceFirst(RegExp(r'^parking-'), '');
      final vSlotStripped = normalizeSlotId(vSlotClean);

      // Do NOT relock if slot was freed by unparking
      if (_optimisticStatuses[vSlotNorm] == ParkingSlotStatus.free ||
          _optimisticStatuses[vSlotClean] == ParkingSlotStatus.free ||
          _optimisticStatuses[vSlotStripped] == ParkingSlotStatus.free) {
        continue;
      }

      if (_recentlyUpdatedSlots.containsKey(vSlotNorm) ||
          _recentlyUpdatedSlots.containsKey(vSlotClean)) {
        final lastUpdate =
            _recentlyUpdatedSlots[vSlotNorm] ??
            _recentlyUpdatedSlots[vSlotClean]!;
        if (DateTime.now().difference(lastUpdate) <
            const Duration(seconds: 8)) {
          continue; // Grace period: do not relock a recently freed slot!
        }
      }
      for (final list in newMap.values) {
        for (final s in list) {
          if (isMatchingSlotId(s.id, v.slotId)) {
            final sNorm = s.id.trim().toLowerCase();
            final sClean = sNorm.replaceFirst(RegExp(r'^parking-'), '');
            if (_optimisticStatuses[sNorm] != ParkingSlotStatus.free &&
                _optimisticStatuses[sClean] != ParkingSlotStatus.free) {
              s.status = ParkingSlotStatus.occupied;
            }
          }
        }
      }
    }

    _mallFloorSlots[normId] = newMap;
    _mallFloorSlots[cleanId] = newMap;
    _syncLegacyFloorSlots(normId);

    _slotStreamController.add(_floorSlots);
    notifyListeners();

    final all = newMap.values.expand((s) => s).toList();
    final encoded = jsonEncode(all.map((s) => s.toJson()).toList());
    unawaited(
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('cache_parking_slots_$cleanId', encoded);
        prefs.setString('cache_parking_slots_$normId', encoded);
      }),
    );
  }

  /// 1. Authenticate user session & switch active user context
  void authenticateUser({required String userId, required String token}) {
    _currentUserId = userId;
    _authToken = token;
    _isAuthenticated = true;
    _loadVehicleFromStorage();
    notifyListeners();
  }

  /// 2. User-Scoped Vehicle Data API (GET /parking/my-vehicle?userId={userId})
  MyVehicleLocation? fetchMyVehicleLocation(String userId) {
    final effectiveId = userId.isNotEmpty ? userId : _currentUserId;
    if (effectiveId.isNotEmpty) {
      final record = _userVehicleRecords[effectiveId];
      if (record != null && record.status == 'parked') {
        return record;
      }
    }

    if (_currentUserId.isNotEmpty) {
      final curRecord = _userVehicleRecords[_currentUserId];
      if (curRecord != null && curRecord.status == 'parked') {
        return curRecord;
      }
    }

    for (final rec in _userVehicleRecords.values) {
      if (rec.status == 'parked') {
        return rec;
      }
    }
    return null;
  }

  /// 3. Shared Occupancy Status API Endpoint (fetchFloorSlotStatus)
  /// Returns shared slot availability (free/occupied/reserved) without user identities.
  List<ParkingSlot> fetchFloorSlotStatus(String floorId, [String? mallId]) {
    return fetchFloorMap(floorId, mallId);
  }

  /// 4. Private Vehicle Marker helper (renderMyVehicleMarker)
  /// Returns true ONLY if the slot contains the logged-in user's active parked vehicle.
  bool renderMyVehicleMarker(String slotId, String floorId) {
    if (!_isAuthenticated) return false;
    final myVehicle = fetchMyVehicleLocation(_currentUserId);
    if (myVehicle == null) return false;
    return isMatchingSlotId(myVehicle.slotId, slotId) &&
        isMatchingFloor(myVehicle.floorId, floorId) &&
        myVehicle.status == 'parked';
  }

  Map<String, List<ParkingSlot>> get allFloorSlots {
    if (_activeMallId.isNotEmpty) {
      final norm = normalizeMallId(_activeMallId);
      if (_mallFloorSlots.containsKey(norm)) {
        return _mallFloorSlots[norm]!;
      }
    }
    if (_mallFloorSlots.isNotEmpty) {
      return _mallFloorSlots.values.first;
    }
    return _floorSlots;
  }

  Map<String, List<ParkingSlot>> getFloorSlotsForMall(String? mallId) {
    Map<String, List<ParkingSlot>> rawMap = allFloorSlots;
    if (mallId != null && mallId.trim().isNotEmpty) {
      final clean = mallId.trim().toLowerCase();
      final norm = normalizeMallId(clean);
      if (_mallFloorSlots.containsKey(norm)) {
        rawMap = _mallFloorSlots[norm]!;
      } else if (_mallFloorSlots.containsKey(clean)) {
        rawMap = _mallFloorSlots[clean]!;
      } else {
        for (final entry in _mallFloorSlots.entries) {
          if (normalizeMallId(entry.key) == norm) {
            rawMap = entry.value;
            break;
          }
        }
      }
    }

    final cleanResult = <String, List<ParkingSlot>>{};
    for (final entry in rawMap.entries) {
      cleanResult[entry.key] = deduplicateSlots(entry.value);
    }
    return cleanResult;
  }

  /// Load parking bay layouts anchored at a specific Mall Map package.
  /// Uses real backend slots and cached local slots, eliminating hardcoded dummy data.
  Future<void> loadLayoutForMallMetadata({
    required String mallId,
    required double baseLat,
    required double baseLon,
    int basementFloors = 0,
  }) async {
    await loadSlotsForMall(mallId);
  }

  /// Safe no-op to ensure valid user-created stalls are never destructively pruned
  Future<void> pruneSlotsToValidFloors(
    String mallId,
    List<String> validFloors,
  ) async {
    return;
  }

  /// Completely clears all slots for a mall venue
  Future<void> clearAllSlotsForMall(String mallId) async {
    final cleanId = mallId.trim();
    if (cleanId.isEmpty) return;
    final normId = normalizeMallId(cleanId);

    final allSlots =
        _mallFloorSlots[normId]?.values.expand((s) => s).toList() ??
        _mallFloorSlots[cleanId]?.values.expand((s) => s).toList() ??
        _floorSlots.values.expand((s) => s).toList();

    // OCCUPIED VEHICLE PROTECTION: Only delete stalls that are NOT occupied by vehicles!
    final slotsToDelete = allSlots.where((s) {
      final isOccupied =
          s.status == ParkingSlotStatus.occupied ||
          getParkedVehicleForSlot(s.id) != null;
      return !isOccupied;
    }).toList();

    for (final s in slotsToDelete) {
      _deletedSlotIds.add(s.id.trim().toLowerCase());
      unawaited(ApiService.instance.deleteParkingSlot(s.id, mallId: cleanId));
    }

    // Remove deleted slots from memory while preserving any occupied slots
    if (_mallFloorSlots.containsKey(normId)) {
      for (final list in _mallFloorSlots[normId]!.values) {
        list.removeWhere(
          (s) => slotsToDelete.any((d) => isMatchingSlotId(d.id, s.id)),
        );
      }
      _mallFloorSlots[normId]!.removeWhere((key, value) => value.isEmpty);
    }
    if (_mallFloorSlots.containsKey(cleanId)) {
      for (final list in _mallFloorSlots[cleanId]!.values) {
        list.removeWhere(
          (s) => slotsToDelete.any((d) => isMatchingSlotId(d.id, s.id)),
        );
      }
      _mallFloorSlots[cleanId]!.removeWhere((key, value) => value.isEmpty);
    }
    for (final list in _floorSlots.values) {
      list.removeWhere(
        (s) => slotsToDelete.any((d) => isMatchingSlotId(d.id, s.id)),
      );
    }
    _floorSlots.removeWhere((key, value) => value.isEmpty);

    _slotStreamController.add(_floorSlots);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final remaining =
        (_mallFloorSlots[normId]?.values.expand((s) => s).toList()) ??
        _floorSlots.values.expand((s) => s).toList();
    final encoded = jsonEncode(remaining.map((s) => s.toJson()).toList());
    await prefs.setString('cache_parking_slots_$cleanId', encoded);
    await prefs.setString('cache_parking_slots_$normId', encoded);
    await prefs.setStringList(
      'NexNav_deleted_slot_ids',
      _deletedSlotIds.toList(),
    );

    ApiService.instance.notifyDataSynced('parking');
    ApiService.instance.notifyDataSynced('destinations');
  }

  /// Reset all slots across all floors for active mall map to FREE status immediately
  Future<void> resetAllSlotsToFree(String mallId) async {
    final cleanId = mallId.trim();
    if (cleanId.isEmpty) return;
    final normId = normalizeMallId(cleanId);

    final targetMap = _mallFloorSlots[normId] ?? _floorSlots;
    for (final slots in targetMap.values) {
      for (final slot in slots) {
        slot.status = ParkingSlotStatus.free;
      }
    }
    _userVehicleRecords.clear();
    _allParkedVehicles.clear();

    // Broadcast immediately so UI responds in 0ms
    _slotStreamController.add(_floorSlots);
    notifyListeners();

    // Sync status and clear vehicle pins on backend in background
    ApiService.instance.resetAllSlotsToFree(cleanId);
    ApiService.instance.clearAllVehicles(cleanId);

    for (final slots in targetMap.values) {
      for (final slot in slots) {
        ApiService.instance.updateParkingSlotStatus(
          slot.id,
          'free',
          mallId: cleanId,
        );
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final all = targetMap.values.expand((s) => s).toList();
    final encoded = jsonEncode(all.map((s) => s.toJson()).toList());
    await prefs.setString('cache_parking_slots_$cleanId', encoded);
    await prefs.setString('cache_parking_slots_$normId', encoded);
    ApiService.instance.notifyDataSynced('parking');
  }

  /// Clears all user vehicle pins on the current mall venue
  Future<void> clearAllUserPins(String mallId) async {
    final cleanId = mallId.trim();
    final normId = normalizeMallId(cleanId);
    _allParkedVehicles.clear();
    _userVehicleRecords.clear();

    final targetMap = _mallFloorSlots[normId] ?? _floorSlots;
    for (final slots in targetMap.values) {
      for (final slot in slots) {
        if (slot.status == ParkingSlotStatus.occupied) {
          slot.status = ParkingSlotStatus.free;
          unawaited(
            ApiService.instance.updateParkingSlotStatus(
              slot.id,
              'free',
              mallId: cleanId,
            ),
          );
        }
      }
    }

    _slotStreamController.add(_floorSlots);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final vKeys = prefs.getKeys().where(
      (k) => k.startsWith(_vehicleStorageKeyPrefix),
    );
    for (final k in vKeys) {
      await prefs.remove(k);
    }

    await ApiService.instance.clearAllVehicles(cleanId);
    ApiService.instance.notifyDataSynced('parking');
  }

  /// Clear in-memory loaded parking slots
  void clearLoadedSlots([String? mallId]) {
    if (mallId != null && mallId.trim().isNotEmpty) {
      final norm = normalizeMallId(mallId);
      _mallFloorSlots.remove(norm);
      if (_activeMallId == norm) {
        _floorSlots.clear();
      }
    } else {
      _floorSlots.clear();
    }
    _slotStreamController.add(_floorSlots);
    notifyListeners();
  }

  /// Load parking slots dynamically from backend API for a given venue
  Future<void> loadSlotsForMall(String mallId) async {
    final cleanId = mallId.trim();
    if (cleanId.isEmpty) return;
    final normId = normalizeMallId(cleanId);
    _activeMallId = normId;

    // Ensure live background sync is active whenever venue slots are loaded (1s polling)
    startLiveSync(intervalSeconds: 1);

    try {
      final prefs = await SharedPreferences.getInstance();

      // First, restore all valid non-deleted slots from local cache
      _mallFloorSlots.putIfAbsent(normId, () => {});
      final cached =
          prefs.getString('cache_parking_slots_$cleanId') ??
          prefs.getString('cache_parking_slots_$normId');
      if (cached != null) {
        try {
          final List list = jsonDecode(cached);
          final seenKeys = <String>{};
          for (final item in list) {
            final slot = ParkingSlot.fromJson(item);
            if (isLegacyMockSlot(slot.id)) continue;
            final idLower = slot.id.trim().toLowerCase();
            if (_deletedSlotIds.contains(idLower)) continue;
            final key =
                '$idLower#${normalizeFloorId(slot.floorId)}#${slot.section.trim().toUpperCase()}#${slot.slotNumber}';
            if (seenKeys.contains(key)) continue;
            seenKeys.add(key);
            _mallFloorSlots[normId]!.putIfAbsent(slot.floorId, () => []);
            final existingList = _mallFloorSlots[normId]![slot.floorId]!;
            final alreadyPresent = existingList.any(
              (s) =>
                  s.id.trim().toLowerCase() == idLower ||
                  (normalizeFloorId(s.floorId) ==
                          normalizeFloorId(slot.floorId) &&
                      s.section.trim().toUpperCase() ==
                          slot.section.trim().toUpperCase() &&
                      s.slotNumber == slot.slotNumber),
            );
            if (!alreadyPresent) {
              existingList.add(slot);
            }
          }
        } catch (_) {}
      }
      _mallFloorSlots[cleanId] = _mallFloorSlots[normId]!;

      List<ParkingSlot> liveSlots = [];
      bool serverContacted = false;
      try {
        liveSlots = await ApiService.instance.fetchParkingSlots(cleanId);
        serverContacted = true;
        if (liveSlots.isEmpty && cleanId != normId) {
          final altSlots = await ApiService.instance.fetchParkingSlots(normId);
          if (altSlots.isNotEmpty) {
            liveSlots = altSlots;
          }
        }
      } catch (e) {
        debugPrint('[ParkingService] Error fetching parking slots: $e');
      }

      if (serverContacted) {
        final remoteVehicles = await ApiService.instance.fetchAllParkedVehicles(
          cleanId,
        );
        _applyServerSlots(
          cleanId,
          normId,
          liveSlots,
          remoteVehicles: remoteVehicles,
        );

        final all = _mallFloorSlots[normId]!.values.expand((s) => s).toList();
        final encoded = jsonEncode(all.map((s) => s.toJson()).toList());
        await prefs.setString('cache_parking_slots_$cleanId', encoded);
        await prefs.setString('cache_parking_slots_$normId', encoded);
      } else {
        // Backend returned error or is offline: keep existing cached slots
        _mallFloorSlots[cleanId] = _mallFloorSlots[normId] ?? {};
        _syncLegacyFloorSlots(normId);
        _slotStreamController.add(_floorSlots);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading parking slots for $cleanId: $e');
    }
  }

  /// Adds a single parking stall
  Future<bool> addParkingSlot(String mallId, ParkingSlot slot) async {
    final cleanId = mallId.trim();
    final normId = normalizeMallId(cleanId);
    _activeMallId = normId;

    final resolvedSlot = slot.mallId.isEmpty
        ? ParkingSlot(
            id: slot.id,
            mallId: cleanId,
            floorId: slot.floorId,
            section: slot.section,
            slotNumber: slot.slotNumber,
            status: slot.status,
            location: slot.location,
            gridRow: slot.gridRow,
            gridCol: slot.gridCol,
            isEVCharging: slot.isEVCharging,
            isHandicapAccessible: slot.isHandicapAccessible,
            sensorId: slot.sensorId,
          )
        : slot;

    _deletedSlotIds.remove(resolvedSlot.id.trim().toLowerCase());
    _pendingCreationSlotIds.add(resolvedSlot.id.trim().toLowerCase());

    if (!_mallFloorSlots.containsKey(normId)) {
      _mallFloorSlots[normId] = {};
    }
    if (!_mallFloorSlots[normId]!.containsKey(resolvedSlot.floorId)) {
      _mallFloorSlots[normId]![resolvedSlot.floorId] = [];
    }

    _mallFloorSlots[normId]![resolvedSlot.floorId]!.removeWhere(
      (s) =>
          s.id.trim().toLowerCase() == resolvedSlot.id.trim().toLowerCase() ||
          (normalizeFloorId(s.floorId) ==
                  normalizeFloorId(resolvedSlot.floorId) &&
              s.section.trim().toUpperCase() ==
                  resolvedSlot.section.trim().toUpperCase() &&
              s.slotNumber == resolvedSlot.slotNumber),
    );
    _mallFloorSlots[normId]![resolvedSlot.floorId]!.add(resolvedSlot);
    _mallFloorSlots[cleanId] = _mallFloorSlots[normId]!;
    _syncLegacyFloorSlots(normId);

    // Notify listeners immediately (0ms) so screen reflects creation without delay
    _slotStreamController.add(_floorSlots);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'NexNav_deleted_slot_ids',
      _deletedSlotIds.toList(),
    );
    final all = _mallFloorSlots[normId]!.values.expand((s) => s).toList();
    final encoded = jsonEncode(all.map((s) => s.toJson()).toList());
    await prefs.setString('cache_parking_slots_$cleanId', encoded);
    await prefs.setString('cache_parking_slots_$normId', encoded);

    // Persist to remote backend in background
    final ok = await ApiService.instance.createParkingSlot(
      cleanId,
      resolvedSlot,
    );
    ApiService.instance.notifyDataSynced('parking');
    return ok;
  }

  /// Adds a batch/panel of parking stalls (e.g. Row of 10 or 20 bays)
  Future<bool> addParkingPanel(
    String mallId, {
    required String floorId,
    required String section,
    required int startNumber,
    required int count,
    required double baseLat,
    required double baseLon,
    required double height,
    bool isEV = false,
    bool isHandicap = false,
  }) async {
    final cleanId = mallId.trim();
    final normId = normalizeMallId(cleanId);
    _activeMallId = normId;

    final List<ParkingSlot> newSlots = [];
    for (int i = 0; i < count; i++) {
      final num = startNumber + i;
      final numStr = num < 10 ? '0$num' : '$num';
      final slotId = '$cleanId-$floorId-$section-$numStr';
      final r = i ~/ 4;
      final c = i % 4;
      final newSlot = ParkingSlot(
        id: slotId,
        mallId: cleanId,
        floorId: floorId,
        section: section,
        slotNumber: num,
        status: ParkingSlotStatus.free,
        location: GeodeticCoords(
          latitude: baseLat + (r * 0.00004),
          longitude: baseLon + (c * 0.00004),
          height: height,
        ),
        gridRow: r,
        gridCol: c,
        isEVCharging: false,
        isHandicapAccessible: isHandicap,
        sensorId: 'SNS-$cleanId-$floorId-$section$numStr',
      );
      _deletedSlotIds.remove(slotId.trim().toLowerCase());
      _pendingCreationSlotIds.add(slotId.trim().toLowerCase());
      newSlots.add(newSlot);
    }

    if (!_mallFloorSlots.containsKey(normId)) {
      _mallFloorSlots[normId] = {};
    }
    if (!_mallFloorSlots[normId]!.containsKey(floorId)) {
      _mallFloorSlots[normId]![floorId] = [];
    }

    for (final s in newSlots) {
      _mallFloorSlots[normId]![floorId]!.removeWhere(
        (x) =>
            x.id.trim().toLowerCase() == s.id.trim().toLowerCase() ||
            (normalizeFloorId(x.floorId) == normalizeFloorId(s.floorId) &&
                x.section.trim().toUpperCase() ==
                    s.section.trim().toUpperCase() &&
                x.slotNumber == s.slotNumber),
      );
      _mallFloorSlots[normId]![floorId]!.add(s);
    }
    _mallFloorSlots[cleanId] = _mallFloorSlots[normId]!;
    _syncLegacyFloorSlots(normId);

    // Notify listeners immediately (0ms)
    _slotStreamController.add(_floorSlots);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final all = _mallFloorSlots[normId]!.values.expand((s) => s).toList();
    final encoded = jsonEncode(all.map((s) => s.toJson()).toList());
    await prefs.setString('cache_parking_slots_$cleanId', encoded);
    await prefs.setString('cache_parking_slots_$normId', encoded);

    final ok = await ApiService.instance.createParkingSlotsBulk(
      cleanId,
      newSlots,
    );
    ApiService.instance.notifyDataSynced('parking');
    return ok;
  }

  /// Deletes a parking slot
  Future<bool> deleteParkingSlot(String mallId, String slotId) async {
    final cleanId = mallId.trim();
    final normId = normalizeMallId(cleanId);
    final targetId = slotId.trim().toLowerCase();

    // 0. OCCUPIED VEHICLE PROTECTION: Reject deletion if slot is occupied or has a parked vehicle!
    final existingSlot = findSlotById(slotId);
    final parkedVehicle = getParkedVehicleForSlot(slotId);
    if ((existingSlot != null &&
            existingSlot.status == ParkingSlotStatus.occupied) ||
        parkedVehicle != null) {
      debugPrint(
        '[ParkingService] REJECTED deleteParkingSlot: Slot $slotId is currently occupied by a parked vehicle!',
      );
      return false;
    }

    _deletedSlotIds.add(targetId);
    _pendingCreationSlotIds.remove(targetId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'NexNav_deleted_slot_ids',
      _deletedSlotIds.toList(),
    );

    if (_mallFloorSlots.containsKey(normId)) {
      for (final list in _mallFloorSlots[normId]!.values) {
        list.removeWhere((s) => isMatchingSlotId(s.id, targetId));
      }
      _mallFloorSlots[normId]!.removeWhere((key, value) => value.isEmpty);
    }
    if (_mallFloorSlots.containsKey(cleanId)) {
      for (final list in _mallFloorSlots[cleanId]!.values) {
        list.removeWhere((s) => isMatchingSlotId(s.id, targetId));
      }
      _mallFloorSlots[cleanId]!.removeWhere((key, value) => value.isEmpty);
    }
    for (final list in _floorSlots.values) {
      list.removeWhere((s) => isMatchingSlotId(s.id, targetId));
    }
    _floorSlots.removeWhere((key, value) => value.isEmpty);

    // Notify listeners immediately (0ms)
    _slotStreamController.add(_floorSlots);
    notifyListeners();

    final all =
        (_mallFloorSlots[normId]?.values.expand((s) => s).toList()) ??
        _floorSlots.values.expand((s) => s).toList();
    final encoded = jsonEncode(all.map((s) => s.toJson()).toList());
    await prefs.setString('cache_parking_slots_$cleanId', encoded);
    await prefs.setString('cache_parking_slots_$normId', encoded);

    final ok = await ApiService.instance.deleteParkingSlot(
      slotId,
      mallId: cleanId,
    );
    ApiService.instance.notifyDataSynced('parking');
    syncSlotsSilently(cleanId);
    return ok;
  }

  /// Toggles or updates slot occupancy status
  Future<void> updateSlotStatus(
    String mallId,
    String slotId,
    ParkingSlotStatus newStatus,
  ) async {
    final cleanId = mallId.trim();
    final normId = normalizeMallId(cleanId);
    final targetId = slotId.trim().toLowerCase();

    final cleanSlot = slotId
        .trim()
        .replaceFirst(RegExp(r'^parking-'), '')
        .toLowerCase();
    final normSlot = normalizeSlotId(cleanSlot);

    final now = DateTime.now();
    _recentlyUpdatedSlots[targetId] = now;
    _recentlyUpdatedSlots[cleanSlot] = now;
    _recentlyUpdatedSlots[normSlot] = now;

    // Immediately cache optimistic status so background sync never reverts recent admin actions
    _optimisticStatuses[targetId] = newStatus;
    _optimisticStatuses[cleanSlot] = newStatus;
    _optimisticStatuses[normSlot] = newStatus;

    for (final map in [_floorSlots, ..._mallFloorSlots.values]) {
      for (final list in map.values) {
        for (final s in list) {
          if (isMatchingSlotId(s.id, targetId)) {
            s.status = newStatus;
          }
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();

    String? matchedUserId;
    // If marked free, purge any stored vehicle record for this slot so it doesn't auto-relock
    if (newStatus == ParkingSlotStatus.free) {
      for (final rec in _userVehicleRecords.values) {
        if (isMatchingSlotId(rec.slotId, targetId)) {
          matchedUserId = rec.userId;
          break;
        }
      }
      if (matchedUserId == null) {
        for (final v in _allParkedVehicles.values) {
          if (isMatchingSlotId(v.slotId, targetId)) {
            matchedUserId = v.userId;
            break;
          }
        }
      }

      _userVehicleRecords.removeWhere(
        (uId, rec) => isMatchingSlotId(rec.slotId, targetId),
      );
      _allParkedVehicles.removeWhere(
        (sId, rec) => isMatchingSlotId(sId, targetId),
      );
    }

    // Broadcast immediately so UI updates in 0ms!
    _slotStreamController.add(_floorSlots);
    notifyListeners();

    if (newStatus == ParkingSlotStatus.free) {
      final vKeys = prefs.getKeys().where(
        (k) => k.startsWith(_vehicleStorageKeyPrefix),
      );
      for (final k in vKeys) {
        final val = prefs.getString(k);
        if (val != null &&
            (val.toLowerCase().contains(targetId) ||
                isMatchingSlotId(val, targetId))) {
          await prefs.remove(k);
        }
      }
      if (matchedUserId != null && matchedUserId.isNotEmpty) {
        await ApiService.instance.deleteVehicleLocation(cleanId, matchedUserId);
      }
      await ApiService.instance.deleteVehicleLocation(cleanId, targetId);
    }

    final all =
        (_mallFloorSlots[normId]?.values.expand((s) => s).toList()) ??
        _floorSlots.values.expand((s) => s).toList();
    final encoded = jsonEncode(all.map((s) => s.toJson()).toList());
    await prefs.setString('cache_parking_slots_$cleanId', encoded);
    await prefs.setString('cache_parking_slots_$normId', encoded);

    await ApiService.instance.updateParkingSlotStatus(
      slotId,
      newStatus.name,
      mallId: cleanId,
    );
    ApiService.instance.notifyDataSynced('parking');
    syncSlotsSilently(cleanId);
  }

  /// Identifies if a destination POI is actually a parking stall and not a retail store
  static bool isParkingDestination(dynamic poi) {
    if (poi == null) return false;
    final cat = (poi.category ?? '').toString().trim().toUpperCase();
    final id = (poi.id ?? '').toString().trim().toLowerCase();
    final name = (poi.name ?? '').toString().trim().toUpperCase();
    final desc = (poi.description ?? '').toString();

    if (cat == 'PARKING' || cat == 'PARKING_SLOT' || cat == 'PARKING_BAY') {
      return true;
    }
    if (id.startsWith('parking-') || id.startsWith('slot-')) {
      return true;
    }
    if (desc.contains('PARKING_META|')) {
      return true;
    }
    if (RegExp(r'^[0-9]+-[A-Z0-9]+-[A-Z]-[0-9]+$').hasMatch(poi.id ?? '')) {
      return true;
    }
    if (name.startsWith('PARKING BAY') ||
        name.startsWith('PARKING STALL') ||
        name.startsWith('PARKING SLOT') ||
        name.contains('MY PARKED CAR')) {
      return true;
    }
    return false;
  }

  /// Normalizes floor identifiers across all formats (P, B1, B2, GF, F1, F2, etc.)
  static String normalizeFloorId(String floor) {
    final s = floor.trim().toUpperCase();
    if (s.isEmpty) return 'P';

    // Dedicated Parking Floor / Deck
    if (s == 'P' ||
        s == 'P1' ||
        s == 'PARKING' ||
        s == 'PARKING FLOOR' ||
        s == 'PARKING DECK') {
      return 'P';
    }

    // Basement 1 / Floor -1 / Parking B1
    if (s == 'B1' ||
        s == 'F-1' ||
        s == '-1' ||
        s == 'PARKING B1' ||
        s == 'BASEMENT 1' ||
        s == 'BASEMENT B1' ||
        s.contains('BASEMENT 1') ||
        s.contains('BASEMENT B1')) {
      return 'B1';
    }

    // Basement 2 / Floor -2
    if (s == 'B2' ||
        s == 'F-2' ||
        s == '-2' ||
        s == 'P2' ||
        s == 'PARKING B2' ||
        s == 'BASEMENT 2' ||
        s == 'BASEMENT B2' ||
        s.contains('BASEMENT 2') ||
        s.contains('BASEMENT B2')) {
      return 'B2';
    }

    // Basement 3 / Floor -3
    if (s == 'B3' ||
        s == 'F-3' ||
        s == '-3' ||
        s == 'P3' ||
        s == 'PARKING B3' ||
        s == 'BASEMENT 3' ||
        s == 'BASEMENT B3' ||
        s.contains('BASEMENT 3') ||
        s.contains('BASEMENT B3')) {
      return 'B3';
    }

    // Ground Floor
    if (s == 'GF' ||
        s == 'G' ||
        s == '0' ||
        s == 'F0' ||
        s == 'GROUND' ||
        s.contains('GROUND')) {
      return 'GF';
    }

    if (s.startsWith('FLOOR ')) return 'F${s.substring(6).trim()}';
    if (s.startsWith('LEVEL ')) return 'F${s.substring(6).trim()}';
    if (RegExp(r'^[0-9]+$').hasMatch(s)) return 'F$s';

    return s;
  }

  static bool isMatchingFloor(String floorA, String floorB) {
    if (floorA.trim().toUpperCase() == floorB.trim().toUpperCase()) return true;
    final normA = normalizeFloorId(floorA);
    final normB = normalizeFloorId(floorB);
    if (normA == normB) return true;
    final isPA = normA == 'P' || normA == 'B1';
    final isPB = normB == 'P' || normB == 'B1';
    if (isPA && isPB) return true;
    return false;
  }

  /// Deduplicates a list of parking slots by ID and by physical coordinate (floor + section + slotNumber)
  List<ParkingSlot> deduplicateSlots(List<ParkingSlot> slots) {
    // Sort so occupied and reserved slots take precedence over free slots
    final sorted = List<ParkingSlot>.from(slots);
    sorted.sort((a, b) {
      int score(ParkingSlot s) {
        if (s.status == ParkingSlotStatus.occupied) return 0;
        if (s.status == ParkingSlotStatus.reserved) return 1;
        return 2;
      }

      return score(a).compareTo(score(b));
    });

    final seenIds = <String>{};
    final seenPositions = <String>{};
    final result = <ParkingSlot>[];
    for (final s in sorted) {
      if (isLegacyMockSlot(s.id)) continue;
      final cleanId = s.id.trim().toLowerCase();
      final posKey =
          '${normalizeFloorId(s.floorId)}#${s.section.trim().toUpperCase()}#${s.slotNumber}';
      if (!seenIds.contains(cleanId) && !seenPositions.contains(posKey)) {
        seenIds.add(cleanId);
        seenPositions.add(posKey);
        // Authoritatively link with any parked vehicle
        if (getParkedVehicleForSlot(s.id) != null) {
          s.status = ParkingSlotStatus.occupied;
        }
        result.add(s);
      }
    }
    return result;
  }

  /// REST / Local API endpoint: fetchFloorMap(floorId, [mallId])
  List<ParkingSlot> fetchFloorMap(String floorId, [String? mallId]) {
    final Map<String, List<ParkingSlot>> slotsSource = getFloorSlotsForMall(
      mallId,
    );

    // 1. Direct exact key match if non-empty
    if (slotsSource.containsKey(floorId) && slotsSource[floorId]!.isNotEmpty) {
      return deduplicateSlots(slotsSource[floorId]!);
    }

    final targetNorm = normalizeFloorId(floorId);

    // 2. Direct key match with normalized floor comparison if non-empty
    for (final entry in slotsSource.entries) {
      if (isMatchingFloor(entry.key, floorId) && entry.value.isNotEmpty) {
        return deduplicateSlots(entry.value);
      }
    }

    // 3. Match any slots whose own floorId property matches target
    final matchedSlots = slotsSource.values
        .expand((list) => list)
        .where((s) => isMatchingFloor(s.floorId, floorId))
        .toList();

    if (matchedSlots.isNotEmpty) {
      return deduplicateSlots(matchedSlots);
    }

    // 4. Fallback: if target floor is a parking floor and slots exist, return them
    if (targetNorm == 'P' ||
        targetNorm == 'B1' ||
        targetNorm == 'B2' ||
        targetNorm == 'B3') {
      final allParkSlots = slotsSource.values.expand((list) => list).where((s) {
        final sn = normalizeFloorId(s.floorId);
        return sn == 'P' || sn == 'B1' || sn == 'B2' || sn == 'B3';
      }).toList();
      if (allParkSlots.isNotEmpty) {
        return deduplicateSlots(allParkSlots);
      }
    }

    return deduplicateSlots(slotsSource[floorId] ?? []);
  }

  /// REST / Local API endpoint: getSlotAvailability(floorId, [mallId])
  Map<String, dynamic> getSlotAvailability(String floorId, [String? mallId]) {
    final slots = fetchFloorMap(floorId, mallId);
    final total = slots.length;
    final free = slots.where((s) => s.status == ParkingSlotStatus.free).length;
    final occupied = slots
        .where((s) => s.status == ParkingSlotStatus.occupied)
        .length;
    final reserved = slots
        .where((s) => s.status == ParkingSlotStatus.reserved)
        .length;

    return {
      'floorId': floorId,
      'totalSlots': total,
      'freeSlots': free,
      'occupiedSlots': occupied,
      'reservedSlots': reserved,
      'occupancyRate': total > 0 ? (occupied / total * 100).round() : 0,
      'slots': slots.map((s) => s.toJson()).toList(),
    };
  }

  /// Toggle Live WebSocket / MQTT Stream simulation
  void toggleLiveStream(bool active) {
    _isLiveStreamActive = active;
    if (active) {
      _startLiveIoTSensorStream();
    } else {
      _sensorSimulationTimer?.cancel();
    }
    notifyListeners();
  }

  /// Live IoT / CV Occupancy Sensor Simulation (WebSocket push simulation)
  void _startLiveIoTSensorStream() {
    _sensorSimulationTimer?.cancel();
    _sensorSimulationTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_isLiveStreamActive) return;

      final random = Random();
      final floors = _floorSlots.keys.toList();
      if (floors.isEmpty) return;
      final targetFloor = floors[random.nextInt(floors.length)];
      final slots = _floorSlots[targetFloor];

      if (slots != null && slots.isNotEmpty) {
        final index = random.nextInt(slots.length);
        final slot = slots[index];

        // Do not flip slot status automatically if any authenticated user has parked there
        final isParkedByUser = _userVehicleRecords.values.any(
          (rec) => rec.status == 'parked' && rec.slotId == slot.id,
        );
        if (isParkedByUser) {
          return;
        }

        if (slot.status == ParkingSlotStatus.free) {
          slot.status = ParkingSlotStatus.occupied;
        } else if (slot.status == ParkingSlotStatus.occupied) {
          slot.status = ParkingSlotStatus.free;
        }

        _slotStreamController.add(_floorSlots);
        notifyListeners();
      }
    });
  }

  /// 5. Save vehicle location (saveVehicleLocation)
  /// Tags vehicle to user + slot with status "parked"
  Future<void> saveVehicleLocation(
    MyVehicleLocation vehicleRecord, {
    String? mallId,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final resolvedMallId = (mallId != null && mallId.isNotEmpty)
        ? mallId
        : (vehicleRecord.mallId.isNotEmpty
              ? vehicleRecord.mallId
              : (vehicleRecord.slotId.contains('-')
                    ? vehicleRecord.slotId.split('-').first
                    : (prefs.getString('NexNav_active_mall_id') ?? '1')));
    final normResolvedId = normalizeMallId(resolvedMallId);

    // 1. Ensure user session is bound to current active user
    final effectiveUserId = vehicleRecord.userId.isNotEmpty
        ? vehicleRecord.userId
        : (_currentUserId.isNotEmpty
              ? _currentUserId
              : (prefs.getString('NexNav_remembered_email') ?? 'user-default'));
    _currentUserId = effectiveUserId;
    _isAuthenticated = true;

    final targetSlotId = vehicleRecord.slotId.trim().toLowerCase();
    final cleanSlot = vehicleRecord.slotId
        .trim()
        .replaceFirst(RegExp(r'^parking-'), '')
        .toLowerCase();
    final existingParked = fetchMyVehicleLocation(_currentUserId);
    final previousSlotId = existingParked?.slotId.trim().toLowerCase();

    _recentlyUpdatedSlots[targetSlotId] = DateTime.now();
    _recentlyUpdatedSlots[cleanSlot] = DateTime.now();
    _optimisticStatuses[targetSlotId] = ParkingSlotStatus.occupied;
    _optimisticStatuses[cleanSlot] = ParkingSlotStatus.occupied;
    final normSlot = normalizeSlotId(cleanSlot);
    _recentlyUpdatedSlots[normSlot] = DateTime.now();
    _optimisticStatuses[normSlot] = ParkingSlotStatus.occupied;
    if (previousSlotId != null) {
      _recentlyUpdatedSlots[previousSlotId] = DateTime.now();
      _optimisticStatuses[previousSlotId] = ParkingSlotStatus.free;
      final cleanPrev = previousSlotId.replaceFirst(RegExp(r'^parking-'), '');
      _recentlyUpdatedSlots[cleanPrev] = DateTime.now();
      _optimisticStatuses[cleanPrev] = ParkingSlotStatus.free;
      final normPrev = normalizeSlotId(cleanPrev);
      _recentlyUpdatedSlots[normPrev] = DateTime.now();
      _optimisticStatuses[normPrev] = ParkingSlotStatus.free;
    }

    // 2. Clear any prior parked location for this user and mark target as occupied in all maps
    for (final map in [_floorSlots, ..._mallFloorSlots.values]) {
      for (final floor in map.values) {
        for (final slot in floor) {
          if (previousSlotId != null &&
              isMatchingSlotId(slot.id, previousSlotId)) {
            slot.status = ParkingSlotStatus.free;
          }
          if (isMatchingSlotId(slot.id, targetSlotId)) {
            slot.status = ParkingSlotStatus.occupied;
          }
        }
      }
    }

    // 3. Update the user vehicle record
    final updatedRecord = MyVehicleLocation(
      userId: _currentUserId,
      vehicleId: vehicleRecord.vehicleId.isNotEmpty
          ? vehicleRecord.vehicleId
          : 'veh-$_currentUserId',
      slotId: vehicleRecord.slotId,
      mallId: resolvedMallId,
      floorId: vehicleRecord.floorId,
      floorName: vehicleRecord.floorName,
      location: vehicleRecord.location,
      timestamp: DateTime.now(),
      status: 'parked',
      licensePlate: vehicleRecord.licensePlate,
      notes: vehicleRecord.notes,
    );

    _userVehicleRecords[_currentUserId] = updatedRecord;
    _allParkedVehicles[targetSlotId] = updatedRecord;
    _allParkedVehicles[cleanSlot] = updatedRecord;
    _allParkedVehicles[normSlot] = updatedRecord;

    // Broadcast to UI immediately (0ms)
    _slotStreamController.add(_floorSlots);
    notifyListeners();

    // 4. Persist vehicle location to local storage
    await prefs.setString(
      '$_vehicleStorageKeyPrefix$_currentUserId',
      jsonEncode(updatedRecord.toJson()),
    );

    // 5. Save updated slot status into cached slots
    final allSlots =
        (_mallFloorSlots[normResolvedId]?.values.expand((s) => s).toList()) ??
        _floorSlots.values.expand((s) => s).toList();
    if (allSlots.isNotEmpty) {
      final encoded = jsonEncode(allSlots.map((s) => s.toJson()).toList());
      await prefs.setString('cache_parking_slots_$resolvedMallId', encoded);
      await prefs.setString('cache_parking_slots_$normResolvedId', encoded);
    }

    // 6. Sync to backend API
    await ApiService.instance.saveVehicleLocation(
      updatedRecord,
      mallId: resolvedMallId,
    );
    await ApiService.instance.updateParkingSlotStatus(
      vehicleRecord.slotId,
      'occupied',
      mallId: resolvedMallId,
    );
    ApiService.instance.notifyDataSynced('parking');
    syncSlotsSilently(resolvedMallId);
  }

  /// Load vehicle location from local storage for current authenticated user
  Future<void> _loadVehicleFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_currentUserId.isEmpty) {
        _currentUserId =
            prefs.getString('NexNav_remembered_email') ?? 'user-default';
        _isAuthenticated = true;
      }
      final jsonStr = prefs.getString(
        '$_vehicleStorageKeyPrefix$_currentUserId',
      );
      if (jsonStr != null) {
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        final record = MyVehicleLocation.fromJson(data);
        if (record.status == 'parked') {
          _userVehicleRecords[_currentUserId] = record;
          _allParkedVehicles[record.slotId.trim().toLowerCase()] = record;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error loading vehicle location: $e');
    }
  }

  /// 6. Clear vehicle location on exit (clearVehicleLocation)
  /// Removes user's marker record (status: "removed") and resets shared slot to "free".
  Future<void> clearVehicleLocation({
    String? userId,
    String? mallId,
    String? slotId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final targetUser = (userId != null && userId.isNotEmpty)
        ? userId
        : (_currentUserId.isNotEmpty
              ? _currentUserId
              : (prefs.getString('NexNav_remembered_email') ?? 'user-default'));
    _currentUserId = targetUser;
    _isAuthenticated = true;

    final activeVehicle = fetchMyVehicleLocation(targetUser);

    // Identify all candidate slot IDs to free
    final slotsToFree = <String>{};
    if (slotId != null && slotId.trim().isNotEmpty) {
      slotsToFree.add(slotId.trim());
    }
    if (activeVehicle != null && activeVehicle.slotId.trim().isNotEmpty) {
      slotsToFree.add(activeVehicle.slotId.trim());
    }
    for (final rec in _userVehicleRecords.values) {
      if (rec.userId.toLowerCase() == targetUser.toLowerCase() ||
          rec.userId == _currentUserId) {
        if (rec.slotId.trim().isNotEmpty) {
          slotsToFree.add(rec.slotId.trim());
        }
      }
    }

    // 1. Completely remove matching vehicles from _allParkedVehicles
    _allParkedVehicles.removeWhere(
      (key, v) =>
          slotsToFree.any(
            (s) => isMatchingSlotId(key, s) || isMatchingSlotId(v.slotId, s),
          ) ||
          (targetUser.isNotEmpty &&
              v.userId.toLowerCase() == targetUser.toLowerCase()) ||
          v.userId == _currentUserId,
    );

    // 2. Remove or mark removed in _userVehicleRecords
    _userVehicleRecords.removeWhere(
      (key, v) =>
          key.toLowerCase() == targetUser.toLowerCase() ||
          key == _currentUserId ||
          slotsToFree.any((s) => isMatchingSlotId(v.slotId, s)),
    );

    // 3. Mark optimistic status as FREE so no sync can override it back to occupied
    for (final sId in slotsToFree) {
      final t = sId.trim().toLowerCase();
      final c = t.replaceFirst(RegExp(r'^parking-'), '');
      final n = normalizeSlotId(c);
      _recentlyUpdatedSlots[t] = DateTime.now();
      _recentlyUpdatedSlots[c] = DateTime.now();
      _recentlyUpdatedSlots[n] = DateTime.now();
      _optimisticStatuses[t] = ParkingSlotStatus.free;
      _optimisticStatuses[c] = ParkingSlotStatus.free;
      _optimisticStatuses[n] = ParkingSlotStatus.free;
    }

    // 4. Reset slot status to free in all in-memory collections
    for (final map in [_floorSlots, ..._mallFloorSlots.values]) {
      for (final floor in map.values) {
        for (final slot in floor) {
          if (slotsToFree.any((s) => isMatchingSlotId(slot.id, s))) {
            slot.status = ParkingSlotStatus.free;
          }
        }
      }
    }

    // Broadcast to UI immediately (0ms)
    _slotStreamController.add(_floorSlots);
    notifyListeners();

    // 5. Clean local preferences storage
    await prefs.remove('$_vehicleStorageKeyPrefix$targetUser');
    await prefs.remove('$_vehicleStorageKeyPrefix${targetUser.toLowerCase()}');
    await prefs.remove('$_vehicleStorageKeyPrefix$_currentUserId');

    final resolvedMallId = (mallId != null && mallId.isNotEmpty)
        ? mallId
        : (activeVehicle?.mallId.isNotEmpty == true
              ? activeVehicle!.mallId
              : (slotsToFree.isNotEmpty && slotsToFree.first.contains('-')
                    ? slotsToFree.first.split('-').first
                    : (prefs.getString('NexNav_active_mall_id') ?? '1')));
    final normResolvedId = normalizeMallId(resolvedMallId);

    final allSlots =
        (_mallFloorSlots[normResolvedId]?.values.expand((s) => s).toList()) ??
        _floorSlots.values.expand((s) => s).toList();
    if (allSlots.isNotEmpty) {
      final encoded = jsonEncode(allSlots.map((s) => s.toJson()).toList());
      await prefs.setString('cache_parking_slots_$resolvedMallId', encoded);
      await prefs.setString('cache_parking_slots_$normResolvedId', encoded);
    }

    // 6. Sync with backend API
    await ApiService.instance.deleteVehicleLocation(resolvedMallId, targetUser);
    for (final sId in slotsToFree) {
      await ApiService.instance.updateParkingSlotStatus(
        sId,
        'free',
        mallId: resolvedMallId,
      );
    }
    ApiService.instance.notifyDataSynced('parking');
    syncSlotsSilently(resolvedMallId);
  }

  /// 7. AR-Guided Path Locator (findMyCar)
  /// Returns user's active parked vehicle location record if status is "parked".
  MyVehicleLocation? findMyCar(String userId) {
    return fetchMyVehicleLocation(userId);
  }

  /// Auto-Detect nearest parking slot via BLE / UWB proximity simulation
  ParkingSlot? autoDetectNearestSlot(
    GeodeticCoords userCoords,
    String floorId,
  ) {
    final slots = fetchFloorMap(floorId);
    if (slots.isEmpty) return null;

    final effectiveUser = userCoords;

    ParkingSlot? nearest;
    double minDistance = double.infinity;

    for (final slot in slots) {
      if (slot.status == ParkingSlotStatus.free ||
          slot.status == ParkingSlotStatus.occupied) {
        final dist = calculateAccurate3DDistance(
          effectiveUser,
          slot.location,
          userFloorNumber: 1,
          targetFloorNumber: floorId == 'B2' ? -2 : (floorId == 'B1' ? -1 : 1),
        );
        if (dist < minDistance) {
          minDistance = dist;
          nearest = slot;
        }
      }
    }
    return nearest;
  }

  /// Auto-clear exit detection logic (Slot status change or Geofence threshold)
  Future<bool> detectVehicleExit(
    String slotId,
    GeodeticCoords currentUserCoords,
  ) async {
    final activeVehicle = fetchMyVehicleLocation(_currentUserId);
    if (activeVehicle == null) return false;

    final effectiveUser = currentUserCoords;

    final dist = calculateAccurate3DDistance(
      effectiveUser,
      activeVehicle.location,
      userFloorNumber: 1,
      targetFloorNumber: activeVehicle.floorId.contains('B2') ? -2 : -1,
    );

    if (dist > 500.0) {
      await clearVehicleLocation(userId: _currentUserId);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _sensorSimulationTimer?.cancel();
    _liveSyncTimer?.cancel();
    _slotStreamController.close();
    super.dispose();
  }
}
