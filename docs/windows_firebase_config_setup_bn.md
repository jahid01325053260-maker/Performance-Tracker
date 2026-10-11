# Performance Tracker — Windows GitHub Actions সেটআপ (আপডেট)

## আপনার ত্রুটির কারণ

আগের `.github/workflows/desktop.yml` শুধু `WINDOWS_FIREBASE_OPTIONS_JSON` Secret পড়ত। আপনার পাঁচটি `PT_*` Variable থাকলেও সেটি `Missing WINDOWS_FIREBASE_OPTIONS_JSON` দেখাত। নতুন workflow দুটো পদ্ধতির **যেকোনো একটি** গ্রহণ করে।

## পদ্ধতি A: পাঁচটি PT_* GitHub Variables (সহজ)

Repository → **Settings → Secrets and variables → Actions → Variables → New repository variable** থেকে আলাদাভাবে তৈরি করুন:

- `PT_API_KEY` — Web App-এর পূর্ণ apiKey
- `PT_APP_ID` — Web App-এর appId (`1:...:web:...`)
- `PT_MESSAGING_SENDER_ID` — Web App-এর messagingSenderId
- `PT_PROJECT_ID` — `performance-tracker-66b42`
- `PT_AUTH_DOMAIN` — `performance-tracker-66b42.firebaseapp.com`

একটি JSON বা `KEY: value` ব্লক একসঙ্গে পেস্ট করবেন **না**। প্রতিটি Name-এর Value ঘরে শুধু মান বসান। `Secrets` ট্যাবে আলাদাভাবে রাখলেও নতুন Workflow কাজ করবে।

## পদ্ধতি B: একটি JSON Secret

Repository → **Settings → Secrets and variables → Actions → Secrets → New repository secret**:

- Name: `WINDOWS_FIREBASE_OPTIONS_JSON`
- Value: বৈধ JSON, এই নমুনার মতো (আপনার প্রকৃত Firebase Web App মান বসান):

```json
{
  "FIREBASE_API_KEY": "YOUR_WEB_API_KEY",
  "FIREBASE_APP_ID": "1:YOUR_SENDER_ID:web:YOUR_WEB_APP_ID",
  "FIREBASE_MESSAGING_SENDER_ID": "YOUR_SENDER_ID",
  "FIREBASE_PROJECT_ID": "performance-tracker-66b42",
  "FIREBASE_AUTH_DOMAIN": "performance-tracker-66b42.firebaseapp.com"
}
```

`WINDOWS_FIREBASE_OPTIONS_JSON` Secret দিলে সেটি `PT_*` মানগুলোর আগে ব্যবহার হবে। Secret-এ ভুল/পুরোনো JSON থাকলে সেটি ঠিক করুন অথবা মুছে কেবল `PT_*` ব্যবহার করুন।

## চালানোর নিয়ম

1. `.github/workflows/desktop.yml` এবং `lib/main.dart` পরিবর্তিত ফাইল Replace করুন।
2. GitHub-এ Commit করুন।
3. Actions → **Desktop Builds** → **Run workflow**।
4. Windows job সফল হলে Artifacts থেকে `PerformanceTracker-windows` ডাউনলোড করুন। `exe`-এর পাশাপাশি DLL ও data ফোল্ডারও রাখতে হবে।

## কেন main.dart পরিবর্তন করা হয়েছে

Windows-এ Android-এর `google-services.json` থাকে না। `flutter build windows --release --dart-define-from-file=firebase_config/windows/firebase_options.local.json` থেকে পাওয়া পাঁচটি মান দিয়ে এখন Windows-এর `Firebase.initializeApp(options: ...)` করা হবে। Android-এর নিজের initialization অপরিবর্তিত।

## বিশেষ সতর্কতা

- এই JSON সাধারণ ক্লায়েন্ট Web App config, **Admin service-account/private key নয়**।
- `firebase_config/windows/firebase_options.local.json` `.gitignore`-এ আছে; স্থানীয় ফাইলটি GitHub-এ Commit করা দরকার নেই।
- Github Environment-level Secret/Variable ব্যবহার করলে সংশ্লিষ্ট Job-এ `environment:` সেট থাকতে হয়; সহজ উপায় হলো Repository-level Variables/Secrets।
- Windows Firebase Auth/Firestore-এর beta plugin compatibility ও বাস্তব Login/Reporting আলাদা করে পরীক্ষা করতে হবে।
- Windows, Linux ও macOS jobs এক Workflow-তে থাকলেও এই পরিবর্তন কেবল Windows setup-এর জন্য।
