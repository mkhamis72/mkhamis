# Security & Anti-Cheat Spec

## 1. Threat model

| # | Threat | Defence |
|---|---|---|
| T1 | Student forwards a photo/screenshot of the QR to an absent friend | Rotating QR expires in ~30 s; geofence; static QR always geofenced |
| T2 | Absent student fakes their location | Mock-location flag rejected; accuracy limit; rotating QR + device binding as primary defence |
| T3 | One student signs in for others on their own phone | Device binding: a phone can sign only one student per session |
| T4 | A student logs into a friend's account on their own phone | Account bound to the friend's phone → `device_mismatch`; rebinding mid-class → `device_changed_during_session` |
| T5 | Student forges a QR or edits the payload | HMAC-SHA256 with a per-session secret the client can never read |
| T6 | Client writes attendance directly | Firestore rules: `allow write: if false` everywhere |
| T7 | Anyone registers as a lecturer and creates fake sessions | Lecturer needs `approved` (invite code or admin approval); server checks on every lecturer call |
| T8 | Invite code reused or shared | Single-use (transactional reservation), 7-day expiry, optional Staff ID lock, revocable |
| T9 | Anyone registers as admin | Only IDs in `ADMIN_STAFF_IDS` |
| T10 | Old printed static QR reused next week | Session ended → `session_closed`; Regenerate → new secret |
| T11 | Late scans long after class | Time window (default 15 min) |

## 2. Roles & enforcement points

| Layer | Enforces |
|---|---|
| Custom claims | `role`, `personId`, `approved` (set only by functions) |
| `requireRole(req, role)` | Every callable checks the role claim |
| `requireLecturer(req)` | Lecturer + `approved == true` |
| `loadOwnedSession` | A lecturer can only act on their own sessions |
| `firestore.rules` | Read scoping per role; **no client writes**; `sessionSecrets` and `deviceUse` unreadable |

## 3. Scan checks (in order)

Implemented in `functions/src/checks.ts → evaluateScan()` (pure) plus pre-checks in `submitScan`.

| # | Check | Reject reason | Applies |
|---|---|---|---|
| 0a | QR text parses as a v1 payload | `bad_signature` | always |
| 0b | Session + secret exist | `bad_signature` | always |
| 0c | Already recorded → return success (idempotent) | n/a | always |
| 1 | Session status is `open` | `session_closed` | always |
| 2 | `startsAt ≤ now ≤ startsAt + windowMinutes` | `outside_time_window` | timeWindow on |
| 3 | Payload mode matches the session mode | `wrong_mode` | always |
| 4 | HMAC matches (timing-safe) | `bad_signature` | always |
| 5 | Rotating: `abs(slotNow − t) ≤ 1` | `expired_qr` | rotating |
| 6 | Bound device equals the scanning device (unbound → bind now) | `device_mismatch` | deviceBinding on |
| 7 | `rebindAt` is null or `≤ session.startsAt` | `device_changed_during_session` | deviceBinding on |
| 8 | This device hasn't signed another student into this session | `device_already_used` | deviceBinding on |
| 9 | Location present | `location_missing` | geofence on (always for static) |
| 10 | Not mocked | `location_mocked` | geofence on |
| 11 | accuracy ≤ 100 m | `location_inaccurate` | geofence on |
| 12 | distance ≤ radius + min(accuracy, 30) | `outside_hall` | geofence on |
| ✓ | Accepted. Flag `near_hall_edge` if distance > radius | n/a | |

Constants: `SLOT_SECONDS = 10`, `SLOT_TOLERANCE = 1`, `MAX_ACCURACY_M = 100`, `MAX_ACCURACY_BONUS_M = 30`, `INVITE_VALID_DAYS = 7`.

User-facing messages live in `REASON_MESSAGES` (`checks.ts`).

## 4. Firestore rules summary

| Path | Read | Write |
|---|---|---|
| students/{id} | self | ✗ |
| staff/{id} | self (lecturer) or any admin | ✗ |
| admins/{id} | self (admin) | ✗ |
| invites/{code} | admin | ✗ |
| sessions/{id} | owning lecturer | ✗ |
| attendance/{id} | its lecturer or its student | ✗ |
| sessionSecrets/{id} | ✗ | ✗ |
| deviceUse/{id} | ✗ | ✗ |

Queries must carry the equality filter the rule depends on (e.g. `where('lecturerUid', '==', uid)`). Otherwise Firestore rejects the whole query.

## 5. Invariants (never break these)
1. No client-side Firestore writes. Add a callable instead.
2. The QR secret never leaves the server.
3. Every new lecturer endpoint uses `requireLecturer`; every admin endpoint uses `requireRole(req, "admin")`.
4. Static mode always implies the geofence (`effectiveSettings`).
5. Scan writes stay inside the `submitScan` transaction.
6. `emailForId` must be identical in `functions/src/roster.ts` and `app/lib/screens/login_screen.dart`.

## 6. Accepted residual risks
- GPS spoofing on rooted devices without a mock flag.
- A present student relaying a live code by video call.
- Admin list race: register admins immediately after the first deploy.
- `ADMIN_STAFF_IDS` changes don't affect existing accounts.
