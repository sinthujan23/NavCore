import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/api_service.dart';
import '../data/email_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'widgets/nexnav_logo_widget.dart';

enum UserRole { guest, user, admin }

/// Evaluates password security strength for strict policy enforcement
class PasswordStrength {
  final bool hasMinLength;
  final bool hasUppercase;
  final bool hasLowercase;
  final bool hasDigit;
  final bool hasSpecial;

  const PasswordStrength({
    required this.hasMinLength,
    required this.hasUppercase,
    required this.hasLowercase,
    required this.hasDigit,
    required this.hasSpecial,
  });

  bool get isStrong =>
      hasMinLength && hasUppercase && hasLowercase && hasDigit && hasSpecial;

  int get score {
    int count = 0;
    if (hasMinLength) count++;
    if (hasUppercase) count++;
    if (hasLowercase) count++;
    if (hasDigit) count++;
    if (hasSpecial) count++;
    return count;
  }

  List<String> get missingRequirements {
    final List<String> missing = [];
    if (!hasMinLength) missing.add('8+ characters');
    if (!hasUppercase) missing.add('uppercase letter (A-Z)');
    if (!hasLowercase) missing.add('lowercase letter (a-z)');
    if (!hasDigit) missing.add('number (0-9)');
    if (!hasSpecial) missing.add('symbol (!@#\$...)');
    return missing;
  }

  String get strengthLabel {
    if (score == 0) return '';
    if (score <= 2) return 'Weak';
    if (score <= 4) return 'Moderate';
    return 'Strong';
  }

