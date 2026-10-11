import { readFileSync } from "fs";
import { resolve } from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, updateDoc, where } from "firebase/firestore";

const PROJECT_ID = "demo-attendance";
let env: RulesTestEnvironment;

// Who's who: Auth uid → custom claims, mirroring what the registration functions set.
const STUDENT_1 = { uid: "uid-s1", claims: { role: "student", personId: "S1" } };
const STUDENT_2 = { uid: "uid-s2", claims: { role: "student", personId: "S2" } };
const LECTURER_1 = { uid: "uid-l1", claims: { role: "lecturer", personId: "L1", approved: true } };
const LECTURER_2 = { uid: "uid-l2", claims: { role: "lecturer", personId: "L2", approved: true } };
const ADMIN = { uid: "uid-a1", claims: { role: "admin", personId: "A1" } };

type User = typeof STUDENT_1 | typeof LECTURER_1 | typeof ADMIN;
const db = (u: User) => env.authenticatedContext(u.uid, u.claims).firestore();
const anon = () => env.unauthenticatedContext().firestore();

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8") },
  });
});

afterAll(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  // Seed data as Cloud Functions would write it.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, "students/S1"), { name: "Student One", authUid: STUDENT_1.uid, boundDeviceId: "dev-1" });
    await setDoc(doc(f, "students/S2"), { name: "Student Two", authUid: STUDENT_2.uid, boundDeviceId: "dev-2" });
    await setDoc(doc(f, "staff/L1"), { name: "Lecturer One", authUid: LECTURER_1.uid, status: "approved" });
    await setDoc(doc(f, "staff/L2"), { name: "Lecturer Two", authUid: LECTURER_2.uid, status: "pending" });
    await setDoc(doc(f, "admins/A1"), { name: "Admin", authUid: ADMIN.uid });
    await setDoc(doc(f, "admins/A2"), { name: "Other admin", authUid: "uid-a2" });
    await setDoc(doc(f, "invites/ABCDEFGH"), { createdBy: "A1", usedBy: null });
    await setDoc(doc(f, "sessions/sess1"), { lecturerUid: LECTURER_1.uid, subject: "Math", status: "open" });
    await setDoc(doc(f, "sessionSecrets/sess1"), { secret: "top-secret" });
    await setDoc(doc(f, "deviceUse/sess1_dev-1"), { studentId: "S1" });
    await setDoc(doc(f, "attendance/sess1_S1"), {
      sessionId: "sess1",
      lecturerUid: LECTURER_1.uid,
      studentId: "S1",
      studentUid: STUDENT_1.uid,
    });
  });
});

describe("signed out", () => {
  it.each(["students/S1", "staff/L1", "admins/A1", "invites/ABCDEFGH", "sessions/sess1", "attendance/sess1_S1"])(
    "cannot read %s",
    async (path) => {
      await assertFails(getDoc(doc(anon(), path)));
    },
  );
});

describe("students/{id}", () => {
  it("student reads own record only", async () => {
    await assertSucceeds(getDoc(doc(db(STUDENT_1), "students/S1")));
    await assertFails(getDoc(doc(db(STUDENT_1), "students/S2")));
  });

  it("lecturers and admins cannot read student records", async () => {
    await assertFails(getDoc(doc(db(LECTURER_1), "students/S1")));
    await assertFails(getDoc(doc(db(ADMIN), "students/S1")));
  });
});

describe("staff/{id}", () => {
  it("lecturer reads own record only", async () => {
    await assertSucceeds(getDoc(doc(db(LECTURER_1), "staff/L1")));
    await assertFails(getDoc(doc(db(LECTURER_1), "staff/L2")));
  });

  it("admin reads any lecturer and lists pending ones", async () => {
    await assertSucceeds(getDoc(doc(db(ADMIN), "staff/L2")));
    await assertSucceeds(getDocs(query(collection(db(ADMIN), "staff"), where("status", "==", "pending"))));
  });

  it("students cannot read staff records", async () => {
    await assertFails(getDoc(doc(db(STUDENT_1), "staff/L1")));
  });

  it("a matching personId alone is not enough: the role must be lecturer", async () => {
    const impostor = { uid: "uid-x", claims: { role: "student", personId: "L1" } };
    await assertFails(getDoc(doc(db(impostor), "staff/L1")));
  });
});

