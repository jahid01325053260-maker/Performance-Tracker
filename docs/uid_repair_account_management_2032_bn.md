# Performance Tracker — 2032 / UID / Admin ID management / Reminder

## 1. What changed

- All report year selectors now cover **2020 through 2032** (including 2027–2032).
- The admin dashboard has **Monthly PDF / Export** with **PDF and Excel** inside the same page. The redundant **Export Excel** tile is removed.
- Officer Directory (ADMIN): **Change role**, **Reset password / recovery**, **Disable and request ID deletion**.
- `Missing Firebase Auth UID` is not silently bypassed. It requires verified UID repair on an operator's PC.
- **Not Submitted** includes a notification action to the right of the dashboard tile. Report month is due by **the 10th of the next month**; reminders are available from then. In the Not Submitted page, select the reporting month/year and tap the alert icon.
- The app publishes an inbox reminder and an Android **local notification while the recipient app is running**. Closed-app/background remote delivery is **not available yet**; it needs an FCM-capable, trusted sender. Do not embed Firebase service-account keys or server FCM credentials into the app.

## 2. First: deploy test application and protect your Firebase database

1. Back up the existing Firestore data, Auth UID mapping and **current Firestore security rules**. Be aware an existing native Android app sharing the Firebase project can be affected by new rules.
2. Replace only the provided files in the GitHub repository and run `flutter pub get`, `flutter analyze`, `flutter test`, and the Android APK workflow.
3. Verify the **new** `backend/firestore.rules` in the Firebase Emulator with Admin, normal Officer, Sales Manager, AGM and DGM roles. In particular, prove that users CANNOT update `authUid`, delete someone else's `auth_users` doc, or create their own `account_deletion_requests` doc.
4. Only after that verification, deploy `firebase deploy --only firestore:rules --project performance-tracker-66b42` from the repository root. Cloud Functions/Blaze are not needed.

## 3. Repair "Missing Firebase Auth UID" — Windows CMD, trusted PC

**Do NOT enter a random UID in Firestore.** The repair tool only considers actual Firebase Auth users found by existing UID, `login_index` identity, deterministic Auth alias, or an existing `auth_users` link. If matches conflict, it skips the Employee ID for manual review.

Install Node.js 22, then from the extracted project:

```bat
cd backend
npm install
set FIREBASE_PROJECT_ID=performance-tracker-66b42
set GOOGLE_APPLICATION_CREDENTIALS=C:\private\firebase-service-account.json
set TARGET_EMPLOYEE_ID=202429021688
node scripts\repair_missing_uids.cjs
```

The service-account JSON is **not** the Android `google-services.json`. Get it only through the Firebase Admin SDK service account setup on your trusted PC. Never place it in GitHub, the Flutter `assets` directory, a ZIP sent to others, or an APK.

After independently checking the UID against the known user's actual Firebase Auth account, and after backing up the database, approve the repair:

```bat
set APPLY=1
set BACKUP_CONFIRMED=1
node scripts\repair_missing_uids.cjs
```

Clear the environment variables after. If the script says **MANUAL REVIEW**, stop; verify the login email and UID in Firebase Authentication. If the user has NO Auth account, you cannot fix it merely by assigning a UID; the account needs an independently verified Auth recovery/provisioning process.

## 4. Admin password recovery

- ADMIN > Officer List > three dots > **Reset password / recovery** sends a Firebase Auth reset email **only if** `login_index` has a real sign-in email and a matching UID.
- Accounts with the `.invalid` email alias or unlinked UIDs **cannot receive a normal reset email**. For these, first repair the UID, independently verify the person's identity, and use `backend/scripts/reset_employee_password.js` on your trusted PC with environment variables `FIREBASE_PROJECT_ID`, `TARGET_EMPLOYEE_ID`, `NEW_EMPLOYEE_PASSWORD` and the `--apply` argument. Keep the new password out of GitHub/logs and require immediate password change.
- Neither `google-services.json` nor Spark Free allows a client to reset arbitrary other users' Firebase Auth passwords directly.

## 5. Admin delete ID (two stages)

- ADMIN > Officer List > three dots > **Disable and request ID deletion**. A warning appears; the administrator must then type the exact 12-digit Employee ID. The app disables both employee and identity, and writes a **Pending** request. This blocks app authorization but does **not** physically delete the Firebase Auth user yet.
- An operator **on the trusted PC** completes deletion. First run a dry run:

```bat
cd backend
set FIREBASE_PROJECT_ID=performance-tracker-66b42
set GOOGLE_APPLICATION_CREDENTIALS=C:\private\firebase-service-account.json
set TARGET_EMPLOYEE_ID=202429021688
node scripts\finalize_account_deletion.cjs
```

After reviewing the UID, checking the Pending request and backing up Auth/Firestore, explicitly set:

```bat
set APPLY=1
set BACKUP_CONFIRMED=1
node scripts\finalize_account_deletion.cjs
```

The script removes Auth, Employee ID, Login Index, Manager Directory and ranking entry. **Historical KPI performance records are intentionally retained for audit**; plan separate retention/personal-data erasure if required by your institution. Firebase Auth deletion and Firestore deletion are two independent API operations and cannot be made into a single atomic transaction. On partial failure, inspect and reconcile rather than attempting a blind rerun.

## 6. Reminder delivery and 10th-day deadline

- For example, September 2026's report is due **10 October 2026**. ADMIN dashboard > **Not Submitted** > right alert button defaults to the latest report month with a passed deadline. The Not Submitted screen has explicit year/month selectors and its own alert icon.
- Notification documents are idempotent (`missing_YYYY-MM` per employee), so duplicate taps will not create a second reminder for the same period.
- The recipient must be signed in and **running the app** to display the native local notification immediately. The Inbox is kept in Firestore, visible on their next sign-in even if the app was closed.
- Real push to a closed device requires a trusted FCM sender (external PC/server or appropriate paid/cloud infrastructure), device token handling, notification permissions and delivery testing. This ZIP **does not claim to provide background push**.

## 7. Verification checklist

- An account missing an Auth UID cannot be given someone else's UID by the phone app.
- A disabled employee cannot sign into the app, while other officers' IDs continue to work.
- A Sales Manager cannot access applicant-level data for another manager's team.
- Report Year drop-down exposes 2028, 2029, 2030, 2031 and 2032.
- Monthly PDF / Export includes both PDF and Excel; no separate Export Excel dashboard tile.
- September's Not Submitted button becomes active from October 10, rather than silently notifying before the deadline.

**Tests run in this environment:** Node.js backend logic tests and JS syntax checks; Flutter SDK/Firebase Emulator are unavailable, so full APK build and Firestore permission tests must be completed in GitHub Actions and emulator before production rollout.
