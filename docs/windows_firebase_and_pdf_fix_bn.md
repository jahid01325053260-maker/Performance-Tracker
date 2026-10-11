# PerformanceTracker: Windows Firebase এবং PDF Import Build Fix

## 1. কী পরিবর্তন হয়েছে

- `lib/main.dart` Windows-এ Firebase initialization-এর জন্য আলাদা app options গ্রহণ করে। Android-এর `google-services.json` অপরিবর্তিত।
- `lib/features/performance/submission_screen.dart`-এ নিরাপদ আগের PDF Import workflow রাখা হয়েছে; এটি `ApiClient.submit()` ব্যবহার করে। আপনার বর্তমান branch-এ `existingReportIdsForPdfReplacement` ও `replaceAllReportsWithPdf` call থাকলে এই ফাইলটি Replace করতে হবে। এটি পুরোনো রিপোর্ট DELETE/REPLACE করে না; একই Employee + Period + Account-এর duplicate skip করে।
- Firebase Firestore Rules অপরিবর্তিত; deploy করতে হবে না।

## 2. Windows Firebase configuration (Spark Free-compatible)

**গুরুত্বপূর্ণ:** Android-এর `google-services.json` দিয়ে Windows configure হয় না। Windows Firebase Auth/Firestore FlutterFire-এ beta; production deployment নয়, development/test হিসেবে ধরুন।

1. https://console.firebase.google.com/ এ আপনার বর্তমান Firebase Project খুলুন।
2. Project settings -> General -> Your apps-এ **Web (</>) app** যোগ করুন / existing Web app-এর SDK setup and configuration দেখুন। নতুন *Firebase Project* তৈরি করবেন না।
3. Web app-এর `apiKey`, `appId`, `messagingSenderId`, `projectId`, `authDomain` সংগ্রহ করুন। এগুলো Android app's `mobilesdk_app_id` থেকে কপি করবেন না।
4. `firebase_config/windows/firebase_options.example.json` কপি করে `firebase_config/windows/firebase_options.local.json` বানান। কেবল ওই local ফাইলে বাস্তব মান বসান।
5. Windows Terminal/PowerShell-এ project root থেকে চালান:

```powershell
flutter create --platforms=android,windows --project-name performance_tracker_flutter --org com.performance .
flutter pub get
flutter analyze
flutter test
flutter run -d windows --dart-define-from-file=firebase_config/windows/firebase_options.local.json
```

Release Windows binary-এর জন্য একই dart-define JSON দিতে হবে:

```powershell
flutter build windows --release --dart-define-from-file=firebase_config/windows/firebase_options.local.json
```

**নোট:** Windows app config ব্যবহার করলেও Windows Firestore/Auth plugin beta। SDK বা plugin incompatibility থাকলে Windows beta limitation পরীক্ষা করতে হবে। Android package `com.performance.tracker` ও তার Firebase JSON পরিবর্তন করবেন না।

### Optional official FlutterFire CLI

`dart pub global activate flutterfire_cli` এবং `flutterfire configure --project=performance-tracker-66b42` চালিয়ে platform app registration যাচাই করতে পারেন। বর্তমান `main.dart` Windows-এর ক্ষেত্রে সরাসরি `--dart-define-from-file` config ব্যবহার করে; শুধু CLI-এর generated `firebase_options.dart` তৈরি করলে সেটি স্বয়ংক্রিয়ভাবে ব্যবহার হবে না।

## 3. আপনার `flutter analyze` errors

```text
The method 'existingReportIdsForPdfReplacement' isn't defined for the type 'ApiClient'
The method 'replaceAllReportsWithPdf' isn't defined for the type 'ApiClient'
```

এই নামের API method বর্তমান সংরক্ষিত full project-এ নেই। PDF report **replace-all/delete** করার implementation আন্দাজ করে যোগ করা হয়নি, কারণ user-submitted records immutable। পরিবর্তে ZIP-এর `submission_screen.dart` ব্যবহার করলে আগের safe `submit` workflow ফিরে আসবে।

যদি `android/` ও `windows/` ফোল্ডার আগে থেকেই থাকে, `flutter create` পুনরায় চালাতে হবে না।

GitHub-এ প্রথমে শুধু দুই Dart ফাইল Replace করুন, তারপর `flutter analyze`, `flutter test` ও `flutter build apk --debug` চালান। Windows JSON কেবল Windows local run-এর জন্য।

## 4. Limitations / verification

Flutter SDK এই runtime-এ নেই; Windows build, Dart analyzer, APK বা live Firebase login চালিয়ে নিশ্চিত করা হয়নি। `api.dart`-এর exact বর্তমান version ZIP-এর সঙ্গে আলাদা হলে সর্বশেষ `api.dart` ও `submission_screen.dart` ফাইল দিন; সেই অনুযায়ী merge করতে হবে।
