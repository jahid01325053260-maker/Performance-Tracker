# Validation status — Spark Free version

- Source files migrated away from direct Cloud Functions/API calls to Cloud Firestore/Firebase Auth client SDKs.
- Firebase config script is unchanged and uses supplied Android `google-services.json`.
- API logic/Firestore rules reviewed statically; real Firebase emulator tests not run.
- No Flutter SDK or Dart binary in this environment; `flutter pub get`, `flutter analyze`, widget tests and APK builds are **not verified**.
- Old Node.js backend logic tests are not tests of the new Firestore authorization and should not be confused with production safety checks.
- Before live rollout: emulator security test of USER Pending/Approved, manager scoped reads, ADMIN approvals, unauthenticated lookups, duplicate account submissions, and two-device offline edits; test coexistence with original Android client.
