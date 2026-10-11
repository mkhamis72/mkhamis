import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { effectiveSettings, evaluateScan, REASON_MESSAGES, SessionDoc, SessionSettings } from "./checks";
import { LocationFix } from "./geo";
import { buildPayload, decodePayload, encodePayload, newSecret, QrMode, SLOT_SECONDS, slotAt } from "./qr";
import { emailForId, parseRosterRows, RosterRow } from "./roster";

initializeApp();
const db = getFirestore();

type Role = "student" | "lecturer" | "admin";

function requireRole(req: CallableRequest, ...roles: Role[]): { uid: string; role: Role; personId: string } {
  const token = req.auth?.token;
  if (!req.auth || !token) throw new HttpsError("unauthenticated", "Sign in first.");
  const role = token.role as Role | undefined;
  if (!role || !roles.includes(role)) throw new HttpsError("permission-denied", "Not allowed for your role.");
  return { uid: req.auth.uid, role, personId: String(token.personId ?? "") };
}

async function loadOwnedSession(sessionId: string, uid: string, role: Role) {
  const ref = db.collection("sessions").doc(String(sessionId));
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Session not found.");
  const session = snap.data()!;
  if (role !== "admin" && session.lecturerUid !== uid) {
    throw new HttpsError("permission-denied", "This is not your session.");
  }
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
// Lecturer: create and drive a session (rotating or static QR)
// ---------------------------------------------------------------------------

export const createSession = onCall(async (req) => {
  const { uid, role } = requireRole(req, "lecturer", "admin");
  const { courseId, hallId, mode, settings, windowMinutes } = req.data ?? {};
  if (mode !== "rotating" && mode !== "static") throw new HttpsError("invalid-argument", "mode must be rotating or static.");

  const course = await db.collection("courses").doc(String(courseId)).get();
  if (!course.exists) throw new HttpsError("not-found", "Course not found.");
  if (role !== "admin" && course.get("lecturerUid") !== uid) {
    throw new HttpsError("permission-denied", "You do not teach this course.");
  }
  const hallRef = db.collection("halls").doc(String(hallId || course.get("defaultHallId")));
  const hall = await hallRef.get();
  if (!hall.exists) throw new HttpsError("not-found", "Hall not found.");

  const minutes = Math.min(Math.max(Number(windowMinutes) || course.get("defaultWindowMinutes") || 15, 1), 240);
  const ref = db.collection("sessions").doc();
  const batch = db.batch();
  batch.set(ref, {
    courseId: course.id,
    subject: course.get("subject"),
    hallId: hall.id,
    hallName: hall.get("name"),
    lecturerUid: course.get("lecturerUid"),
    mode,
    status: "open",
    startsAt: Timestamp.now(),
    windowMinutes: minutes,
    settings: cleanSettings(settings ?? course.get("defaultSettings"), mode),
    attendeeCount: 0,
    createdBy: uid,
  });
  // Secrets live in a collection that clients can never read.
  batch.set(db.collection("sessionSecrets").doc(ref.id), { secret: newSecret() });
  await batch.commit();
  return { sessionId: ref.id };
});

export const getQrToken = onCall(async (req) => {
  const { uid, role } = requireRole(req, "lecturer", "admin");
  const { session, ref } = await loadOwnedSession(req.data?.sessionId, uid, role);
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
  const { uid, role } = requireRole(req, "lecturer", "admin");
  const { ref, session } = await loadOwnedSession(req.data?.sessionId, uid, role);
  const action = req.data?.action;
  switch (action) {
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

/** Lecturer marks a student present/absent by hand (e.g. phone dead), or clears a flag. */
export const overrideAttendance = onCall(async (req) => {
  const { uid, role } = requireRole(req, "lecturer", "admin");
  const { ref, session } = await loadOwnedSession(req.data?.sessionId, uid, role);
  const studentId = String(req.data?.studentId ?? "");
  const present = req.data?.present !== false;
  const course = await db.collection("courses").doc(session.courseId).get();
  if (!(course.get("studentIds") ?? []).includes(studentId)) {
    throw new HttpsError("invalid-argument", "Student is not enrolled in this course.");
  }
  const attRef = db.collection("attendance").doc(`${ref.id}_${studentId}`);
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(attRef);
    if (present) {
      const student = await tx.get(db.collection("students").doc(studentId));
      tx.set(attRef, {
        sessionId: ref.id,
        courseId: session.courseId,
        subject: session.subject,
        hallName: session.hallName,
        lecturerUid: session.lecturerUid,
        studentId,
        studentUid: student.get("authUid") ?? null,
        studentName: student.get("name") ?? "",
        at: existing.exists ? existing.get("at") : Timestamp.now(),
        flags: [],
        manual: true,
        overriddenBy: uid,
      }, { merge: true });
      if (!existing.exists) tx.update(ref, { attendeeCount: FieldValue.increment(1) });
    } else if (existing.exists) {
      tx.delete(attRef);
      tx.update(ref, { attendeeCount: FieldValue.increment(-1) });
    }
  });
  return { ok: true };
});

// ---------------------------------------------------------------------------
// Student: register phone and scan
// ---------------------------------------------------------------------------

/** Called right after login. Binds the account to this phone the first time. */
export const registerDevice = onCall(async (req) => {
  const { personId } = requireRole(req, "student");
  const deviceId = String(req.data?.deviceId ?? "");
  if (deviceId.length < 8) throw new HttpsError("invalid-argument", "Missing device id.");
  const ref = db.collection("students").doc(personId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Student not on roster.");
    const bound = snap.get("boundDeviceId");
    if (!bound) {
      tx.update(ref, { boundDeviceId: deviceId, boundAt: Timestamp.now() });
      return { bound: true, matches: true, name: snap.get("name") };
    }
    return { bound: true, matches: bound === deviceId, name: snap.get("name") };
  });
});

export const submitScan = onCall(async (req) => {
  const { uid, personId: studentId } = requireRole(req, "student");
  const payload = decodePayload(String(req.data?.qr ?? ""));
  if (!payload) return { ok: false, reason: "bad_signature", message: REASON_MESSAGES.bad_signature };
  const deviceId = String(req.data?.deviceId ?? "");
  if (deviceId.length < 8) throw new HttpsError("invalid-argument", "Missing device id.");
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
    const s = sessionSnap.data()!;
    if (attSnap.exists) {
      return { ok: true, alreadyRecorded: true, subject: s.subject, hallName: s.hallName };
    }
    const [courseSnap, hallSnap] = await Promise.all([
      tx.get(db.collection("courses").doc(s.courseId)),
      tx.get(db.collection("halls").doc(s.hallId)),
    ]);
    const session: SessionDoc = {
      courseId: s.courseId,
      hallId: s.hallId,
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
      enrolled: studentSnap.exists && (courseSnap.get("studentIds") ?? []).includes(studentId),
      student: { studentId, boundDeviceId: studentSnap.get("boundDeviceId") },
      hall: { lat: hallSnap.get("lat"), lng: hallSnap.get("lng"), radiusMeters: hallSnap.get("radiusMeters") ?? 50 },
      deviceId,
      location,
      deviceUsedBy: deviceUseSnap.exists ? deviceUseSnap.get("studentId") : null,
    });
    if (!decision.ok) {
      return { ok: false, reason: decision.reason, message: REASON_MESSAGES[decision.reason] };
    }

    tx.set(attRef, {
      sessionId: payload.sid,
      courseId: s.courseId,
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
      manual: false,
    });
    tx.set(deviceUseRef, { studentId, at: Timestamp.now() });
    tx.update(sessionRef, { attendeeCount: FieldValue.increment(1) });
    if (decision.bindDevice) tx.update(studentRef, { boundDeviceId: deviceId, boundAt: Timestamp.now() });
    return { ok: true, subject: s.subject, hallName: s.hallName, flags: decision.flags };
  });
});

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------

