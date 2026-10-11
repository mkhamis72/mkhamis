import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Must match `emailForId` in functions/src/roster.ts.
String emailForId(String id) => '${id.trim().toLowerCase()}@attendance.local';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _id = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailForId(_id.text),
        password: _password.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = switch (e.code) {
            'invalid-credential' || 'wrong-password' || 'user-not-found' => 'Wrong ID or password.',
            'too-many-requests' => 'Too many attempts. Try again later.',
            _ => e.message ?? e.code,
          });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.qr_code_scanner, size: 72),
              const SizedBox(height: 12),
              Text('Class Attendance', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 32),
              TextField(
                controller: _id,
                decoration: const InputDecoration(labelText: 'University ID', border: OutlineInputBorder()),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                onSubmitted: (_) => _signIn(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _signIn,
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Sign in'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
