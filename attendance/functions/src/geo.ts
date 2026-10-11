const EARTH_RADIUS_M = 6371000;

/** Above this the fix is too vague to judge. */
export const MAX_ACCURACY_M = 100;
/** Most GPS slack added on top of the hall radius. */
export const MAX_ACCURACY_BONUS_M = 30;

export interface GeoPoint {
  lat: number;
  lng: number;
}

export interface LocationFix extends GeoPoint {
  accuracy: number; // metres, as reported by the phone
  isMocked?: boolean;
}

export function distanceMeters(a: GeoPoint, b: GeoPoint): number {
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

export type GeofenceResult =
  | { ok: true; distance: number; flags: string[] }
  | { ok: false; reason: "location_missing" | "location_mocked" | "location_inaccurate" | "outside_hall"; distance?: number };

export function checkGeofence(
  hall: GeoPoint & { radiusMeters: number },
  fix: LocationFix | undefined,
): GeofenceResult {
  if (!fix || !Number.isFinite(fix.lat) || !Number.isFinite(fix.lng)) {
    return { ok: false, reason: "location_missing" };
  }
  if (fix.isMocked) return { ok: false, reason: "location_mocked" };
  if (!Number.isFinite(fix.accuracy) || fix.accuracy > MAX_ACCURACY_M) {
    return { ok: false, reason: "location_inaccurate" };
  }
  const distance = distanceMeters(hall, fix);
  const allowed = hall.radiusMeters + Math.min(fix.accuracy, MAX_ACCURACY_BONUS_M);
  if (distance > allowed) return { ok: false, reason: "outside_hall", distance };
  // Accepted only thanks to the GPS slack: let the lecturer review it.
  const flags = distance > hall.radiusMeters ? ["near_hall_edge"] : [];
  return { ok: true, distance, flags };
}
