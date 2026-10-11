import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/admin/admin_home.dart';
import 'screens/lecturer/lecturer_home.dart';
import 'screens/lecturer/pending_approval_screen.dart';
import 'screens/login_screen.dart';
import 'screens/student/student_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark, useMaterial3: true),
      home: const AuthGate(),
    );
  }
}

/// Sends the signed-in user to the home screen for their role (custom claim set at registration).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.idTokenChanges(),
      builder: (context, snap) {
        final user = snap.data;
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (user == null) return const LoginScreen();
        return FutureBuilder<IdTokenResult>(
          future: user.getIdTokenResult(),
          builder: (context, tokenSnap) {
            if (!tokenSnap.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final claims = tokenSnap.data!.claims ?? {};
            final personId = '${claims['personId'] ?? ''}';
            switch (claims['role']) {
              case 'student':
                return StudentHome(studentId: personId);
              case 'lecturer':
                if (claims['approved'] != true) return const PendingApprovalScreen();
                return const LecturerHome();
              case 'admin':
                return const AdminHome();
              default:
                return const _NoRoleScreen();
            }
          },
        );
      },
    );
  }
}

class _NoRoleScreen extends StatelessWidget {
  const _NoRoleScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Your account is not set up correctly. Register again or contact support.'),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Sign out')),
        ]),
      ),
    );
  }
}
