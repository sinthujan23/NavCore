import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../data/api_service.dart';
import '../../data/mall_database_service.dart';
import '../../data/geocoding_service.dart';
import '../../engine/ecef_engine.dart';
import '../../engine/bearing_engine.dart';
import 'admin_osm_map_screen.dart';

class AdminVenueManagerScreen extends StatefulWidget {
  final MallDatabaseService mallService;
  final Function(String mallId) onSelectActiveMall;
  final GeodeticCoords? userCoords;

  const AdminVenueManagerScreen({
    super.key,
    required this.mallService,
    required this.onSelectActiveMall,
    this.userCoords,
  });

  @override
  State<AdminVenueManagerScreen> createState() =>
      _AdminVenueManagerScreenState();
}

class _AdminVenueManagerScreenState extends State<AdminVenueManagerScreen> {
  late List<MallMetadata> _venues;

  @override
  void initState() {
    super.initState();
    _venues = List.from(widget.mallService.catalog);
    _loadVenuesFromApi();
  }

  Future<void> _loadVenuesFromApi() async {
    try {
      final list = await widget.mallService.getMallsList();
      if (mounted) {
        setState(() {
          _venues = list;
        });
      }
    } catch (_) {}
  }

  void _openAddVenueScreen([MallMetadata? existingVenue]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditVenueScreen(
          existingVenue: existingVenue,
          userCoords: widget.userCoords,
          onSaveVenue: (newMall) async {
            setState(() {
              if (existingVenue != null) {
                final idx = _venues.indexWhere((m) => m.id == existingVenue.id);
                if (idx != -1) {
                  _venues[idx] = newMall;
                } else {
                  _venues.add(newMall);
                }
              } else {
                _venues.add(newMall);
              }
            });
            if (existingVenue != null) {
              await ApiService.instance.updateMall(newMall);
            } else {
              await ApiService.instance.createMall(newMall);
            }
            widget.onSelectActiveMall(newMall.id);
            _loadVenuesFromApi();
          },
        ),
      ),
    );
  }

  void _confirmDeleteVenue(MallMetadata mall) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                LucideIcons.trash2,
                color: Color(0xFFEF4444),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Venue',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${mall.name}" from the database?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: const Color(0xFF64748B),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                _venues.removeWhere((m) => m.id == mall.id);
              });
              await ApiService.instance.deleteMall(mall.id);
              _loadVenuesFromApi();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Venue "${mall.name}" deleted from database.'),
                    backgroundColor: const Color(0xFFEF4444),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text(
              'Delete',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        surfaceTintColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Center(
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Icon(
                  LucideIcons.arrowLeft,
                  size: 18,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Venue Package Manager',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              '${_venues.length} venue packages registered',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14, top: 10, bottom: 10),
            child: Center(
              child: InkWell(
                onTap: () => _openAddVenueScreen(),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.22),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.plus,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'ADD NEW MALL',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _venues.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.building,
                        size: 40,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Venue Packages Yet',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap "ADD NEW MALL" above to register and configure your first indoor navigation venue.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _venues.length,
              itemBuilder: (context, idx) {
                final mall = _venues[idx];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: mall.isActive
                          ? const Color(0xFF10B981)
                          : const Color(0xFFE2E8F0),
                      width: mall.isActive ? 1.5 : 1.0,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A0F172A),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              mall.name,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              InkWell(
                                onTap: () => _openAddVenueScreen(mall),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFBFDBFE),
                                    ),
                                  ),
                                  child: const Icon(
                                    LucideIcons.pencil,
                                    size: 13,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _confirmDeleteVenue(mall),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFFECACA),
                                    ),
                                  ),
                                  child: const Icon(
                                    LucideIcons.trash2,
                                    size: 13,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: mall.isActive
                                      ? const Color(0xFFECFDF5)
                                      : const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: mall.isActive
                                        ? const Color(0xFFA7F3D0)
                                        : const Color(0xFFBFDBFE),
                                  ),
                                ),
                                child: Text(
                                  mall.isActive ? 'ACTIVE VENUE' : 'REGISTERED',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: mall.isActive
                                        ? const Color(0xFF047857)
                                        : const Color(0xFF1D4ED8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Builder(
                        builder: (context) {
                          double? venueDistMeters;
                          if (widget.userCoords != null &&
                              widget.userCoords!.latitude != 0.0) {
                            venueDistMeters = haversineDistance(
                              widget.userCoords!,
                              GeodeticCoords(
                                latitude: mall.latitude,
                                longitude: mall.longitude,
                                height: widget.userCoords!.height,
                              ),
                            );
                          }

                          return Row(
                            children: [
                              if (venueDistMeters != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFFBFDBFE),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        LucideIcons.navigation,
                                        size: 10,
                                        color: Color(0xFF2563EB),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        venueDistMeters < 1000
                                            ? '${venueDistMeters.toInt()}m away'
                                            : '${(venueDistMeters / 1000).toStringAsFixed(1)}km away',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF2563EB),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              Expanded(
                                child: Text(
                                  '${mall.city}, ${mall.country} • ${mall.floorCount} Floors • ${mall.packageSizeBytesMB} MB',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                widget.onSelectActiveMall(mall.id);
                                Navigator.pop(context);
                              },
                              icon: Icon(
                                LucideIcons.checkCircle2,
                                size: 15,
                                color: mall.isActive
                                    ? const Color(0xFF059669)
                                    : const Color(0xFF2563EB),
                              ),
                              label: Text(
                                mall.isActive
                                    ? 'Venue Currently Active'
                                    : 'Activate Venue Map',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: mall.isActive
                                      ? const Color(0xFF059669)
                                      : const Color(0xFF2563EB),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                side: BorderSide(
                                  color: mall.isActive
                                      ? const Color(0xFFA7F3D0)
                                      : const Color(0xFFBFDBFE),
                                ),
                                backgroundColor: mall.isActive
                                    ? const Color(0xFFECFDF5)
                                    : const Color(0xFFEFF6FF),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// HIGH-ACCURACY GPS CONVERGENCE RESULT
class _GpsConvergenceResult {
  final GeodeticCoords coords;
  final double accuracy;
  final int sampleCount;

  const _GpsConvergenceResult({
    required this.coords,
    required this.accuracy,
    required this.sampleCount,
  });
}

/// FULL-SCREEN VENUE CREATION & EDITING SCREEN
class AddEditVenueScreen extends StatefulWidget {
  final MallMetadata? existingVenue;
  final GeodeticCoords? userCoords;
  final Function(MallMetadata venue) onSaveVenue;

  const AddEditVenueScreen({
    super.key,
    this.existingVenue,
    this.userCoords,
    required this.onSaveVenue,
  });

  @override
  State<AddEditVenueScreen> createState() => _AddEditVenueScreenState();
}

class _AddEditVenueScreenState extends State<AddEditVenueScreen> {
  late final TextEditingController _idController;
  late final TextEditingController _nameController;
  late final TextEditingController _cityController;
  late final TextEditingController _countryController;
  late final TextEditingController _categoryController;
  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  late final TextEditingController _heightController;
  late final TextEditingController _floorGapController;

  int _floorCount = 5;
  bool _userEditedId = false;
  bool _isFetchingGps = false;
  bool _isResolvingPlace = false;
  bool _isStationaryLocked = false;

  // Phone motion tracking & continuous auto-sync
  final bool _isMotionSyncActive = true;
  bool _isPhoneInMotion = false;
  StreamSubscription<Position>? _positionStreamSub;
  StreamSubscription<UserAccelerometerEvent>? _accelStreamSub;
  StreamSubscription<AccelerometerEvent>? _rawAccelStreamSub;
  DateTime? _lastReverseGeocodeTime;
  Timer? _stationaryDebounceTimer;

  // High-accuracy multi-sample GPS convergence & stationary lock anchor
  GeodeticCoords? _lastStabilizedCoords;

  @override
  void initState() {
    super.initState();
    final v = widget.existingVenue;
    _idController = TextEditingController(text: v?.id ?? '');
    _nameController = TextEditingController(text: v?.name ?? '');
    _cityController = TextEditingController(text: v?.city ?? '');
    _countryController = TextEditingController(text: v?.country ?? '');
    _categoryController = TextEditingController(
      text: v?.category ?? 'Shopping & Entertainment',
    );

    final initialLat =
        v?.latitude ??
        (widget.userCoords != null && widget.userCoords!.latitude != 0.0
            ? widget.userCoords!.latitude
            : null);
    final initialLng =
        v?.longitude ??
        (widget.userCoords != null && widget.userCoords!.longitude != 0.0
            ? widget.userCoords!.longitude
            : null);
    final rawInitialAlt = widget.userCoords?.height ?? 0.0;
    final initialAlt = (rawInitialAlt < 0.0 || rawInitialAlt > 4000.0)
        ? 0.0
        : rawInitialAlt;

    _latController = TextEditingController(
      text: initialLat != null ? initialLat.toStringAsFixed(6) : '',
    );
    _lngController = TextEditingController(
      text: initialLng != null ? initialLng.toStringAsFixed(6) : '',
    );
    _heightController = TextEditingController(
      text: initialAlt.toStringAsFixed(1),
    );
    _floorGapController = TextEditingController(text: '4.5');
    _floorCount = v?.floorCount ?? 5;

    if (v != null) {
      _userEditedId = true;
      _lastStabilizedCoords = GeodeticCoords(
        latitude: v.latitude,
        longitude: v.longitude,
        height: initialAlt,
      );
    }

    // Auto-generate slug ID as user types title
    _nameController.addListener(() {
      if (!_userEditedId) {
        final raw = _nameController.text.trim();
        if (raw.isNotEmpty) {
          final slug = raw
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
              .replaceAll(RegExp(r'^-+|-+$'), '');
          _idController.value = TextEditingValue(
            text: 'mall-$slug',
            selection: TextSelection.collapsed(offset: ('mall-$slug').length),
          );
        } else {
          _idController.value = const TextEditingValue(
            text: '',
            selection: TextSelection.collapsed(offset: 0),
          );
        }
      }
    });

    // Start continuous phone motion listener & live auto-sync
    _startLiveMotionSync();

    // Auto-trigger live GPS convergence on new venue creation
    if (widget.existingVenue == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncLiveGpsAndArchitecture();
      });
    }
  }

  @override
  void dispose() {
    _stopLiveMotionSync();
    _idController.dispose();
    _nameController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _categoryController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _heightController.dispose();
    _floorGapController.dispose();
    super.dispose();
  }

  void _flagPhoneMotionDetected() {
    _stationaryDebounceTimer?.cancel();
    if (!_isPhoneInMotion) {
      if (mounted) {
        setState(() {
          _isPhoneInMotion = true;
          _isStationaryLocked = false;
        });
      }
    }
    _stationaryDebounceTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted && _isPhoneInMotion) {
        setState(() {
          _isPhoneInMotion = false;
        });
      }
    });
  }

  void _startLiveMotionSync() async {
    _stopLiveMotionSync();
    if (!_isMotionSyncActive) return;

    // 1. High-sensitivity physical phone motion detection (linear user acceleration)
    try {
      _accelStreamSub =
          userAccelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 150),
          ).listen((UserAccelerometerEvent event) {
            if (!mounted || !_isMotionSyncActive) return;
            final double mag = math.sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z,
            );
            // Sensitive threshold for natural phone movement / walking (0.22 m/s²)
            if (mag > 0.22) {
              _flagPhoneMotionDetected();
            }
          }, onError: (_) {});
    } catch (_) {}

    // 1b. Fallback standard accelerometer listener (deviation from static 1G = 9.80665 m/s²)
    try {
      _rawAccelStreamSub =
          accelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 150),
          ).listen((AccelerometerEvent event) {
            if (!mounted || !_isMotionSyncActive) return;
            final double totalG = math.sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z,
            );
            if ((totalG - 9.80665).abs() > 0.28) {
              _flagPhoneMotionDetected();
            }
          }, onError: (_) {});
    } catch (_) {}

    // 2. Real-time GPS stream listener with motion-based coordinate & calculation updates
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      const settings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );

      _positionStreamSub =
          Geolocator.getPositionStream(locationSettings: settings).listen((
            Position pos,
          ) {
            if (!mounted || !_isMotionSyncActive || _isFetchingGps) return;
            _onLivePositionUpdate(pos);
          }, onError: (_) {});
    } catch (_) {}
  }

  void _stopLiveMotionSync() {
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
    _accelStreamSub?.cancel();
    _accelStreamSub = null;
    _rawAccelStreamSub?.cancel();
    _rawAccelStreamSub = null;
    _stationaryDebounceTimer?.cancel();
    _stationaryDebounceTimer = null;
  }

  void _onLivePositionUpdate(Position pos) {
    if (pos.latitude.isNaN ||
        pos.longitude.isNaN ||
        (pos.latitude == 0.0 && pos.longitude == 0.0)) {
      return;
    }

    final newCoords = GeodeticCoords(
      latitude: pos.latitude,
      longitude: pos.longitude,
      height: pos.altitude,
    );

    // If GPS detects movement speed >= 0.15 m/s (~0.5 km/h walking), flag phone motion
    if (!pos.speed.isNaN && pos.speed >= 0.15) {
      _flagPhoneMotionDetected();
    }

    GeodeticCoords? anchorCoords = _lastStabilizedCoords;
    if (anchorCoords == null) {
      final curLat = double.tryParse(_latController.text);
      final curLng = double.tryParse(_lngController.text);
      if (curLat != null && curLng != null && curLat != 0.0 && curLng != 0.0) {
        anchorCoords = GeodeticCoords(
          latitude: curLat,
          longitude: curLng,
          height: pos.altitude,
        );
      }
    }

    if (anchorCoords != null) {
      final double distMeters = haversineDistance(anchorCoords, newCoords);

      // If displacement exceeds 0.70m, physical user motion is verified
      if (distMeters >= 0.70) {
        _flagPhoneMotionDetected();
      }

      // If phone is completely stationary (no motion detected, no speed, displacement < 0.70m)
      if (!_isPhoneInMotion && distMeters < 0.70) {
        if (!_isStationaryLocked) {
          setState(() {
            _isStationaryLocked = true;
          });
        }
        return; // Suppress sub-meter noise while completely still on a desk
      }
    }

    // Phone is moving or user has moved to new position:
    _lastStabilizedCoords = newCoords;

    setState(() {
      _isStationaryLocked = false;
      // Auto-update latitude and longitude continuously based on phone motion
      _latController.text = newCoords.latitude.toStringAsFixed(6);
      _lngController.text = newCoords.longitude.toStringAsFixed(6);

      // Live ground level altitude calculation
      double calibratedAlt = 0.0;
      if (pos.altitude > 0.0 && pos.altitude < 4000.0) {
        calibratedAlt = double.parse(pos.altitude.toStringAsFixed(1));
      }
      _heightController.text = calibratedAlt.toStringAsFixed(1);
    });

    // Auto-recalculate architecture and reverse geocode when moving (throttled every 3 seconds)
    final now = DateTime.now();
    if (_lastReverseGeocodeTime == null ||
        now.difference(_lastReverseGeocodeTime!).inSeconds >= 3) {
      _lastReverseGeocodeTime = now;
      GeocodingService.reverseGeocode(
            newCoords.latitude,
            newCoords.longitude,
            rawAltitude: newCoords.height,
          )
          .then((geo) {
            if (mounted) {
              setState(() {
                _heightController.text = geo.groundAltitude.toStringAsFixed(1);
                _floorGapController.text = geo.floorGap.toStringAsFixed(1);
                _floorCount = geo.floorCount;
                if (!_userEditedId &&
                    _nameController.text.trim().isEmpty &&
                    geo.placeName.isNotEmpty) {
                  _nameController.text = geo.placeName;
                  _idController.text = geo.suggestedVenueId;
                }
                if (_cityController.text.trim().isEmpty &&
                    geo.city.isNotEmpty) {
                  _cityController.text = geo.city;
                }
                if (_countryController.text.trim().isEmpty &&
                    geo.country.isNotEmpty) {
                  _countryController.text = geo.country;
                }
              });
            }
          })
          .catchError((_) {});
    }
  }

  Future<_GpsConvergenceResult?> _getLiveGpsCoordinates() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'GPS Location service is disabled on device. Please enable location.',
              ),
              backgroundColor: Color(0xFFF59E0B),
            ),
          );
        }
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied.'),
                backgroundColor: Color(0xFFEF4444),
              ),
            );
          }
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission is permanently denied in settings.',
              ),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
        return null;
      }

      // Collect multiple high-accuracy samples for satellite convergence
      final List<Position> collectedSamples = [];
      StreamSubscription<Position>? streamSub;

      try {
        const locationSettings = LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        );

        final completer = Completer<void>();

        streamSub =
            Geolocator.getPositionStream(
              locationSettings: locationSettings,
            ).listen((Position pos) {
              if (!pos.latitude.isNaN &&
                  !pos.longitude.isNaN &&
                  !(pos.latitude == 0.0 && pos.longitude == 0.0)) {
                collectedSamples.add(pos);
                // If collected at least 4 samples and reached precision <= 3.5m, converge early
                if (collectedSamples.length >= 4 && pos.accuracy <= 3.5) {
                  if (!completer.isCompleted) completer.complete();
                } else if (collectedSamples.length >= 6) {
                  if (!completer.isCompleted) completer.complete();
                }
              }
            }, onError: (_) {});

        // Allow up to 2.4 seconds for satellite convergence
        await Future.any([
          completer.future,
          Future.delayed(const Duration(milliseconds: 2400)),
        ]);
      } catch (_) {
        // Fallback below
      } finally {
        await streamSub?.cancel();
      }

      // Fallback single fix if stream was empty
      if (collectedSamples.isEmpty) {
        try {
          final singleFix = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              timeLimit: Duration(seconds: 4),
            ),
          );
          collectedSamples.add(singleFix);
        } catch (_) {}
      }

      if (collectedSamples.isEmpty) {
        return null;
      }

      // Filter out low-accuracy outliers if better readings exist
      List<Position> validSamples = collectedSamples;
      final hasHighAccuracy = validSamples.any((p) => p.accuracy <= 15.0);
      if (hasHighAccuracy) {
        validSamples = validSamples.where((p) => p.accuracy <= 25.0).toList();
      }
      if (validSamples.isEmpty) {
        validSamples = collectedSamples;
      }

      // Compute inverse-variance weighted average coordinates
      double sumWeights = 0.0;
      double weightedLat = 0.0;
      double weightedLng = 0.0;
      double weightedAlt = 0.0;
      double bestAccuracy = double.infinity;

      for (final p in validSamples) {
        final acc = (p.accuracy.isNaN || p.accuracy <= 0.0) ? 5.0 : p.accuracy;
        final w = 1.0 / (acc * acc);
        sumWeights += w;
        weightedLat += p.latitude * w;
        weightedLng += p.longitude * w;
        final alt = (p.altitude.isNaN || p.altitude.isInfinite)
            ? 45.0
            : p.altitude;
        weightedAlt += alt * w;
        if (acc < bestAccuracy) {
          bestAccuracy = acc;
        }
      }

      if (sumWeights <= 0.0) {
        final p = validSamples.first;
        return _GpsConvergenceResult(
          coords: GeodeticCoords(
            latitude: p.latitude,
            longitude: p.longitude,
            height: p.altitude,
          ),
          accuracy: p.accuracy,
          sampleCount: 1,
        );
      }

      final avgCoords = GeodeticCoords(
        latitude: weightedLat / sumWeights,
        longitude: weightedLng / sumWeights,
        height: weightedAlt / sumWeights,
      );

      return _GpsConvergenceResult(
        coords: avgCoords,
        accuracy: bestAccuracy == double.infinity ? 5.0 : bestAccuracy,
        sampleCount: validSamples.length,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching GPS: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _syncLiveGpsAndArchitecture() async {
    setState(() {
      _isFetchingGps = true;
      _isResolvingPlace = true;
    });

    final fixData = await _getLiveGpsCoordinates();

    if (fixData != null && mounted) {
      GeodeticCoords finalCoords = fixData.coords;
      bool isStationary = false;

      // Check existing coordinate anchor (previous sync or form values)
      final currentLat = double.tryParse(_latController.text);
      final currentLng = double.tryParse(_lngController.text);
      GeodeticCoords? anchorCoords = _lastStabilizedCoords;

      if (anchorCoords == null &&
          currentLat != null &&
          currentLng != null &&
          currentLat != 0.0 &&
          currentLng != 0.0) {
        anchorCoords = GeodeticCoords(
          latitude: currentLat,
          longitude: currentLng,
          height: double.tryParse(_heightController.text) ?? finalCoords.height,
        );
      }

      if (anchorCoords != null) {
        final double distMeters = haversineDistance(anchorCoords, finalCoords);

        // STATIONARY NOISE CLAMP & DEADBAND FILTER:
        // When staying at the same place, successive GPS fixes drift by ~0.5m-3.5m due to multipath noise.
        if (distMeters <= 2.2) {
          // Strict lock: preserve the exact coordinates so they never fluctuate at the same spot!
          finalCoords = anchorCoords;
          isStationary = true;
        } else if (distMeters <= 3.8) {
          // Gentle damping: blend 85% anchor + 15% new reading to stabilize drift
          final blendedLat =
              anchorCoords.latitude * 0.85 + finalCoords.latitude * 0.15;
          final blendedLng =
              anchorCoords.longitude * 0.85 + finalCoords.longitude * 0.15;
          finalCoords = GeodeticCoords(
            latitude: blendedLat,
            longitude: blendedLng,
            height: finalCoords.height,
          );
          isStationary = true;
        }
      }

      _lastStabilizedCoords = finalCoords;
      _isStationaryLocked = isStationary;

      // Dynamic calculation of floor gap, ground level Alt, and floors based on live GPS
      final geo = await GeocodingService.reverseGeocode(
        finalCoords.latitude,
        finalCoords.longitude,
        rawAltitude: finalCoords.height,
      );

      if (mounted) {
        setState(() {
          _latController.text = finalCoords.latitude.toStringAsFixed(6);
          _lngController.text = finalCoords.longitude.toStringAsFixed(6);
          _heightController.text = geo.groundAltitude.toStringAsFixed(1);
          _floorGapController.text = geo.floorGap.toStringAsFixed(1);
          _floorCount = geo.floorCount;

          if (!_userEditedId &&
              _nameController.text.trim().isEmpty &&
              geo.placeName.isNotEmpty) {
            _nameController.text = geo.placeName;
            _idController.text = geo.suggestedVenueId;
          }
          if (_cityController.text.trim().isEmpty && geo.city.isNotEmpty) {
            _cityController.text = geo.city;
          }
          if (_countryController.text.trim().isEmpty &&
              geo.country.isNotEmpty) {
            _countryController.text = geo.country;
          }
          _isFetchingGps = false;
          _isResolvingPlace = false;
        });

        final accText = '±${fixData.accuracy.toStringAsFixed(1)}m';
        final statusMessage = isStationary
            ? 'Coordinates locked at same place ($accText precision • Anti-jitter active)'
            : 'Live GPS synchronized: ${_latController.text}, ${_lngController.text} ($accText precision • Architecture calibrated)';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  isStationary
                      ? LucideIcons.shieldCheck
                      : LucideIcons.checkCircle2,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusMessage,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: isStationary
                ? const Color(0xFF0D9488)
                : const Color(0xFF16A34A),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      if (mounted) {
        setState(() {
          _isFetchingGps = false;
          _isResolvingPlace = false;
        });
      }
    }
  }

  void _saveVenue() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a Mall / Building Title.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final isEditing = widget.existingVenue != null;
    final cleanSlug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final id = _idController.text.trim().isNotEmpty
        ? _idController.text.trim()
        : (cleanSlug.isNotEmpty
              ? 'mall-$cleanSlug'
              : 'mall-venue-${DateTime.now().millisecondsSinceEpoch % 10000}');

    final lat =
        double.tryParse(_latController.text) ??
        widget.userCoords?.latitude ??
        0.0;
    final lng =
        double.tryParse(_lngController.text) ??
        widget.userCoords?.longitude ??
        0.0;

    final newMall = MallMetadata(
      id: id,
      name: name,
      city: _cityController.text.trim().isNotEmpty
          ? _cityController.text.trim()
          : 'Colombo',
      country: _countryController.text.trim().isNotEmpty
          ? _countryController.text.trim()
          : 'Sri Lanka',
      latitude: lat,
      longitude: lng,
      floorCount: _floorCount,
      packageSizeBytesMB: widget.existingVenue?.packageSizeBytesMB ?? 4.8,
      category: _categoryController.text.trim().isNotEmpty
          ? _categoryController.text.trim()
          : 'Shopping & Entertainment',
      rating: widget.existingVenue?.rating ?? '4.8',
      isDownloaded: widget.existingVenue?.isDownloaded ?? true,
      isActive: widget.existingVenue?.isActive ?? false,
    );

    widget.onSaveVenue(newMall);
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Venue package "${newMall.name}" ${isEditing ? 'updated' : 'registered'} successfully!',
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildFormFieldCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextInput({
    required String label,
    required TextEditingController controller,
    String? hintText,
    IconData? prefixIcon,
    int maxLines = 1,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          onChanged: onChanged,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF94A3B8),
              fontSize: 12.5,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: 16, color: const Color(0xFF64748B))
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 12,
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFF2563EB),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingVenue != null;
    final floorGapVal = double.tryParse(_floorGapController.text) ?? 4.5;
    final groundAltVal = double.tryParse(_heightController.text) ?? 0.0;
    final totalHeightVal = _floorCount * floorGapVal;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        surfaceTintColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Center(
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Icon(
                  LucideIcons.arrowLeft,
                  size: 18,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing ? 'Edit Venue Package' : 'Add New Venue Package',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              isEditing
                  ? 'Update venue & spatial boundary details'
                  : 'Configure venue & geodetic boundaries',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.x,
                        size: 13,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Cancel',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CARD 1: VENUE BASIC INFORMATION
            _buildFormFieldCard(
              title: 'VENUE BASIC INFORMATION',
              icon: LucideIcons.building2,
              iconColor: const Color(0xFF2563EB),
              children: [
                _buildTextInput(
                  label: 'Venue Unique Identifier (ID)',
                  controller: _idController,
                  hintText: _isResolvingPlace
                      ? 'Resolving venue ID...'
                      : 'e.g. mall-grand-atrium (auto-generated)',
                  prefixIcon: LucideIcons.hash,
                  onChanged: (val) {
                    _userEditedId = true;
                  },
                ),
                const SizedBox(height: 14),

                _buildTextInput(
                  label: 'Mall / Building Title',
                  controller: _nameController,
                  hintText: _isResolvingPlace
                      ? 'Resolving place name...'
                      : 'e.g. Colombo City Centre, One Galle Face',
                  prefixIcon: LucideIcons.building,
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: _buildTextInput(
                        label: 'City',
                        controller: _cityController,
                        hintText: _isResolvingPlace
                            ? 'Detecting city...'
                            : 'City',
                        prefixIcon: LucideIcons.mapPin,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTextInput(
                        label: 'Country',
                        controller: _countryController,
                        hintText: _isResolvingPlace
                            ? 'Detecting country...'
                            : 'Country',
                        prefixIcon: LucideIcons.globe,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                _buildTextInput(
                  label: 'Category / Taxonomy',
                  controller: _categoryController,
                  hintText: 'e.g. Shopping & Entertainment, Retail Mall',
                  prefixIcon: LucideIcons.tag,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // CARD 2: GEODETIC POSITIONING (WGS84)
            _buildFormFieldCard(
              title: 'GEODETIC POSITIONING (WGS84)',
              icon: LucideIcons.mapPin,
              iconColor: const Color(0xFF16A34A),
              children: [
                // Quick Picker & GPS sync Actions
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AdminOSMMapScreen(
                                userCoords:
                                    widget.userCoords ??
                                    const GeodeticCoords(
                                      latitude: 0.0,
                                      longitude: 0.0,
                                      height: 0.0,
                                    ),
                                destinations: const [],
                                isPickerMode: true,
                                onSelectCoordinates: (coords) {
                                  setState(() {
                                    _latController.text = coords.latitude
                                        .toStringAsFixed(6);
                                    _lngController.text = coords.longitude
                                        .toStringAsFixed(6);
                                    _lastStabilizedCoords = coords;
                                    _isStationaryLocked = false;
                                  });
                                  // Recalibrate altitude and architecture for picked coords
                                  GeocodingService.reverseGeocode(
                                    coords.latitude,
                                    coords.longitude,
                                    rawAltitude: coords.height,
                                  ).then((geo) {
                                    if (mounted) {
                                      setState(() {
                                        _heightController.text = geo
                                            .groundAltitude
                                            .toStringAsFixed(1);
                                        _floorGapController.text = geo.floorGap
                                            .toStringAsFixed(1);
                                        _floorCount = geo.floorCount;
                                      });
                                    }
                                  });
                                },
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                LucideIcons.map,
                                size: 14,
                                color: Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  'PICK ON MAP',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF16A34A),
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: (_isFetchingGps || _isResolvingPlace)
                            ? null
                            : _syncLiveGpsAndArchitecture,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isFetchingGps || _isResolvingPlace)
                                const Padding(
                                  padding: EdgeInsets.only(right: 5.0),
                                  child: SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                )
                              else ...[
                                const Icon(
                                  LucideIcons.navigation,
                                  size: 14,
                                  color: Color(0xFF2563EB),
                                ),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text(
                                  (_isFetchingGps || _isResolvingPlace)
                                      ? 'SAMPLING GPS...'
                                      : 'SYNC LIVE GPS',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF2563EB),
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 2 Coordinate Inputs
                Row(
                  children: [
                    Expanded(
                      child: _buildTextInput(
                        label: 'Latitude (°N)',
                        controller: _latController,
                        hintText: '8.502424',
                        onChanged: (_) {
                          _lastStabilizedCoords = null;
                          _isStationaryLocked = false;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTextInput(
                        label: 'Longitude (°E)',
                        controller: _lngController,
                        hintText: '81.181251',
                        onChanged: (_) {
                          _lastStabilizedCoords = null;
                          _isStationaryLocked = false;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // CARD 3: ELEVATION & MULTI-FLOOR ARCHITECTURE
            _buildFormFieldCard(
              title: 'ELEVATION & MULTI-FLOOR ARCHITECTURE',
              icon: LucideIcons.layers,
              iconColor: const Color(0xFF7C3AED),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildTextInput(
                        label: 'Ground Alt (m)',
                        controller: _heightController,
                        hintText: '45.0',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTextInput(
                        label: 'Floor Gap (m)',
                        controller: _floorGapController,
                        hintText: '4.5',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Floors',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<int>(
                            initialValue: _floorCount,
                            isExpanded: true,
                            dropdownColor: Colors.white,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                            ),
                            items: List.generate(10, (i) => i + 1).map((f) {
                              return DropdownMenuItem(
                                value: f,
                                child: Text('$f Lvl'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _floorCount = val;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Computed Architecture Preview Box
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Building Height:',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${totalHeightVal.toStringAsFixed(1)}m',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12.5,
                              color: const Color(0xFF0F172A),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Elevation Span (MSL):',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${groundAltVal.toStringAsFixed(1)}m → ${(groundAltVal + totalHeightVal).toStringAsFixed(1)}m',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: const Color(0xFF2563EB),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
          border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: _saveVenue,
          icon: Icon(
            isEditing ? LucideIcons.check : LucideIcons.plus,
            size: 18,
          ),
          label: Text(
            isEditing ? 'SAVE CHANGES' : 'REGISTER VENUE PACKAGE',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
