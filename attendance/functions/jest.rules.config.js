/** Firestore security rules tests. Run via `npm run test:rules` (starts the Firestore emulator). */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/test-rules"],
  testTimeout: 20000,
};
