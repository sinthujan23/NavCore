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
    final int floorNum = floorId == 'B2' ? -2 : (floorId == 'B1' ? -1 : 1);
    return DestinationPOI(
      id: id,
      name: 'Parking Stall $id',
      category: 'PARKING',
      floorNumber: floorNum,
      rating: 4.8,
      location: location,
      description:
          '${isEVCharging ? 'EV Charger • ' : ''}${isHandicapAccessible ? 'Handicap Accessible • ' : ''}Basement Parking Slot $id',
      openStatus: '24/7',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
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
    id: json['id'],
    floorId: json['floorId'],
    section: json['section'],
    slotNumber: json['slotNumber'],
    status: ParkingSlotStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => ParkingSlotStatus.free,
    ),
    location: GeodeticCoords(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    ),
    gridRow: json['gridRow'],
    gridCol: json['gridCol'],
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
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'vehicleId': vehicleId,
    'slotId': slotId,
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

  factory MyVehicleLocation.fromJson(Map<String, dynamic> json) =>
      MyVehicleLocation(
        userId: json['userId'] ?? 'user-001',
        vehicleId: json['vehicleId'] ?? 'veh-default',
        slotId: json['slotId'],
        floorId: json['floorId'],
        floorName: json['floorName'] ?? 'Basement Parking',
        location: GeodeticCoords(
          latitude: (json['latitude'] as num).toDouble(),
          longitude: (json['longitude'] as num).toDouble(),
          height: (json['height'] as num).toDouble(),
        ),
        timestamp: DateTime.parse(json['timestamp']),
        status: json['status'] ?? 'parked',
        licensePlate: json['licensePlate'] ?? 'WP CAB-8821',
        notes: json['notes'],
      );
}

class ParkingService extends ChangeNotifier {
  static const String _vehicleStorageKeyPrefix = 'NexNav_my_vehicle_location_';

  static final ParkingService _instance = ParkingService._internal();
  factory ParkingService() => _instance;
  static ParkingService get instance => _instance;

  final Map<String, List<ParkingSlot>> _floorSlots = {};

  // Auth state tracking
  String _currentUserId = '';
  String _authToken = '';
  bool _isAuthenticated = false;

  // Per-user record repository store (simulating backend DB records: userId -> MyVehicleLocation)
  final Map<String, MyVehicleLocation> _userVehicleRecords = {};
  Timer? _sensorSimulationTimer;
  final StreamController<Map<String, List<ParkingSlot>>> _slotStreamController =
      StreamController<Map<String, List<ParkingSlot>>>.broadcast();

  bool _isLiveStreamActive = false;

  ParkingService._internal() {
    _loadVehicleFromStorage();
  }

  String get currentUserId => _currentUserId;
  String get authToken => _authToken;
  bool get isAuthenticated => _isAuthenticated;
  MyVehicleLocation? get currentVehicleLocation =>
      fetchMyVehicleLocation(_currentUserId);
  bool get hasParkedVehicle => currentVehicleLocation != null;
  Stream<Map<String, List<ParkingSlot>>> get slotStream =>
      _slotStreamController.stream;
  bool get isLiveStreamActive => _isLiveStreamActive;

  /// 1. Authenticate user session & switch active user context
  void authenticateUser({required String userId, required String token}) {
    _currentUserId = userId;
    _authToken = token;
    _isAuthenticated = true;
    _loadVehicleFromStorage();
    notifyListeners();
  }

  /// 2. User-Scoped Vehicle Data API (GET /parking/my-vehicle?userId={userId})
  /// Enforces backend-level authorization so cross-user queries return null.
  MyVehicleLocation? fetchMyVehicleLocation(String userId) {
    if (!_isAuthenticated || _currentUserId != userId) {
      debugPrint(
        '[Security Auth Denied] Requesting userId ($userId) does not match authenticated session ($_currentUserId)',
      );
      return null;
    }

    final record = _userVehicleRecords[userId];
    if (record != null && record.status == 'parked') {
      return record;
    }
    return null;
  }

