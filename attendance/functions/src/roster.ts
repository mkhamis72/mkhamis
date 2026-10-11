export type RosterRole = "student" | "lecturer" | "admin";

export interface RosterRow {
  id: string;
  name: string;
  role: RosterRole;
  password?: string;
  isNew?: boolean;
}

/** Users sign in with their university ID; Firebase Auth needs an email, so we derive one. Keep in sync with the app. */
export function emailForId(id: string): string {
  return `${id.trim().toLowerCase()}@attendance.local`;
}

const ROLES: RosterRole[] = ["student", "lecturer", "admin"];

/** Parses `id,name,role,password` lines. A header row is skipped. Role defaults to student. */
export function parseRosterRows(csv: string): { rows: RosterRow[]; errors: string[] } {
  const rows: RosterRow[] = [];
  const errors: string[] = [];
  const seen = new Set<string>();
  csv.split(/\r?\n/).forEach((line, i) => {
    if (!line.trim()) return;
    const [id = "", name = "", role = "", password = ""] = line.split(",").map((c) => c.trim());
    if (i === 0 && id.toLowerCase() === "id") return;
    const r = (role.toLowerCase() || "student") as RosterRole;
    if (!/^[A-Za-z0-9._-]{2,40}$/.test(id)) return errors.push(`line ${i + 1}: invalid id "${id}"`);
    if (!name) return errors.push(`line ${i + 1}: missing name`);
    if (!ROLES.includes(r)) return errors.push(`line ${i + 1}: invalid role "${role}"`);
    if (password && password.length < 6) return errors.push(`line ${i + 1}: password must be 6+ characters`);
    if (seen.has(id.toLowerCase())) return errors.push(`line ${i + 1}: duplicate id "${id}"`);
    seen.add(id.toLowerCase());
    rows.push({ id, name, role: r, password: password || undefined });
  });
  return { rows, errors };
}
