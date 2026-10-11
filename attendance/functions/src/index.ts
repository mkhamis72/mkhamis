import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { defineString } from "firebase-functions/params";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { effectiveSettings, evaluateScan, REASON_MESSAGES, SessionDoc, SessionSettings } from "./checks";
import { LocationFix } from "./geo";
import { buildPayload, decodePayload, encodePayload, newSecret, QrMode, SLOT_SECONDS, slotAt } from "./qr";
import {
  emailForId,
  INVITE_VALID_DAYS,
  inviteProblem,
  newInviteCode,
  normalizeInviteCode,
  parseAdminIds,
  Role,
  validateRegistration,
} from "./roster";

initializeApp();
const db = getFirestore();

/** Most recent subject/hall/location sets kept per lecturer for quick re-use. */
const RECENT_PLACES = 10;

/** Staff IDs (comma separated, set in functions/.env) allowed to register as admins. */
const ADMIN_STAFF_IDS = defineString("ADMIN_STAFF_IDS", { default: "" });

function requireRole(req: CallableRequest, role: Role): { uid: string; personId: string } {
  const token = req.auth?.token;
  if (!req.auth || !token) throw new HttpsError("unauthenticated", "Sign in first.");
  if (token.role !== role) throw new HttpsError("permission-denied", "Not allowed for your role.");
  return { uid: req.auth.uid, personId: String(token.personId ?? "") };
}

/** Lecturer calls need an account approved by an admin (directly or via an invite code). */
function requireLecturer(req: CallableRequest): { uid: string; personId: string } {
  const who = requireRole(req, "lecturer");
  if (req.auth!.token.approved !== true) {
    throw new HttpsError("permission-denied", "Your lecturer account is waiting for admin approval.");
  }
  return who;
}

function requireDeviceId(raw: unknown): string {
  const deviceId = String(raw ?? "");
  if (deviceId.length < 8 || deviceId.length > 100) throw new HttpsError("invalid-argument", "Missing device id.");
  return deviceId;
}

async function loadOwnedSession(sessionId: unknown, uid: string) {
  const ref = db.collection("sessions").doc(String(sessionId));
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Session not found.");
  const session = snap.data()!;
  if (session.lecturerUid !== uid) throw new HttpsError("permission-denied", "This is not your session.");
  return { ref, session };
}

function cleanSettings(raw: unknown, mode: QrMode): SessionSettings {
  const s = (raw ?? {}) as Partial<SessionSettings>;
  return effectiveSettings(mode, {
    geofence: s.geofence !== false,
    deviceBinding: s.deviceBinding !== false,
    timeWindow: s.timeWindow !== false,
  });
}

// ---------------------------------------------------------------------------
// Registration (self-service)
// ---------------------------------------------------------------------------

async function createAccount(
  id: string,
  name: string,
  password: string,
  role: Role,
  extraClaims: Record<string, unknown> = {},
): Promise<string> {
  const problem = validateRegistration(id, name, password);
  if (problem) throw new HttpsError("invalid-argument", problem);
  try {
    const user = await getAuth().createUser({ email: emailForId(id), password, displayName: name.trim() });
    await getAuth().setCustomUserClaims(user.uid, { role, personId: id.trim(), ...extraClaims });
    return user.uid;
  } catch (e) {
    if ((e as { code?: string }).code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "This ID is already registered. Sign in instead.");
    }
    throw e;
  }
}

/** Student signs up once with ID + name + password. The registering phone becomes the bound phone. */
export const registerStudent = onCall(async (req) => {
  const { studentId, name, password } = req.data ?? {};
  const deviceId = requireDeviceId(req.data?.deviceId);
  const id = String(studentId ?? "").trim();
  const uid = await createAccount(id, String(name ?? ""), String(password ?? ""), "student");
  await db.collection("students").doc(id).set({
    name: String(name).trim(),
    authUid: uid,
    boundDeviceId: deviceId,
    boundAt: Timestamp.now(),
    rebindAt: null, // only set when the student moves to another phone
  });
  return { ok: true };
});

/**
 * Lecturer signs up. With a valid invite code from an admin the account is approved at once;
 * without one it waits until an admin approves it.
 */
