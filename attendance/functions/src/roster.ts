export type Role = "student" | "lecturer";

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
