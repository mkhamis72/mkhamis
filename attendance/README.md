# Class Attendance (QR + Location)

Students sign attendance by scanning a QR code in the lecture hall. The design blocks the usual trick of sending a photo of the QR to friends who aren't in class.

- **`app/`**: one Flutter app (Android, iOS, Web). The screen you get depends on your role:
  - **Student:** scan the QR, see own attendance history.
  - **Lecturer:** create a session and choose **Rotating** or **Static** QR, show it full screen (projector/phone), live count, pause / regenerate / extend / end, attendee report with manual override and CSV export.
  - **Admin:** import users from CSV, manage halls (GPS position + radius) and courses, reset a student's device binding.
- **`functions/`**: Firebase Cloud Functions (TypeScript). **Every check runs on the server.** The app can never write attendance itself.
- `firestore.rules`: clients can't write attendance or sessions, and can never read QR secrets.

## How cheating is blocked

| Layer | What it stops | Setting |
|---|---|---|
| **Rotating QR** (mode 1) | The QR is HMAC-signed and changes every 10 s, and the server accepts about 30 s at most. A forwarded screenshot is dead on arrival. Needs internet on the lecturer's screen. | Lecturer picks the QR type |
| **Static QR + GPS** (mode 2) | For halls without a live screen. The code can be printed, so the **geofence is always enforced** for it. | Lecturer picks the QR type |
| **Geofence** | The phone must be within the hall radius (+ up to 30 m of GPS slack). Fixes with poor accuracy (>100 m) and mock locations are rejected. Scans accepted only thanks to the slack are **flagged** for review. | Toggle per session (forced on for static) |
| **Device binding** | Each student account is locked to the first phone that signs in, and one phone can't sign two students into the same session. | Toggle per session |
| **Time window** | Scans are only accepted for N minutes after the session starts (lecturer can extend). | Toggle per session |
| **Regenerate** | Issues a new secret, so every code shown or printed earlier stops working. | Button on the live screen |

Course defaults for the toggles are set by the admin, and the lecturer can change them when creating each session.

## Setup

1. Create a Firebase project and enable **Authentication → Email/Password**, **Firestore** and **Functions** (Blaze plan).
2. Deploy the backend:
   ```bash
   cd attendance/functions && npm install && npm test
   cd .. && firebase use <project-id> && firebase deploy --only functions,firestore
   ```
3. Configure the app (this replaces the placeholder `app/lib/firebase_options.dart`):
   ```bash
   cd attendance/app
   dart pub global activate flutterfire_cli && flutterfire configure
   flutter run            # phone
   flutter build web && cd .. && firebase deploy --only hosting   # lecturer projector / admin
   ```
4. **First admin:** create a user `<id>@attendance.local` in the Firebase console, then give it the custom claims `{"role":"admin","personId":"<id>"}` (e.g. with a one-off Admin SDK script). Then sign in to the app with `<id>` and its password.
5. As admin: import users (CSV `id,name,role,password`), add halls (stand in the hall and tap *Use my current location*), add courses (subject, lecturer ID, student IDs, default hall, default toggles).

Users sign in with their **university ID + password**. Behind the scenes the ID is mapped to `<id>@attendance.local` (see `emailForId` in both `functions/src/roster.ts` and `app/lib/screens/login_screen.dart`).

## Tests

```bash
cd functions && npm test     # QR signing/expiry, geofence, device binding, time window, toggles, static-mode rule, CSV parsing
cd app && flutter analyze && flutter test
```

## Known limits

- Indoor GPS can be 20–50 m off. Pick a hall radius that covers the room, and check the flagged scans.
- A rooted phone can spoof GPS without the OS noticing. Rotating QR + device binding are the main defence, and the geofence is a second layer.
- A student who is actually in the hall can still read a live code out to someone over a video call. Compare the scan count with a quick headcount if this happens.
