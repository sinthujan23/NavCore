import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../data/api_service.dart';

/// Shows the Server Configuration dialog allowing users and admins to configure and test
/// the backend REST API URL on physical mobile phones and emulators.
Future<void> showServerConfigModal(
  BuildContext context, {
  VoidCallback? onSaved,
}) async {
  final currentUrl = await ApiService.instance.getBaseUrl();
  final controller = TextEditingController(text: currentUrl);
  bool testing = false;
  String? testResult;
  Color testResultColor = const Color(0xFF10B981);

  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setDialogState) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                LucideIcons.server,
                color: Color(0xFF2563EB),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Backend Server API',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'Multi-Device Data Sync Configuration',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'API Endpoint URL',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12.5,
                  color: const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: 'https://nexnav.hashnate.com/api',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: const Color(0xFF94A3B8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF2563EB),
                      width: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Presets
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ActionChip(
                    avatar: const Icon(
                      LucideIcons.cloud,
                      size: 13,
                      color: Color(0xFF2563EB),
                    ),
                    label: Text(
                      'Production Cloud (nexnav.hashnate.com)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                    backgroundColor: const Color(0xFFEFF6FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                    ),
                    onPressed: () {
                      controller.text = 'https://nexnav.hashnate.com/api';
                      setDialogState(() {
                        testResult = null;
                      });
                    },
                  ),
                ],
              ),

              const SizedBox(height: 10),

              if (testResult != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: testResultColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: testResultColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        testResultColor == const Color(0xFF10B981)
                            ? LucideIcons.circleCheck
                            : LucideIcons.circleAlert,
                        size: 15,
                        color: testResultColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          testResult!,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: testResultColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 38),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: testing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.radio, size: 15),
                label: Text(
                  testing ? 'Testing Connection...' : 'Test Connection',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: testing
                    ? null
                    : () async {
                        setDialogState(() {
                          testing = true;
                          testResult = null;
                        });
                        final target = controller.text.trim();
                        final isOk = await ApiService.instance.testConnection(
                          target,
                        );
                        setDialogState(() {
                          testing = false;
                          if (isOk) {
                            testResult = 'Online: Connected to NavCore backend!';
                            testResultColor = const Color(0xFF10B981);
                          } else {
                            testResult =
                                'Offline: Could not reach server. Verify connection to nexnav.hashnate.com.';
                            testResultColor = const Color(0xFFEF4444);
                          }
                        });
                      },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
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
              backgroundColor: const Color(0xFF2563EB),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                await ApiService.instance.updateBaseUrl(newUrl);
                ApiService.instance.notifyDataSynced('server_url_updated');
                onSaved?.call();
              }
              if (dialogCtx.mounted) {
                Navigator.pop(dialogCtx);
              }
            },
            child: Text(
              'Save & Sync Now',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A compact, live status badge that can be placed in any AppBar or header.
/// Shows online (green) or offline (red) status and opens the config modal on tap.
class ServerStatusBadge extends StatefulWidget {
  final VoidCallback? onSaved;

  const ServerStatusBadge({super.key, this.onSaved});

  @override
  State<ServerStatusBadge> createState() => _ServerStatusBadgeState();
}

class _ServerStatusBadgeState extends State<ServerStatusBadge> {
  bool _isOnline = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  Future<void> _checkServer() async {
    if (!mounted || _isChecking) return;
    setState(() => _isChecking = true);
    final isOk = await ApiService.instance.testConnection();
    if (mounted) {
      setState(() {
        _isOnline = isOk;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showServerConfigModal(context, onSaved: () {
        _checkServer();
        widget.onSaved?.call();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _isOnline
              ? const Color(0xFF10B981).withValues(alpha: 0.12)
              : const Color(0xFFEF4444).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isOnline
                ? const Color(0xFF10B981).withValues(alpha: 0.35)
                : const Color(0xFFEF4444).withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isOnline
                    ? const Color(0xFF10B981)
                    : const Color(0xFFEF4444),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              _isOnline ? 'LIVE SYNC' : 'OFFLINE',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: _isOnline
                    ? const Color(0xFF047857)
                    : const Color(0xFFB91C1C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