export const registerLecturer = onCall(async (req) => {
  const { staffId, name, password } = req.data ?? {};
  const id = String(staffId ?? "").trim();
  const code = normalizeInviteCode(String(req.data?.inviteCode ?? ""));
  const problem = validateRegistration(id, String(name ?? ""), String(password ?? ""));
  if (problem) throw new HttpsError("invalid-argument", problem);

  // Reserve the invite before creating the account, so one code can't approve two lecturers.
  const inviteRef = code ? db.collection("invites").doc(code) : null;
  if (inviteRef) {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(inviteRef);
      const invite = snap.exists
        ? { usedBy: snap.get("usedBy"), staffId: snap.get("staffId"), expiresAtMs: (snap.get("expiresAt") as Timestamp).toMillis() }
        : undefined;
      const reason = inviteProblem(invite, id, Date.now());
      if (reason) throw new HttpsError("failed-precondition", reason);
      tx.update(inviteRef, { usedBy: id, usedAt: Timestamp.now() });
    });
  }

  const approved = inviteRef !== null;
  let uid: string;
  try {
    uid = await createAccount(id, String(name ?? ""), String(password ?? ""), "lecturer", { approved });
  } catch (e) {
    // Account not created (e.g. ID already registered): give the invite back.
    if (inviteRef) await inviteRef.update({ usedBy: null, usedAt: null });
    throw e;
  }
  await db.collection("staff").doc(id).set({
    name: String(name).trim(),
    authUid: uid,
    status: approved ? "approved" : "pending",
    approvedBy: approved ? `invite:${code}` : null,
    createdAt: Timestamp.now(),
    recentPlaces: [],
  });
  return { ok: true, approved };
});

/** Admins self-register too, but only with a staff ID listed in ADMIN_STAFF_IDS. */
export const registerAdmin = onCall(async (req) => {
  const { staffId, name, password } = req.data ?? {};
  const id = String(staffId ?? "").trim();
  if (!parseAdminIds(ADMIN_STAFF_IDS.value()).has(id.toLowerCase())) {
    throw new HttpsError("permission-denied", "This Staff ID is not on the admin list.");
  }
  const uid = await createAccount(id, String(name ?? ""), String(password ?? ""), "admin");
  await db.collection("admins").doc(id).set({ name: String(name).trim(), authUid: uid, createdAt: Timestamp.now() });
  return { ok: true };
});

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------

/** Approves (claims updated) or rejects (account deleted) a lecturer who registered without a code. */
export const approveLecturer = onCall(async (req) => {
  const { personId: adminId } = requireRole(req, "admin");
  const staffId = String(req.data?.staffId ?? "");
  const ref = db.collection("staff").doc(staffId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Lecturer not found.");
  if (snap.get("status") !== "pending") throw new HttpsError("failed-precondition", "This account is not pending.");
  const authUid = snap.get("authUid") as string;
  if (req.data?.approve === true) {
    await getAuth().setCustomUserClaims(authUid, { role: "lecturer", personId: staffId, approved: true });
    await ref.update({ status: "approved", approvedBy: adminId, approvedAt: Timestamp.now() });
  } else {
    await getAuth().deleteUser(authUid);
    await ref.delete();
  }
  return { ok: true };
});

/** Creates a single-use invite code to send to a lecturer, optionally locked to their staff ID. */
export const createInvite = onCall(async (req) => {
  const { personId: adminId } = requireRole(req, "admin");
  const staffId = String(req.data?.staffId ?? "").trim() || null;
  const note = String(req.data?.note ?? "").trim().slice(0, 100) || null;
  const expiresAt = Timestamp.fromMillis(Date.now() + INVITE_VALID_DAYS * 86_400_000);
  // Retry on the (very unlikely) chance the random code already exists.
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = newInviteCode();
    try {
      await db.collection("invites").doc(code).create({
        createdBy: adminId,
        createdAt: Timestamp.now(),
        expiresAt,
        staffId,
        note,
        usedBy: null,
      });
      return { code, expiresAtMs: expiresAt.toMillis() };
    } catch (e) {
      if ((e as { code?: number }).code !== 6 /* ALREADY_EXISTS */) throw e;
    }
  }
  throw new HttpsError("internal", "Could not create a code. Try again.");
});

/** Cancels an unused invite code. */
export const revokeInvite = onCall(async (req) => {
  requireRole(req, "admin");
  const ref = db.collection("invites").doc(normalizeInviteCode(String(req.data?.code ?? "")));
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    if (snap.get("usedBy")) throw new HttpsError("failed-precondition", "This code has already been used.");
    tx.delete(ref);
  });
  return { ok: true };
});

// ---------------------------------------------------------------------------
// Student
// ---------------------------------------------------------------------------

