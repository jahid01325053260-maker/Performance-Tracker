# PerformanceTracker — Windows Firebase Configuration

## Local Windows build

Firebase Console > Project settings > Your apps > Web app > Config থেকে প্রকৃত Web App configuration নিন।
`firebase_config/windows/firebase_options.example.json` কপি করে একই ফোল্ডারে
`firebase_options.local.json` নাম দিন, এবং পাঁচটি `FIREBASE_*` মান বসান।

```powershell
flutter pub get
flutter run -d windows --dart-define-from-file=firebase_config/windows/firebase_options.local.json
flutter build windows --release --dart-define-from-file=firebase_config/windows/firebase_options.local.json
```

শুধু `.exe`-র পাশে ফাইল রাখলে কাজ করবে না—Firebase values build time-এ যুক্ত হয়।

## GitHub Actions Windows release

1. Repository > Settings > Secrets and variables > Actions > New repository secret.
2. Name: `WINDOWS_FIREBASE_OPTIONS_JSON`
3. Value: নিচের JSON-এ প্রকৃত Firebase WEB app values বসিয়ে সম্পূর্ণ JSON পেস্ট করুন:

```json
{
  "FIREBASE_API_KEY": "YOUR_WEB_API_KEY",
  "FIREBASE_APP_ID": "YOUR_WEB_APP_ID",
  "FIREBASE_MESSAGING_SENDER_ID": "YOUR_WEB_SENDER_ID",
  "FIREBASE_PROJECT_ID": "performance-tracker-66b42",
  "FIREBASE_AUTH_DOMAIN": "performance-tracker-66b42.firebaseapp.com"
}
```

4. `.github/workflows/desktop.yml` Replace করে Commit করুন।
5. Actions > Desktop Builds > Run workflow; Build হলে নতুন Windows artifact ডাউনলোড করুন।

**নোট:** Windows-এ Firebase Authentication ও Cloud Firestore FlutterFire-এ beta / local development; production ব্যবহারের জন্য আনুষ্ঠানিক সমর্থন নেই। Firebase service-account/private key কখনও এই JSON-এ রাখবেন না।
