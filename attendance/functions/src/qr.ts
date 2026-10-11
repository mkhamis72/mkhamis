import { createHmac, randomBytes, timingSafeEqual } from "crypto";

/** Rotating QR codes change every SLOT_SECONDS. */
export const SLOT_SECONDS = 10;
/** Accept the current slot and this many slots either side (clock skew + scan delay). */
export const SLOT_TOLERANCE = 1;

export type QrMode = "rotating" | "static";

/** What is encoded inside the QR image. */
export interface QrPayload {
  v: 1;
  sid: string; // session id
  subject: string;
  hall: string;
  t?: number; // time slot, rotating mode only
  sig: string;
}

export function newSecret(): string {
  return randomBytes(32).toString("hex");
}

export function slotAt(nowMs: number): number {
  return Math.floor(nowMs / 1000 / SLOT_SECONDS);
}

function hmac(secret: string, message: string): string {
  return createHmac("sha256", secret).update(message).digest("base64url");
}

function signedMessage(sid: string, t?: number): string {
  return t === undefined ? `${sid}|static` : `${sid}|${t}`;
}

export function buildPayload(
  mode: QrMode,
  sid: string,
  subject: string,
  hall: string,
  secret: string,
  nowMs: number,
): QrPayload {
  const t = mode === "rotating" ? slotAt(nowMs) : undefined;
  const payload: QrPayload = { v: 1, sid, subject, hall, sig: hmac(secret, signedMessage(sid, t)) };
  if (t !== undefined) payload.t = t;
  return payload;
}

export function encodePayload(p: QrPayload): string {
  return JSON.stringify(p);
}

export function decodePayload(raw: string): QrPayload | null {
  try {
    const p = JSON.parse(raw);
    if (p && p.v === 1 && typeof p.sid === "string" && typeof p.sig === "string") {
      return p as QrPayload;
    }
  } catch {
    // fall through
  }
  return null;
}

export type SignatureResult = "ok" | "bad_signature" | "expired_qr" | "wrong_mode";

export function verifyPayload(
  mode: QrMode,
  p: QrPayload,
  secret: string,
  nowMs: number,
): SignatureResult {
  if ((mode === "rotating") !== (typeof p.t === "number")) return "wrong_mode";
  const expected = Buffer.from(hmac(secret, signedMessage(p.sid, p.t)));
  const given = Buffer.from(p.sig);
  if (expected.length !== given.length || !timingSafeEqual(expected, given)) {
    return "bad_signature";
  }
  if (mode === "rotating" && Math.abs(slotAt(nowMs) - (p.t as number)) > SLOT_TOLERANCE) {
    return "expired_qr";
  }
  return "ok";
}
