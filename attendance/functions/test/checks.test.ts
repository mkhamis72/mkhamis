import { evaluateScan, ScanContext } from "../src/checks";
import { checkGeofence, distanceMeters } from "../src/geo";
import { buildPayload, decodePayload, encodePayload, SLOT_SECONDS, verifyPayload } from "../src/qr";
import { emailForId, parseAdminIds, validateRegistration } from "../src/roster";

const SECRET = "test-secret";
const NOW = 1_760_000_000_000;
const HALL = { lat: 30.0444, lng: 31.2357, radiusMeters: 50 };
const INSIDE = { lat: 30.0444, lng: 31.2358, accuracy: 10 }; // ~10 m away
const FAR = { lat: 30.05, lng: 31.24, accuracy: 10 }; // ~750 m away

function ctx(overrides: Partial<ScanContext> = {}, mode: "rotating" | "static" = "rotating"): ScanContext {
  return {
    nowMs: NOW,
    payload: buildPayload(mode, "s1", "Math", "Hall A", SECRET, NOW),
    secret: SECRET,
    session: {
      mode,
      status: "open",
      startsAtMs: NOW - 60_000,
      windowMinutes: 15,
      settings: { geofence: true, deviceBinding: true, timeWindow: true },
    },
    student: { studentId: "st1", boundDeviceId: "device-AAAA", rebindAtMs: null },
    hall: HALL,
    deviceId: "device-AAAA",
    location: INSIDE,
    deviceUsedBy: null,
    ...overrides,
  };
}

const reason = (c: ScanContext) => {
  const d = evaluateScan(c);
  return d.ok ? "ok" : d.reason;
};

describe("QR payload", () => {
  it("round-trips through encode/decode", () => {
    const p = buildPayload("rotating", "s1", "Math", "Hall A", SECRET, NOW);
    expect(decodePayload(encodePayload(p))).toEqual(p);
    expect(decodePayload("not json")).toBeNull();
  });

  it("rotating code expires after the tolerance window", () => {
    const p = buildPayload("rotating", "s1", "Math", "Hall A", SECRET, NOW);
    expect(verifyPayload("rotating", p, SECRET, NOW + SLOT_SECONDS * 1000)).toBe("ok");
    expect(verifyPayload("rotating", p, SECRET, NOW + 3 * SLOT_SECONDS * 1000)).toBe("expired_qr");
  });

  it("static code never expires on its own", () => {
    const p = buildPayload("static", "s1", "Math", "Hall A", SECRET, NOW);
    expect(p.t).toBeUndefined();
    expect(verifyPayload("static", p, SECRET, NOW + 86_400_000)).toBe("ok");
  });

  it("rejects tampering, wrong secret (regenerated) and mode mix-ups", () => {
    const p = buildPayload("rotating", "s1", "Math", "Hall A", SECRET, NOW);
    expect(verifyPayload("rotating", { ...p, sid: "s2" }, SECRET, NOW)).toBe("bad_signature");
    expect(verifyPayload("rotating", p, "new-secret", NOW)).toBe("bad_signature");
    expect(verifyPayload("static", p, SECRET, NOW)).toBe("wrong_mode");
  });
});

describe("geofence", () => {
  it("computes distances", () => {
    expect(distanceMeters(HALL, INSIDE)).toBeLessThan(15);
    expect(distanceMeters(HALL, FAR)).toBeGreaterThan(500);
  });

  it("flags scans accepted only thanks to GPS slack", () => {
    // ~65 m away, accuracy 20 → allowed 70 m
    const r = checkGeofence(HALL, { lat: 30.04498, lng: 31.2357, accuracy: 20 });
    expect(r).toMatchObject({ ok: true, flags: ["near_hall_edge"] });
  });

  it("rejects vague, mocked or missing fixes", () => {
    expect(checkGeofence(HALL, { ...INSIDE, accuracy: 500 })).toMatchObject({ reason: "location_inaccurate" });
    expect(checkGeofence(HALL, { ...INSIDE, isMocked: true })).toMatchObject({ reason: "location_mocked" });
    expect(checkGeofence(HALL, undefined)).toMatchObject({ reason: "location_missing" });
  });
});

