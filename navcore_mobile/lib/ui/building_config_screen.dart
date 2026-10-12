import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';

import '../engine/floor_tracker.dart';
import '../engine/ecef_engine.dart';
import '../data/geocoding_service.dart';

class BuildingConfigScreen extends StatefulWidget {
  final BuildingElevationProfile? profile;
  final GeodeticCoords? userCoords;
  final ValueChanged<BuildingElevationProfile>? onProfileUpdated;

  const BuildingConfigScreen({
    super.key,
    this.profile,
    this.userCoords,
    this.onProfileUpdated,
  });

  @override
  State<BuildingConfigScreen> createState() => _BuildingConfigScreenState();
}

class _BuildingConfigScreenState extends State<BuildingConfigScreen> {
  late BuildingElevationProfile _currentProfile;
  GeodeticCoords? _currentCoords;
  bool _isLoading = false;
  String _locationCity = '';

  @override
  void initState() {
    super.initState();
    _currentCoords = widget.userCoords;
    _currentProfile = widget.profile ?? defaultBuildingProfile;

    // Automatically resolve elevation bands from user's current physical location if unconfigured
    if (_currentProfile.floors.isEmpty || _currentProfile.name.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoResolveElevationFromRealLocation();
      });
    }
  }

  Future<void> _autoResolveElevationFromRealLocation() async {
    setState(() => _isLoading = true);

    try {
      GeodeticCoords? target = _currentCoords;
      if (target == null || target.latitude == 0.0) {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission != LocationPermission.denied &&
              permission != LocationPermission.deniedForever) {
            final last = await Geolocator.getLastKnownPosition();
            if (last != null && last.latitude != 0.0) {
              target = GeodeticCoords(
                latitude: last.latitude,
                longitude: last.longitude,
                height: last.altitude,
              );
            } else {
              final pos = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: Duration(seconds: 8),
                ),
              );
              target = GeodeticCoords(
                latitude: pos.latitude,
                longitude: pos.longitude,
                height: pos.altitude,
              );
            }
          }
        }
      }

      if (target != null && target.latitude != 0.0) {
        _currentCoords = target;

        final geo = await GeocodingService.reverseGeocode(
          target.latitude,
          target.longitude,
          rawAltitude: target.height,
        );

        final String venueName = geo.placeName.isNotEmpty
            ? geo.placeName
            : (geo.city.isNotEmpty ? '${geo.city} Real Location Profile' : 'Current Location Profile');

        final double baseAltitude = geo.groundAltitude;
        final double storyGap = geo.floorGap;
        final int floorCount = geo.floorCount;

        final realFloors = List.generate(floorCount, (i) {
          final int flrNum = i + 1;
          final double relHeight = i * storyGap;
          final double absHeight = baseAltitude + relHeight;
          return FloorLevelConfig(
            floorId: 'fl-$flrNum',
            floorNumber: flrNum,
            name: flrNum == 1 ? 'Level 1 (Ground)' : 'Level $flrNum',
            relativeVectorMeters: relHeight,
            absoluteHeightMeters: absHeight,
            bandMinMeters: absHeight - (storyGap / 2),
            bandMaxMeters: absHeight + (storyGap / 2),
            storesCount: 0,
            ceilingHeightMeters: storyGap,
          );
        });

        final updated = BuildingElevationProfile(
          buildingId: geo.suggestedVenueId.isNotEmpty
              ? geo.suggestedVenueId
              : 'venue-${target.latitude.toStringAsFixed(4)}-${target.longitude.toStringAsFixed(4)}',
          name: venueName,
          entranceBaseAnchorHeight: baseAltitude,
          floorGapMeters: storyGap,
          floors: realFloors,
        );

        if (mounted) {
          setState(() {
            _currentProfile = updated;
            _locationCity = '${geo.city}, ${geo.country}';
            _isLoading = false;
          });
          widget.onProfileUpdated?.call(updated);
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRealFloors = _currentProfile.floors.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(
          'Building Geodetic Elevation Config',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
                  )
                : const Icon(LucideIcons.refreshCw, color: Color(0xFF2563EB)),
            tooltip: 'Sync Live GPS Location',
            onPressed: _isLoading ? null : _autoResolveElevationFromRealLocation,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Live Real Location Anchor Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x060F172A),
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
                        _currentProfile.name.isNotEmpty
                            ? _currentProfile.name
                            : (_locationCity.isNotEmpty ? _locationCity : 'Current Location Reference'),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.navigation, size: 10, color: Color(0xFF2563EB)),
                          const SizedBox(width: 4),
                          Text(
                            'LIVE GPS',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_currentCoords != null && _currentCoords!.latitude != 0.0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'GPS: ${_currentCoords!.latitude.toStringAsFixed(6)}°, ${_currentCoords!.longitude.toStringAsFixed(6)}°',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Base Anchor Height: ${_currentProfile.entranceBaseAnchorHeight.toStringAsFixed(1)}m WGS84 | Story Gap: ${_currentProfile.floorGapMeters.toStringAsFixed(1)}m',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _autoResolveElevationFromRealLocation,
                  icon: const Icon(LucideIcons.crosshair, size: 14, color: Color(0xFF2563EB)),
                  label: Text(
                    _isLoading ? 'CALCULATING REAL LOCATION...' : 'RE-CALCULATE FROM REAL DEVICE GPS',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 38),
                    side: const BorderSide(color: Color(0xFFBFDBFE)),
                    backgroundColor: const Color(0xFFEFF6FF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MAPPED GEODETIC ELEVATION BANDS',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF64748B),
                  letterSpacing: 1.0,
                ),
              ),
              if (hasRealFloors)
                Text(
                  '${_currentProfile.floors.length} Real Floors',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF059669),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          if (_isLoading)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Color(0xFF2563EB)),
                  const SizedBox(height: 14),
                  Text(
                    'Calculating geodetic elevation bands from your location...',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else if (!hasRealFloors)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(LucideIcons.mapPinOff, size: 36, color: Color(0xFF94A3B8)),
                  const SizedBox(height: 12),
                  Text(
                    'No Elevation Bands Configured',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap the button above to automatically detect real elevation bands based on your current physical GPS coordinates.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            )
          else
            ..._currentProfile.floors.map((floor) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0.5,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFEFF6FF),
                      child: Text(
                        floor.floorNumber < 0
                            ? 'B${floor.floorNumber.abs()}'
                            : 'F${floor.floorNumber}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                      ),
                    ),
                    title: Text(
                      floor.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: Text(
                      'Band: ${floor.bandMinMeters.toStringAsFixed(1)}m – ${floor.bandMaxMeters.toStringAsFixed(1)}m',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    trailing: Text(
                      '${floor.absoluteHeightMeters.toStringAsFixed(1)}m',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                        fontSize: 14,
                      ),
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
