import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

  void _showAddVenueModal() {
    final idController = TextEditingController(text: 'mall-colombo-city-centre');
    final nameController = TextEditingController(text: 'Colombo City Centre');
    final cityController = TextEditingController(text: 'Colombo');
    final countryController = TextEditingController(text: 'Sri Lanka');
    final latController = TextEditingController(
      text: widget.userCoords?.latitude.toStringAsFixed(6) ?? '6.917420',
    );
    final lngController = TextEditingController(
      text: widget.userCoords?.longitude.toStringAsFixed(6) ?? '79.856100',
    );
    int floorCount = 5;

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
                        Text(
                          'GEODETIC COORDINATES',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF64748B),
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (widget.userCoords != null)
                          InkWell(
                            onTap: () {
                              setModalState(() {
                                latController.text = widget.userCoords!.latitude.toStringAsFixed(6);
                                lngController.text = widget.userCoords!.longitude.toStringAsFixed(6);
                              });
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
                                  const Icon(LucideIcons.navigation, size: 12, color: Color(0xFF2563EB)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'USE REAL DEVICE GPS',
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: _buildTextField('Latitude (°N)', latController)),
                        const SizedBox(width: 10),
                        Expanded(child: _buildTextField('Longitude (°E)', lngController)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total Floor Levels',
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
                                      horizontal: 12, vertical: 10),
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
                                    child: Text('$f Floors'),
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
          'Venue & Mall Package Manager',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF059669),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: const Icon(LucideIcons.plus, color: Colors.white, size: 18),
              onPressed: _showAddVenueModal,
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
