# Development & Deployment (VS Code)

## 1. Prerequisites
| Tool | Version | Install |
|---|---|---|
| VS Code | latest | https://code.visualstudio.com |
| Node.js | 22 | https://nodejs.org |
| Flutter SDK | stable 3.x (Dart ≥ 3.4) | https://docs.flutter.dev/get-started/install |
| Firebase CLI | latest | `npm i -g firebase-tools` |
| FlutterFire CLI | latest | `dart pub global activate flutterfire_cli` |
| Java 17+ | for the Firestore emulator | |
| Android Studio / Xcode | for phone builds | |

Recommended VS Code extensions are listed in `attendance/.vscode/extensions.json`: VS Code offers to install them when you open the folder.

## 2. First-time setup
```bash
git clone https://github.com/mkhamis72/mkhamis.git
cd mkhamis && git checkout claude/brave-galileo-v49ynt
code attendance                    # open this folder in VS Code

# Firebase project (console.firebase.google.com):
#   enable Authentication → Email/Password, create Firestore, upgrade to Blaze
firebase login
firebase use --add                 # select the project, alias "default"

cp functions/.env.example functions/.env    # set ADMIN_STAFF_IDS=A001,...
(cd functions && npm install)
(cd app && flutter pub get && flutterfire configure)   # select android, ios, web
```
`flutterfire configure` overwrites the placeholder `app/lib/firebase_options.dart`. Commit it: it holds public client config, not secrets.

## 3. Daily development
| Task | Command (from `attendance/`) | VS Code |
|---|---|---|
| Functions tests | `cd functions && npm test` | Task: **functions: test** |
| Functions typecheck | `cd functions && npx tsc --noEmit` | Task: **functions: typecheck** |
| App analyze / test | `cd app && flutter analyze && flutter test` | Task: **app: analyze** |
| Run app in Chrome | `cd app && flutter run -d chrome` | Run ▶ **App (Chrome)** |
| Run app on phone | `cd app && flutter run` | Run ▶ **App (device)** |
| Local backend | `firebase emulators:start` | Task: **firebase: emulators** |

To point the app at the emulators while developing, add this after `Firebase.initializeApp` in `main.dart`, behind a `const bool.fromEnvironment('USE_EMULATORS')` flag:
```dart
FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001);
```
(Not yet in the code. See the v1.1 backlog in the [PRD](PRD.md#8-release-plan).)

## 4. Deploy
```bash
firebase deploy --only functions,firestore      # backend + rules + indexes
(cd app && flutter build web) && firebase deploy --only hosting
```
Web URL: `https://<project-id>.web.app`.
**Immediately register the admin accounts** (Register → Admin) with the IDs in `ADMIN_STAFF_IDS`.

## 5. Phone builds
- Android: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk` (sideload), or `flutter build appbundle` for Google Play. Set up release signing first.
- iOS: on a Mac, `flutter build ipa` → TestFlight / App Store (Apple Developer account).
- Permissions are already declared: Android `CAMERA`, `ACCESS_FINE/COARSE_LOCATION`, `INTERNET`; iOS `NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`.

## 6. Configuration
| Setting | Where | Meaning |
|---|---|---|
| `ADMIN_STAFF_IDS` | `functions/.env` | Comma-separated Staff IDs allowed to register as admin |
| Slot / tolerance | `functions/src/qr.ts` | `SLOT_SECONDS=10`, `SLOT_TOLERANCE=1` |
| GPS limits | `functions/src/geo.ts` | `MAX_ACCURACY_M=100`, `MAX_ACCURACY_BONUS_M=30` |
| Invite validity | `functions/src/roster.ts` | `INVITE_VALID_DAYS=7` |
| Recent places | `functions/src/index.ts` | `RECENT_PLACES=10` |

## 7. Troubleshooting
| Symptom | Fix |
|---|---|
| App throws "Run `flutterfire configure`…" | Generate `firebase_options.dart` (step 2) |
| Query error "requires an index" | `firebase deploy --only firestore:indexes` (or open the link in the error) |
| "Missing or insufficient permissions" | The query lacks the equality filter the rules need (see [SECURITY §4](SECURITY.md#4-firestore-rules-summary)) |
| Approved lecturer still sees Pending | Tap **Check again** (forces a token refresh) |
| Functions deploy fails on plan | The project must be on the Blaze plan |
