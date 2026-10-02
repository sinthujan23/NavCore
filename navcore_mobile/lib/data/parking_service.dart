import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../engine/ecef_engine.dart';
import '../engine/bearing_engine.dart';
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
          '${isEVCharging ? 'EV Charger ⚡ • ' : ''}${isHandicapAccessible ? 'Handicap Accessible ♿ • ' : ''}Basement Parking Slot $id',
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
  String _currentUserId = 'user-001';
  String _authToken = 'jwt-mock-token-user-001';
  bool _isAuthenticated = true;

  // Per-user record repository store (simulating backend DB records: userId -> MyVehicleLocation)
  final Map<String, MyVehicleLocation> _userVehicleRecords = {};
  Timer? _sensorSimulationTimer;
  final StreamController<Map<String, List<ParkingSlot>>> _slotStreamController =
      StreamController<Map<String, List<ParkingSlot>>>.broadcast();

  bool _isLiveStreamActive = true;

  ParkingService._internal() {
    _initializeMockParkingLayouts();
    _loadVehicleFromStorage();
    _startLiveIoTSensorStream();
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

  /// Dynamically load and generate parking bay grid layouts anchored at a specific Mall Map package's geodetic location
  void loadLayoutForMallMetadata({
    required String mallId,
    required double baseLat,
    required double baseLon,
    int basementFloors = 2,
  }) {
    _floorSlots.clear();

    final int numBasements = basementFloors > 0 ? basementFloors : 2;

    for (int b = numBasements; b >= 1; b--) {
      final String floorId = 'B$b';
      final double height = 45.0 - (b * 5.0);
      _floorSlots[floorId] = _generateGridSlots(
        floorId: floorId,
        baseHeight: height,
        rows: 6,
        cols: 4,
        sections: ['A', 'B'],
        baseLat: baseLat - (b * 0.0002),
        baseLon: baseLon - (b * 0.0002),
      );
    }

    // Ground Floor / VIP Surface Parking
    _floorSlots['GF'] = _generateGridSlots(
      floorId: 'GF',
      baseHeight: 45.0,
      rows: 3,
      cols: 4,
      sections: ['P'],
      baseLat: baseLat + 0.0001,
      baseLon: baseLon + 0.0001,
    );

    _slotStreamController.add(_floorSlots);
    notifyListeners();
  }

  /// Reset all slots across all floors for active mall map to FREE status
  void resetAllSlotsToFree() {
    for (final slots in _floorSlots.values) {
      for (final slot in slots) {
        slot.status = ParkingSlotStatus.free;
      }
    }
    _slotStreamController.add(_floorSlots);
    notifyListeners();
  }

  /// Initialize Parking Layout Grids for B2, B1, and Ground Floor
  void _initializeMockParkingLayouts() {
    const baseLat = 6.927079;
    const baseLon = 79.845612;

    // Floor B2 (Basement 2 - Height 35.0m)
    _floorSlots['B2'] = _generateGridSlots(
      floorId: 'B2',
      baseHeight: 35.0,
      rows: 6,
      cols: 4,
      sections: ['A', 'B'],
      baseLat: baseLat - 0.0003,
      baseLon: baseLon - 0.0003,
    );

    // Floor B1 (Basement 1 - Height 40.0m)
    _floorSlots['B1'] = _generateGridSlots(
      floorId: 'B1',
      baseHeight: 40.0,
      rows: 6,
      cols: 4,
      sections: ['A', 'B'],
      baseLat: baseLat - 0.0001,
      baseLon: baseLon - 0.0001,
    );

    // Floor GF (Ground Floor - Height 45.0m)
    _floorSlots['GF'] = _generateGridSlots(
      floorId: 'GF',
      baseHeight: 45.0,
      rows: 3,
      cols: 4,
      sections: ['P'],
      baseLat: baseLat + 0.0001,
      baseLon: baseLon + 0.0001,
    );
  }

  List<ParkingSlot> _generateGridSlots({
    required String floorId,
    required double baseHeight,
    required int rows,
    required int cols,
    required List<String> sections,
    required double baseLat,
    required double baseLon,
  }) {
    final List<ParkingSlot> slots = [];
    final random = Random(floorId.hashCode);

    if (floorId == 'B1' || floorId == 'B2') {
      for (final sec in ['A', 'B']) {
        for (int i = 1; i <= 12; i++) {
          final numStr = i < 10 ? '0$i' : '$i';
          final slotId = '$floorId-$sec-$numStr';
          final isEV = (sec == 'A' && (i == 1 || i == 2));
          final isHandicap = (sec == 'A' && (i == 3 || i == 4));

          ParkingSlotStatus initialStatus = ParkingSlotStatus.free;
          final randVal = random.nextDouble();
          if (randVal < 0.35) {
            initialStatus = ParkingSlotStatus.occupied;
          } else if (randVal < 0.45) {
            initialStatus = ParkingSlotStatus.reserved;
          }

          final r = (i - 1) ~/ 2;
          final c = (i - 1) % 2;

          slots.add(
            ParkingSlot(
              id: slotId,
              floorId: floorId,
              section: sec,
              slotNumber: i,
              status: initialStatus,
              location: GeodeticCoords(
                latitude: baseLat + (r * 0.00004),
                longitude: baseLon + (c * 0.00004),
                height: baseHeight,
              ),
              gridRow: r,
              gridCol: c,
              isEVCharging: isEV,
              isHandicapAccessible: isHandicap,
              sensorId: 'IOT-SNS-$floorId-$sec$numStr',
            ),
          );
        }
      }
      return slots;
    }

    int counter = 1;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final sec = sections[(r + c) % sections.length];
        final numStr = counter < 10 ? '0$counter' : '$counter';
        final slotId = '$floorId-$sec-$numStr';

        ParkingSlotStatus initialStatus = ParkingSlotStatus.free;
        final randVal = random.nextDouble();
        if (randVal < 0.55) {
          initialStatus = ParkingSlotStatus.occupied;
        } else if (randVal < 0.65) {
          initialStatus = ParkingSlotStatus.reserved;
        }

        final isEV = (r == 0 && c < 2);
        final isHandicap = (r == 0 && c >= 2 && c < 4);

        slots.add(
          ParkingSlot(
            id: slotId,
            floorId: floorId,
            section: sec,
            slotNumber: counter,
            status: initialStatus,
            location: GeodeticCoords(
              latitude: baseLat + (r * 0.00004),
              longitude: baseLon + (c * 0.00004),
              height: baseHeight,
            ),
            gridRow: r,
            gridCol: c,
            isEVCharging: isEV,
            isHandicapAccessible: isHandicap,
            sensorId: 'IOT-SNS-$floorId-$r$c',
          ),
        );
        counter++;
      }
    }
    return slots;
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
    notifyListeners();
  }

  /// Live IoT / CV Occupancy Sensor Simulation (WebSocket push simulation)
  void _startLiveIoTSensorStream() {
    _sensorSimulationTimer?.cancel();
    _sensorSimulationTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_isLiveStreamActive) return;

      final random = Random();
      final floors = _floorSlots.keys.toList();
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
    if (existingParked != null && existingParked.slotId != vehicleRecord.slotId) {
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

    final effectiveUser = getEffectiveUserCoords(userCoords, entranceAnchor);

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

    final effectiveUser = getEffectiveUserCoords(
      currentUserCoords,
      entranceAnchor,
    );

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
