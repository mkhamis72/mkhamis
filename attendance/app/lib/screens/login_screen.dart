import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/device.dart';

/// Must match `emailForId` in functions/src/roster.ts.
String emailForId(String id) => '${id.trim().toLowerCase()}@attendance.local';

/// Sign in, or register once as a student or lecturer.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _invite = TextEditingController();
  final _university = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  bool _register = false;
  String _role = 'student';
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        if (_role == 'student') {
          await Api.registerStudent(
            studentId: _id.text.trim(),
            name: _name.text.trim(),
            password: _password.text,
            university: _university.text.trim(),
            mobile: _mobile.text.trim(),
            email: _email.text.trim(),
            deviceId: await DeviceId.get(),
          );
        } else if (_role == 'lecturer') {
          await Api.registerLecturer(
            staffId: _id.text.trim(),
            name: _name.text.trim(),
            password: _password.text,
            university: _university.text.trim(),
            mobile: _mobile.text.trim(),
            email: _email.text.trim(),
            inviteCode: _invite.text.trim().isEmpty ? null : _invite.text.trim(),
          );
        } else {
          await Api.registerAdmin(staffId: _id.text.trim(), name: _name.text.trim(), password: _password.text);
        }
      }
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: emailForId(_id.text), password: _password.text);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = switch (e.code) {
            'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-email' => 'Wrong ID or password.',
            'too-many-requests' => 'Too many attempts. Try again later.',
            _ => e.message ?? e.code,
          });
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final idLabel = !_register ? 'ID' : (_role == 'student' ? 'Student ID' : 'Staff ID');
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
              const SizedBox(height: 24),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Sign in')),
                  ButtonSegment(value: true, label: Text('Register')),
                ],
                selected: {_register},
                onSelectionChanged: (s) => setState(() {
                  _register = s.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
              if (_register) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'student', icon: Icon(Icons.school), label: Text('Student')),
                    ButtonSegment(value: 'lecturer', icon: Icon(Icons.co_present), label: Text('Lecturer')),
                    ButtonSegment(value: 'admin', icon: Icon(Icons.admin_panel_settings), label: Text('Admin')),
                  ],
                  selected: {_role},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _role = s.first),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _id,
                decoration: InputDecoration(labelText: idLabel, border: const OutlineInputBorder()),
                textInputAction: TextInputAction.next,
              ),
              if (_register) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
                  textInputAction: TextInputAction.next,
                ),
              ],
              if (_register && _role != 'admin') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _university,
                  decoration: const InputDecoration(labelText: 'University', border: OutlineInputBorder()),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Mobile', border: OutlineInputBorder()),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  textInputAction: TextInputAction.next,
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                onSubmitted: (_) => _submit(),
              ),
              if (_register && _role == 'lecturer') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _invite,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Invite code (optional)',
                    helperText: 'With a code from the admin your account is ready at once. Without one, an admin must approve it.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_register && _role == 'admin') ...[
                const SizedBox(height: 8),
                Text('Only Staff IDs on the admin list can register as admin.', style: Theme.of(context).textTheme.bodySmall),
              ],
              if (_register && _role == 'student') ...[
                const SizedBox(height: 8),
                Text('This phone becomes your attendance phone.', style: Theme.of(context).textTheme.bodySmall),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_register ? 'Create account' : 'Sign in'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
