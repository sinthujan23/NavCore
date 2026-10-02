import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/destinations.dart';
import '../../engine/ecef_engine.dart';
import '../../engine/floor_tracker.dart';
import 'admin_osm_map_screen.dart';

class AdminPOIManagerScreen extends StatefulWidget {
  final List<DestinationPOI> destinations;
  final Function(DestinationPOI newPoi) onAddPoi;
  final Function(DestinationPOI updatedPoi) onUpdatePoi;
  final Function(String poiId) onDeletePoi;
  final GeodeticCoords? userCoords;

  const AdminPOIManagerScreen({
    super.key,
    required this.destinations,
    required this.onAddPoi,
    required this.onUpdatePoi,
    required this.onDeletePoi,
    this.userCoords,
  });

  @override
  State<AdminPOIManagerScreen> createState() => _AdminPOIManagerScreenState();
}

class _AdminPOIManagerScreenState extends State<AdminPOIManagerScreen> {
  late List<DestinationPOI> _poiList;
  String _selectedCategory = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final List<String> _categories = [
    'ALL',
    'FOOD & DRINK',
    'RETAIL & FASHION',
    'TECH & ELECTRONICS',
    'ENTERTAINMENT',
    'SERVICES',
  ];

  @override
  void initState() {
    super.initState();
    _poiList = List.from(widget.destinations);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DestinationPOI> get _filteredPois {
    return _poiList.where((poi) {
      final matchesCat = _selectedCategory == 'ALL' ||
          poi.category.toUpperCase().contains(_selectedCategory);
      final matchesSearch = _searchQuery.isEmpty ||
          poi.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          poi.description.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCat && matchesSearch;
    }).toList();
  }

  Future<GeodeticCoords?> _getLiveGpsCoordinates(BuildContext context) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS Location service is disabled on device. Please enable location.'),
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
          if (context.mounted) {
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
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is permanently denied in settings.'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return GeodeticCoords(
        latitude: position.latitude,
        longitude: position.longitude,
        height: position.altitude,
      );
    } catch (e) {
      if (context.mounted) {
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

  void _showAddEditPoiModal([DestinationPOI? existingPoi]) {
    final isEditing = existingPoi != null;
    final nameController = TextEditingController(text: existingPoi?.name ?? '');
    final categoryController = TextEditingController(
        text: existingPoi?.category ?? 'RETAIL & FASHION');
    final descController =
        TextEditingController(text: existingPoi?.description ?? '');

    int floorNumber = existingPoi?.floorNumber ?? 1;
    double floorOffset(int flr) => flr < 0 ? (flr * 4.5) : ((flr - 1) * 4.5);

    double activeBaseAltitude;
    if (existingPoi != null) {
      activeBaseAltitude = existingPoi.location.height - floorOffset(existingPoi.floorNumber);
    } else if (widget.userCoords != null && widget.userCoords!.height != 0.0) {
      activeBaseAltitude = widget.userCoords!.height;
    } else {
      activeBaseAltitude = 45.0;
    }

    final initialLat = existingPoi?.location.latitude ??
        (widget.userCoords != null && widget.userCoords!.latitude != 0.0 ? widget.userCoords!.latitude : null);
    final initialLng = existingPoi?.location.longitude ??
        (widget.userCoords != null && widget.userCoords!.longitude != 0.0 ? widget.userCoords!.longitude : null);
    final initialAlt = existingPoi?.location.height ?? (activeBaseAltitude + floorOffset(floorNumber));

    final latController = TextEditingController(
        text: initialLat != null ? initialLat.toStringAsFixed(6) : '');
    final lngController = TextEditingController(
        text: initialLng != null ? initialLng.toStringAsFixed(6) : '');
    final heightController = TextEditingController(
        text: initialAlt.toStringAsFixed(1));
    double rating = existingPoi?.rating ?? 4.5;
    String openStatus = existingPoi?.openStatus ?? 'Open Today: 10 AM - 10 PM';
    bool isFetchingGps = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void recalculateHeight() {
              final double currentOffset = floorOffset(floorNumber);
              final double computedHeight = activeBaseAltitude + currentOffset;
              heightController.text = computedHeight.toStringAsFixed(1);
            }

            // Auto-fetch live device hardware GPS & barometer altitude if creating a new POI and initial coordinates are blank
            if (!isEditing && (latController.text.isEmpty || lngController.text.isEmpty)) {
              _getLiveGpsCoordinates(context).then((liveCoords) {
                if (liveCoords != null && mounted) {
                  setModalState(() {
                    latController.text = liveCoords.latitude.toStringAsFixed(6);
                    lngController.text = liveCoords.longitude.toStringAsFixed(6);
                    final autoDetectedFloor = resolveFloorByHeight(liveCoords.height);
                    floorNumber = autoDetectedFloor.floorNumber;
                    activeBaseAltitude = liveCoords.height - floorOffset(floorNumber);
                    recalculateHeight();
                  });
                }
              });
            }

            final double currentOffset = floorOffset(floorNumber);
            final String floorLabel = floorNumber < 0 ? 'B${floorNumber.abs()}' : 'Floor $floorNumber';
            final String offsetStr = '${currentOffset >= 0 ? '+' : ''}${currentOffset.toStringAsFixed(1)}m';

            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 20,
                right: 20,
                top: 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing ? 'Edit Store / POI' : 'Add New POI Destination',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.x, color: Color(0xFF64748B)),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTextField('Store / POI Name', nameController),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Category',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                initialValue: categoryController.text,
                                isExpanded: true,
                                dropdownColor: Colors.white,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF0F172A),
                                ),
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                ),
                                items: _categories
                                    .where((c) => c != 'ALL')
                                    .map((c) => DropdownMenuItem(
                                          value: c,
                                          child: Text(c, overflow: TextOverflow.ellipsis),
                                        ))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setModalState(() {
                                      categoryController.text = val;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Floor Level',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<int>(
                                key: ValueKey('floor-dropdown-$floorNumber'),
                                initialValue: floorNumber,
                                isExpanded: true,
                                dropdownColor: Colors.white,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF0F172A),
                                ),
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                ),
                                items: List.generate(7, (i) => i - 1).map((f) {
                                  return DropdownMenuItem(
                                    value: f,
                                    child: Text(f < 0 ? 'B${f.abs()}' : 'Floor $f'),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setModalState(() {
                                      floorNumber = val;
                                      recalculateHeight();
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildTextField('Description / Tags', descController),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'GEODETIC POSITION',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF64748B),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => AdminOSMMapScreen(
                                          userCoords: widget.userCoords ?? const GeodeticCoords(latitude: 6.9175, longitude: 79.8530, height: 0.0),
                                          destinations: _poiList,
                                          isPickerMode: true,
                                          onSelectCoordinates: (coords) {
                                            setModalState(() {
                                              latController.text = coords.latitude.toStringAsFixed(6);
                                              lngController.text = coords.longitude.toStringAsFixed(6);
                                            });
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0FDF4),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFBBF7D0)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(LucideIcons.map, size: 12, color: Color(0xFF16A34A)),
                                        const SizedBox(width: 4),
                                        Text(
                                          'PICK ON OSM MAP',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF16A34A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: isFetchingGps
                                    ? null
                                    : () async {
                                        setModalState(() {
                                          isFetchingGps = true;
                                        });

                                        final liveCoords = await _getLiveGpsCoordinates(context);

                                        if (liveCoords != null) {
                                          setModalState(() {
                                            latController.text = liveCoords.latitude.toStringAsFixed(6);
                                            lngController.text = liveCoords.longitude.toStringAsFixed(6);
                                            final autoDetectedFloor = resolveFloorByHeight(liveCoords.height);
                                            floorNumber = autoDetectedFloor.floorNumber;
                                            activeBaseAltitude = liveCoords.height - floorOffset(floorNumber);
                                            recalculateHeight();
                                            isFetchingGps = false;
                                          });
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    'Live location tracked: ${liveCoords.latitude.toStringAsFixed(6)}, ${liveCoords.longitude.toStringAsFixed(6)} (Situated Floor $floorNumber, Alt: ${liveCoords.height.toStringAsFixed(1)}m)'),
                                                backgroundColor: const Color(0xFF16A34A),
                                                duration: const Duration(seconds: 3),
                                              ),
                                            );
                                          }
                                        } else if (widget.userCoords != null) {
                                          setModalState(() {
                                            latController.text = widget.userCoords!.latitude.toStringAsFixed(6);
                                            lngController.text = widget.userCoords!.longitude.toStringAsFixed(6);
                                            final autoDetectedFloor = resolveFloorByHeight(widget.userCoords!.height);
                                            floorNumber = autoDetectedFloor.floorNumber;
                                            activeBaseAltitude = widget.userCoords!.height - floorOffset(floorNumber);
                                            recalculateHeight();
                                            isFetchingGps = false;
                                          });
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Loaded position from current active session (Floor $floorNumber).'),
                                                backgroundColor: const Color(0xFF2563EB),
                                                duration: const Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        } else {
                                          setModalState(() {
                                            isFetchingGps = false;
                                          });
                                        }
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFBFDBFE)),
                                  ),
                                  child: Row(
                                    children: [
                                      if (isFetchingGps)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 4.0),
                                          child: SizedBox(
                                            width: 10,
                                            height: 10,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFF2563EB),
                                            ),
                                          ),
                                        )
                                      else ...[
                                        const Icon(LucideIcons.navigation, size: 12, color: Color(0xFF2563EB)),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        isFetchingGps ? 'LOCATING...' : 'GPS',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF2563EB),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: _buildTextField('Latitude (°N)', latController)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildTextField('Longitude (°E)', lngController)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildTextField(
                            'WGS84 Alt (m)',
                            heightController,
                            onChanged: (val) {
                              final parsed = double.tryParse(val);
                              if (parsed != null) {
                                setModalState(() {
                                  activeBaseAltitude = parsed - floorOffset(floorNumber);
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBAE6FD)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.layers, size: 14, color: Color(0xFF0284C7)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'WGS84 Floor Height: ${heightController.text}m  •  (Base Alt: ${activeBaseAltitude.toStringAsFixed(1)}m, $floorLabel Offset: $offsetStr)',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF0369A1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        if (nameController.text.trim().isEmpty) return;

                        final newPoi = DestinationPOI(
                          id: isEditing
                              ? existingPoi.id
                              : 'poi-${DateTime.now().millisecondsSinceEpoch}',
                          name: nameController.text.trim(),
                          category: categoryController.text,
                          floorNumber: floorNumber,
                          rating: rating,
                          location: GeodeticCoords(
                            latitude:
                                double.tryParse(latController.text) ?? (widget.userCoords?.latitude ?? 0.0),
                            longitude:
                                double.tryParse(lngController.text) ?? (widget.userCoords?.longitude ?? 0.0),
                            height:
                                double.tryParse(heightController.text) ?? (widget.userCoords?.height ?? 10.0),
                          ),
                          description: descController.text.trim(),
                          openStatus: openStatus,
                        );

                        setState(() {
                          if (isEditing) {
                            final idx =
                                _poiList.indexWhere((p) => p.id == existingPoi.id);
                            if (idx != -1) _poiList[idx] = newPoi;
                            widget.onUpdatePoi(newPoi);
                          } else {
                            _poiList.insert(0, newPoi);
                            widget.onAddPoi(newPoi);
                          }
                        });

                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                '${newPoi.name} ${isEditing ? 'updated' : 'added'} successfully!'),
                            backgroundColor: const Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: Text(
                        isEditing ? 'SAVE CHANGES' : 'CREATE POI DESTINATION',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          onChanged: onChanged,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredPois;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'POI Store Directory',
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showAddEditPoiModal(),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.plus, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'ADD NEW SHOP',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3,
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
      body: Column(
        children: [
          // Search & Filter Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFF0F172A), fontSize: 13),
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search POI stores by name, floor or category...',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    prefixIcon: const Icon(LucideIcons.search, size: 18, color: Color(0xFF2563EB)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                      borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            cat,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? Colors.white : const Color(0xFF475569),
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: const Color(0xFF2563EB),
                          backgroundColor: const Color(0xFFF1F5F9),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                          ),
                          onSelected: (val) {
                            if (val) setState(() => _selectedCategory = cat);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // POI List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.searchX, color: Color(0xFF94A3B8), size: 36),
                        const SizedBox(height: 8),
                        Text(
                          'No POIs matched your filter criteria',
                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, idx) {
                      final poi = filtered[idx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0A0F172A),
                              blurRadius: 10,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Center(
                                child: Text(
                                  poi.floorNumber < 0
                                      ? 'B${poi.floorNumber.abs()}'
                                      : 'F${poi.floorNumber}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF2563EB),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    poi.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          poi.category,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF2563EB),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(LucideIcons.star, size: 12, color: Color(0xFFD97706)),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${poi.rating}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.edit2, size: 16, color: Color(0xFF2563EB)),
                              onPressed: () => _showAddEditPoiModal(poi),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.trash2, size: 16, color: Color(0xFFEF4444)),
                              onPressed: () {
                                setState(() {
                                  _poiList.removeWhere((p) => p.id == poi.id);
                                });
                                widget.onDeletePoi(poi.id);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
