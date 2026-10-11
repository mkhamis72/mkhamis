# API: Cloud Functions (callable)

All endpoints are Firebase **v2 `onCall`** functions in `functions/src/index.ts`. The app calls them through `app/lib/services/api.dart`.

Errors are thrown as `HttpsError(code, message)`. The `message` is user-facing and shown as-is. Scan rejections are **not** errors: `submitScan` returns `{ok:false, reason, message}`.

Auth column: **none** = callable signed out; **student** / **lecturer** / **admin** = required `role` claim; **lecturer✓** = lecturer with `approved == true`.

## Registration

### `registerStudent`, auth: none
| In | Type | Rules |
|---|---|---|
| studentId | string | 2–40 `[A-Za-z0-9._-]` |
| name | string | 2–80 |
| password | string | ≥ 6 |
| university, mobile, email | string | See `cleanContactDetails` |
| deviceId | string | 8–100 chars |

Out: `{ok:true}`. Errors: `invalid-argument` (validation), `already-exists` ("This ID is already registered. Sign in instead.").
Effect: creates the Auth user (claims `{role:'student', personId}`) and `students/{id}` with the device bound and `rebindAt:null`.

### `registerLecturer`, auth: none
| In | Type | Rules |
|---|---|---|
| staffId, name, password | string | As above |
| university, mobile, email | string | As above |
| inviteCode | string? | Optional. Normalised: upper-case, spaces/dashes removed |

Out: `{ok:true, approved:boolean}`.
Errors: `invalid-argument`; `failed-precondition` with one of: "Invite code not found." / "…already been used." / "…has expired…" / "…issued for a different Staff ID."; `already-exists`.
Effect: with a valid code, the code is reserved in a transaction (`usedBy`), then the account is created with `approved:true`. If account creation fails, the reservation is released. Without a code: `approved:false`, `staff.status:'pending'`.

### `registerAdmin`, auth: none
In: `staffId, name, password`. Out: `{ok:true}`.
Errors: `permission-denied` ("This Staff ID is not on the admin list.") unless the ID is in `ADMIN_STAFF_IDS`.

## Profile

### `updateStudentProfile`, auth: student · `updateLecturerProfile`, auth: lecturer (approved or not)
In: `name, university, mobile, email`. Out: `{ok:true}`. Also updates the Auth display name.

## Student

### `deviceStatus`, auth: student
In: `deviceId`. Out: `{matches:boolean, name}`.

### `rebindDevice`, auth: student
In: `deviceId`. Out: `{ok:true}`. Sets `boundDeviceId`, `boundAt`, `rebindAt = now`.

### `submitScan`, auth: student
| In | Type |
|---|---|
| qr | string (raw QR text, JSON) |
| deviceId | string |
| location | {lat, lng, accuracy, isMocked}? |

Out (success): `{ok:true, subject, hallName, flags}` or `{ok:true, alreadyRecorded:true, subject, hallName}`.
Out (rejected): `{ok:false, reason, message}`, where `reason` ∈
`bad_signature, wrong_mode, expired_qr, session_closed, outside_time_window, device_mismatch, device_changed_during_session, device_already_used, location_missing, location_mocked, location_inaccurate, outside_hall`.
Runs in a Firestore transaction. See [SECURITY §3](SECURITY.md#3-scan-checks-in-order) for the check order.

## Lecturer (approved)

### `createSession`, auth: lecturer✓
| In | Type | Rules |
|---|---|---|
| subject, hallName | string | Required, ≤ 100 |
| lat, lng | number | Valid coordinates |
| radiusMeters | number | Clamped 10–500, default 50 |
| mode | `rotating` \| `static` | |
| settings | {geofence, deviceBinding, timeWindow} | Missing = true. Static forces geofence |
| windowMinutes | number | Clamped 1–240, default 15 |

Out: `{sessionId}`. Also saves the place in `staff.recentPlaces`.

### `getQrToken`, auth: lecturer✓ (owner)
In: `sessionId`. Out: `{qr, mode, refreshAtMs|null}`.
Errors: `failed-precondition` if the session is not open; `permission-denied` if it is not the caller's session.

### `updateSession`, auth: lecturer✓ (owner)
In: `sessionId, action, minutes?`. Actions: `pause`, `resume` (not after end), `end`, `regenerate` (new secret), `extend` (+minutes, clamped 1–120, default 5). Out: `{ok:true}`.

### `removeAttendance`, auth: lecturer✓ (owner)
In: `sessionId, studentId`. Out: `{ok:true}`. Deletes the record and decrements `attendeeCount`. The `deviceUse` record is kept.

## Admin

### `approveLecturer`, auth: admin
In: `staffId, approve:boolean`. Approve sets claims `{role:'lecturer', personId, approved:true}` and `status:'approved'`. Reject deletes the Auth user and the staff doc. Errors: `not-found`, `failed-precondition` (not pending).

### `createInvite`, auth: admin
In: `staffId?, note?`. Out: `{code, expiresAtMs}`.

### `revokeInvite`, auth: admin
In: `code`. Out: `{ok:true}`. Errors: `failed-precondition` if already used.

## QR payload (inside the QR image)

```json
{ "v": 1, "sid": "<sessionId>", "subject": "Math 101", "hall": "Hall A", "t": 176000000, "sig": "<base64url HMAC>" }
```
- `t` (rotating only) = `floor(epochMs / 1000 / 10)`.
- `sig = HMAC_SHA256(secret, "<sid>|<t>")` for rotating, `HMAC_SHA256(secret, "<sid>|static")` for static, base64url-encoded.
- Accepted if the signature matches (timing-safe compare) and, for rotating, `|currentSlot − t| ≤ 1`.
