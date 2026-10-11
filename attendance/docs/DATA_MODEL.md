# Data Model (Firestore)

All writes are done by Cloud Functions (Admin SDK). The **Client read** column shows what `firestore.rules` allows.

## Auth custom claims

| Claim | Values | Set by |
|---|---|---|
| `role` | `student` \| `lecturer` \| `admin` | `registerStudent` / `registerLecturer` / `registerAdmin` |
| `personId` | Student ID or Staff ID as typed (trimmed) | Registration |
| `approved` | `true` \| `false` (lecturers only) | `registerLecturer` (true with a valid invite), `approveLecturer` |

Auth email = `lowercase(trim(id)) + "@attendance.local"`. Display name = full name.

## Collections

### `students/{studentId}`
| Field | Type | Notes |
|---|---|---|
| name | string | 2–80 chars |
| university | string | 2–100 |
| mobile | string | 7+ digits, `+ ( ) - space` allowed |
| email | string | Lower-cased |
| authUid | string | Firebase Auth UID |
| boundDeviceId | string \| null | The phone allowed to scan |
| boundAt | timestamp | When it was bound |
| rebindAt | timestamp \| null | Set only by "Use this phone". Scans in sessions that started before this are rejected |

Client read: the student themself (`token.personId == studentId`).

### `staff/{staffId}` (lecturers)
| Field | Type | Notes |
|---|---|---|
| name, university, mobile, email | string | Same validation as students |
| authUid | string | |
| status | `pending` \| `approved` | |
| approvedBy | string \| null | Admin Staff ID, or `invite:<CODE>` |
| approvedAt | timestamp | Manual approvals only |
| createdAt | timestamp | |
| recentPlaces | array<{subject, hallName, lat, lng, radiusMeters}> | Newest first, max 10, unique by subject+hall |

Client read: the lecturer themself, and admins (any doc).

### `admins/{staffId}`
| Field | Type |
|---|---|
| name | string |
| authUid | string |
| createdAt | timestamp |

Client read: the admin themself.

### `invites/{CODE}`
Doc ID = 8-char code, upper-case, alphabet `ABCDEFGHJKMNPQRSTUVWXYZ23456789`.

| Field | Type | Notes |
|---|---|---|
| createdBy | string | Admin Staff ID |
| createdAt | timestamp | |
| expiresAt | timestamp | createdAt + 7 days |
| staffId | string \| null | If set, only this Staff ID may use it (case-insensitive) |
| note | string \| null | "For" label, ≤ 100 chars |
| usedBy | string \| null | Staff ID that used it |
| usedAt | timestamp \| null | |

Client read: admins.

### `sessions/{sessionId}`
| Field | Type | Notes |
|---|---|---|
| subject | string | ≤ 100 |
| hallName | string | ≤ 100 |
| lat, lng | number | Hall centre (the lecturer's position at creation) |
| radiusMeters | number | Clamped 10–500 (UI offers 20–200), default 50 |
| lecturerUid | string | Owner |
| lecturerId | string | Owner Staff ID |
| mode | `rotating` \| `static` | |
| status | `open` \| `paused` \| `ended` | |
| startsAt | timestamp | Creation time |
| endedAt | timestamp | When ended |
| windowMinutes | number | Clamped 1–240, default 15. `extend` adds 1–120 |
| settings | {geofence, deviceBinding, timeWindow: bool} | `geofence` forced true when mode = static |
| attendeeCount | number | Maintained by functions |

Client read: the owning lecturer.

### `sessionSecrets/{sessionId}`
| Field | Type |
|---|---|
| secret | string (64 hex chars, 32 random bytes) |

Client read: **never**.

### `attendance/{sessionId}_{studentId}`
| Field | Type | Notes |
|---|---|---|
| sessionId, subject, hallName | string | Copied from the session |
| lecturerUid | string | For rules + lecturer queries |
| studentId, studentUid, studentName | string | Name as it was at scan time |
| at | timestamp | Scan time |
| deviceId | string | |
| location | {lat, lng, accuracy} \| null | |
| distanceMeters | number \| null | Null when the geofence is off |
| flags | string[] | e.g. `near_hall_edge` |

Client read: the session's lecturer (`lecturerUid`) or the student (`studentUid`). Queries must include the matching equality filter.

### `deviceUse/{sessionId}_{deviceId}`
| Field | Type |
|---|---|
| studentId | string |
| at | timestamp |

Stops one phone signing two students into the same session. Client read: **never**.

## Composite indexes (`firestore.indexes.json`)
| Collection | Fields | Used by |
|---|---|---|
| attendance | studentUid ↑, at ↓ | Student history |
| attendance | lecturerUid ↑, at ↓ | Lecturer "Attended students" (date range) |
| sessions | lecturerUid ↑, startsAt ↓ | Lecturer session list |

The per-session report query (`sessionId ==` and `lecturerUid ==`) uses equality filters only and needs no composite index.
