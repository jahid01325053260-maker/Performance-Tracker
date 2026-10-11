# Performance Tracker — ২০৩২ / Admin / Notifications

- Year নির্বাচন: ২০২০–২০৩২ (Month View, Targets, Export, Not Submitted)।
- Dashboard-এ এখন শুধু `Monthly PDF / Export`; ভিতরে PDF / Excel / CSV নির্বাচন করা যাবে।
- ADMIN → Officer List → তিন-ডট: `Send password reset email` অথবা `Delete ID (disable and queue)`।
- Delete ID প্রথম ধাপে account **Disabled** করে এবং `identity_deletion_requests`-এ request রাখে; Firebase Auth account **এখনও মুছে যায় না**।
- বাস্তব Firebase Authentication user Delete অথবা `.invalid` alias-এর Password Reset: বিশ্বস্ত Admin PC-তে `backend/scripts/manage_firebase_identity.mjs` ব্যবহার করুন। Flutter অ্যাপে service account key কখনো দেবেন না।
- ADMIN → Not Submitted-এর উপরে 🔔 বাটনে চাপলে অনুপস্থিতদের Firestore inbox-এ সতর্কবার্তা লিখবে। Officer → Notifications-এ সেই বার্তা দেখতে পাবেন।
- Android 13+ Notifications permission চাইবে। অ্যাপ foreground-এ চালু থাকা অবস্থায় নতুন alert এলে system notification দেখানো সম্ভব। **বন্ধ অ্যাপে Push পাঠাতে Spark Client-only architecture যথেষ্ট নয়; trusted backend/FCM sender প্রয়োজন।**
- নতুন Rules `backend/firestore.rules` staging-এ পরীক্ষা করুন। আগে Backup নিন; পুরোনো Android অ্যাপ একই Firebase ব্যবহার করলে permissions পরিবর্তন প্রভাব ফেলতে পারে।
- `flutter create --platforms=android .`-এর পরে `python tool/configure_firebase_android.py` চালাতে হবে; এটি Manifest ও MainActivity-তে notification channel যোগ করে।
- APK workflow-এ একই Android setup script পুনরায় চালান।
- UI-র Delete অনুরোধ Firebase Authentication User-কে Delete করে না; admin script দিয়ে সম্পন্ন করতে হবে।
- সরাসরি Flutter build/test এই পরিবেশে করা হয়নি; GitHub Actions দিয়ে `flutter analyze`, `flutter test`, APK build যাচাই করুন।

## Trusted Desktop Admin operations (Firebase Spark-compatible)

**Important:** These commands must NEVER run inside the distributed Flutter APK. Run on a secure administrator PC only, with Firebase Authentication administration permissions. Take a Firestore backup first and verify the target ID and backup retention policy.

1. Install Node.js, Google Cloud CLI and authenticate `gcloud auth application-default login` using an authorized Google Cloud admin account. Ensure `firebase-admin` is installed inside `backend` (`cd backend && npm install`).
2. From `backend/` run (replace the 12-digit ID):

```bash
node scripts/manage_firebase_identity.mjs --action=reset --id=123456789012 --confirm=123456789012 --project=performance-tracker-66b42
```

The script asks for a hidden temporary password interactively. Share it privately and ask the user to change it after login. If the ID uses a `.invalid` Auth login alias, email reset is not deliverable: this Admin SDK command is required.

3. To **permanently delete an ID** first disable it with the app's `Delete ID (disable and queue)` action and verify its deletion request. Then run:

```bash
node scripts/manage_firebase_identity.mjs --action=delete --id=123456789012 --confirm=123456789012 --project=performance-tracker-66b42
```

This deletes the Firebase Auth identity, profile, sign-in index, leaderboard record and notification inbox. Existing performance reports and audit history are intentionally retained; separately consider financial-record retention requirements. The tool does **not** indiscriminately delete applicant records. It refuses operations on ADMIN-role targets without an additional, separately reviewed flag.

4. For Firestore access the `identity_deletion_requests` and `user_notifications` rules must be tested in a staging project before deploying:

```bash
firebase deploy --only firestore:rules --project performance-tracker-66b42
```

Old apps sharing these rules may be affected. No Cloud Functions or Firebase Blaze plan is required for the inbox-and-foreground-alert model; fully asynchronous FCM notifications to a terminated app are **not** implemented.
