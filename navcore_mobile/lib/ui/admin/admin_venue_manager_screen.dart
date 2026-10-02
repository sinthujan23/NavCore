import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/mall_database_service.dart';
import '../../engine/ecef_engine.dart';

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
  State<AdminVenueManagerScreen> createState() => _AdminVenueManagerScreenState();
}

class _AdminVenueManagerScreenState extends State<AdminVenueManagerScreen> {
  late List<MallMetadata> _venues;

  @override
  void initState() {
    super.initState();
    _venues = widget.mallService.catalog;
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

  void _showAddVenueModal() {
    final idController = TextEditingController(text: 'mall-colombo-city-centre');
    final nameController = TextEditingController(text: 'Colombo City Centre');
    final cityController = TextEditingController(text: 'Colombo');
    final countryController = TextEditingController(text: 'Sri Lanka');
    final initialLat = widget.userCoords?.latitude != 0.0 && widget.userCoords?.latitude != null ? widget.userCoords!.latitude : null;
    final initialLng = widget.userCoords?.longitude != 0.0 && widget.userCoords?.longitude != null ? widget.userCoords!.longitude : null;

    final latController = TextEditingController(
      text: initialLat != null ? initialLat.toStringAsFixed(6) : '',
    );
    final lngController = TextEditingController(
      text: initialLng != null ? initialLng.toStringAsFixed(6) : '',
    );
    final initialAlt = widget.userCoords?.height != 0.0 && widget.userCoords?.height != null ? widget.userCoords!.height : 45.0;
    final heightController = TextEditingController(text: initialAlt.toStringAsFixed(1));
    final floorGapController = TextEditingController(text: '4.5');
    int floorCount = 5;
    bool isFetchingGps = false;

    if (initialLat == null || initialLng == null) {
      _getLiveGpsCoordinates(context).then((liveCoords) {
        if (liveCoords != null && mounted) {
          latController.text = liveCoords.latitude.toStringAsFixed(6);
          lngController.text = liveCoords.longitude.toStringAsFixed(6);
          heightController.text = liveCoords.height.toStringAsFixed(1);
        }
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                          'Register New Mall Package',
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
                    _buildTextField('Venue Unique Identifier (ID)', idController),
                    const SizedBox(height: 10),
                    _buildTextField('Mall / Building Title', nameController),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _buildTextField('City', cityController)),
                        const SizedBox(width: 10),
                        Expanded(child: _buildTextField('Country', countryController)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'GEODETIC COORDINATES',
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
                            child: InkWell(
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
                                          isFetchingGps = false;
                                        });
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('GPS set to: ${liveCoords.latitude.toStringAsFixed(6)}, ${liveCoords.longitude.toStringAsFixed(6)}'),
                                              backgroundColor: const Color(0xFF16A34A),
                                              duration: const Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      } else if (widget.userCoords != null) {
                                        setModalState(() {
                                          latController.text = widget.userCoords!.latitude.toStringAsFixed(6);
                                          lngController.text = widget.userCoords!.longitude.toStringAsFixed(6);
                                          isFetchingGps = false;
                                        });
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Loaded position from current active session.'),
                                              backgroundColor: Color(0xFF2563EB),
                                              duration: Duration(seconds: 2),
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
                                      isFetchingGps ? 'LOCATING...' : 'USE REAL DEVICE GPS',
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
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _buildTextField('Ground WGS84 Alt (m)', heightController)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildTextField('Floor Gap (m)', floorGapController)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Floors',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<int>(
                                initialValue: floorCount,
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
                                items: List.generate(10, (i) => i + 1).map((f) {
                                  return DropdownMenuItem(
                                    value: f,
                                    child: Text('$f Lvl'),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setModalState(() {
                                      floorCount = val;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(LucideIcons.binary, size: 14, color: Color(0xFF16A34A)),
                              const SizedBox(width: 6),
                              Text(
                                'Geometric WGS84 Floor Height Breakdown',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF15803D),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Base WGS84 Altitude: ${(double.tryParse(heightController.text) ?? 45.0).toStringAsFixed(1)}m  •  Story Gap: ${(double.tryParse(floorGapController.text) ?? 4.5).toStringAsFixed(1)}m',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              color: const Color(0xFF166534),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: List.generate(floorCount, (i) {
                              final int flr = i + 1;
                              final double baseAlt = double.tryParse(heightController.text) ?? 45.0;
                              final double gap = double.tryParse(floorGapController.text) ?? 4.5;
                              final double flrHeight = baseAlt + (flr - 1) * gap;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF86EFAC)),
                                ),
                                child: Text(
                                  'Floor $flr: ${flrHeight.toStringAsFixed(1)}m WGS84',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF14532D),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        final newMall = MallMetadata(
                          id: idController.text.trim(),
                          name: nameController.text.trim(),
                          city: cityController.text.trim(),
                          country: countryController.text.trim(),
                          latitude: double.tryParse(latController.text) ?? 6.917420,
                          longitude: double.tryParse(lngController.text) ?? 79.856100,
                          floorCount: floorCount,
                          packageSizeBytesMB: 4.8,
                          category: 'Shopping & Entertainment',
                          rating: '4.8',
                          isDownloaded: true,
                          isActive: false,
                        );

                        setState(() {
                          _venues.add(newMall);
                        });

                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Venue package "${newMall.name}" registered successfully!'),
                            backgroundColor: const Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: Text(
                        'REGISTER VENUE PACKAGE',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
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

  Widget _buildTextField(String label, TextEditingController controller) {
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
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Venue Package Manager',
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
                onTap: _showAddVenueModal,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF059669), Color(0xFF047857)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF059669).withValues(alpha: 0.3),
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
                        'ADD NEW MALL',
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
      body: ListView.builder(
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
                color: mall.isActive ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: mall.isActive
                            ? const Color(0xFFECFDF5)
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: mall.isActive ? const Color(0xFFA7F3D0) : const Color(0xFFBFDBFE),
                        ),
                      ),
                      child: Text(
                        mall.isActive ? 'ACTIVE VENUE' : 'REGISTERED',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: mall.isActive ? const Color(0xFF047857) : const Color(0xFF1D4ED8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${mall.city}, ${mall.country} • ${mall.floorCount} Floors • ${mall.packageSizeBytesMB} MB Map Package',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                  ),
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
                          color: mall.isActive ? const Color(0xFF059669) : const Color(0xFF2563EB),
                        ),
                        label: Text(
                          mall.isActive ? 'Venue Currently Active' : 'Activate Venue Map',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: mall.isActive ? const Color(0xFF059669) : const Color(0xFF2563EB),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(
                            color: mall.isActive ? const Color(0xFFA7F3D0) : const Color(0xFFBFDBFE),
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