/** Tells the app whether this phone is the bound one. */
export const deviceStatus = onCall(async (req) => {
  const { personId } = requireRole(req, "student");
  const deviceId = requireDeviceId(req.data?.deviceId);
  const snap = await db.collection("students").doc(personId).get();
  if (!snap.exists) throw new HttpsError("not-found", "Student record missing.");
  return { matches: snap.get("boundDeviceId") === deviceId, name: snap.get("name") };
});

/** "Use this phone": move the account here. Takes effect for sessions that start after now. */
export const rebindDevice = onCall(async (req) => {
  const { personId } = requireRole(req, "student");
  const deviceId = requireDeviceId(req.data?.deviceId);
  const now = Timestamp.now();
  await db.collection("students").doc(personId).update({ boundDeviceId: deviceId, boundAt: now, rebindAt: now });
  return { ok: true };
});

export const submitScan = onCall(async (req) => {
  const { uid, personId: studentId } = requireRole(req, "student");
  const payload = decodePayload(String(req.data?.qr ?? ""));
  if (!payload) return { ok: false, reason: "bad_signature", message: REASON_MESSAGES.bad_signature };
  const deviceId = requireDeviceId(req.data?.deviceId);
  const location = req.data?.location as LocationFix | undefined;

  const sessionRef = db.collection("sessions").doc(payload.sid);
  const attRef = db.collection("attendance").doc(`${payload.sid}_${studentId}`);
  const studentRef = db.collection("students").doc(studentId);
  const deviceUseRef = db.collection("deviceUse").doc(`${payload.sid}_${deviceId}`);

  return db.runTransaction(async (tx) => {
    const [sessionSnap, secretSnap, studentSnap, attSnap, deviceUseSnap] = await Promise.all([
      tx.get(sessionRef),
      tx.get(db.collection("sessionSecrets").doc(payload.sid)),
      tx.get(studentRef),
      tx.get(attRef),
      tx.get(deviceUseRef),
    ]);
    if (!sessionSnap.exists || !secretSnap.exists) {
      return { ok: false, reason: "bad_signature", message: REASON_MESSAGES.bad_signature };
    }
    if (!studentSnap.exists) throw new HttpsError("not-found", "Student record missing.");
    const s = sessionSnap.data()!;
    if (attSnap.exists) {
      return { ok: true, alreadyRecorded: true, subject: s.subject, hallName: s.hallName };
    }
    const session: SessionDoc = {
      mode: s.mode,
      status: s.status,
      startsAtMs: (s.startsAt as Timestamp).toMillis(),
      windowMinutes: s.windowMinutes,
      settings: s.settings,
    };
    const decision = evaluateScan({
      nowMs: Date.now(),
      payload,
      secret: secretSnap.get("secret"),
      session,
      student: {
        studentId,
        boundDeviceId: studentSnap.get("boundDeviceId"),
        rebindAtMs: (studentSnap.get("rebindAt") as Timestamp | null)?.toMillis() ?? null,
      },
      hall: { lat: s.lat, lng: s.lng, radiusMeters: s.radiusMeters },
      deviceId,
      location,
      deviceUsedBy: deviceUseSnap.exists ? deviceUseSnap.get("studentId") : null,
    });
    if (!decision.ok) {
      return { ok: false, reason: decision.reason, message: REASON_MESSAGES[decision.reason] };
    }

    tx.set(attRef, {
      sessionId: payload.sid,
      subject: s.subject,
      hallName: s.hallName,
      lecturerUid: s.lecturerUid,
      studentId,
      studentUid: uid,
      studentName: studentSnap.get("name"),
      at: Timestamp.now(),
      deviceId,
      location: location ? { lat: location.lat, lng: location.lng, accuracy: location.accuracy } : null,
      distanceMeters: decision.distance ?? null,
      flags: decision.flags,
    });
    tx.set(deviceUseRef, { studentId, at: Timestamp.now() });
    tx.update(sessionRef, { attendeeCount: FieldValue.increment(1) });
    if (decision.bindDevice) tx.update(studentRef, { boundDeviceId: deviceId, boundAt: Timestamp.now() });
    return { ok: true, subject: s.subject, hallName: s.hallName, flags: decision.flags };
  });
});

// ---------------------------------------------------------------------------
// Lecturer: create and drive a session (rotating or static QR)
// ---------------------------------------------------------------------------

