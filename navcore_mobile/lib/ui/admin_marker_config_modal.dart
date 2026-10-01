import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../data/building_data_service.dart';
import '../engine/ecef_engine.dart';

class AdminMarkerConfigModal extends StatefulWidget {
  final Function(ReferenceMarker) onSaveMarker;
  final GeodeticCoords? initialCoords;

  const AdminMarkerConfigModal({
    super.key,
    required this.onSaveMarker,
    this.initialCoords,
  });

  @override
  State<AdminMarkerConfigModal> createState() => _AdminMarkerConfigModalState();
}

class _AdminMarkerConfigModalState extends State<AdminMarkerConfigModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _markerIdController;
  late final TextEditingController _nameController;
  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  late final TextEditingController _heightController;
  int _selectedFloor = 1;
  final double _physicalWidth = 0.25;

  @override
  void initState() {
    super.initState();
    _markerIdController = TextEditingController(text: 'REF-ENTRANCE-MARKER-01');
    _nameController = TextEditingController(text: 'North Atrium Entrance');
    _latController = TextEditingController(
      text: widget.initialCoords?.latitude.toStringAsFixed(6) ?? '6.927079',
    );
    _lngController = TextEditingController(
      text: widget.initialCoords?.longitude.toStringAsFixed(6) ?? '79.845612',
    );
    _heightController = TextEditingController(
      text: widget.initialCoords?.height.toStringAsFixed(1) ?? '45.0',
    );
  }

  @override
  void dispose() {
    _markerIdController.dispose();
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 30,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'AR Reference Marker Config',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF0F172A),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              _buildTextField('Marker ID Code', _markerIdController),
              const SizedBox(height: 10),
              _buildTextField('Marker Name / Physical Location', _nameController),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildTextField('Latitude (°N)', _latController)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildTextField('Longitude (°E)', _lngController)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      'Base Height (m WGS84)',
                      _heightController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Floor Level',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF475569),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedFloor,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF0F172A),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
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
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                            ),
                          ),
                          items: List.generate(10, (idx) {
                            return DropdownMenuItem(
                              value: idx + 1,
                              child: Text('Floor ${idx + 1}', style: const TextStyle(color: Color(0xFF0F172A))),
                            );
                          }),
                          onChanged: (val) =>
                              setState(() => _selectedFloor = val ?? 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final marker = ReferenceMarker(
                      markerId: _markerIdController.text,
                      name: _nameController.text,
                      floorNumber: _selectedFloor,
                      position: GeodeticCoords(
                        latitude:
                            double.tryParse(_latController.text) ?? 6.927079,
                        longitude:
                            double.tryParse(_lngController.text) ?? 79.845612,
                        height: double.tryParse(_heightController.text) ?? 45.0,
                      ),
                      physicalWidthMeters: _physicalWidth,
                      physicalHeightMeters: _physicalWidth,
                      qrCodeData: 'NexNav:${_markerIdController.text}',
                    );
                    widget.onSaveMarker(marker);
                    Navigator.pop(context);
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.check, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'SAVE AR REFERENCE MARKER',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFF475569),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFF0F172A),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
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
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
          validator: (val) =>
              val == null || val.isEmpty ? 'Required field' : null,
        ),
      ],
    );
  }
}
