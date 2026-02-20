import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/child_request_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class BlockedOverlayScreen extends StatelessWidget {
  const BlockedOverlayScreen({
    super.key,
    required this.modeName,
    this.remainingLabel = '1h 34m',
    this.blockedDomain,
    this.child,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
    this.onRequestAccess,
    this.onDismiss,
  });

  final String modeName;
  final String remainingLabel;
  final String? blockedDomain;
  final ChildProfile? child;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;
  final VoidCallback? onRequestAccess;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildShieldIcon(),
                const SizedBox(height: 22),
                Text(
                  'This app is off right now',
                  key: const Key('blocked_overlay_title'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This is blocked during $modeName',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                        height: 1.35,
                      ),
                ),
                if (blockedDomain != null &&
                    blockedDomain!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    blockedDomain!.trim(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ],
                const SizedBox(height: 18),
                _buildStatusCard(context),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    key: const Key('blocked_overlay_request_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E86FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _handleRequestAccess(context),
                    icon: const Icon(Icons.assignment_outlined),
                    label: const Text(
                      'Ask to use it',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    key: const Key('blocked_overlay_dismiss_button'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: Colors.grey.withValues(alpha: 0.35)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _handleDismiss(context),
                    child: const Text(
                      'OK, I understand',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShieldIcon() {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF58A8FF), Color(0xFF2E86FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E86FF).withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.shield_rounded,
        size: 48,
        color: Colors.white,
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    return Container(
      key: const Key('blocked_overlay_status_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9E4F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Free time starts in $remainingLabel',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF334155),
                ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: 0.62,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFF2E86FF),
            backgroundColor: const Color(0xFFD8E8FF),
          ),
        ],
      ),
    );
  }

  void _handleRequestAccess(BuildContext context) {
    if (onRequestAccess != null) {
      onRequestAccess!();
      return;
    }
    final linkedChild = child;
    if (linkedChild == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChildRequestScreen(
          child: linkedChild,
          authService: authService,
          firestoreService: firestoreService,
          parentIdOverride: parentIdOverride,
        ),
      ),
    );
  }

  void _handleDismiss(BuildContext context) {
    if (onDismiss != null) {
      onDismiss!();
      return;
    }
    Navigator.of(context).pop();
  }
}
