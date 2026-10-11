import { randomInt } from "crypto";

export type Role = "student" | "lecturer" | "admin";

/** Users sign in with their university/staff ID; Firebase Auth needs an email, so we derive one. Keep in sync with the app. */
export function emailForId(id: string): string {
  return `${id.trim().toLowerCase()}@attendance.local`;
}

/** Returns an error message, or null when the registration input is valid. */
export function validateRegistration(id: string, name: string, password: string): string | null {
  if (!/^[A-Za-z0-9._-]{2,40}$/.test(id.trim())) return "ID must be 2–40 letters, digits, dot, dash or underscore.";
  if (name.trim().length < 2 || name.trim().length > 80) return "Enter your full name.";
  if (password.length < 6) return "Password must be at least 6 characters.";
  return null;
}

/** Parses the ADMIN_STAFF_IDS setting ("L001, L002") into lower-cased IDs. */
export function parseAdminIds(raw: string): Set<string> {
  return new Set(raw.split(/[\s,;]+/).map((s) => s.trim().toLowerCase()).filter(Boolean));
}

/** Invite codes stay valid for this long. */
export const INVITE_VALID_DAYS = 7;
/** No 0/O, 1/I/L: easy to read out or type from a message. */
const INVITE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export function newInviteCode(length = 8): string {
  let code = "";
  for (let i = 0; i < length; i++) code += INVITE_ALPHABET[randomInt(INVITE_ALPHABET.length)];
  return code;
}

/** Codes are stored upper-case without spaces or dashes, so "abcd-efgh" works too. */
export function normalizeInviteCode(raw: string): string {
  return raw.toUpperCase().replace(/[\s-]/g, "");
}

export interface Invite {
  usedBy?: string | null;
  expiresAtMs: number;
  /** When set, only this staff ID may use the code. */
  staffId?: string | null;
}

/** Returns why an invite can't be used by `staffId`, or null when it can. */
export function inviteProblem(invite: Invite | undefined, staffId: string, nowMs: number): string | null {
  if (!invite) return "Invite code not found.";
  if (invite.usedBy) return "This invite code has already been used.";
  if (nowMs > invite.expiresAtMs) return "This invite code has expired. Ask the admin for a new one.";
  if (invite.staffId && invite.staffId.toLowerCase() !== staffId.trim().toLowerCase()) {
    return "This invite code was issued for a different Staff ID.";
  }
  return null;
}
