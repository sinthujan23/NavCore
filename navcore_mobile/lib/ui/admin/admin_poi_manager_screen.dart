import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/destinations.dart';
import '../../engine/ecef_engine.dart';

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

  void _showAddEditPoiModal([DestinationPOI? existingPoi]) {
    final isEditing = existingPoi != null;
    final nameController = TextEditingController(text: existingPoi?.name ?? '');
    final categoryController = TextEditingController(
        text: existingPoi?.category ?? 'RETAIL & FASHION');
    final descController =
        TextEditingController(text: existingPoi?.description ?? '');
    final latController = TextEditingController(
        text: existingPoi?.location.latitude.toString() ?? '6.927079');
    final lngController = TextEditingController(
        text: existingPoi?.location.longitude.toString() ?? '79.845612');
    final heightController = TextEditingController(
        text: existingPoi?.location.height.toString() ?? '45.0');
    int floorNumber = existingPoi?.floorNumber ?? 1;
    double rating = existingPoi?.rating ?? 4.5;
    String openStatus = existingPoi?.openStatus ?? 'Open Today: 10 AM - 10 PM';

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
                        Text(
                          'GEODETIC POSITION',
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
                                heightController.text = widget.userCoords!.height.toStringAsFixed(1);
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
                        Expanded(child: _buildTextField('Latitude', latController)),
                        const SizedBox(width: 10),
                        Expanded(child: _buildTextField('Longitude', lngController)),
                      ],
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
                                double.tryParse(latController.text) ?? 6.927079,
                            longitude:
                                double.tryParse(lngController.text) ?? 79.845612,
                            height:
                                double.tryParse(heightController.text) ?? 45.0,
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
          'POI & Store Directory Manager',
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
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: const Icon(LucideIcons.plus, color: Colors.white, size: 18),
              onPressed: () => _showAddEditPoiModal(),
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
