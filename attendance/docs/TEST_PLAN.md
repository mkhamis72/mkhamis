# Test Plan

## 1. Automated

### Functions unit tests (`functions/test/checks.test.ts`, Jest)
Run: `cd attendance/functions && npm test` (26 tests, all must pass).

| Area | Cases |
|---|---|
| QR | Round-trip encode/decode; rotating valid ±1 slot, expired after 3 slots; static never expires; tampered sid, wrong secret (regenerated), wrong mode |
| Geofence | Distance math; `near_hall_edge` flag; reject inaccurate / mocked / missing |
| evaluateScan | Valid; paused/ended; time window on/off; old rotating screenshot; device mismatch / shared phone / first bind / binding off; rebind during vs before session vs binding off; geofence on/off; static forces geofence |
| Registration | emailForId; ID/name/password validation; admin ID list parsing |
| Invites | Code format/uniqueness; normalisation; valid / not found / used / expired; Staff ID lock |
| Contact details | Trim + lower-case email; bad university / mobile / email |

**Rule:** any change to `checks.ts`, `qr.ts`, `geo.ts` or `roster.ts` adds or updates tests here.

### App
Run: `cd attendance/app && flutter analyze && flutter test`. Analyzer must report **No issues found**.
`flutter build web` must succeed (it catches compile errors across every screen).

### Typecheck
`cd attendance/functions && npx tsc --noEmit`.

### Firestore security rules (`functions/test-rules/firestore.rules.test.ts`)
Run: `cd attendance/functions && npm run test:rules` (51 tests). Starts the Firestore emulator (needs Java 17+), loads `../firestore.rules`, seeds data with rules disabled, then tests as signed-out, student, lecturer and admin users with the real custom claims.

| Area | Cases |
|---|---|
| Signed out | Cannot read any collection |
| students | Own record only; lecturers/admins denied |
| staff | Lecturer own only; admin any + pending query; students denied; `personId` alone is not enough without the lecturer role |
| admins | Own record only |
| invites | Admin read + list; lecturers/students denied |
| sessions | Owner read + `lecturerUid` query; others denied; unfiltered query rejected |
| attendance | Lecturer via record + per-session query (with `lecturerUid`); student own + history; others denied; query without `lecturerUid` rejected |
| Server-only | `sessionSecrets`, `deviceUse` unreadable for every role |
| Writes | create/update/delete denied on every collection for every role; a student can't forge attendance |

Mutation check done when the suite was written: allowing client writes on `attendance` makes 4 tests fail.

## 2. Callable integration on the emulators (to automate later)
Verified manually with the Firebase JS SDK against `npm run serve`: admin list enforced, invite lock/reuse, lecturer claims, session + QR, scan accepted/idempotent, outside hall, device mismatch, mid-session phone switch, forged QR, attendee count. Candidate for a committed `test-integration/` suite.

## 3. Manual end-to-end (before each release)

Setup: deployed project (or emulators), laptop browser = lecturer projector, phone A = student 1, phone B = student 2.

| # | Steps | Expected |
|---|---|---|
| E1 | Register admin with a listed ID; try a non-listed ID | Listed: Admin Home. Other: "not on the admin list" |
| E2 | Admin creates an invite locked to L100 → lecturer registers as L100 with the code | Lecturer Home immediately; code shows "Used by L100" |
| E3 | Lecturer L200 registers without a code | Pending screen; admin sees L200 with details; approve → Check again → Lecturer Home |
| E4 | Reuse E2's code; expired code; code locked to another ID | Specific errors, no account created |
| E5 | Lecturer creates a rotating session in the hall | QR refreshes every 10 s; counter 0 |
| E6 | Phone A scans in the hall | ✓; counter 1; appears in the report |
| E7 | Phone A scans again | "Already recorded" |
| E8 | Screenshot the QR, send to phone B outside the hall after 40 s | ✗ expired QR |
| E9 | Static session; phone B scans a photo of it from 500 m away | ✗ not in the lecture hall |
| E10 | Student 2 logs in on phone A and scans | ✗ account registered to another phone |
| E11 | Student 2 taps "Use this phone" on phone A during the session, scans | ✗ switched phones after class started |
| E12 | Pause → scan; Resume → scan; End → scan | ✗ not open / ✓ / ✗ not open |
| E13 | Time window 5 min, scan at 6 min; Extend +5, scan | ✗ window closed / ✓ |
| E14 | Regenerate, scan an old static print | ✗ invalid QR |
| E15 | Remove a student in the report; export CSV | Count decrements; CSV opens with correct columns |
| E16 | Edit My details as student and lecturer | Saved; the name updates in the AppBar after re-login |
| E17 | Turn GPS off and scan a geofenced session | ✗ location required |