describe("evaluateScan", () => {
  it("accepts a valid scan", () => {
    expect(evaluateScan(ctx())).toEqual({ ok: true, flags: [], distance: expect.any(Number), bindDevice: false });
  });

  it("rejects paused / ended sessions", () => {
    const c = ctx();
    c.session.status = "paused";
    expect(reason(c)).toBe("session_closed");
  });

  it("time window: enforced when on, ignored when off", () => {
    const late = ctx({ nowMs: NOW + 20 * 60_000 });
    late.payload = buildPayload("rotating", "s1", "Math", "Hall A", SECRET, late.nowMs);
    expect(reason(late)).toBe("outside_time_window");
    late.session.settings.timeWindow = false;
    expect(reason(late)).toBe("ok");
  });

  it("rejects a shared screenshot of an old rotating code", () => {
    const old = buildPayload("rotating", "s1", "Math", "Hall A", SECRET, NOW - 60_000);
    expect(reason(ctx({ payload: old }))).toBe("expired_qr");
  });

  it("device binding: mismatch, shared phone, first bind, off", () => {
    expect(reason(ctx({ deviceId: "device-BBBB" }))).toBe("device_mismatch");
    expect(reason(ctx({ deviceUsedBy: "st2" }))).toBe("device_already_used");
    expect(evaluateScan(ctx({ student: { studentId: "st1", boundDeviceId: null } }))).toMatchObject({ ok: true, bindDevice: true });

    const off = ctx({ deviceId: "device-BBBB", deviceUsedBy: "st2" });
    off.session.settings.deviceBinding = false;
    expect(reason(off)).toBe("ok");
  });

  it("phone switched after the session started can't sign that session", () => {
    const during = ctx({ student: { studentId: "st1", boundDeviceId: "device-AAAA", rebindAtMs: NOW - 30_000 } });
    expect(reason(during)).toBe("device_changed_during_session");
  });

  it("phone switched before the session started works", () => {
    const before = ctx({ student: { studentId: "st1", boundDeviceId: "device-AAAA", rebindAtMs: NOW - 3_600_000 } });
    expect(reason(before)).toBe("ok");
  });

  it("phone-switch rule is skipped when device binding is off", () => {
    const c = ctx({ student: { studentId: "st1", boundDeviceId: "device-AAAA", rebindAtMs: NOW - 30_000 } });
    c.session.settings.deviceBinding = false;
    expect(reason(c)).toBe("ok");
  });

  it("geofence: rejects far away when on, ignored when off (rotating)", () => {
    expect(reason(ctx({ location: FAR }))).toBe("outside_hall");
    const off = ctx({ location: undefined });
    off.session.settings.geofence = false;
    expect(evaluateScan(off)).toMatchObject({ ok: true });
  });

  it("static mode always enforces the geofence, even if toggled off", () => {
    const c = ctx({ location: FAR }, "static");
    c.session.settings.geofence = false;
    expect(reason(c)).toBe("outside_hall");
    expect(reason(ctx({}, "static"))).toBe("ok");
  });
});

describe("registration", () => {
  it("maps IDs to auth emails", () => {
    expect(emailForId(" S1001 ")).toBe("s1001@attendance.local");
  });

  it("validates ID, name and password", () => {
    expect(validateRegistration("S1001", "Ali Hassan", "secret1")).toBeNull();
    expect(validateRegistration("bad id", "Ali", "secret1")).toMatch(/ID/);
    expect(validateRegistration("S1001", "", "secret1")).toMatch(/name/);
    expect(validateRegistration("S1001", "Ali", "123")).toMatch(/Password/);
  });

  it("parses the admin staff ID list", () => {
    expect([...parseAdminIds(" L001, l002;L003\n")]).toEqual(["l001", "l002", "l003"]);
    expect(parseAdminIds("").size).toBe(0);
  });
});