  Color get strengthColor {
    if (score <= 2) return const Color(0xFFEF4444);
    if (score <= 4) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  static PasswordStrength evaluate(String text) {
    final trimmed = text.trim();
    return PasswordStrength(
      hasMinLength: trimmed.length >= 8,
      hasUppercase: trimmed.contains(RegExp(r'[A-Z]')),
      hasLowercase: trimmed.contains(RegExp(r'[a-z]')),
      hasDigit: trimmed.contains(RegExp(r'[0-9]')),
      hasSpecial: trimmed.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]')),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final UserRole? initialRole;
  final Function(UserRole role, String email) onLoginSuccess;
  final VoidCallback onBackToWelcome;

  const LoginScreen({
    super.key,
    this.initialRole,
    required this.onLoginSuccess,
    required this.onBackToWelcome,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isSignUpMode = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _rememberMe = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String _activeServerUrl = ApiService.defaultBaseUrl;

  // Real-time email verification & OTP state
  bool _isVerificationMode = false;
  String _verifyingEmail = '';
  String _verificationType = 'registration';
  String? _previewOtpCode;
  String? _pendingAuthToken;
  String? _pendingUserRole;
  bool _isVerifyingOtp = false;
  bool _isResending = false;
  bool _canResend = false;
  int _resendCountdown = 60;
  Timer? _resendTimer;
  // Pending registration data held until OTP is confirmed (account is NOT created until verified!)
  String? _pendingSignUpName;
  String? _pendingSignUpEmail;
  String? _pendingSignUpPassword;
  late final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  late final List<FocusNode> _otpFocusNodes = List.generate(
    6,
    (_) => FocusNode(),
  );

  // Forgot Password & Reset Password state
  bool _isForgotPasswordMode = false;
  int _forgotPasswordStep =
      1; // 1 = Request code, 2 = Verify code, 3 = Create new password
  bool _isVerifyingResetCode = false;
  String _verifiedResetCode = '';
  final TextEditingController _forgotEmailController = TextEditingController();
  final TextEditingController _forgotNewPasswordController =
      TextEditingController();
  final TextEditingController _forgotConfirmPasswordController =
      TextEditingController();
  bool _isForgotNewPasswordVisible = false;
  bool _isForgotConfirmPasswordVisible = false;
  bool _isSendingResetCode = false;
  bool _isResettingPassword = false;
  bool _canForgotResend = false;
  int _forgotResendCountdown = 60;
  Timer? _forgotResendTimer;
  String? _forgotPasswordPreviewOtp;
  late final List<TextEditingController> _forgotOtpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  late final List<FocusNode> _forgotOtpFocusNodes = List.generate(
    6,
    (_) => FocusNode(),
  );

  static const String _prefRememberMe = 'NexNav_remember_me';
  static const String _prefSavedEmail = 'NexNav_remembered_email';
  static const String _prefSavedRole = 'NexNav_remembered_role';
  static const String _prefAutoLogin = 'NexNav_auto_login_enabled';
  // Server Client ID (Web Application OAuth Client ID from Google Cloud Console)
  static const String _googleServerClientId =
      '120287082166-5io846ej4iho3aho5o2pe25fnjtphrod.apps.googleusercontent.com';
  // iOS Client ID (used by GIDSignIn on iOS)
  static const String _googleIosClientId =
      '120287082166-5io846ej4iho3aho5o2pe25fnjtphrod.apps.googleusercontent.com';

  @override
  void initState() {
    super.initState();
    _loadRememberedPreferences();
    _checkServerConnection();
  }

  Future<void> _checkServerConnection() async {
    if (!mounted) return;
    final url = await ApiService.instance.getBaseUrl();
    if (!mounted) return;
    setState(() {
      _activeServerUrl = url;
    });
  }

  void _showServerConfigDialog() async {
    final currentUrl = await ApiService.instance.getBaseUrl();
    final controller = TextEditingController(text: currentUrl);
    bool testing = false;
    String? testResult;
    Color testResultColor = const Color(0xFF10B981);

    if (!mounted) return;
    showDialog(
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
                      'Live Cloud & Local Database Sync',
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
                    hintText: ApiService.productionServerUrl,
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: const Color(0xFFEFF6FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      onPressed: () {
                        controller.text = ApiService.productionServerUrl;
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
                              ? LucideIcons.checkCircle2
                              : LucideIcons.alertCircle,
                          size: 14,
                          color: testResultColor,
                        ),
                        const SizedBox(width: 6),
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

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: testing
                            ? null
                            : () async {
                                setDialogState(() {
                                  testing = true;
                                  testResult = 'Testing connection...';
                                  testResultColor = const Color(0xFF3B82F6);
                                });
                                final input = controller.text.trim();
                                final norm = ApiService.normalizeUrl(
                                  input.isNotEmpty
                                      ? input
                                      : ApiService.defaultBaseUrl,
                                );
                                final sw = Stopwatch()..start();
                                try {
                                  final res = await http
                                      .get(Uri.parse('$norm/health'))
                                      .timeout(const Duration(seconds: 5));
                                  sw.stop();
                                  if (res.statusCode == 200) {
                                    setDialogState(() {
                                      testing = false;
                                      testResult =
                                          'Online (200 OK â€¢ ${sw.elapsedMilliseconds}ms)';
                                      testResultColor = const Color(0xFF10B981);
                                    });
                                  } else {
                                    setDialogState(() {
                                      testing = false;
                                      testResult = 'HTTP ${res.statusCode}';
                                      testResultColor = const Color(0xFFEF4444);
                                    });
                                  }
                                } catch (e) {
                                  setDialogState(() {
                                    testing = false;
                                    testResult = 'Offline / Timed out';
                                    testResultColor = const Color(0xFFEF4444);
                                  });
                                }
                              },
                        icon: const Icon(LucideIcons.activity, size: 14),
                        label: Text(
                          testing ? 'Pinging...' : 'Test Ping',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        controller.text = ApiService.productionServerUrl;
                        await ApiService.instance.resetToDefaultBaseUrl();
                        await _checkServerConnection();
                        setDialogState(() {
                          testResult = 'Reset to Cloud default';
                          testResultColor = const Color(0xFF10B981);
                        });
                      },
                      child: Text(
                        'Reset Cloud',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
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
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final input = controller.text.trim();
                if (input.isEmpty || input == ApiService.defaultBaseUrl) {
                  await ApiService.instance.resetToDefaultBaseUrl();
                } else {
                  await ApiService.instance.setCustomBaseUrl(input);
                }
                // ignore: use_build_context_synchronously
                Navigator.pop(dialogCtx);
                await _checkServerConnection();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(
                            LucideIcons.checkCircle2,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Connected to $_activeServerUrl',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: const Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
              },
              child: Text(
                'Save & Connect',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadRememberedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool remember = prefs.getBool(_prefRememberMe) ?? true;
      final String? savedEmail = prefs.getString(_prefSavedEmail);

      if (!mounted) return;
      setState(() {
        _rememberMe = remember;
        if (remember && savedEmail != null && savedEmail.isNotEmpty) {
          _emailController.text = savedEmail;
        }
        // Always require genuine email input; do not populate mock emails
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _forgotResendTimer?.cancel();
    _forgotEmailController.dispose();
    _forgotNewPasswordController.dispose();
    _forgotConfirmPasswordController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    for (final c in _forgotOtpControllers) {
      c.dispose();
    }
    for (final f in _forgotOtpFocusNodes) {
      f.dispose();
    }
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.alertCircle, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.checkCircle2, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _resendCountdown = 60;
      _canResend = false;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown > 1) {
        setState(() {
          _resendCountdown--;
        });
      } else {
        timer.cancel();
        setState(() {
          _resendCountdown = 0;
          _canResend = true;
        });
      }
    });
  }

  void _enterVerificationMode(
    String email, {
    String type = 'email_verification',
    String? infoMessage,
    String? previewCode,
    String? token,
    String? role,
  }) {
    final resolvedCode = (previewCode != null && previewCode.trim().isNotEmpty)
        ? previewCode.trim()
        : (100000 + math.Random().nextInt(900000)).toString();

    setState(() {
      _isVerificationMode = true;
      _verifyingEmail = email;
      _verificationType = type;
      _previewOtpCode = resolvedCode;
      _pendingAuthToken = token;
      _pendingUserRole = role ?? 'user';
      for (final c in _otpControllers) {
        c.clear();
      }
    });
    _startResendTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_otpFocusNodes[0].canRequestFocus) {
        _otpFocusNodes[0].requestFocus();
      }
    });

    if (infoMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(LucideIcons.mailCheck, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  infoMessage,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF2563EB),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Prominently displays celebratory success modal when account is verified
  Future<void> _showAccountCreatedSuccessDialog(
    String email,
    UserRole role, {
    bool isRegistration = true,
  }) async {
    if (!mounted) return;

    Timer? autoDismissTimer;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        autoDismissTimer = Timer(const Duration(milliseconds: 2800), () {
          if (Navigator.of(dialogCtx).canPop()) {
            Navigator.of(dialogCtx).pop();
          }
        });

        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x330F172A),
                  blurRadius: 36,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Celebratory checkmark badge
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      LucideIcons.checkCheck,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  isRegistration
                      ? 'Account Created Successfully!'
                      : 'Verified Successfully!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isRegistration
                      ? 'Welcome to NexNav! Your email has been verified and your account is active.'
                      : 'Your security identity has been confirmed. Signing you in...',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    height: 1.5,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 18),

                // Account verification details pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          LucideIcons.badgeCheck,
                          color: Color(0xFF10B981),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              email,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              role == UserRole.admin
                                  ? 'Role: Administrator'
                                  : 'Status: Active & Verified',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // Enter NexNav button
                ElevatedButton(
                  onPressed: () {
                    autoDismissTimer?.cancel();
                    if (Navigator.of(dialogCtx).canPop()) {
                      Navigator.of(dialogCtx).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'CONTINUE TO NEXNAV',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(LucideIcons.arrowRight, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    autoDismissTimer?.cancel();

    if (!mounted) return;

    _showSuccessSnackBar(
      isRegistration
          ? 'Account created and verified successfully! Welcome to NexNav.'
          : 'Email verified successfully! Welcome to NexNav.',
    );

    widget.onLoginSuccess(role, email);
  }

  Future<void> _submitOtpVerification() async {
    final code = _otpControllers.map((c) => c.text.trim()).join();
    if (code.length < 6) {
      _showErrorSnackBar('Please enter the complete 6-digit verification code');
      return;
    }

    // 1. Verify 6-digit OTP code first
    if (_previewOtpCode != null && code.trim() != _previewOtpCode!.trim()) {
      setState(() => _isVerifyingOtp = false);
      _showErrorSnackBar(
        'Incorrect verification code. Please check the code and try again.',
      );
      return;
    }

    AuthResult authResult;
    if (_verificationType == 'signup_pending_otp' ||
        _pendingSignUpEmail != null) {
      // Real-world registration flow: ONLY AFTER OTP is confirmed, officially create the account!
      final emailToCreate = _pendingSignUpEmail ?? _verifyingEmail;
      final passwordToCreate = _pendingSignUpPassword ?? '';
      final nameToCreate = _pendingSignUpName;

      authResult = await ApiService.instance.confirmAndCreateAccount(
        email: emailToCreate,
        password: passwordToCreate,
        name: nameToCreate,
        otpCode: code,
      );
    } else if (_verificationType == 'login_otp') {
      authResult = await ApiService.instance.verifyLoginOtp(
        email: _verifyingEmail,
        code: code,
      );
    } else {
      authResult = await ApiService.instance.verifyEmail(
        email: _verifyingEmail,
        code: code,
        expectedCode: _previewOtpCode,
        token: _pendingAuthToken,
        role: _pendingUserRole,
      );
    }

    if (!mounted) return;
    setState(() => _isVerifyingOtp = false);

    if (!authResult.isSuccess) {
      _showErrorSnackBar(
        authResult.errorMessage ?? 'Invalid verification code',
      );
      return;
    }

    // Account confirmed and created successfully! Wipe pending temporary signup data
    _pendingSignUpEmail = null;
    _pendingSignUpPassword = null;
    _pendingSignUpName = null;

    final userRole = authResult.role == 'admin'
        ? UserRole.admin
        : UserRole.user;

    // Persist remember me preferences
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool(_prefRememberMe, true);
      await prefs.setString(_prefSavedEmail, _verifyingEmail);
      await prefs.setString(_prefSavedRole, userRole.name);
      await prefs.setBool(_prefAutoLogin, true);
    } else {
      await prefs.setBool(_prefRememberMe, false);
      await prefs.remove(_prefSavedEmail);
      await prefs.remove(_prefSavedRole);
      await prefs.setBool(_prefAutoLogin, false);
    }

    // Display celebratory success modal notification before transition
    await _showAccountCreatedSuccessDialog(
      authResult.email ?? _verifyingEmail,
      userRole,
      isRegistration: _verificationType != 'login_otp',
    );
  }

  Future<void> _handleResendOtp() async {
    if (!_canResend || _isResending) return;

    setState(() => _isResending = true);
    final freshCode = (100000 + math.Random().nextInt(900000)).toString();

    setState(() {
      _previewOtpCode = freshCode;
    });

    // Send the fresh OTP code directly to the recipient's real email address
    await MobileEmailService.instance.sendOtpEmail(
      to: _verifyingEmail,
      code: freshCode,
      name: _pendingSignUpName,
      purpose: 'Verification Code Resend',
    );

    if (!mounted) return;
    setState(() => _isResending = false);

    _startResendTimer();
    _showSuccessSnackBar(
      'A fresh verification code has been sent to $_verifyingEmail. Please check your inbox.',
    );
  }

  void _startForgotResendTimer() {
    _forgotResendTimer?.cancel();
    setState(() {
      _forgotResendCountdown = 60;
      _canForgotResend = false;
    });
    _forgotResendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_forgotResendCountdown > 1) {
        setState(() => _forgotResendCountdown--);
      } else {
        timer.cancel();
        setState(() {
          _canForgotResend = true;
          _forgotResendCountdown = 0;
        });
      }
    });
  }

  Future<void> _handleSendResetCode() async {
    final email = _forgotEmailController.text.trim();
    if (email.isEmpty) {
      _showErrorSnackBar('Please enter your email address');
      return;
    }
    if (!RegExp(
      r'^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$',
    ).hasMatch(email)) {
      _showErrorSnackBar('Please enter a valid email address');
      return;
    }

    setState(() => _isSendingResetCode = true);

    try {
      final res = await ApiService.instance.forgotPassword(email);
      if (!mounted) return;

      if (res['success'] == true) {
        _forgotPasswordPreviewOtp = res['previewCode']?.toString();
        if (_forgotPasswordPreviewOtp != null) {
          await MobileEmailService.instance.sendOtpEmail(
            to: email,
            code: _forgotPasswordPreviewOtp!,
            purpose: 'Password Reset Request',
          );
        }

        if (!mounted) return;
        setState(() => _isSendingResetCode = false);

        for (final c in _forgotOtpControllers) {
          c.clear();
        }

        setState(() {
          _forgotPasswordStep = 2;
        });
        _startForgotResendTimer();

        _showSuccessSnackBar(
          'A 6-digit password reset code has been sent to $email. Please check your inbox.',
        );
      } else {
        setState(() => _isSendingResetCode = false);
        _showErrorSnackBar(
          res['error'] ?? 'Could not find an account with this email address.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSendingResetCode = false);
      _showErrorSnackBar('Network connection error. Please try again.');
    }
  }

  Future<void> _handleResendResetCode() async {
    if (!_canForgotResend || _isSendingResetCode) return;
    final email = _forgotEmailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _isSendingResetCode = true);
    final res = await ApiService.instance.forgotPassword(email);
    if (!mounted) return;

    if (res['success'] == true) {
      _forgotPasswordPreviewOtp = res['previewCode']?.toString();
      if (_forgotPasswordPreviewOtp != null) {
        await MobileEmailService.instance.sendOtpEmail(
          to: email,
          code: _forgotPasswordPreviewOtp!,
          purpose: 'Password Reset Request',
        );
      }
      if (!mounted) return;
      setState(() => _isSendingResetCode = false);
      _startForgotResendTimer();
      _showSuccessSnackBar('A fresh reset code has been sent to $email.');
    } else {
      setState(() => _isSendingResetCode = false);
      _showErrorSnackBar(
        res['error'] ?? 'Failed to resend code. Please try again.',
      );
    }
  }

  Future<void> _handleVerifyResetCode() async {
    final email = _forgotEmailController.text.trim();
    final code = _forgotOtpControllers.map((c) => c.text.trim()).join();

    if (code.length < 6) {
      _showErrorSnackBar('Please enter the complete 6-digit verification code');
      return;
    }

    setState(() => _isVerifyingResetCode = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode =
          prefs.getString('pwd_reset_code_$email') ?? _forgotPasswordPreviewOtp;
      final savedTime = prefs.getInt('pwd_reset_time_$email') ?? 0;
      final elapsedMinutes = savedTime > 0
          ? (DateTime.now().millisecondsSinceEpoch - savedTime) / (1000 * 60)
          : 0;

      if (savedCode != null && code.trim() != savedCode.trim()) {
        if (!mounted) return;
        setState(() => _isVerifyingResetCode = false);
        _showErrorSnackBar(
          'Incorrect verification code. Please check your inbox and try again.',
        );
        return;
      }

      if (elapsedMinutes > 15 && savedTime > 0) {
        if (!mounted) return;
        setState(() => _isVerifyingResetCode = false);
        _showErrorSnackBar(
          'Verification code has expired. Please request a new code.',
        );
        return;
      }

      _verifiedResetCode = code.trim();
      _forgotNewPasswordController.clear();
      _forgotConfirmPasswordController.clear();

      if (!mounted) return;
      setState(() {
        _isVerifyingResetCode = false;
        _forgotPasswordStep = 3;
      });
      HapticFeedback.mediumImpact();
      _showSuccessSnackBar('Code verified! Please create your new password.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVerifyingResetCode = false);
      _showErrorSnackBar('Verification error. Please try again.');
    }
  }

  Future<void> _handleSubmitResetPassword() async {
    final email = _forgotEmailController.text.trim();
    final code = _verifiedResetCode.isNotEmpty
        ? _verifiedResetCode
        : _forgotOtpControllers.map((c) => c.text.trim()).join();
    final newPass = _forgotNewPasswordController.text.trim();
    final confirmPass = _forgotConfirmPasswordController.text.trim();

    if (code.length < 6) {
      _showErrorSnackBar('Please enter the 6-digit code you received');
      setState(() => _forgotPasswordStep = 2);
      return;
    }

    if (newPass.isEmpty) {
      _showErrorSnackBar('Please enter your new password');
      return;
    }

    if (newPass != confirmPass) {
      _showErrorSnackBar('New passwords do not match. Please verify.');
      return;
    }

    final strength = PasswordStrength.evaluate(newPass);
    if (!strength.isStrong) {
      _showErrorSnackBar(
        'Password missing: ${strength.missingRequirements.join(', ')}',
      );
      return;
    }

    setState(() => _isResettingPassword = true);

    try {
      final res = await ApiService.instance.resetPassword(
        email: email,
        code: code,
        newPassword: newPass,
      );

      if (!mounted) return;
      setState(() => _isResettingPassword = false);

      if (res['success'] == true) {
        await _showPasswordResetSuccessDialog(email);

        if (!mounted) return;
        setState(() {
          _isForgotPasswordMode = false;
          _forgotPasswordStep = 1;
          _emailController.text = email;
          _passwordController.clear();
          _confirmPasswordController.clear();
        });

        _showSuccessSnackBar(
          'Password reset successfully! Please log in with your new password.',
        );
      } else {
        _showErrorSnackBar(
          res['error'] ?? 'Invalid or expired reset code. Please try again.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isResettingPassword = false);
      _showErrorSnackBar('Network connection error. Please try again.');
    }
  }

  Future<void> _showPasswordResetSuccessDialog(String email) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFECFDF5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.checkCircle2,
                color: Color(0xFF10B981),
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Password Reset Successful!',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your password for $email has been updated. You can now log in with your new credentials.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: const Color(0xFF64748B),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'CONTINUE TO LOG IN',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleForgotPasswordBack() {
    if (_isResettingPassword || _isVerifyingResetCode || _isSendingResetCode) return;

    if (_forgotPasswordStep == 3) {
      _forgotNewPasswordController.clear();
      _forgotConfirmPasswordController.clear();
      _isForgotNewPasswordVisible = false;
      _isForgotConfirmPasswordVisible = false;
      setState(() => _forgotPasswordStep = 2);
    } else if (_forgotPasswordStep == 2) {
      _forgotResendTimer?.cancel();
      setState(() => _forgotPasswordStep = 1);
    } else {
      setState(() => _isForgotPasswordMode = false);
    }
  }

  Widget _buildForgotPasswordStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),

        // Centered App Logo
        Center(child: const NexNavLogoWidget(size: 76)),

        const SizedBox(height: 32),

        // Title: Forgot Password?
        Text(
          'Forgot Password?',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
        ),

        const SizedBox(height: 12),

        // Subtitle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            "Enter your registered email address below. We'll send you a 6-digit verification code to reset your password.",
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13.5,
              color: const Color(0xFF64748B),
              height: 1.45,
            ),
          ),
        ),

        const SizedBox(height: 36),

        // Email Input Field (Matching user screenshot)
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _forgotEmailController,
            keyboardType: TextInputType.emailAddress,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              icon: const Icon(
                LucideIcons.mail,
                size: 20,
                color: Color(0xFF94A3B8),
              ),
              hintText: 'Enter your email address',
              hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: const Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onSubmitted: (_) => _handleSendResetCode(),
          ),
        ),

        const SizedBox(height: 28),

        // SEND RESET CODE button (Matching user screenshot)
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F172A),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _isSendingResetCode ? null : _handleSendResetCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: _isSendingResetCode
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'SEND RESET CODE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 24),

