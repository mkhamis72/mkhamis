# PRD: Class Attendance (QR + Location)

| | |
|---|---|
| **Status** | v1 implemented (PR mkhamis72/mkhamis#1) |
| **Platforms** | Android, iOS (Flutter app) · Web (same Flutter app, for projector and admin use) |
| **Backend** | Firebase: Auth, Firestore, Cloud Functions (TypeScript), Hosting |
| **Related docs** | [ARCHITECTURE](ARCHITECTURE.md) · [DATA_MODEL](DATA_MODEL.md) · [API](API.md) · [SECURITY](SECURITY.md) · [UI_SPEC](UI_SPEC.md) · [TEST_PLAN](TEST_PLAN.md) · [DEPLOYMENT](DEPLOYMENT.md) |

---

## 1. Problem

Lecturers take attendance by having students scan a QR code in the hall. Students defeat this by **sending a photo of the QR to friends who are not in class**, who then sign in remotely. Attendance records become unreliable.

## 2. Goals

| # | Goal | Measure |
|---|---|---|
| G1 | A student can only sign attendance when physically present in the hall | Remote sign-ins via shared QR are rejected (rotating QR expiry + geofence) |
| G2 | One student cannot sign in for another | One phone per student, one student per phone per session |
| G3 | Taking attendance takes the lecturer < 1 minute to set up | Create QR = subject + hall + "use my location" + type → Start |
| G4 | Lecturers get an accurate attended list they can export | Per-session and all-sessions lists, CSV export |
| G5 | Only genuine lecturers can create attendance sessions | Lecturer accounts accepted by an admin (invite code or approval) |

### Non-goals (v1)
- Timetables, course catalogs, enrolment rosters, grade integration.
- Absence tracking against a roster (no roster exists; "absent" is not computed).
- Offline scanning (a scan needs internet; a static QR can be *shown* offline).
- Password reset flow (done by hand in the Firebase console in v1).
- Push notifications, multi-language UI.

## 3. Users & roles

| Role | Who | How they get an account |
|---|---|---|
| **Student** | Attends classes, scans the QR | Self-registers in the app. Ready immediately. The registering phone becomes their attendance phone |
| **Lecturer** | Runs classes, creates QR codes, views attendance | Self-registers. **With a valid invite code** → ready immediately. **Without one** → waits for admin approval |
| **Admin** | Accepts lecturers | Self-registers, but only with a Staff ID listed in the server setting `ADMIN_STAFF_IDS` |

All users sign in with **ID + password** (the ID is mapped internally to `<id>@attendance.local` for Firebase Auth).

## 4. User stories & acceptance criteria

### 4.1 Student

**S1: Register**
As a student I register once with my Student ID, full name, university, mobile, email and a password.
- AC1: Each Student ID can be registered only once ("already registered" error otherwise).
- AC2: Validation: ID 2–40 chars `[A-Za-z0-9._-]`. Name 2–80. University 2–100. Mobile 7+ digits, may contain `+ ( ) - space`. Valid email. Password ≥ 6.
- AC3: The registering phone is bound to the account.

**S2: Scan attendance**
As a student I tap **Scan**, point the camera at the QR, and get a clear result.
- AC1: Success shows ✓, the subject and the hall.
- AC2: Failure shows ✗ with a human-readable reason (see [SECURITY §3](SECURITY.md#3-scan-checks-in-order) for the full list).
- AC3: Scanning again after success shows "Already recorded" (idempotent).
- AC4: The app requests camera and location permission when first needed.

**S3: History**
As a student I see my attendance history (subject, hall, date/time), newest first.

**S4: Change phone**
As a student with a new or lost phone, I sign in on the new phone and tap **Use this phone**.
- AC1: The old phone stops working for attendance immediately.
- AC2: **The new phone cannot sign a session that had already started when I switched.** It works from the next session.
- AC3: The home screen shows a banner when the account is bound to a different phone.

**S5: My details**
As a student I can edit my name, university, mobile and email.

### 4.2 Lecturer

**L1: Register**
As a lecturer I register with Staff ID, full name, university, mobile, email, password and an optional invite code.
- AC1: Valid code → account active immediately.
- AC2: No code → "Waiting for approval" screen with **Check again**, **Edit my details** and **Sign out**.
- AC3: Invalid code → specific error: not found, already used, expired, or issued for a different Staff ID.
- AC4: The server rejects every lecturer action from an unapproved account.

**L2: Create attendance QR**
As a lecturer I create a session by entering:
- **Subject** (text) and **Hall name** (text).
- **Hall GPS location**: tap "Use my current location" while standing in the hall. Shows coordinates ± accuracy.
- **Allowed radius**: 20–200 m, default 50.
- **QR type**: **Rotating** (default) or **Static**.
- **Anti-cheat toggles**: Location (geofence), Device binding, Time window (+ minutes, 5–90, default 15).

Acceptance criteria:
- AC1: Recently used subject/hall/location sets (last 10) appear as one-tap picks.
- AC2: **Static** forces the geofence ON (toggle locked).
- AC3: Start opens the live QR screen.

**L3: Run the live session**
- AC1: Full-screen QR with a live "N present" counter.
- AC2: A rotating QR refreshes every 10 s. A static QR stays fixed.
- AC3: Controls: Pause / Resume, End (with confirmation), Regenerate (old codes stop working), Extend time window +5 min.
- AC4: Static QR: **Print / PDF** (A4 page with subject, hall, QR, instructions).
- AC5: Connection loss shows "Retrying…" and recovers automatically.

**L4: Attended students**
- AC1: Per session: list of attended students with time, distance from the hall and a flag icon for edge-of-geofence scans. Remove an entry (with confirmation). CSV export.
- AC2: All my sessions: filter by date range (default last 7 days) and search (student, subject, hall). CSV export.
- AC3: CSV columns: `student_id, name, subject, hall, time, distance_m, flags`.

**L5: My details**
As a lecturer I can edit my name, university, mobile and email, including while waiting for approval.

### 4.3 Admin

**A1: Invite codes**
As an admin I create an invite code and send it to a lecturer.
- AC1: Optional "For (name)" note and optional **Lock to Staff ID**.
- AC2: The code is 8 characters from an unambiguous alphabet (no 0/O/1/I/L), single-use, and valid for 7 days.
- AC3: **Send** opens the OS share sheet (WhatsApp, SMS, e-mail…) with a ready-made message. **Copy** copies the code.
- AC4: The list shows each code as Active (with expiry), Used (by Staff ID) or Expired. An active code can be revoked.

**A2: Approvals**
As an admin I see lecturers who registered without a code, with their name, Staff ID, university, mobile, email and registration time.
- AC1: Approve → the lecturer gets access (after "Check again").
- AC2: Reject (with confirmation) → the account is deleted.

## 5. Functional requirements (summary)

| ID | Requirement |
|---|---|
| FR-1 | Three roles stored as Firebase Auth custom claims: `role` ∈ {student, lecturer, admin}, plus `personId` and (lecturer) `approved` |
| FR-2 | All writes to sessions, attendance, accounts, invites happen **only in Cloud Functions**. Clients never write Firestore directly |
| FR-3 | Rotating QR: HMAC-SHA256 signed, 10 s slot, ±1 slot tolerance (~30 s validity) |
| FR-4 | Static QR: HMAC signed, no time slot, geofence always enforced |
| FR-5 | Per-session secret stored in a client-unreadable collection. "Regenerate" replaces it |
| FR-6 | Geofence: distance ≤ radius + min(accuracy, 30 m). Reject accuracy > 100 m or a mocked location. Flag `near_hall_edge` if accepted only thanks to the slack |
| FR-7 | Device binding: account bound to one device ID. One device can't sign two students into one session. A rebind after session start blocks that session |
| FR-8 | Time window: scans accepted from session start to start + windowMinutes (extendable) |
| FR-9 | Each scan is idempotent per (session, student) |
| FR-10 | Invite codes: single-use (reserved transactionally), 7-day expiry, optional Staff ID lock, revocable while unused |
| FR-11 | Admin registration only for IDs in `ADMIN_STAFF_IDS` |

## 6. Non-functional requirements

| Area | Requirement |
|---|---|
| Security | Server-side enforcement of every rule. Firestore rules deny all client writes. Secrets never readable (see [SECURITY](SECURITY.md)) |
| Performance | Scan → result < 3 s on 4G. QR refresh aligned to slot boundaries |
| Reliability | Scan writes in a Firestore transaction (no double counts, no races on device use) |
| Privacy | Location is stored only with the attendance record (lat/lng/accuracy at scan time). Contact details are visible only to the owner and admins (lecturer details) |
| Accessibility | Material 3, light/dark theme, large scan button, text results (not colour only) |
| Compatibility | Android 7+ (Flutter default minSdk), iOS 13+, modern browsers for web |

## 7. Known limitations (accepted for v1)
- Indoor GPS can be 20–50 m off. Mitigated by the radius slack and flagged scans.
- A rooted/jailbroken phone can spoof GPS undetected. The rotating QR + device binding are the primary defence.
- A present student can read a live code out over a video call. Mitigated by the lecturer comparing the count with a headcount.
- The admin list (`ADMIN_STAFF_IDS`) applies only at registration. Register admins right after deploy.

## 8. Release plan
| Phase | Scope | Status |
|---|---|---|
| v1 | Everything above | ✅ Implemented, unit-tested, web build compiles |
| v1.1 | Emulator switch for local dev ✅, Firestore rules tests ✅, password reset, Android/iOS store builds, CI | In progress |
| v2 | Roster / absence report, timetable, notifications, multi-language (Arabic) | Idea |
