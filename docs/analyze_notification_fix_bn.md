# GitHub Actions flutter analyze — 15 issues

Source: logs_103161773665.zip (Analyze step).

- `lib/services/api.dart`: adds `watchOwnAlerts()` and Admin-only `alertNotSubmitted()` with employee ID bound to the authenticated Firebase session.
- `lib/features/dashboard/home_screen.dart`: preserves dashboard and Export Excel; imports existing `showMessage` helper.
- `lib/features/notifications/notifications_screen.dart`: imports helper and encloses `if` body in braces.
- `lib/services/report_tables.dart`: replaces redundant null-assertions with typed month boundaries. January–June scope and totals are unchanged.
- `test/report_years_test.dart`: package-style import.
- `lib/core/report_years.dart` and `lib/services/notification_service.dart`: companion files included in case they are not yet on the branch.
- `backend/firestore.rules`: narrowly scoped notification inbox permissions.

## GitHub

1. Extract `Only_Modified.zip` and copy each file into its exact repository path. Do **not** delete other files.
2. Commit and rerun GitHub Actions. `flutter analyze`, `flutter test`, and build must be checked on the runner; none of them was executed locally.
3. Before deploying `backend/firestore.rules`, back up your current Firebase rules and test compatibility with the old native app and these Rules in Firebase Emulator. If validated, deploy the rules explicitly.
4. The inbox works while the app is signed in and connected. True background device push notifications are **not** provided by Spark Free without trusted push-sending infrastructure. The optional Android platform channel gracefully falls back to inbox-only behavior if not implemented.

**Security note**: No anonymous read permissions are added for employee records or applicant reports. `user_notifications` only permits ADMIN to create a reminder and that recipient to read it.
