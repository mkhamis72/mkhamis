# Class Attendance (QR + Location)

Students sign attendance by scanning a QR code in the lecture hall. The design blocks the usual trick of sending a photo of the QR to friends who aren't in class.

There are only **two roles**, and both sign up in the app themselves. Lecturer accounts need **admin confirmation**. An admin is simply a lecturer whose Staff ID is listed in the server config.

**Student**
- Registers once: Student ID, full name, password. Each ID can be registered only once, and the registering phone becomes the student's attendance phone.
- Scans the QR → ✓ recorded, or the reason it was rejected. Sees own attendance history.
- New or lost phone: sign in on the new phone and tap **Use this phone**. The new phone works **from the next class**. It can't sign a class that had already started when the switch was made.

**Lecturer**
- Registers with Staff ID, full name, password. The account waits on an "awaiting approval" screen until an **admin approves** it, and only then can it create QR codes.
- **Admins** (lecturers listed in `ADMIN_STAFF_IDS`) get an extra **Approvals** tab: approve or reject (which deletes the account) pending lecturers. Admin accounts are approved automatically when they register.
- **New QR:** Subject, Hall name, **GPS location** (stand in the hall and tap *Use my current location*) + allowed radius, **QR type Rotating / Static**, anti-cheat toggles. Recently used subject/hall/location sets appear as one-tap picks.
- Live QR screen (projector or phone): live count, pause / resume, regenerate, extend time, end. A static QR can be printed or saved as PDF.
- **Attended students:** per session, and across all sessions with date range + search. Flagged scans are marked, an entry can be removed, and either list exports to CSV.

## How cheating is blocked (all checks run on the server)

| Layer | What it stops | Setting |
|---|---|---|
| **Rotating QR** | The QR is HMAC-signed and changes every 10 s, and the server accepts about 30 s at most. A forwarded screenshot is dead on arrival. Needs internet on the lecturer's device. | Lecturer picks the QR type |
| **Static QR** | For halls without a live screen. The code can be printed, so the **geofence is always enforced** for it. | Lecturer picks the QR type |
| **Geofence** | The phone must be within the hall radius (+ up to 30 m of GPS slack). Fixes with poor accuracy (>100 m) and mock locations are rejected. Scans accepted only thanks to the slack are **flagged**. | Toggle (forced on for static) |
| **Lecturer approval** | Only lecturers approved by an admin can create sessions; the server rejects every lecturer call from an unapproved account. | Always |
| **Device binding** | An account only signs from its own phone, and a phone can't sign two students into the same session. A **phone switch only counts for sessions that start after it**, so a student can't switch phones in class to sign a friend in. | Toggle |
| **Time window** | Scans are only accepted for N minutes after the session starts (the lecturer can extend). | Toggle |
| **Regenerate** | Issues a new secret, so every code shown or printed earlier stops working. | Button on the live screen |

The app never writes attendance itself: `firestore.rules` block all client writes, and QR secrets are never readable.

## Layout

- `app/`: Flutter app (Android, iOS, Web).
- `functions/`: Cloud Functions (TypeScript). Pure check logic is in `src/checks.ts`, `src/qr.ts` and `src/geo.ts`; the callable endpoints are in `src/index.ts`.
- `firestore.rules`, `firestore.indexes.json`, `firebase.json`.

## Setup

1. Create a Firebase project and enable **Authentication → Email/Password**, **Firestore** and **Functions** (Blaze plan).
2. Choose who can approve lecturers: copy `functions/.env.example` to `functions/.env` and set `ADMIN_STAFF_IDS=L001,L002` (staff IDs). Those lecturers are approved and made admins when they register in the app. **Register the admin accounts right after deploying**: whoever registers first with a listed ID becomes that admin.
3. Deploy the backend:
   ```bash
   cd attendance/functions && npm install && npm test
   cd .. && firebase use <project-id> && firebase deploy --only functions,firestore
   ```
4. Configure and run the app (this replaces the placeholder `app/lib/firebase_options.dart`):
   ```bash
   cd attendance/app
   dart pub global activate flutterfire_cli && flutterfire configure
   flutter run                                                    # phone
   flutter build web && cd .. && firebase deploy --only hosting   # lecturer projector screen
   ```

Users sign in with their **ID + password**. Behind the scenes the ID is mapped to `<id>@attendance.local` (see `emailForId` in `functions/src/roster.ts` and `app/lib/screens/login_screen.dart`).

## Tests

```bash
cd functions && npm test     # QR signing/expiry, geofence, device binding + phone-switch rule, time window, toggles, static-mode rule, registration validation, admin ID list
cd app && flutter analyze && flutter test
```

## Known limits

- Indoor GPS can be 20–50 m off. Pick a radius that covers the room, and check the flagged scans.
- A rooted phone can spoof GPS without the OS noticing. Rotating QR + device binding are the main defence, and the geofence is a second layer.
- A student who is actually in the hall can still read a live code out to someone over a video call. Compare the count with a quick headcount if this happens.
- Adding or removing an admin means changing `ADMIN_STAFF_IDS` and redeploying. The list only applies at registration, so an existing account has to have its claims changed in the Firebase console.
- There is no password reset yet. A forgotten password has to be reset in the Firebase console.
