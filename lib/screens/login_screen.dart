import 'package:flutter/material.dart';
import 'package:trustbridge_app/screens/dashboard_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  bool _isOtpSent = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
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
          : 'Failed to send OTP. Check number and try again.';
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

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
    });

    if (user == null) {
      setState(() {
        _errorMessage = 'Invalid OTP or verification failed. Try again.';
      });
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
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
          onPressed: () {},
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