/** Creates/updates Auth accounts + roster docs from CSV rows: id,name,role,password */
export const importRoster = onCall({ timeoutSeconds: 300 }, async (req) => {
  requireRole(req, "admin");
  const { rows, errors } = parseRosterRows(String(req.data?.csv ?? ""));
  const auth = getAuth();
  const results = { created: 0, updated: 0, errors };
  for (const row of rows) {
    try {
      const uid = await upsertAuthUser(row);
      await auth.setCustomUserClaims(uid, { role: row.role, personId: row.id });
      const collection = row.role === "student" ? "students" : "staff";
      await db.collection(collection).doc(row.id).set({ name: row.name, authUid: uid, role: row.role }, { merge: true });
      await db.collection("users").doc(uid).set({ role: row.role, personId: row.id, name: row.name });
      row.isNew ? results.created++ : results.updated++;
    } catch (e) {
      results.errors.push(`${row.id}: ${(e as Error).message}`);
    }
  }
  return results;

  async function upsertAuthUser(row: RosterRow): Promise<string> {
    const email = emailForId(row.id);
    try {
      const user = await auth.getUserByEmail(email);
      await auth.updateUser(user.uid, { displayName: row.name, ...(row.password ? { password: row.password } : {}) });
      return user.uid;
    } catch (e) {
      if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
      if (!row.password) throw new Error("password required for new account");
      row.isNew = true;
      return (await auth.createUser({ email, password: row.password, displayName: row.name })).uid;
    }
  }
});

export const resetDevice = onCall(async (req) => {
  requireRole(req, "admin");
  const studentId = String(req.data?.studentId ?? "");
  await db.collection("students").doc(studentId).update({ boundDeviceId: null, boundAt: null });
  return { ok: true };
});