  /// 3. Shared Occupancy Status API Endpoint (fetchFloorSlotStatus)
  /// Returns shared slot availability (free/occupied/reserved) without user identities.
  List<ParkingSlot> fetchFloorSlotStatus(String floorId) {
    return fetchFloorMap(floorId);
  }

  /// 4. Private Vehicle Marker helper (renderMyVehicleMarker)
  /// Returns true ONLY if the slot contains the logged-in user's active parked vehicle.
  bool renderMyVehicleMarker(String slotId, String floorId) {
    if (!_isAuthenticated) return false;
    final myVehicle = fetchMyVehicleLocation(_currentUserId);
    if (myVehicle == null) return false;
    return myVehicle.slotId == slotId &&
        myVehicle.floorId == floorId &&
        myVehicle.status == 'parked';
  }

  Map<String, List<ParkingSlot>> get allFloorSlots => _floorSlots;

  /// Load parking bay layouts anchored at a specific Mall Map package.
  /// Uses real backend slots and cached local slots, eliminating hardcoded dummy data.
  Future<void> loadLayoutForMallMetadata({
    required String mallId,
    required double baseLat,
    required double baseLon,
    int basementFloors = 2,
  }) async {
    await loadSlotsForMall(mallId);
  }

  /// Reset all slots across all floors for active mall map to FREE status
  Future<void> resetAllSlotsToFree(String mallId) async {
    for (final slots in _floorSlots.values) {
      for (final slot in slots) {
        slot.status = ParkingSlotStatus.free;
        ApiService.instance.updateParkingSlotStatus(slot.id, 'free');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final all = _floorSlots.values.expand((s) => s).toList();
    await prefs.setString(
      'cache_parking_slots_$mallId',
      jsonEncode(all.map((s) => s.toJson()).toList()),
    );
    _slotStreamController.add(_floorSlots);
    notifyListeners();
  }

  /// Load parking slots dynamically from backend API for a given venue
  Future<void> loadSlotsForMall(String mallId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final slots = await ApiService.instance.fetchParkingSlots(mallId);
      _floorSlots.clear();
      if (slots.isNotEmpty) {
        for (final slot in slots) {
          if (!_floorSlots.containsKey(slot.floorId)) {
            _floorSlots[slot.floorId] = [];
          }
          _floorSlots[slot.floorId]!.add(slot);
        }
        await prefs.setString(
          'cache_parking_slots_$mallId',
          jsonEncode(slots.map((s) => s.toJson()).toList()),
        );
      } else {
        // Read from local cache if offline or backend freshly started
        final cached = prefs.getString('cache_parking_slots_$mallId');
        if (cached != null) {
          final List list = jsonDecode(cached);
          for (final item in list) {
            final slot = ParkingSlot.fromJson(item);
            if (!_floorSlots.containsKey(slot.floorId)) {
              _floorSlots[slot.floorId] = [];
            }
            _floorSlots[slot.floorId]!.add(slot);
          }
        }
      }
      _slotStreamController.add(_floorSlots);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading parking slots for $mallId: $e');
    }
  }

  /// Adds a single parking stall
  Future<bool> addParkingSlot(String mallId, ParkingSlot slot) async {
    final ok = await ApiService.instance.createParkingSlot(mallId, slot);
    if (!_floorSlots.containsKey(slot.floorId)) {
      _floorSlots[slot.floorId] = [];
    }
    _floorSlots[slot.floorId]!.removeWhere((s) => s.id == slot.id);
    _floorSlots[slot.floorId]!.add(slot);

    final prefs = await SharedPreferences.getInstance();
    final all = _floorSlots.values.expand((s) => s).toList();
    await prefs.setString(
      'cache_parking_slots_$mallId',
      jsonEncode(all.map((s) => s.toJson()).toList()),
    );

    _slotStreamController.add(_floorSlots);
    notifyListeners();
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
    final List<ParkingSlot> newSlots = [];
    for (int i = 0; i < count; i++) {
      final num = startNumber + i;
      final numStr = num < 10 ? '0$num' : '$num';
      final slotId = '$floorId-$section-$numStr';
      final r = i ~/ 4;
      final c = i % 4;
      newSlots.add(
        ParkingSlot(
          id: slotId,
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
          isEVCharging: isEV,
          isHandicapAccessible: isHandicap,
          sensorId: 'SNS-$floorId-$section$numStr',
        ),
      );
    }

    final ok = await ApiService.instance.createParkingSlotsBulk(
      mallId,
      newSlots,
    );
    if (!_floorSlots.containsKey(floorId)) {
      _floorSlots[floorId] = [];
    }
    for (final s in newSlots) {
      _floorSlots[floorId]!.removeWhere((x) => x.id == s.id);
      _floorSlots[floorId]!.add(s);
    }

    final prefs = await SharedPreferences.getInstance();
    final all = _floorSlots.values.expand((s) => s).toList();
    await prefs.setString(
      'cache_parking_slots_$mallId',
      jsonEncode(all.map((s) => s.toJson()).toList()),
    );

    _slotStreamController.add(_floorSlots);
    notifyListeners();
    return ok;
  }

  /// Deletes a parking slot
  Future<bool> deleteParkingSlot(String mallId, String slotId) async {
    final ok = await ApiService.instance.deleteParkingSlot(slotId);
    for (final list in _floorSlots.values) {
      list.removeWhere((s) => s.id == slotId);
    }
    _floorSlots.removeWhere((key, value) => value.isEmpty);

    final prefs = await SharedPreferences.getInstance();
    final all = _floorSlots.values.expand((s) => s).toList();
    await prefs.setString(
      'cache_parking_slots_$mallId',
      jsonEncode(all.map((s) => s.toJson()).toList()),
    );

    _slotStreamController.add(_floorSlots);
    notifyListeners();
    return ok;
  }

  /// Toggles or updates slot occupancy status
  Future<void> updateSlotStatus(
    String mallId,
    String slotId,
    ParkingSlotStatus newStatus,
  ) async {
    for (final list in _floorSlots.values) {
      for (final s in list) {
        if (s.id == slotId) {
          s.status = newStatus;
          break;
        }
      }
    }
    await ApiService.instance.updateParkingSlotStatus(slotId, newStatus.name);
    final prefs = await SharedPreferences.getInstance();
    final all = _floorSlots.values.expand((s) => s).toList();
    await prefs.setString(
      'cache_parking_slots_$mallId',
      jsonEncode(all.map((s) => s.toJson()).toList()),
    );

    _slotStreamController.add(_floorSlots);
    notifyListeners();
  }

  /// REST / Local API endpoint: fetchFloorMap(floorId)
  List<ParkingSlot> fetchFloorMap(String floorId) {
    return _floorSlots[floorId] ?? [];
  }

  /// REST / Local API endpoint: getSlotAvailability(floorId)
  Map<String, dynamic> getSlotAvailability(String floorId) {
    final slots = fetchFloorMap(floorId);
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
  Future<void> saveVehicleLocation(MyVehicleLocation vehicleRecord) async {
    if (!_isAuthenticated || vehicleRecord.userId != _currentUserId) {
      throw Exception(
        'Unauthorized: Cannot save vehicle location for another user',
      );
    }

    // Restriction: Prevent double-parking if the user already has a parked vehicle location
    final existingParked = fetchMyVehicleLocation(vehicleRecord.userId);
    if (existingParked != null &&
        existingParked.slotId != vehicleRecord.slotId) {
      throw Exception(
        'Vehicle Already Parked: You currently have a vehicle parked at Stall ${existingParked.slotId} (${existingParked.floorName}). Please remove your existing parked location before parking in a new slot.',
      );
    }

    // Restriction: Prevent parking in a slot occupied or reserved by another vehicle
    for (final floor in _floorSlots.values) {
      for (final slot in floor) {
        if (slot.id == vehicleRecord.slotId) {
          final isParkedByOther = _userVehicleRecords.entries.any(
            (e) =>
                e.key != vehicleRecord.userId &&
                e.value.status == 'parked' &&
                e.value.slotId == slot.id,
          );
          if (isParkedByOther ||
              (slot.status != ParkingSlotStatus.free &&
                  slot.id != _userVehicleRecords[_currentUserId]?.slotId)) {
            throw Exception(
              'Parking Restricted: Stall ${slot.id} is occupied by another vehicle.',
            );
          }
        }
      }
    }

    final updatedRecord = MyVehicleLocation(
      userId: vehicleRecord.userId,
      vehicleId: vehicleRecord.vehicleId.isNotEmpty
          ? vehicleRecord.vehicleId
          : 'veh-${vehicleRecord.userId}',
      slotId: vehicleRecord.slotId,
      floorId: vehicleRecord.floorId,
      floorName: vehicleRecord.floorName,
      location: vehicleRecord.location,
      timestamp: DateTime.now(),
      status: 'parked',
      licensePlate: vehicleRecord.licensePlate,
      notes: vehicleRecord.notes,
    );

    _userVehicleRecords[vehicleRecord.userId] = updatedRecord;

    // Mark slot as occupied in shared layout
    for (final floor in _floorSlots.values) {
      for (final slot in floor) {
        if (slot.id == vehicleRecord.slotId) {
          slot.status = ParkingSlotStatus.occupied;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_vehicleStorageKeyPrefix${vehicleRecord.userId}',
      jsonEncode(updatedRecord.toJson()),
    );
    ApiService.instance.saveVehicleLocation(updatedRecord);
    notifyListeners();
  }

  /// Load vehicle location from local storage for current authenticated user
  Future<void> _loadVehicleFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(
        '$_vehicleStorageKeyPrefix$_currentUserId',
      );
      if (jsonStr != null) {
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        final record = MyVehicleLocation.fromJson(data);
        if (record.status == 'parked') {
          _userVehicleRecords[_currentUserId] = record;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error loading vehicle location: $e');
    }
  }

  /// 6. Clear vehicle location on exit (clearVehicleLocation)
  /// Removes user's marker record (status: "removed") and resets shared slot to "free".
  Future<void> clearVehicleLocation({String? userId}) async {
    final targetUser = userId ?? _currentUserId;
    if (!_isAuthenticated || targetUser != _currentUserId) {
      debugPrint(
        '[Security Auth Denied] Cannot clear vehicle location for $targetUser',
      );
      return;
    }

    final activeVehicle = fetchMyVehicleLocation(targetUser);
    if (activeVehicle != null) {
      final slotId = activeVehicle.slotId;

      _userVehicleRecords[targetUser] = MyVehicleLocation(
        userId: activeVehicle.userId,
        vehicleId: activeVehicle.vehicleId,
        slotId: activeVehicle.slotId,
        floorId: activeVehicle.floorId,
        floorName: activeVehicle.floorName,
        location: activeVehicle.location,
        timestamp: DateTime.now(),
        status: 'removed',
        licensePlate: activeVehicle.licensePlate,
        notes: activeVehicle.notes,
      );

      // Reset slot status to free in shared map
      for (final floor in _floorSlots.values) {
        for (final slot in floor) {
          if (slot.id == slotId) {
            slot.status = ParkingSlotStatus.free;
          }
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_vehicleStorageKeyPrefix$targetUser');
    ApiService.instance.deleteVehicleLocation(
      'mall-one-galle-face',
      targetUser,
    );
    notifyListeners();
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
    _slotStreamController.close();
    super.dispose();
  }
}
