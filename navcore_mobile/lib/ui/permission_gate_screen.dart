import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../engine/real_sensor_service.dart';
import 'widgets/nexnav_logo_widget.dart';

class PermissionGateScreen extends StatefulWidget {
  final RealSensorService sensorService;
  final VoidCallback onAllAccessFulfilled;

  const PermissionGateScreen({
    super.key,
    required this.sensorService,
    required this.onAllAccessFulfilled,
  });

  @override
  State<PermissionGateScreen> createState() => _PermissionGateScreenState();
}

class _PermissionGateScreenState extends State<PermissionGateScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  AccessStatusReport _report = const AccessStatusReport(
    isLocationGranted: false,
    isLocationPermanentlyDenied: false,
    isCameraGranted: false,
    isCameraPermanentlyDenied: false,
    isGpsServiceEnabled: false,
  );

  bool _locationUserConfirmed = false;
  bool _cameraUserConfirmed = false;
  bool _openedSettingsForLocation = false;
  bool _openedSettingsForCamera = false;
  bool _isRequesting = false;
  bool _hasAutoAdvanced = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  bool get isLocationReady =>
      _locationUserConfirmed && _report.isLocationGranted;
  bool get isCameraReady =>
      _cameraUserConfirmed && _report.isCameraGranted;
  bool get isGpsReady => _report.isGpsServiceEnabled;

  bool get isAllDone => isLocationReady && isCameraReady && isGpsReady;

  int get fulfilledCount =>
      (isLocationReady ? 1 : 0) +
      (isCameraReady ? 1 : 0) +
      (isGpsReady ? 1 : 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initialCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAccessStatus();
    }
  }

  Future<void> _initialCheck() async {
    final report = await widget.sensorService.checkAllAccessStatus();
    if (!mounted) return;
    setState(() {
      _report = report;
      if (report.isLocationGranted) _locationUserConfirmed = true;
      if (report.isCameraGranted) _cameraUserConfirmed = true;
    });
    _checkAndAutoAdvance();
  }

  Future<void> _refreshAccessStatus() async {
    final report = await widget.sensorService.checkAllAccessStatus();
    if (!mounted) return;

    setState(() {
      _report = report;

      // If user returned from device settings after enabling blocked permissions
      if (_openedSettingsForLocation && report.isLocationGranted) {
        _locationUserConfirmed = true;
        _openedSettingsForLocation = false;
      }
      if (_openedSettingsForCamera && report.isCameraGranted) {
        _cameraUserConfirmed = true;
        _openedSettingsForCamera = false;
      }

      // If OS revoked permissions while backgrounded
      if (!report.isLocationGranted) {
        _locationUserConfirmed = false;
      }
      if (!report.isCameraGranted) {
        _cameraUserConfirmed = false;
      }
    });

    _checkAndAutoAdvance();
  }

  void _checkAndAutoAdvance() {
    if (isAllDone && !_hasAutoAdvanced) {
      _hasAutoAdvanced = true;
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 650), () {
        if (mounted) {
          widget.onAllAccessFulfilled();
        }
      });
    }
  }

  Future<void> _requestLocation() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);
    try {
      await widget.sensorService.requestLocationPermission();
      final report = await widget.sensorService.checkAllAccessStatus();
      if (mounted) {
        setState(() {
          _isRequesting = false;
          _report = report;
          if (report.isLocationGranted) {
            _locationUserConfirmed = true;
            HapticFeedback.mediumImpact();
          }
        });
        _checkAndAutoAdvance();
      }
    } catch (e) {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  Future<void> _requestCamera() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);
    try {
      await widget.sensorService.requestCameraPermission();
      final report = await widget.sensorService.checkAllAccessStatus();
      if (mounted) {
        setState(() {
          _isRequesting = false;
          _report = report;
          if (report.isCameraGranted) {
            _cameraUserConfirmed = true;
            HapticFeedback.mediumImpact();
          }
        });
        _checkAndAutoAdvance();
      }
    } catch (e) {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  Future<void> _openLocationSettings() async {
    await widget.sensorService.openDeviceLocationSettings();
  }

  Future<void> _openAppSettingsForLocation() async {
    _openedSettingsForLocation = true;
    await widget.sensorService.openDeviceAppSettings();
  }

  Future<void> _openAppSettingsForCamera() async {
    _openedSettingsForCamera = true;
    await widget.sensorService.openDeviceAppSettings();
  }

  Future<void> _turnOnAllPermissions() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);

    try {
      if (!isLocationReady) {
        if (_report.isLocationPermanentlyDenied) {
          await _openAppSettingsForLocation();
          if (mounted) setState(() => _isRequesting = false);
          return;
        }
        await widget.sensorService.requestLocationPermission();
      }

      if (!isCameraReady) {
        if (_report.isCameraPermanentlyDenied) {
          await _openAppSettingsForCamera();
          if (mounted) setState(() => _isRequesting = false);
          return;
        }
        await widget.sensorService.requestCameraPermission();
      }

      if (!isGpsReady) {
        await widget.sensorService.openDeviceLocationSettings();
        if (mounted) setState(() => _isRequesting = false);
        return;
      }

      final report = await widget.sensorService.checkAllAccessStatus();
      if (mounted) {
        setState(() {
          _isRequesting = false;
          _report = report;
          if (report.isLocationGranted) _locationUserConfirmed = true;
          if (report.isCameraGranted) _cameraUserConfirmed = true;
        });
        _checkAndAutoAdvance();
      }
    } catch (_) {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  Future<void> _handlePrimaryAction() async {
    if (isAllDone) {
      widget.onAllAccessFulfilled();
      return;
    }
    await _turnOnAllPermissions();
  }

  @override
  Widget build(BuildContext context) {
    const totalCount = 3;
    final progress = fulfilledCount / totalCount;

    IconData buttonIcon;
    String buttonText;
    Color buttonBgColor;
    VoidCallback? buttonAction;

    if (isAllDone) {
      buttonIcon = LucideIcons.circleCheck;
      buttonText = 'All Access Fulfilled — Enter NexNav';
      buttonBgColor = const Color(0xFF059669);
      buttonAction = () => widget.onAllAccessFulfilled();
    } else if (_report.isLocationPermanentlyDenied) {
      buttonIcon = LucideIcons.settings;
      buttonText = 'Open Settings for Location';
      buttonBgColor = const Color(0xFF0F172A);
      buttonAction = _openAppSettingsForLocation;
    } else if (_report.isCameraPermanentlyDenied) {
      buttonIcon = LucideIcons.settings;
      buttonText = 'Open Settings for Camera';
      buttonBgColor = const Color(0xFF0F172A);
      buttonAction = _openAppSettingsForCamera;
    } else {
      buttonIcon = LucideIcons.shieldCheck;
      buttonText = 'Turn On All Settings';
      buttonBgColor = const Color(0xFF2563EB);
      buttonAction = _handlePrimaryAction;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              content: Row(
                children: [
                  const Icon(
                    LucideIcons.shieldAlert,
                    color: Color(0xFFF59E0B),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'NexNav requires all 3 accesses to provide indoor navigation.',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22.0,
                    vertical: 18.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header & Animated NexNav App Logo
                      Center(
                        child: AnimatedBuilder(
                          animation: _pulseScale,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: isAllDone ? 1.0 : _pulseScale.value,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isAllDone
                                          ? const Color(0x3510B981)
                                          : const Color(0x302563EB),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const NexNavLogoWidget(size: 72),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Badge Tag
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isAllDone
                                ? const Color(0xFFECFDF5)
                                : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isAllDone
                                  ? const Color(0xFFA7F3D0)
                                  : const Color(0xFFBFDBFE),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAllDone
                                    ? LucideIcons.check
                                    : LucideIcons.shield,
                                size: 14,
                                color: isAllDone
                                    ? const Color(0xFF059669)
                                    : const Color(0xFF2563EB),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isAllDone
                                    ? 'ALL ACCESS VERIFIED'
                                    : 'MANDATORY SETUP FOR INDOOR AR',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: isAllDone
                                      ? const Color(0xFF059669)
                                      : const Color(0xFF2563EB),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Text(
                        isAllDone
                            ? 'All Access Fulfilled!'
                            : 'Permissions Required',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'For a better experience, your device will need to turn on all required permissions. The following settings should be on:',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF64748B),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Permission Card 1: Precise Location
                      _buildAccessCard(
                        title: 'Device Location',
                        subtitle:
                            'Precise location for accurate indoor positioning & venue detection.',
                        icon: LucideIcons.mapPin,
                        iconGradient: const [
                          Color(0xFF2563EB),
                          Color(0xFF3B82F6),
                        ],
                        isGranted: isLocationReady,
                        isPermanentlyDenied:
                            _report.isLocationPermanentlyDenied,
                        onRequest: _requestLocation,
                        onOpenSettings: _openAppSettingsForLocation,
                        actionLabel: 'Allow Location',
                        actionIcon: LucideIcons.mapPin,
                        statusBadgeText: isLocationReady
                            ? 'Granted'
                            : (_report.isLocationPermanentlyDenied
                                ? 'Blocked'
                                : 'Required'),
                      ),
                      const SizedBox(height: 12),

                      // Permission Card 2: Location Accuracy & GPS Service
                      _buildAccessCard(
                        title: 'Location Accuracy & GPS',
                        subtitle:
                            'High-accuracy Google Location & GPS hardware services.',
                        icon: LucideIcons.locateFixed,
                        iconGradient: const [
                          Color(0xFF0284C7),
                          Color(0xFF0EA5E9),
                        ],
                        isGranted: isGpsReady,
                        isPermanentlyDenied: false,
                        onRequest: _openLocationSettings,
                        onOpenSettings: _openLocationSettings,
                        actionLabel: 'Turn On',
                        actionIcon: LucideIcons.locateFixed,
                        statusBadgeText: isGpsReady
                            ? 'Active'
                            : 'Disabled',
                      ),
                      const SizedBox(height: 12),

                      // Permission Card 3: Camera Access (AR Viewport)
                      _buildAccessCard(
                        title: 'Camera Access (AR Viewport)',
                        subtitle:
                            'Augmented Reality (AR) camera overlays and 3D directional waypoints.',
                        icon: LucideIcons.camera,
                        iconGradient: const [
                          Color(0xFF7C3AED),
                          Color(0xFF8B5CF6),
                        ],
                        isGranted: isCameraReady,
                        isPermanentlyDenied: _report.isCameraPermanentlyDenied,
                        onRequest: _requestCamera,
                        onOpenSettings: _openAppSettingsForCamera,
                        actionLabel: 'Allow Camera',
                        actionIcon: LucideIcons.camera,
                        statusBadgeText: isCameraReady
                            ? 'Granted'
                            : (_report.isCameraPermanentlyDenied
                                ? 'Blocked'
                                : 'Required'),
                      ),
                      const SizedBox(height: 12),

                      // Permission Card 4: Motion & Heading Sensors
                      _buildAccessCard(
                        title: 'Motion & Heading Sensors',
                        subtitle:
                            'Compass, gyroscope & accelerometer for real-time heading and step detection.',
                        icon: LucideIcons.compass,
                        iconGradient: const [
                          Color(0xFF059669),
                          Color(0xFF10B981),
                        ],
                        isGranted: true,
                        isPermanentlyDenied: false,
                        onRequest: () {},
                        onOpenSettings: () {},
                        actionLabel: 'Ready',
                        actionIcon: LucideIcons.check,
                        statusBadgeText: 'Active',
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // Bottom Sticky Action Footer
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x080F172A),
                      blurRadius: 16,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Progress Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isAllDone
                              ? 'Setup Complete'
                              : 'Fulfilled ($fulfilledCount/$totalCount)',
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: isAllDone
                                ? const Color(0xFF059669)
                                : const Color(0xFF475569),
                          ),
                        ),
                        Text(
                          '${(progress * 100).toInt()}% Ready',
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: isAllDone
                                ? const Color(0xFF059669)
                                : const Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Smooth Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.0, end: progress),
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        builder: (context, val, child) {
                          return LinearProgressIndicator(
                            value: val,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFF1F5F9),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isAllDone
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF2563EB),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Primary Master Button
                    ElevatedButton(
                      onPressed: _isRequesting ? null : buttonAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonBgColor,
                        foregroundColor: Colors.white,
                        elevation: 3,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isRequesting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(buttonIcon, size: 19),
                                const SizedBox(width: 8),
                                Text(
                                  buttonText,
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (isAllDone) ...[
                                  const SizedBox(width: 6),
                                  const Icon(LucideIcons.arrowRight, size: 18),
                                ],
                              ],
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

  Widget _buildAccessCard({
    required String title,
    String? subtitle,
    required IconData icon,
    required List<Color> iconGradient,
    required bool isGranted,
    required bool isPermanentlyDenied,
    required VoidCallback onRequest,
    required VoidCallback onOpenSettings,
    required String actionLabel,
    required IconData actionIcon,
    required String statusBadgeText,
  }) {
    Color badgeBg;
    Color badgeFg;
    Color borderColor;

    if (isGranted) {
      badgeBg = const Color(0xFFECFDF5);
      badgeFg = const Color(0xFF059669);
      borderColor = const Color(0xFFA7F3D0);
    } else if (isPermanentlyDenied) {
      badgeBg = const Color(0xFFFEF2F2);
      badgeFg = const Color(0xFFDC2626);
      borderColor = const Color(0xFFFECACA);
    } else {
      badgeBg = const Color(0xFFFFFBEB);
      badgeFg = const Color(0xFFD97706);
      borderColor = const Color(0xFFFDE68A);
    }

    final handleTap = isGranted
        ? null
        : (isPermanentlyDenied ? onOpenSettings : onRequest);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: handleTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isGranted ? const Color(0xFFD1FAE5) : const Color(0xFFE2E8F0),
              width: isGranted ? 1.5 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x060F172A),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon Box
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: isGranted
                            ? const [Color(0xFF059669), Color(0xFF10B981)]
                            : iconGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isGranted
                              ? const Color(0x3010B981)
                              : iconGradient.first.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      isGranted ? LucideIcons.check : icon,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Title, Subtitle, and Status Badge
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3.5,
                              ),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: borderColor),
                              ),
                              child: Text(
                                statusBadgeText,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: badgeFg,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (subtitle != null && subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF64748B),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // Individual Action Button if not granted
              if (!isGranted) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    height: 36,
                    child: isPermanentlyDenied
                        ? OutlinedButton.icon(
                            onPressed: onOpenSettings,
                            icon: const Icon(LucideIcons.settings, size: 14),
                            label: const Text('Open Settings'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: const BorderSide(color: Color(0xFFFCA5A5)),
                              textStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: onRequest,
                            icon: Icon(
                              actionIcon,
                              size: 14,
                            ),
                            label: Text(actionLabel),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              textStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable modal sheet styled after the Android Location Accuracy prompt.
/// Prompts when any required access is revoked or missing while using the app.
Future<bool> showRequiredPermissionsDialog(
  BuildContext context, {
  required RealSensorService sensorService,
  VoidCallback? onAllGranted,
}) async {
  final report = await sensorService.checkAllAccessStatus();
  if (report.isAllFulfilled) return true;
  if (!context.mounted) return false;

  final res = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalCtx) => _RequiredPermissionsModal(
      sensorService: sensorService,
      onAllGranted: () {
        Navigator.of(modalCtx).pop(true);
        onAllGranted?.call();
      },
    ),
  );

  return res ?? false;
}

class _RequiredPermissionsModal extends StatefulWidget {
  final RealSensorService sensorService;
  final VoidCallback onAllGranted;

  const _RequiredPermissionsModal({
    required this.sensorService,
    required this.onAllGranted,
  });

  @override
  State<_RequiredPermissionsModal> createState() =>
      _RequiredPermissionsModalState();
}

class _RequiredPermissionsModalState extends State<_RequiredPermissionsModal>
    with WidgetsBindingObserver {
  AccessStatusReport _report = const AccessStatusReport(
    isLocationGranted: false,
    isLocationPermanentlyDenied: false,
    isCameraGranted: false,
    isCameraPermanentlyDenied: false,
    isGpsServiceEnabled: false,
  );
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final report = await widget.sensorService.checkAllAccessStatus();
    if (!mounted) return;
    setState(() => _report = report);
    if (report.isAllFulfilled) {
      widget.onAllGranted();
    }
  }

  Future<void> _turnOnAll() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);
    try {
      if (!_report.isLocationGranted) {
        if (_report.isLocationPermanentlyDenied) {
          await widget.sensorService.openDeviceAppSettings();
          if (mounted) setState(() => _isRequesting = false);
          return;
        }
        await widget.sensorService.requestLocationPermission();
      }

      if (!_report.isCameraGranted) {
        if (_report.isCameraPermanentlyDenied) {
          await widget.sensorService.openDeviceAppSettings();
          if (mounted) setState(() => _isRequesting = false);
          return;
        }
        await widget.sensorService.requestCameraPermission();
      }

      if (!_report.isGpsServiceEnabled) {
        await widget.sensorService.openDeviceLocationSettings();
        if (mounted) setState(() => _isRequesting = false);
        return;
      }

      final report = await widget.sensorService.checkAllAccessStatus();
      if (mounted) {
        setState(() {
          _isRequesting = false;
          _report = report;
        });
        if (report.isAllFulfilled) {
          widget.onAllGranted();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF475569),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'For a better experience, your device will need to use Location & Camera',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'The following settings should be on:',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 16),
            _buildModalItem(
              icon: LucideIcons.mapPin,
              title: 'Device location',
              description:
                  'Precise location for accurate indoor positioning and venue detection.',
              isOn: _report.isLocationGranted,
            ),
            const SizedBox(height: 12),
            _buildModalItem(
              icon: LucideIcons.locateFixed,
              title: 'Location Accuracy (GPS)',
              description:
                  'High-accuracy Google Location & GPS hardware services.',
              isOn: _report.isGpsServiceEnabled,
            ),
            const SizedBox(height: 12),
            _buildModalItem(
              icon: LucideIcons.camera,
              title: 'Camera access',
              description:
                  'Augmented Reality (AR) camera overlays and 3D directional waypoints.',
              isOn: _report.isCameraGranted,
            ),
            const SizedBox(height: 12),
            _buildModalItem(
              icon: LucideIcons.compass,
              title: 'Motion & orientation sensors',
              description:
                  'Real-time compass heading, gyroscope, and step dead-reckoning.',
              isOn: true,
            ),
            const SizedBox(height: 20),
            Text(
              'NexNav requires these permissions to provide live indoor AR navigation.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    widget.sensorService.openDeviceAppSettings();
                  },
                  child: Text(
                    'Settings',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isRequesting ? null : _turnOnAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: const Color(0xFF0F172A),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _isRequesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF0F172A),
                          ),
                        )
                      : Text(
                          'Turn on',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalItem({
    required IconData icon,
    required String title,
    required String description,
    required bool isOn,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon,
            size: 18,
            color: isOn ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isOn
                          ? const Color(0xFF064E3B)
                          : const Color(0xFF451A03),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isOn ? 'On' : 'Required',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isOn
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFFFDBA74),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  color: const Color(0xFF94A3B8),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