describe("admins/{id}", () => {
  it("admin reads own record only", async () => {
    await assertSucceeds(getDoc(doc(db(ADMIN), "admins/A1")));
    await assertFails(getDoc(doc(db(ADMIN), "admins/A2")));
  });

  it("lecturers cannot read admin records", async () => {
    await assertFails(getDoc(doc(db(LECTURER_1), "admins/A1")));
  });
});

describe("invites/{code}", () => {
  it("admin reads and lists invites", async () => {
    await assertSucceeds(getDoc(doc(db(ADMIN), "invites/ABCDEFGH")));
    await assertSucceeds(getDocs(collection(db(ADMIN), "invites")));
  });

  it("lecturers and students cannot read invites", async () => {
    await assertFails(getDoc(doc(db(LECTURER_1), "invites/ABCDEFGH")));
    await assertFails(getDoc(doc(db(STUDENT_1), "invites/ABCDEFGH")));
  });
});

describe("sessions/{id}", () => {
  it("owning lecturer reads the session and queries own sessions", async () => {
    await assertSucceeds(getDoc(doc(db(LECTURER_1), "sessions/sess1")));
    await assertSucceeds(
      getDocs(query(collection(db(LECTURER_1), "sessions"), where("lecturerUid", "==", LECTURER_1.uid))),
    );
  });

  it("other lecturers, students and admins cannot read it", async () => {
    await assertFails(getDoc(doc(db(LECTURER_2), "sessions/sess1")));
    await assertFails(getDoc(doc(db(STUDENT_1), "sessions/sess1")));
    await assertFails(getDoc(doc(db(ADMIN), "sessions/sess1")));
  });

  it("a query without the lecturerUid filter is rejected", async () => {
    await assertFails(getDocs(collection(db(LECTURER_1), "sessions")));
  });
});

describe("attendance/{id}", () => {
  it("the session's lecturer reads it, also via the per-session report query", async () => {
    await assertSucceeds(getDoc(doc(db(LECTURER_1), "attendance/sess1_S1")));
    await assertSucceeds(
      getDocs(
        query(
          collection(db(LECTURER_1), "attendance"),
          where("sessionId", "==", "sess1"),
          where("lecturerUid", "==", LECTURER_1.uid),
        ),
      ),
    );
  });

  it("the student reads own record and history", async () => {
    await assertSucceeds(getDoc(doc(db(STUDENT_1), "attendance/sess1_S1")));
    await assertSucceeds(
      getDocs(query(collection(db(STUDENT_1), "attendance"), where("studentUid", "==", STUDENT_1.uid))),
    );
  });

  it("other students and lecturers cannot read it", async () => {
    await assertFails(getDoc(doc(db(STUDENT_2), "attendance/sess1_S1")));
    await assertFails(getDoc(doc(db(LECTURER_2), "attendance/sess1_S1")));
  });

  it("a per-session query without the lecturerUid filter is rejected", async () => {
    await assertFails(getDocs(query(collection(db(LECTURER_1), "attendance"), where("sessionId", "==", "sess1"))));
  });
});

describe("server-only collections", () => {
  it.each([STUDENT_1, LECTURER_1, ADMIN])("sessionSecrets and deviceUse are unreadable for $claims.role", async (u) => {
    await assertFails(getDoc(doc(db(u), "sessionSecrets/sess1")));
    await assertFails(getDoc(doc(db(u), "deviceUse/sess1_dev-1")));
  });
});

describe("no client writes anywhere", () => {
  const paths = [
    "students/S1",
    "staff/L1",
    "admins/A1",
    "invites/ABCDEFGH",
    "sessions/sess1",
    "sessionSecrets/sess1",
    "deviceUse/sess1_dev-1",
    "attendance/sess1_S1",
  ];
  const users: Array<[string, User]> = [
    ["student", STUDENT_1],
    ["lecturer", LECTURER_1],
    ["admin", ADMIN],
  ];

  describe.each(users)("%s", (_role, u) => {
    it.each(paths)("cannot create, update or delete %s", async (path) => {
      await assertFails(setDoc(doc(db(u), path), { hacked: true }));
      await assertFails(updateDoc(doc(db(u), path), { hacked: true }));
      await assertFails(deleteDoc(doc(db(u), path)));
    });
  });

  it("a student cannot forge their own attendance record", async () => {
    await assertFails(
      setDoc(doc(db(STUDENT_1), "attendance/sess1_S1x"), {
        sessionId: "sess1",
        lecturerUid: LECTURER_1.uid,
        studentId: "S1",
        studentUid: STUDENT_1.uid,
      }),
    );
  });
});
