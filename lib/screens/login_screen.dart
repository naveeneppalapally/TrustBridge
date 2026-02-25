import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/app_mode.dart';
import 'package:trustbridge_app/services/app_mode_service.dart';
import 'package:trustbridge_app/services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final AppModeService _appModeService = AppModeService();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  StreamSubscription<User?>? _authSubscription;

  bool _isOtpSent = false;
  bool _isLoading = false;
  bool _hasNavigatedToDashboard = false;
  String? _errorMessage;

  ({String route, AppMode mode}) _resolvePostLoginPlan() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final redirectRaw = args['redirectAfterLogin'];
      final targetModeRaw = args['targetMode'];
      final redirectRoute = redirectRaw is String ? redirectRaw.trim() : '';
      final targetMode = targetModeRaw is String
          ? targetModeRaw.trim().toLowerCase()
          : '';
      if (redirectRoute.isNotEmpty) {
        return (
          route: redirectRoute,
          mode: targetMode == 'child' ? AppMode.child : AppMode.parent,
        );
      }
    }
    return (route: '/parent/dashboard', mode: AppMode.parent);
  }

  Future<void> _goToDashboardIfNeeded() async {
    if (!mounted || _hasNavigatedToDashboard) {
      return;
    }
    _hasNavigatedToDashboard = true;
    final plan = _resolvePostLoginPlan();
    try {
      await _appModeService.setMode(plan.mode);
    } catch (_) {
      // Navigation should still proceed if secure mode persistence fails.
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(plan.route);
  }

  String _friendlyError(String fallback) {
    final code = _authService.lastErrorMessage;
    if (code == null || code.isEmpty) {
      return fallback;
    }

    switch (code) {
      case 'network-request-failed':
      case 'network-timeout':
        return 'Firebase sign-in did not complete on this network. Retry once. If it still fails, check Wi-Fi/router filtering, disable VPN/Private DNS, or try mobile data.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Invalid email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      default:
        return '$fallback ($code)';
    }
  }

  @override
  void initState() {
    super.initState();
    _authSubscription = _authService.authStateChanges.listen((user) {
      if (!mounted || user == null) {
        return;
      }
      unawaited(_goToDashboardIfNeeded());
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp({bool isResend = false}) async {
    final phoneText = _phoneController.text.trim();
    if (phoneText.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your mobile number.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await _authService.sendOTP(phoneText);

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
      _isOtpSent = success || _isOtpSent;
      _errorMessage = success
          ? (isResend ? 'OTP resent successfully.' : null)
          : _friendlyError('Failed to send OTP. Check number and try again.');
    });
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length < 6) {
      setState(() {
        _errorMessage = 'Enter a valid 6-digit OTP.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = await _authService.verifyOTP(otp);
    final resolvedUser = user ?? _authService.currentUser;

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
    });

    if (resolvedUser == null) {
      setState(() {
        _errorMessage = _friendlyError(
          'Invalid OTP or verification failed. Try again.',
        );
      });
      return;
    }

    await _goToDashboardIfNeeded();
  }

  Future<void> _showEmailAuthSheet() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool isSignUp = false;
    bool isLoading = false;
    String? errorMessage;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              final sheetNavigator = Navigator.of(sheetContext);
              final email = emailController.text.trim();
              final password = passwordController.text;
              if (email.isEmpty || password.isEmpty) {
                setModalState(() {
                  errorMessage = 'Email and password are required.';
                });
                return;
              }
              if (password.length < 6) {
                setModalState(() {
                  errorMessage = 'Password must be at least 6 characters.';
                });
                return;
              }

              setModalState(() {
                isLoading = true;
                errorMessage = null;
              });

              final user = isSignUp
                  ? await _authService.signUpWithEmail(
                      email: email,
                      password: password,
                    )
                  : await _authService.signInWithEmail(
                      email: email,
                      password: password,
                    );
              final resolvedUser = user ?? _authService.currentUser;

              if (!mounted) {
                return;
              }

              if (resolvedUser == null) {
                setModalState(() {
                  isLoading = false;
                  errorMessage = _friendlyError(
                    isSignUp
                        ? 'Sign up failed. Try again.'
                        : 'Sign in failed. Try again.',
                  );
                });
                return;
              }

              if (sheetNavigator.canPop()) {
                sheetNavigator.pop();
              }
              await _goToDashboardIfNeeded();
            }

            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isSignUp ? 'Create account with Email' : 'Login with Email',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorMessage!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: isLoading ? null : submit,
                    child: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isSignUp ? 'Create Account' : 'Login'),
                  ),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () {
                            setModalState(() {
                              isSignUp = !isSignUp;
                              errorMessage = null;
                            });
                          },
                    child: Text(
                      isSignUp
                          ? 'Already have an account? Login'
                          : 'No account? Create one',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    emailController.dispose();
    passwordController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= 600;

    final horizontalPadding = isTablet ? 40.0 : 24.0;
    final topSpacing = isTablet ? 56.0 : 36.0;
    final maxContentWidth = isTablet ? 640.0 : 420.0;

    final backgroundColor =
        isDark ? const Color(0xFF101A22) : const Color(0xFFF5F7F8);
    final cardColor = isDark ? const Color(0xFF1F2937) : Colors.white;
    final mutedText = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final borderColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final fieldColor =
        isDark ? const Color(0xFF111827) : const Color(0xFFF1F5F9);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: topSpacing,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(
                    colorScheme: colorScheme,
                    mutedText: mutedText,
                    isTablet: isTablet,
                    isDark: isDark,
                  ),
                  SizedBox(height: isTablet ? 42 : 32),
                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.20)
                              : Colors.black.withValues(alpha: 0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(isTablet ? 28 : 20),
                      child: _isOtpSent
                          ? _buildOtpStep(
                              colorScheme: colorScheme,
                              borderColor: borderColor,
                              fieldColor: fieldColor,
                              mutedText: mutedText,
                            )
                          : _buildPhoneStep(
                              colorScheme: colorScheme,
                              borderColor: borderColor,
                              fieldColor: fieldColor,
                              mutedText: mutedText,
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildAlternativeActions(mutedText: mutedText),
                  SizedBox(height: isTablet ? 48 : 42),
                  _buildFooter(colorScheme: colorScheme, mutedText: mutedText),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required ColorScheme colorScheme,
    required Color mutedText,
    required bool isTablet,
    required bool isDark,
  }) {
    return Column(
      children: [
        Container(
          width: isTablet ? 88 : 80,
          height: isTablet ? 88 : 80,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.shield_outlined,
                color: colorScheme.primary,
                size: isTablet ? 50 : 46,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Icon(Icons.straighten, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'TrustBridge',
          style: TextStyle(
            fontSize: isTablet ? 40 : 48,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 250,
          child: Text(
            'Set boundaries without\nbreaking trust',
            style: TextStyle(
              fontSize: 16,
              color: mutedText,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneStep({
    required ColorScheme colorScheme,
    required Color borderColor,
    required Color fieldColor,
    required Color mutedText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Mobile Number',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: fieldColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.flag_outlined, size: 18),
              const SizedBox(width: 6),
              Text(
                '+91',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: mutedText.withValues(alpha: 0.9),
                ),
              ),
              Icon(Icons.expand_more, size: 18, color: mutedText),
              const SizedBox(width: 8),
              Container(width: 1, height: 22, color: borderColor),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '000 000 0000',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _isLoading ? null : () => _sendOtp(),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Send OTP',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep({
    required ColorScheme colorScheme,
    required Color borderColor,
    required Color fieldColor,
    required Color mutedText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the 6-digit OTP sent to ${_phoneController.text.trim()}',
          style: TextStyle(fontSize: 14, color: mutedText),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: fieldColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 6,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '000000',
              counterText: '',
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorMessage!,
            style: TextStyle(
              color: _errorMessage == 'OTP resent successfully.'
                  ? Colors.green
                  : Colors.redAccent,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _isLoading ? null : _verifyOtp,
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Verify OTP',
                    style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _isOtpSent = false;
                        _errorMessage = null;
                        _otpController.clear();
                      });
                    },
              child: const Text('Change Number'),
            ),
            TextButton(
              onPressed: _isLoading ? null : () => _sendOtp(isResend: true),
              child: const Text('Resend OTP'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlternativeActions({required Color mutedText}) {
    return Column(
      children: [
        TextButton(
          onPressed: _showEmailAuthSheet,
          child: const Text('Login with Email'),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: Divider(color: mutedText.withValues(alpha: 0.35))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'or',
                style: TextStyle(
                    color: mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Divider(color: mutedText.withValues(alpha: 0.35))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _socialButton(icon: Icons.g_mobiledata),
            const SizedBox(width: 12),
            _socialButton(icon: Icons.apple),
          ],
        ),
      ],
    );
  }

  Widget _socialButton({required IconData icon}) {
    return OutlinedButton(
      onPressed: () {},
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(50, 50),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      child: Icon(icon, size: 24),
    );
  }

  Widget _buildFooter({
    required ColorScheme colorScheme,
    required Color mutedText,
  }) {
    return Text.rich(
      TextSpan(
        style: TextStyle(color: mutedText, fontSize: 11.5, height: 1.45),
        children: [
          const TextSpan(text: "By continuing, you agree to TrustBridge's "),
          TextSpan(
            text: 'Terms of Service',
            style: TextStyle(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: TextStyle(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