        // Back to Login link
        Center(
          child: TextButton.icon(
            onPressed: () {
              setState(() => _isForgotPasswordMode = false);
            },
            icon: const Icon(
              LucideIcons.arrowLeft,
              size: 15,
              color: Color(0xFF64748B),
            ),
            label: Text(
              'Back to Log In',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForgotPasswordStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),

        Text(
          'Verify Code',
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
          'We sent a 6-digit verification code to:',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: const Color(0xFF64748B),
          ),
        ),

        const SizedBox(height: 8),

        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.mail, size: 14, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _forgotEmailController.text.trim(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 26),

        // 6-digit OTP Input Boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (index) => _buildForgotOtpDigitBox(index)),
        ),

        const SizedBox(height: 18),

        // Resend Timer / Button
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              "Didn't receive the code? ",
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                color: const Color(0xFF64748B),
              ),
            ),
            if (!_canForgotResend)
              Text(
                'Resend in ${_forgotResendCountdown}s',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2563EB),
                ),
              )
            else
              InkWell(
                onTap: _isSendingResetCode ? null : _handleResendResetCode,
                child: Text(
                  _isSendingResetCode ? 'Sending...' : 'Resend Code',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF2563EB),
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 28),

        // VERIFY CODE button
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F172A),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _isVerifyingResetCode ? null : _handleVerifyResetCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: _isVerifyingResetCode
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'VERIFY CODE',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(LucideIcons.arrowRight, size: 16),
                    ],
                  ),
          ),
        ),

        const SizedBox(height: 18),

        // Back to Step 1
        Center(
          child: TextButton.icon(
            onPressed: () {
              _forgotResendTimer?.cancel();
              setState(() => _forgotPasswordStep = 1);
            },
            icon: const Icon(
              LucideIcons.arrowLeft,
              size: 15,
              color: Color(0xFF64748B),
            ),
            label: Text(
              'Change Email Address',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForgotPasswordStep3() {
    final newPassText = _forgotNewPasswordController.text;
    final strength = PasswordStrength.evaluate(newPassText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),

        Text(
          'Create New Password',
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
          'Your code has been verified. Enter a strong new password for your account.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: const Color(0xFF64748B),
          ),
        ),

        const SizedBox(height: 24),

        // New Password Input
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _forgotNewPasswordController,
            obscureText: !_isForgotNewPasswordVisible,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              icon: const Icon(
                LucideIcons.lock,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
              hintText: 'New Password',
              hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: const Color(0xFF94A3B8),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _isForgotNewPasswordVisible
                      ? LucideIcons.eyeOff
                      : LucideIcons.eye,
                  size: 18,
                  color: const Color(0xFF64748B),
                ),
                onPressed: () {
                  setState(
                    () => _isForgotNewPasswordVisible =
                        !_isForgotNewPasswordVisible,
                  );
                },
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),

        if (newPassText.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildPasswordStrengthBar(strength),
        ],

        const SizedBox(height: 14),

        // Confirm New Password Input
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _forgotConfirmPasswordController,
            obscureText: !_isForgotConfirmPasswordVisible,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              icon: const Icon(
                LucideIcons.checkCheck,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
              hintText: 'Confirm New Password',
              hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: const Color(0xFF94A3B8),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _isForgotConfirmPasswordVisible
                      ? LucideIcons.eyeOff
                      : LucideIcons.eye,
                  size: 18,
                  color: const Color(0xFF64748B),
                ),
                onPressed: () {
                  setState(
                    () => _isForgotConfirmPasswordVisible =
                        !_isForgotConfirmPasswordVisible,
                  );
                },
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // RESET PASSWORD button
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F172A),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _isResettingPassword ? null : _handleSubmitResetPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: _isResettingPassword
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'RESET PASSWORD',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 18),

        // Back to Verification Code link
        Center(
          child: TextButton.icon(
            onPressed: _handleForgotPasswordBack,
            icon: const Icon(
              LucideIcons.arrowLeft,
              size: 15,
              color: Color(0xFF64748B),
            ),
            label: Text(
              'Back to Verification Code',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForgotOtpDigitBox(int index) {
    return Flexible(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        constraints: const BoxConstraints(maxWidth: 46, maxHeight: 52),
        height: 50,
        child: TextFormField(
          controller: _forgotOtpControllers[index],
          focusNode: _forgotOtpFocusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFCBD5E1),
                width: 1.2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFE2E8F0),
                width: 1.2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF0F172A),
                width: 2.0,
              ),
            ),
          ),
          onChanged: (value) {
            if (value.length > 1) {
              final digits = value.replaceAll(RegExp(r'\D'), '');
              for (int i = 0; i < 6; i++) {
                if (i < digits.length) {
                  _forgotOtpControllers[i].text = digits[i];
                }
              }
              if (digits.length >= 6) {
                _forgotOtpFocusNodes[5].unfocus();
                _handleVerifyResetCode();
              } else if (digits.isNotEmpty) {
                _forgotOtpFocusNodes[digits.length.clamp(0, 5)].requestFocus();
              }
              return;
            }

            if (value.isNotEmpty) {
              _forgotOtpControllers[index].text = value;
              if (index < 5) {
                _forgotOtpFocusNodes[index + 1].requestFocus();
              } else {
                _forgotOtpFocusNodes[index].unfocus();
                final fullCode = _forgotOtpControllers
                    .map((c) => c.text.trim())
                    .join();
                if (fullCode.length == 6) {
                  _handleVerifyResetCode();
                }
              }
            } else {
              if (index > 0) {
                _forgotOtpFocusNodes[index - 1].requestFocus();
              }
            }
          },
        ),
      ),
    );
  }

  Widget _buildPasswordStrengthBar(PasswordStrength strength) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: strength.score / 5.0,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    strength.strengthColor,
                  ),
                  minHeight: 4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              strength.strengthLabel,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: strength.strengthColor,
              ),
            ),
          ],
        ),
        if (strength.missingRequirements.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Missing: ${strength.missingRequirements.join(', ')}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: const Color(0xFFEF4444),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  void _handleAuth() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isSignUpMode &&
        _passwordController.text != _confirmPasswordController.text) {
      _showErrorSnackBar('Passwords do not match. Please verify.');
      return;
    }

    setState(() => _isLoading = true);

    final emailInput = _emailController.text.trim();
    final passwordInput = _passwordController.text.trim();

    if (_isSignUpMode) {
      final nameInput = _nameController.text.trim();

      // Strict one-account-per-email policy: verify if email already exists
      final isAlreadyRegistered = await ApiService.instance.checkIfEmailExists(
        emailInput,
      );
      if (isAlreadyRegistered) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showErrorSnackBar(
          'An account with $emailInput already exists. Only one account can be created per email. Please log in instead.',
        );
        return;
      }

      // Real-world registration architecture:
      // The account is NOT created yet! Credentials are held pending OTP confirmation.
      _pendingSignUpName = nameInput.isNotEmpty ? nameInput : null;
      _pendingSignUpEmail = emailInput;
      _pendingSignUpPassword = passwordInput;

      final generatedCode = (100000 + math.Random().nextInt(900000)).toString();

      // Dispatch the real 6-digit OTP code directly to user's real email address via Google SMTP
      await MobileEmailService.instance.sendOtpEmail(
        to: emailInput,
        code: generatedCode,
        name: nameInput.isNotEmpty ? nameInput : null,
        purpose: 'New Account Registration',
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      _enterVerificationMode(
        emailInput,
        type: 'signup_pending_otp',
        infoMessage:
            'A 6-digit verification code has been sent to $emailInput. Please check your inbox.',
        previewCode: generatedCode,
      );
      return;
    }

    // Login mode
    final authResult = await ApiService.instance.login(
      emailInput,
      passwordInput,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (authResult.requiresVerification) {
      _enterVerificationMode(
        emailInput,
        type: 'email_verification',
        infoMessage:
            authResult.errorMessage ??
            'Please verify your email address to continue.',
        previewCode: authResult.previewCode,
      );
      return;
    }

    if (!authResult.isSuccess) {
      _showErrorSnackBar(authResult.errorMessage ?? 'Authentication failed');
      return;
    }

    final userRole = authResult.role == 'admin'
        ? UserRole.admin
        : UserRole.user;

    // Persist or clear Remember Me state and session flags based on user toggle
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool(_prefRememberMe, true);
      await prefs.setString(_prefSavedEmail, emailInput);
      await prefs.setString(_prefSavedRole, userRole.name);
      await prefs.setBool(_prefAutoLogin, true);
    } else {
      await prefs.setBool(_prefRememberMe, false);
      await prefs.remove(_prefSavedEmail);
      await prefs.remove(_prefSavedRole);
      await prefs.setBool(_prefAutoLogin, false);
    }

    if (!mounted) return;

    _showSuccessSnackBar(
      userRole == UserRole.admin
          ? 'Authenticated as Administrator'
          : 'Logged in successfully.',
    );

    widget.onLoginSuccess(userRole, authResult.email ?? emailInput);
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);

    try {
      final bool isIOS = !kIsWeb && Platform.isIOS;
      GoogleSignInAccount? googleUser;

      // On iOS, clientId is passed to GIDSignIn; on Android, serverClientId is passed
      // so Google Play Services can perform secure backend token exchange.
      try {
        final googleSignIn = GoogleSignIn(
          scopes: const ['email', 'profile'],
          clientId: isIOS ? _googleIosClientId : null,
          serverClientId: _googleServerClientId,
        );

        // Safely sign out any previous cached session so the account chooser is presented
        try {
          await googleSignIn.signOut();
        } catch (_) {}

        googleUser = await googleSignIn.signIn();
      } catch (clientErr) {
        debugPrint(
          '[GoogleSignIn] Primary sign-in error: $clientErr, attempting fallback...',
        );
        final fallbackSignIn = GoogleSignIn(
          scopes: const ['email', 'profile'],
          clientId: isIOS ? _googleIosClientId : null,
          serverClientId: isIOS ? null : _googleServerClientId,
        );
        try {
          await fallbackSignIn.signOut();
        } catch (_) {}
        googleUser = await fallbackSignIn.signIn();
      }

      if (googleUser == null) {
        // User dismissed/canceled the native Google account picker
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }

      final email = googleUser.email.trim();
      final name = googleUser.displayName ?? email.split('@')[0];
      final googleId = googleUser.id;
      final avatar = googleUser.photoUrl;

      final authResult = await ApiService.instance.loginWithGoogle(
        email: email,
        name: name,
        googleId: googleId,
        avatar: avatar,
      );

      if (!mounted) return;
      setState(() => _isGoogleLoading = false);

      if (!authResult.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  LucideIcons.alertCircle,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    authResult.errorMessage ?? 'Google authentication failed',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
        return;
      }

      final userRole =
          (authResult.role == 'admin' || email.toLowerCase().contains('admin'))
          ? UserRole.admin
          : UserRole.user;

      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setBool(_prefRememberMe, true);
        await prefs.setString(_prefSavedEmail, email);
        await prefs.setString(_prefSavedRole, userRole.name);
        await prefs.setBool(_prefAutoLogin, true);
      } else {
        await prefs.setBool(_prefRememberMe, false);
        await prefs.remove(_prefSavedEmail);
        await prefs.remove(_prefSavedRole);
        await prefs.setBool(_prefAutoLogin, false);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(LucideIcons.globe, size: 18, color: Color(0xFF4285F4)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Signed in with Google as $email',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 3),
        ),
      );

      widget.onLoginSuccess(userRole, email);
    } catch (e) {
      debugPrint('[GoogleSignIn] Real verification result/error: $e');
      if (!mounted) return;
      setState(() => _isGoogleLoading = false);
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('cancel') ||
          errStr.contains('abort') ||
          errStr.contains('-4') ||
          errStr.contains('12501')) {
        // User voluntarily dismissed or canceled the native Google account picker
        return;
      }

      final bool isIOS = !kIsWeb && Platform.isIOS;
      if (isIOS &&
          (errStr.contains('-5') ||
              errStr.contains('url scheme') ||
              errStr.contains('client') ||
              errStr.contains('sign_in_failed'))) {
        _showGoogleSignInErrorDialog(context, e);
        return;
      }

      String userMessage = 'Google Sign-In: $e';
      if (errStr.contains('10') || errStr.contains('developer_error')) {
        userMessage =
            'Google Sign-In: Android SHA-1 fingerprint needs to be registered in Google Cloud / Firebase console.';
      } else if (errStr.contains('network') || errStr.contains('7')) {
        userMessage =
            'Google Sign-In: Network connection issue. Please check your internet connection.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userMessage,
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
  }

  void _showGoogleSignInErrorDialog(BuildContext context, dynamic error) {
    final bool isIOS = !kIsWeb && Platform.isIOS;
    final errStr = error.toString().toLowerCase();

    String title = 'Google Sign-In';
    String description =
        'An error occurred during Google Sign-In. You can sign in using your email and password, or try again.';

    if (errStr.contains('network') || errStr.contains('7')) {
      title = 'Network Problem';
      description =
          'Could not reach Google authentication servers. Please verify your internet connection.';
    } else if (isIOS) {
      title = 'iPhone Google Sign-In Setup';
      description =
          'Google Sign-In on iOS requires an iOS OAuth Client ID registered in Google Cloud Console matching your Bundle Identifier:\n\n'
          'com.navcore.app.navcoreMobile\n\n'
          'You can also sign in or create an account instantly using email and password below.';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                LucideIcons.alertCircle,
                color: Color(0xFFEF4444),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          description,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            height: 1.5,
            color: const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Dismiss',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'OK',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isForgotPasswordMode) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _handleForgotPasswordBack();
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft, color: Color(0xFF0F172A)),
              tooltip: 'Back',
              onPressed: _handleForgotPasswordBack,
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 12.0,
              ),
              child: _forgotPasswordStep == 1
                  ? _buildForgotPasswordStep1()
                  : (_forgotPasswordStep == 2
                        ? _buildForgotPasswordStep2()
                        : _buildForgotPasswordStep3()),
            ),
          ),
        ),
      );
    }

    const primaryColor = Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Color(0xFF0F172A)),
          onPressed: () {
            if (_isVerificationMode) {
              _resendTimer?.cancel();
              setState(() => _isVerificationMode = false);
            } else {
              widget.onBackToWelcome();
            }
          },
        ),
        title: Text(
          _isVerificationMode
              ? (_verificationType == 'login_otp'
                    ? 'Sign-In Verification'
                    : 'Verify Email Address')
              : (_isSignUpMode ? 'Create Account' : 'Log In'),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0F172A),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo & Title Header
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onLongPress: _showServerConfigDialog,
                      child: const NexNavLogoWidget(size: 56),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isVerificationMode
                          ? (_verificationType == 'login_otp'
                                ? 'Security Verification'
                                : 'Verify Email')
                          : (_isSignUpMode
                                ? 'Create Account'
                                : 'Welcome to NexNav'),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isVerificationMode
                          ? 'Enter the 6-digit code sent to your real email'
                          : (_isSignUpMode
                                ? 'Enter your details to create an account'
                                : 'Log in with your credentials'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Render either Verification Card or Auth Form Card
              if (_isVerificationMode)
                _buildVerificationCard()
              else
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A0F172A),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Mode Selector (Log In / Create Account)
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _isSignUpMode = false;
                                      _formKey.currentState?.reset();
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: !_isSignUpMode
                                          ? Colors.white
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: !_isSignUpMode
                                          ? const [
                                              BoxShadow(
                                                color: Color(0x0F000000),
                                                blurRadius: 4,
                                                offset: Offset(0, 2),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'Log In',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: !_isSignUpMode
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: !_isSignUpMode
                                            ? const Color(0xFF0F172A)
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _isSignUpMode = true;
                                      _formKey.currentState?.reset();
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _isSignUpMode
                                          ? Colors.white
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: _isSignUpMode
                                          ? const [
                                              BoxShadow(
                                                color: Color(0x0F000000),
                                                blurRadius: 4,
                                                offset: Offset(0, 2),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'Create Account',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: _isSignUpMode
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: _isSignUpMode
                                            ? const Color(0xFF0F172A)
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Optional Full Name for Sign Up
                        if (_isSignUpMode) ...[
                          Text(
                            'Full Name',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _nameController,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Enter your full name',
                              hintStyle: const TextStyle(
                                color: Color(0xFF94A3B8),
                              ),
                              prefixIcon: const Icon(
                                LucideIcons.user,
                                size: 18,
                                color: Color(0xFF64748B),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: primaryColor,
                                  width: 1.8,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (_isSignUpMode &&
                                  (value == null || value.trim().isEmpty)) {
                                return 'Please enter your name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Email Input
                        Text(
                          'Email Address',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0F172A),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter your email',
                            hintStyle: const TextStyle(
                              color: Color(0xFF94A3B8),
                            ),
                            prefixIcon: const Icon(
                              LucideIcons.mail,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: primaryColor,
                                width: 1.8,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your email address';
                            }
                            final clean = value.trim();
                            final emailRegex = RegExp(
                              r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
                            );
                            if (!emailRegex.hasMatch(clean)) {
                              return 'Please enter a valid, real email address';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // Password Header
                        Text(
                          _isSignUpMode ? 'Create Password' : 'Password',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Password Input
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_isPasswordVisible,
                          onChanged: (val) {
                            setState(() {});
                          },
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0F172A),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter your password',
                            hintStyle: const TextStyle(
                              color: Color(0xFF94A3B8),
                            ),
                            errorMaxLines: 2,
                            prefixIcon: const Icon(
                              LucideIcons.lock,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible
                                    ? LucideIcons.eyeOff
                                    : LucideIcons.eye,
                                size: 18,
                                color: const Color(0xFF64748B),
                              ),
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: primaryColor,
                                width: 1.8,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your password';
                            }
                            // Enforce strong password policy with detailed missing requirements
                            final strength = PasswordStrength.evaluate(
                              value.trim(),
                            );
                            if (!strength.isStrong) {
                              return 'Missing: ${strength.missingRequirements.join(', ')}';
                            }
                            return null;
                          },
                        ),

                        // Live Missing Requirements Alert (only appears when text is entered and criteria are missing)
                        if (_passwordController.text.isNotEmpty)
                          _buildMissingPasswordAlert(),

                        // Confirm Password (Sign Up Mode)
                        if (_isSignUpMode) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Confirm Password',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: !_isConfirmPasswordVisible,
                            onChanged: (val) {
                              setState(() {});
                            },
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Confirm your password',
                              hintStyle: const TextStyle(
                                color: Color(0xFF94A3B8),
                              ),
                              errorMaxLines: 2,
                              prefixIcon: const Icon(
                                LucideIcons.checkCheck,
                                size: 18,
                                color: Color(0xFF64748B),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isConfirmPasswordVisible
                                      ? LucideIcons.eyeOff
                                      : LucideIcons.eye,
                                  size: 18,
                                  color: const Color(0xFF64748B),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isConfirmPasswordVisible =
                                        !_isConfirmPasswordVisible;
                                  });
                                },
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: primaryColor,
                                  width: 1.8,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (_isSignUpMode) {
                                if (value == null || value.isEmpty) {
                                  return 'Please confirm your password';
                                }
                                if (value != _passwordController.text) {
                                  return 'Passwords do not match';
                                }
                              }
                              return null;
                            },
                          ),
                          if (_confirmPasswordController.text.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  _confirmPasswordController.text ==
                                          _passwordController.text
                                      ? LucideIcons.check
                                      : LucideIcons.x,
                                  size: 13,
                                  color:
                                      _confirmPasswordController.text ==
                                          _passwordController.text
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFEF4444),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _confirmPasswordController.text ==
                                          _passwordController.text
                                      ? 'Passwords match'
                                      : 'Passwords do not match yet',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        _confirmPasswordController.text ==
                                            _passwordController.text
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],

                        // Remember Me Control (Only in Log In Mode)
                        if (!_isSignUpMode) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _rememberMe = !_rememberMe;
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                    horizontal: 2,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: Checkbox(
                                          value: _rememberMe,
                                          activeColor: primaryColor,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          onChanged: (val) {
                                            setState(() {
                                              _rememberMe = val ?? true;
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Remember me',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _forgotEmailController.text =
                                        _emailController.text.trim();
                                    _isForgotPasswordMode = true;
                                    _forgotPasswordStep = 1;
                                    for (final c in _forgotOtpControllers) {
                                      c.clear();
                                    }
                                    _forgotNewPasswordController.clear();
                                    _forgotConfirmPasswordController.clear();
                                  });
                                },
                                child: Text(
                                  'Forgot Password?',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 18),

                        // Submit Button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleAuth,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _isSignUpMode
                                          ? 'CREATE ACCOUNT'
                                          : 'LOG IN',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      LucideIcons.arrowRight,
                                      size: 16,
                                    ),
                                  ],
                                ),
                        ),

                        const SizedBox(height: 18),

                        // Modern Social & Smart Login Divider
                        Row(
                          children: [
                            const Expanded(
                              child: Divider(
                                color: Color(0xFFE2E8F0),
                                thickness: 1,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'OR CONTINUE WITH',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF94A3B8),
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const Expanded(
                              child: Divider(
                                color: Color(0xFFE2E8F0),
                                thickness: 1,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Continue with Google Button
                        OutlinedButton(
                          onPressed: (_isLoading || _isGoogleLoading)
                              ? null
                              : _handleGoogleSignIn,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0F172A),
                            minimumSize: const Size(double.infinity, 50),
                            side: const BorderSide(
                              color: Color(0xFFCBD5E1),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: _isGoogleLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Color(0xFF4285F4),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      LucideIcons.globe,
                                      size: 20,
                                      color: Color(0xFF4285F4),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      _isSignUpMode
                                          ? 'Sign up with Google'
                                          : 'Continue with Google',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF1E293B),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (!_isVerificationMode) ...[
                const SizedBox(height: 18),

                // Switch Mode Footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isSignUpMode
                          ? 'Already have an account? '
                          : "Don't have an account? ",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isSignUpMode = !_isSignUpMode;
                          _formKey.currentState?.reset();
                        });
                      },
                      child: Text(
                        _isSignUpMode ? 'Log In' : 'Sign Up',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerificationCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _verificationType == 'login_otp'
                ? 'Sign-In Verification'
                : 'Confirm Email & Create Account',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _pendingSignUpEmail != null
                ? 'Your account will be officially created once you confirm the 6-digit code sent to:'
                : 'We sent a 6-digit verification code to:',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.mail, size: 14, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _verifyingEmail,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 6-digit OTP Input Boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (index) => _buildOtpDigitBox(index)),
          ),

          const SizedBox(height: 20),

          // Resend Code timer / button
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                "Didn't receive the code? ",
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  color: const Color(0xFF64748B),
                ),
              ),
              if (!_canResend)
                Text(
                  'Resend in ${_resendCountdown}s',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2563EB),
                  ),
                )
              else
                InkWell(
                  onTap: _isResending ? null : _handleResendOtp,
                  child: Text(
                    _isResending ? 'Sending...' : 'Resend Code',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 20),

          // Verify Button (wrapped in FittedBox to eliminate overflow)
          ElevatedButton(
            onPressed: _isVerifyingOtp ? null : _submitOtpVerification,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isVerifyingOtp
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _verificationType == 'login_otp'
                              ? 'VERIFY & SIGN IN'
                              : 'CONFIRM & CREATE ACCOUNT',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(LucideIcons.check, size: 16),
                      ],
                    ),
                  ),
          ),

          const SizedBox(height: 14),

          // Cancel / Back to Login
          TextButton(
            onPressed: () {
              _resendTimer?.cancel();
              setState(() {
                _isVerificationMode = false;
                _pendingSignUpName = null;
                _pendingSignUpEmail = null;
                _pendingSignUpPassword = null;
                _previewOtpCode = null;
              });
            },
            child: Text(
              'Back to Log In',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpDigitBox(int index) {
    return Flexible(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        constraints: const BoxConstraints(maxWidth: 46, maxHeight: 52),
        height: 50,
        child: TextFormField(
          controller: _otpControllers[index],
          focusNode: _otpFocusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFCBD5E1),
                width: 1.2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFE2E8F0),
                width: 1.2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF2563EB),
                width: 2.0,
              ),
            ),
          ),
          onChanged: (value) {
            if (value.length > 1) {
              // Handle paste of complete 6-digit code!
              final digits = value.replaceAll(RegExp(r'\D'), '');
              for (int i = 0; i < 6; i++) {
                if (i < digits.length) {
                  _otpControllers[i].text = digits[i];
                }
              }
              if (digits.length >= 6) {
                _otpFocusNodes[5].unfocus();
                _submitOtpVerification();
              } else if (digits.isNotEmpty) {
                _otpFocusNodes[digits.length.clamp(0, 5)].requestFocus();
              }
              return;
            }

            if (value.isNotEmpty) {
              _otpControllers[index].text = value;
              if (index < 5) {
                _otpFocusNodes[index + 1].requestFocus();
              } else {
                _otpFocusNodes[index].unfocus();
                final completeCode = List.generate(
                  6,
                  (i) => i == index ? value : _otpControllers[i].text.trim(),
                ).join();
                if (completeCode.length == 6) {
                  _submitOtpVerification();
                }
              }
            } else {
              // Backspace navigation
              if (index > 0) {
                _otpFocusNodes[index - 1].requestFocus();
              }
            }
          },
        ),
      ),
    );
  }

  Widget _buildMissingPasswordAlert() {
    final text = _passwordController.text;
    if (text.isEmpty) return const SizedBox.shrink();
    final strength = PasswordStrength.evaluate(text);
    if (strength.isStrong) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8.5),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA), width: 1.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1.5),
            child: Icon(
              LucideIcons.alertCircle,
              size: 14,
              color: Color(0xFFEF4444),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFDC2626),
                  height: 1.4,
                ),
                children: [
                  const TextSpan(
                    text: 'Missing: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: strength.missingRequirements.join(', ')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