export const createSession = onCall(async (req) => {
  const { uid, personId } = requireLecturer(req);
  const d = req.data ?? {};
  const mode = d.mode as QrMode;
  if (mode !== "rotating" && mode !== "static") throw new HttpsError("invalid-argument", "QR type must be rotating or static.");
  const subject = String(d.subject ?? "").trim();
  const hallName = String(d.hallName ?? "").trim();
  if (!subject || subject.length > 100) throw new HttpsError("invalid-argument", "Enter the subject.");
  if (!hallName || hallName.length > 100) throw new HttpsError("invalid-argument", "Enter the hall name.");
  const lat = Number(d.lat), lng = Number(d.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    throw new HttpsError("invalid-argument", "Set the hall GPS location.");
  }
  const radiusMeters = Math.min(Math.max(Math.round(Number(d.radiusMeters) || 50), 10), 500);
  const windowMinutes = Math.min(Math.max(Math.round(Number(d.windowMinutes) || 15), 1), 240);

  const ref = db.collection("sessions").doc();
  const batch = db.batch();
  batch.set(ref, {
    subject,
    hallName,
    lat,
    lng,
    radiusMeters,
    lecturerUid: uid,
    lecturerId: personId,
    mode,
    status: "open",
    startsAt: Timestamp.now(),
    windowMinutes,
    settings: cleanSettings(d.settings, mode),
    attendeeCount: 0,
  });
  // Secrets live in a collection that clients can never read.
  batch.set(db.collection("sessionSecrets").doc(ref.id), { secret: newSecret() });
  await batch.commit();

  // Remember this place for quick re-use (newest first, unique by subject + hall).
  const staffRef = db.collection("staff").doc(personId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(staffRef);
    const recent = (snap.get("recentPlaces") ?? []) as Array<Record<string, unknown>>;
    const place = { subject, hallName, lat, lng, radiusMeters };
    const rest = recent.filter((p) => !(p.subject === subject && p.hallName === hallName));
    tx.set(staffRef, { recentPlaces: [place, ...rest].slice(0, RECENT_PLACES) }, { merge: true });
  });
  return { sessionId: ref.id };
});

export const getQrToken = onCall(async (req) => {
  const { uid } = requireLecturer(req);
  const { session, ref } = await loadOwnedSession(req.data?.sessionId, uid);
  if (session.status !== "open") throw new HttpsError("failed-precondition", `Session is ${session.status}.`);
  const secret = (await db.collection("sessionSecrets").doc(ref.id).get()).get("secret");
  const now = Date.now();
  const payload = buildPayload(session.mode, ref.id, session.subject, session.hallName, secret, now);
  return {
    qr: encodePayload(payload),
    mode: session.mode,
    // Rotating: the app refreshes at this time. Static: never expires on its own.
    refreshAtMs: session.mode === "rotating" ? (slotAt(now) + 1) * SLOT_SECONDS * 1000 : null,
  };
});

export const updateSession = onCall(async (req) => {
  const { uid } = requireLecturer(req);
  const { ref, session } = await loadOwnedSession(req.data?.sessionId, uid);
  switch (req.data?.action) {
    case "pause":
      await ref.update({ status: "paused" });
      break;
    case "resume":
      if (session.status === "ended") throw new HttpsError("failed-precondition", "Session has ended.");
      await ref.update({ status: "open" });
      break;
    case "end":
      await ref.update({ status: "ended", endedAt: Timestamp.now() });
      break;
    case "regenerate":
      // New secret: every previously shown or printed QR stops working.
      await db.collection("sessionSecrets").doc(ref.id).set({ secret: newSecret() });
      break;
    case "extend": {
      const extra = Math.min(Math.max(Number(req.data?.minutes) || 5, 1), 120);
      await ref.update({ windowMinutes: FieldValue.increment(extra) });
      break;
    }
    default:
      throw new HttpsError("invalid-argument", "Unknown action.");
  }
  return { ok: true };
});

/** Lecturer removes an attendance entry (e.g. a flagged scan that turned out to be fake). */
export const removeAttendance = onCall(async (req) => {
  const { uid } = requireLecturer(req);
  const { ref } = await loadOwnedSession(req.data?.sessionId, uid);
  const attRef = db.collection("attendance").doc(`${ref.id}_${String(req.data?.studentId ?? "")}`);
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(attRef);
    if (!existing.exists) return;
    tx.delete(attRef);
    tx.update(ref, { attendeeCount: FieldValue.increment(-1) });
  });
  return { ok: true };
});
