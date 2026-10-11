# PerformanceTracker Flutter — Firebase Spark Free Build

The existing `PerformanceTracker` Android/Kotlin source has been adapted to a Flutter app using **Firebase Authentication + Cloud Firestore directly**, without any paid Firebase Cloud Functions, custom API URL or Blaze upgrade. Android Firebase app package: `com.performance.tracker`. Existing Firebase Project: `performance-tracker-66b42`.

**Start here:** [Bangla Spark Free Setup](docs/spark_free_setup_bn.md)

## Android build on GitHub

Keep your existing repo and overwrite the changed files; do not create a new project. `.github/workflows/android.yml` runs Flutter setup, `tool/configure_firebase_android.py`, analysis, unit tests and APK build.

Local Windows:

```bat
tool\setup_platforms.bat
flutter build apk --debug
```

## Firebase rules first

Deploy **Firestore Rules** separately, after testing/backup and checking compatibility with the legacy native app:

```bash
firebase deploy --only firestore:rules --project performance-tracker-66b42
```

`firebase.json` intentionally contains **no Functions**. `backend/src` is legacy source preserved only for reference; it is not an active backend. **Never deploy old Cloud Functions on Spark.**

## Known limits

- The old native app's legacy plaintext-password users need a controlled migration to Firebase Authentication; the client does not read plaintext passwords.
- Admin approvals rely on an existing trusted ADMIN auth/Firestore mapping. No unauthorized self-promotion.
- Automatic KPI PDF text extraction is not yet available offline and the UI says so. Client-side manual submission and PDF/XLSX/CSV export remain.
- Admin-published leaderboard summaries protect applicant-level records; manager analytics need correct `managerId` mappings.
- Android is the primary configured target. iOS/macOS/Windows require platform-specific FlutterFire configuration; Linux support must be reviewed.
- Flutter SDK and a live Firebase test project are unavailable in this workspace, so the APK, analyzer and deployed-rule behavior are not verified here.

**Firestore rules can break legacy Android clients!** Never deploy blindly over a live project without a backup, rule tests and a cutover plan.

## Login / Month View / Role Editor update

See [Bangla guide](docs/login_month_role_fix_bn.md) for real-email Firebase password reset, `.invalid` alias recovery from a trusted local Admin SDK script (no Cloud Functions), opt-in device credential storage, new management Month View, and server-rule protected role changes. Update Firestore Rules **only after compatibility tests**.
