import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Shown to a lecturer whose account an admin has not approved yet.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _checking = false;

  /// Approval changes the account's claims; a forced token refresh picks them up and AuthGate re-routes.
  Future<void> _checkAgain() async {
    setState(() => _checking = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (_) {
      // A rejected account is deleted, so the refresh fails: sign out.
      await FirebaseAuth.instance.signOut();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.hourglass_top, size: 72),
            const SizedBox(height: 16),
            Text('Waiting for approval', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('An admin must approve your lecturer account before you can create attendance QR codes.',
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Check again'),
              onPressed: _checking ? null : _checkAgain,
            ),
            TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Sign out')),
          ]),
        ),
      ),
    );
  }
}
