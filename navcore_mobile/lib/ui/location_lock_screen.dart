import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../engine/ecef_engine.dart';
import '../engine/real_sensor_service.dart';
import '../data/mall_database_service.dart';

class LocationLockScreen extends StatefulWidget {
  final RealSensorService sensorService;
  final MallDatabaseService mallService;
  final Function(
    GeodeticCoords coords,
    MallMetadata? detectedMall, [
    FullMallPackage? package,
  ]) onSetupCompleted;

  const LocationLockScreen({
    super.key,
    required this.sensorService,
    required this.mallService,
    required this.onSetupCompleted,
  });

  @override
  State<LocationLockScreen> createState() => _LocationLockScreenState();
}

class _LocationLockScreenState extends State<LocationLockScreen> {
  int _currentStep =
      1; // 1: Location, 2: Mall Detection, 3: Downloading, 4: Ready
  GeodeticCoords? _acquiredCoords;
  MallMetadata? _detectedMall;
  FullMallPackage? _loadedPackage;
  MallMetadata? _nearestMallOutside500m;
  double? _nearestDistanceMeters;
  double _downloadProgress = 0.0;
  String _statusText = 'Finding your location...';
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _startStartupFlow();
  }

  Future<void> _startStartupFlow() async {
    setState(() {
      _isProcessing = true;
      _currentStep = 1;
      _statusText = 'Finding your location...';
      _detectedMall = null;
      _loadedPackage = null;
      _nearestMallOutside500m = null;
      _nearestDistanceMeters = null;
      _downloadProgress = 0.0;
    });

    // Step 1: Request Location
    final report = await widget.sensorService.requestAllPermissions();
    if (report.hasLocationPermission) {
      final pos = await widget.sensorService.getLastKnownOrCurrentPosition();
      if (pos != null) {
        _acquiredCoords = pos;
      }
    }

    _acquiredCoords ??= const GeodeticCoords(
      latitude: 0.0,
      longitude: 0.0,
      height: 0.0,
    );

    // Step 2: Detect Mall strictly within 500m of User's Current Location
    final mallsWithin500m = await widget.mallService.getMallsWithinRadius(
      _acquiredCoords!,
      radiusMeters: 500.0,
    );

    if (mallsWithin500m.isNotEmpty) {
      // Find the mall with the minimum distance to user's coordinates
      mallsWithin500m.sort((a, b) {
        final distA = widget.mallService.calculateDistanceToMall(
          _acquiredCoords!,
          a,
        );
        final distB = widget.mallService.calculateDistanceToMall(
          _acquiredCoords!,
          b,
        );
        return distA.compareTo(distB);
      });

      _detectedMall = mallsWithin500m.first;
      final distM = widget.mallService.calculateDistanceToMall(
        _acquiredCoords!,
        _detectedMall!,
      );
      _statusText =
          'Found ${_detectedMall!.name} (${distM.toInt()}m away, within 500m)!';

      setState(() {
        _currentStep = 2;
      });
      await Future.delayed(const Duration(milliseconds: 600));

      // Step 3: Load Mall Map (within 500m only)
      setState(() {
        _currentStep = 3;
        _statusText = 'Loading map for ${_detectedMall!.name}...';
      });

      _loadedPackage = await widget.mallService.autoDownloadAndActivateNearestMall(
        _acquiredCoords!,
        maxRadiusMeters: 500.0,
        isAdmin: false,
        preferredMallId: _detectedMall?.id,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      if (_loadedPackage != null && _loadedPackage!.metadata.id.isNotEmpty) {
        _detectedMall = _loadedPackage!.metadata;
      }

      // Step 4: Completed
      setState(() {
        _currentStep = 4;
        _downloadProgress = 1.0;
        _isProcessing = false;
        _statusText = 'Map ready! You can now start navigating.';
      });
    } else {
      // Above 500m: malls above 500m are NOT loaded in maps!
      final nearest = widget.mallService.findNearestMall(_acquiredCoords!);
      final distM = widget.mallService.calculateDistanceToMall(
        _acquiredCoords!,
        nearest,
      );
      final hasGps =
          _acquiredCoords!.latitude != 0.0 && _acquiredCoords!.longitude != 0.0;

      setState(() {
        _detectedMall = null;
        _nearestMallOutside500m = nearest.id.isNotEmpty ? nearest : null;
        _nearestDistanceMeters = nearest.id.isNotEmpty ? distM : null;
        _currentStep = 4;
        _downloadProgress = 0.0;
        _isProcessing = false;
        _statusText = hasGps
            ? 'Outside 500m coverage (${nearest.name} is ${distM < 1000 ? "${distM.toInt()}m" : "${(distM / 1000).toStringAsFixed(1)}km"} away). Maps only auto-load within 500m.'
            : 'No GPS location detected. Move within 500m of a mall to load maps.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Logo & Title Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x332563EB),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      LucideIcons.compass,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NexNav',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const Text(
                        'Smart Indoor Navigation',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 36),

              Text(
                'Welcome to NexNav',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Setting up your indoor navigation:',
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),

              const SizedBox(height: 28),

              // Steps List
              _buildStepRow(
                1,
                'Finding Your Location',
                _acquiredCoords != null
                    ? 'Location confirmed'
                    : 'Finding your device position...',
                LucideIcons.navigation,
              ),
              const SizedBox(height: 14),
              _buildStepRow(
                2,
                'Identifying Your Mall',
                _detectedMall != null
                    ? '${_detectedMall!.name} (Within 500m)'
                    : (_nearestMallOutside500m != null
                          ? 'Nearest: ${_nearestMallOutside500m!.name} (${_nearestDistanceMeters != null ? (_nearestDistanceMeters! < 1000 ? "${_nearestDistanceMeters!.toInt()}m" : "${(_nearestDistanceMeters! / 1000).toStringAsFixed(1)}km") : ">500m"})'
                          : 'Looking for nearby mall...'),
                LucideIcons.building2,
              ),
              const SizedBox(height: 14),
              _buildStepRow(
                3,
                'Loading Indoor Map',
                _detectedMall != null
                    ? (_currentStep >= 3
                          ? '${(_downloadProgress * 100).toInt()}% Loaded'
                          : 'Preparing map...')
                    : (_currentStep == 4
                          ? 'Not loaded (Outside 500m limit)'
                          : 'Preparing map...'),
                LucideIcons.downloadCloud,
              ),

              const SizedBox(height: 24),

              // Download Progress Bar
              if (_currentStep == 3) ...[
                LinearProgressIndicator(
                  value: _downloadProgress,
                  backgroundColor: const Color(0xFFE2E8F0),
                  color: const Color(0xFF2563EB),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 12),
              ],

              // Status Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    if (_isProcessing)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF2563EB),
                        ),
                      )
                    else
                      Icon(
                        _detectedMall != null
                            ? LucideIcons.checkCircle2
                            : LucideIcons.info,
                        color: _detectedMall != null
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFF59E0B),
                        size: 20,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusText,
                        style: TextStyle(
                          color: _isProcessing
                              ? const Color(0xFF2563EB)
                              : (_detectedMall != null
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFB45309)),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Launch App Action Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _currentStep == 4
                      ? () => widget.onSetupCompleted(
                          _acquiredCoords!,
                          _detectedMall,
                          _loadedPackage,
                        )
                      : _startStartupFlow,
                  icon: Icon(
                    _currentStep == 4
                        ? (_detectedMall != null
                              ? LucideIcons.compass
                              : LucideIcons.arrowRight)
                        : LucideIcons.refreshCw,
                    size: 20,
                  ),
                  label: Text(
                    _currentStep == 4
                        ? (_detectedMall != null
                              ? 'Start Navigation'
                              : 'Continue to App (No Map Loaded)')
                        : (_isProcessing ? 'Loading...' : 'Try Again'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow(
    int stepNum,
    String title,
    String subtitle,
    IconData icon,
  ) {
    bool isDone = _currentStep > stepNum || _currentStep == 4;
    bool isCurrent = _currentStep == stepNum;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrent
            ? const Color(0xFFEFF6FF)
            : (isDone ? Colors.white : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrent
              ? const Color(0xFF2563EB)
              : (isDone ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0)),
          width: isCurrent ? 2 : 1,
        ),
        boxShadow: isDone
            ? const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDone
                  ? const Color(0xFF16A34A)
                  : (isCurrent
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFCBD5E1)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDone ? LucideIcons.check : icon,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step $stepNum: $title',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isCurrent
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
