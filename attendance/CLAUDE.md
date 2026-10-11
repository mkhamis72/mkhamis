# CLAUDE.md: Class Attendance (QR + Location)

Guidance for Claude Code working in this folder. Read the docs before changing behaviour:
- **What & why:** [docs/PRD.md](docs/PRD.md) (user stories with acceptance criteria)
- **How:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/DATA_MODEL.md](docs/DATA_MODEL.md), [docs/API.md](docs/API.md)
- **Rules that must hold:** [docs/SECURITY.md](docs/SECURITY.md)
- **Screens:** [docs/UI_SPEC.md](docs/UI_SPEC.md) · **Tests:** [docs/TEST_PLAN.md](docs/TEST_PLAN.md) · **Run/deploy:** [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)

## Stack
Flutter app (`app/`, Android/iOS/Web, one codebase) + Firebase: Auth, Firestore, Cloud Functions v2 in TypeScript (`functions/`), Hosting (Flutter web build).
Roles via Auth custom claims: `role` = student | lecturer | admin, `personId`, `approved` (lecturers).

## Commands (run from `attendance/`)
```bash
cd functions && npm test            # Jest unit tests: must pass
cd functions && npx tsc --noEmit    # typecheck: must pass
cd functions && npm run test:rules  # Firestore rules tests on the emulator (Java 17+): must pass
cd app && flutter analyze           # must print "No issues found!"
cd app && flutter test
cd app && flutter build web         # compile check for every screen
cd functions && npm run serve       # local Auth/Firestore/Functions emulators (project demo-attendance)
cd app && flutter run -d chrome --dart-define=USE_EMULATORS=true   # app against the emulators
cd app && flutter run -d chrome     # app against the real project (needs firebase_options.dart)
```
Before every commit: tests, typecheck, rules tests, analyze, app test and web build must pass (VS Code task **check: all**).

## Architecture rules (do not break)
1. **Clients never write Firestore.** Every write is a callable in `functions/src/index.ts`, wrapped in `app/lib/services/api.dart`. `firestore.rules` denies all client writes.
2. **Business rules are pure functions** in `checks.ts`, `qr.ts`, `geo.ts` and `roster.ts`, and are unit-tested in `functions/test/checks.test.ts`. Callables stay thin: authorise → load → call the pure function → write.
3. **Auth checks:** student endpoints use `requireRole(req, "student")`, lecturer endpoints `requireLecturer(req)` (requires `approved`), admin endpoints `requireRole(req, "admin")`, and lecturer session endpoints also `loadOwnedSession`.
4. **QR secrets** live only in `sessionSecrets/{id}` and are never returned to clients.
5. **Static QR ⇒ geofence always on** (`effectiveSettings`). Keep it enforced server-side, not just in the UI.
6. **`submitScan` writes in one transaction** (attendance, deviceUse, attendeeCount, device bind). All reads come before writes.
7. **`emailForId`** must be identical in `functions/src/roster.ts` and `app/lib/screens/login_screen.dart`.
8. **Rules-friendly queries:** client queries on `attendance`/`sessions` must include the equality filter the rule checks (`lecturerUid == uid` or `studentUid == uid`). New composite queries need an entry in `firestore.indexes.json`.
9. User-facing error text comes from the server (`HttpsError` message or `REASON_MESSAGES`). Show it as-is via `errorText(e)`.

## Conventions
- TypeScript: strict, Node 22, `firebase-functions/v2/https` `onCall`, `firebase-admin` modular imports. Validate and clamp every input. Throw `HttpsError` with a clear user message.
- Dart: `flutter_lints`, Material 3, `const` where possible, check `mounted` after `await` before using `context`/`setState`.
- Screens live in `app/lib/screens/<role>/`; shared ones in `app/lib/screens/`. API wrappers are grouped by role in `api.dart`.
- Keep comments short and only where the *why* isn't obvious, matching the existing files.
- When behaviour changes, update the matching doc in `docs/` and the `README.md` in the same commit.

## Adding a feature: checklist
1. Update `docs/PRD.md` (story + acceptance criteria) if it's new behaviour.
2. Pure logic + tests in `functions/src/*.ts` / `functions/test/`.
3. Callable in `index.ts` (auth check, validation) → document it in `docs/API.md`.
4. Data changes → `docs/DATA_MODEL.md`, `firestore.rules` (+ cases in `functions/test-rules/`), `firestore.indexes.json`.
5. Wrapper in `api.dart` → screen(s) → `docs/UI_SPEC.md`.
6. Run all checks; add manual cases to `docs/TEST_PLAN.md` if needed.

## Gotchas
- `app/lib/firebase_options.dart` is a placeholder that throws until `flutterfire configure` is run. With `--dart-define=USE_EMULATORS=true` it isn't used (demo project options in `services/emulators.dart`).
- Emulator-only admin IDs go in `functions/.env.local` (git-ignored).
- Approval changes claims. The client must refresh its ID token (`getIdToken(true)`) to see them; `AuthGate` re-routes on `idTokenChanges()`.
- `ADMIN_STAFF_IDS` (`functions/.env`) only applies at registration.
- The Flutter SDK may warn when run as root in containers. That's harmless.
