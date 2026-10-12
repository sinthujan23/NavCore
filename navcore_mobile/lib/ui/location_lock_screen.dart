import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../engine/ecef_engine.dart';
import '../engine/real_sensor_service.dart';
import '../data/mall_database_service.dart';

class LocationLockScreen extends StatefulWidget {
  final RealSensorService sensorService;
  final MallDatabaseService mallService;
  final Function(GeodeticCoords coords, MallMetadata detectedMall)
  onSetupCompleted;

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

    // Step 2: Detect Nearest Mall
    _detectedMall = widget.mallService.findNearestMall(_acquiredCoords!);

    setState(() {
      _currentStep = 2;
      _statusText = 'Connected to ${_detectedMall!.name}!';
    });
    await Future.delayed(const Duration(milliseconds: 600));

    // Step 3: Load Mall Map
    setState(() {
      _currentStep = 3;
      _statusText = 'Loading map for ${_detectedMall!.name}...';
    });

    await widget.mallService.autoDownloadAndActivateNearestMall(
      _acquiredCoords!,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
          });
        }
      },
    );

    // Step 4: Completed
    setState(() {
      _currentStep = 4;
      _downloadProgress = 1.0;
      _isProcessing = false;
      _statusText = 'Map ready! You can now start navigating.';
    });
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
                    ? _detectedMall!.name
                    : 'Looking for nearby mall...',
                LucideIcons.building2,
              ),
              const SizedBox(height: 14),
              _buildStepRow(
                3,
                'Loading Indoor Map',
                _currentStep >= 3
                    ? '${(_downloadProgress * 100).toInt()}% Loaded'
                    : 'Preparing map...',
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
                      const Icon(
                        LucideIcons.checkCircle2,
                        color: Color(0xFF16A34A),
                        size: 20,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusText,
                        style: TextStyle(
                          color: _isProcessing
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF16A34A),
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
                          _detectedMall!,
                        )
                      : _startStartupFlow,
                  icon: Icon(
                    _currentStep == 4
                        ? LucideIcons.compass
                        : LucideIcons.refreshCw,
                    size: 20,
                  ),
                  label: Text(
                    _currentStep == 4
                        ? 'Start Navigation'
                        : (_isProcessing
                              ? 'Loading...'
                              : 'Try Again'),
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
