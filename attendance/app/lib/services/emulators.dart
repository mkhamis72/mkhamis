import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// `flutter run --dart-define=USE_EMULATORS=true` talks to the local Firebase emulators instead of a real project.
const bool useEmulators = bool.fromEnvironment('USE_EMULATORS');

/// Host of the emulators. Use `10.0.2.2` for the Android emulator, or your computer's LAN IP for a real phone.
const String emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

/// `demo-` project IDs work with the emulators without any real Firebase project or `flutterfire configure`.
/// Must match `--project demo-attendance` used by `npm run serve` in functions/.
const FirebaseOptions demoOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:000000000000:web:0000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'demo-attendance',
);

/// Ports must match the `emulators` section of firebase.json.
Future<void> connectToEmulators() async {
  await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
  FirebaseFunctions.instance.useFunctionsEmulator(emulatorHost, 5001);
}
