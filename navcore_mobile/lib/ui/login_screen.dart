import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/api_service.dart';
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

  static const String _prefRememberMe = 'NexNav_remember_me';
  static const String _prefSavedEmail = 'NexNav_remembered_email';
  static const String _prefSavedRole = 'NexNav_remembered_role';
  static const String _prefAutoLogin = 'NexNav_auto_login_enabled';
  static const String _googleServerClientId =
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
        } else if (widget.initialRole == UserRole.admin &&
            _emailController.text.isEmpty) {
          _emailController.text = 'admin@nexnav.com';
          _passwordController.text = 'Admin@1234';
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleAuth() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isSignUpMode &&
        _passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Passwords do not match. Please verify.',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
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

    setState(() => _isLoading = true);

    final emailInput = _emailController.text.trim();
    final passwordInput = _passwordController.text.trim();

    if (_isSignUpMode) {
      final nameInput = _nameController.text.trim();
      final authResult = await ApiService.instance.register(
        emailInput,
        passwordInput,
        name: nameInput.isNotEmpty ? nameInput : null,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

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
                    authResult.errorMessage ?? 'Registration failed',
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

      if (!mounted) return;

      setState(() {
        _isSignUpMode = false;
        _nameController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
        _emailController.text = emailInput;
      });
      _formKey.currentState?.reset();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                LucideIcons.checkCircle2,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Account created successfully.',
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
      return;
    }

    // Login mode
    final authResult = await ApiService.instance.login(
      emailInput,
      passwordInput,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

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
                  authResult.errorMessage ?? 'Authentication failed',
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.checkCircle2, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                userRole == UserRole.admin
                    ? 'Authenticated as Administrator'
                    : 'Logged in successfully.',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 3),
      ),
    );

    widget.onLoginSuccess(userRole, authResult.email ?? emailInput);
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);

    try {
      GoogleSignInAccount? googleUser;
      try {
        final googleSignIn = GoogleSignIn(
          scopes: ['email', 'profile'],
          serverClientId: _googleServerClientId,
        );
        // Disconnect/sign out any cached account so the native "Choose an account" sheet always pops up
        try {
          await googleSignIn.signOut();
        } catch (_) {}

        googleUser = await googleSignIn.signIn();
      } catch (clientErr) {
        debugPrint(
          '[GoogleSignIn] Server client error: $clientErr, falling back to direct sign-in...',
        );
        final fallbackSignIn = GoogleSignIn(
          scopes: ['email', 'profile'],
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
      if (errStr.contains('cancel') || errStr.contains('abort')) {
        // User voluntarily dismissed or canceled the native Google account picker
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

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Color(0xFF0F172A)),
          onPressed: widget.onBackToWelcome,
        ),
        title: Text(
          _isSignUpMode ? 'Create Account' : 'Log In',
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
                      _isSignUpMode ? 'Create Account' : 'Welcome to NexNav',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isSignUpMode
                          ? 'Enter your details to create an account'
                          : 'Log in with your credentials',
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

              // Login / Register Form Card
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
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
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
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
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
                                    _isSignUpMode ? 'CREATE ACCOUNT' : 'LOG IN',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(LucideIcons.arrowRight, size: 16),
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
                            padding: const EdgeInsets.symmetric(horizontal: 12),
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

              const SizedBox(height: 24),
            ],
          ),
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
