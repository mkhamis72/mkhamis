import { checkGeofence, GeoPoint, LocationFix } from "./geo";
import { QrMode, QrPayload, verifyPayload } from "./qr";

export interface SessionSettings {
  geofence: boolean;
  deviceBinding: boolean;
  timeWindow: boolean;
}

export interface SessionDoc {
  courseId: string;
  hallId: string;
  mode: QrMode;
  status: "open" | "paused" | "ended";
  startsAtMs: number;
  windowMinutes: number;
  settings: SessionSettings;
}

export interface StudentDoc {
  studentId: string;
  boundDeviceId?: string | null;
}

export interface ScanContext {
  nowMs: number;
  payload: QrPayload;
  secret: string;
  session: SessionDoc;
  enrolled: boolean;
  student: StudentDoc;
  hall: GeoPoint & { radiusMeters: number };
  deviceId: string;
  location?: LocationFix;
  /** Student id that this device already signed in for this session, if any. */
  deviceUsedBy?: string | null;
}

export type RejectReason =
  | "not_enrolled"
  | "session_closed"
  | "outside_time_window"
  | "bad_signature"
  | "expired_qr"
  | "wrong_mode"
  | "device_mismatch"
  | "device_already_used"
  | "location_missing"
  | "location_mocked"
  | "location_inaccurate"
  | "outside_hall";

export type ScanDecision =
  | { ok: true; flags: string[]; distance?: number; bindDevice: boolean }
  | { ok: false; reason: RejectReason };

/** Static QR codes can be photographed and shared, so they always require the geofence. */
export function effectiveSettings(mode: QrMode, s: SessionSettings): SessionSettings {
  return mode === "static" ? { ...s, geofence: true } : s;
}

/** Runs every anti-cheat check, in order. Pure: callers load the data and write the result. */
export function evaluateScan(ctx: ScanContext): ScanDecision {
  const { session } = ctx;
  const settings = effectiveSettings(session.mode, session.settings);

  if (!ctx.enrolled) return { ok: false, reason: "not_enrolled" };

  if (session.status !== "open") return { ok: false, reason: "session_closed" };
  if (settings.timeWindow) {
    const endMs = session.startsAtMs + session.windowMinutes * 60_000;
    if (ctx.nowMs < session.startsAtMs || ctx.nowMs > endMs) {
      return { ok: false, reason: "outside_time_window" };
    }
  }

  const sig = verifyPayload(session.mode, ctx.payload, ctx.secret, ctx.nowMs);
  if (sig !== "ok") return { ok: false, reason: sig };

  let bindDevice = false;
  if (settings.deviceBinding) {
    const bound = ctx.student.boundDeviceId;
    if (bound && bound !== ctx.deviceId) return { ok: false, reason: "device_mismatch" };
    if (!bound) bindDevice = true;
    if (ctx.deviceUsedBy && ctx.deviceUsedBy !== ctx.student.studentId) {
      return { ok: false, reason: "device_already_used" };
    }
  }

  const flags: string[] = [];
  let distance: number | undefined;
  if (settings.geofence) {
    const geo = checkGeofence(ctx.hall, ctx.location);
    if (!geo.ok) return { ok: false, reason: geo.reason };
    flags.push(...geo.flags);
    distance = geo.distance;
  }

  return { ok: true, flags, distance, bindDevice };
}

export const REASON_MESSAGES: Record<RejectReason, string> = {
  not_enrolled: "You are not enrolled in this course.",
  session_closed: "This attendance session is not open.",
  outside_time_window: "The attendance time window has closed.",
  bad_signature: "Invalid QR code.",
  expired_qr: "This QR code has expired. Scan the live code on the screen.",
  wrong_mode: "Invalid QR code.",
  device_mismatch: "This account is registered to another phone. Ask the admin to reset it.",
  device_already_used: "This phone already signed in another student for this class.",
  location_missing: "Location is required. Turn on GPS and allow location access.",
  location_mocked: "Fake location detected.",
  location_inaccurate: "GPS signal is too weak. Move near a window and try again.",
  outside_hall: "You are not in the lecture hall.",
};
