# PerformanceTracker — KPI PDF full replacement and smaller APK

## PDF Confirm কী করবে

1. User → New Submission → Import Multi-Month KPI PDF → Review।
2. PDF parser কেবল `####-906-######` অ্যাকাউন্ট রাখবে এবং `Period`-এর মাস ও বছর অনুযায়ী ভাগ করবে। Verify Y/N উভয়ই অন্তর্ভুক্ত (আপনার নির্দেশ অনুযায়ী), কিন্তু একই মাসে duplicate একবার গণনা হবে।
3. `REPLACE & UPLOAD` চাপার আগে সার্ভার থেকে **সেই User-এর সব পুরোনো performance রেকর্ড** (manual, PDF, NIL, সব মাস/বছর) গণনা করে দেখাবে। অন্য User-এর কোনো ডেটা পরিবর্তন হবে না।
4. ব্যবহারকারীকে স্পষ্টভাবে `REPLACE` লিখে নিশ্চিত করতে হবে।
5. একই atomic Firestore batch-এ `report_backups/{employeeId}/versions/{importId}`-এ পুরোনো রেকর্ড সংরক্ষণ, পুরোনো performance ডকুমেন্ট মুছে ফেলা / একই ID overwrite করা, নতুন PDF ডকুমেন্ট তৈরি, `pdf_import_states`-এ audit এবং `leaderboard` count update হবে। সবগুলো সফল না হলে কোনো পরিবর্তন হবে না।
6. Firebase server acknowledgement এর পরে অ্যাপে সফল বার্তা দেখাবে। Offline অবস্থায় Replace শুরু হবে না।
7. সাবধানতা: পুরোনো `ranking_proofs` documents delete করা হচ্ছে না—তাতে পুরোনো হিসাবের immutable evidence অক্ষত থাকবে, কিন্তু তার কিছু pointers deleted records নির্দেশ করতে পারে।

### Safety / limits

- নতুন PDF-তে সর্বোচ্চ ১০০টি distinct 906 account; অনেক বড় পুরোনো রিপোর্ট (> ৩৫০ ডকুমেন্ট বা বড় backup) থাকলে transaction শুরু না করে Admin-কে জানায়। কোনো পুরোনো ডেটা মুছে না।
- Concurrent submissions চলাকালে অন্য ডিভাইস থেকে পরিবর্তন হলে অমিল হতে পারে। নতুন request পাঠানোর আগে app পুরোনো ID মিলিয়ে দেখে। একাধিক ডিভাইস থেকে একই সময়ে Full Replace চালানো এড়িয়ে চলুন।
- Backups private; Owner/Admin-ই পড়তে পারবেন। Backup অটোমেটিক Restore UI এখনো নেই।
- Firebase Spark-এর সরাসরি client writes ও Rules দিয়ে সব summary count-এর সার্ভার-স্তরের independent aggregation প্রমাণ করা যায় না। উচ্চ-নিরাপত্তার environment-এ trusted server দরকার।
- এটি **সব মাস/বছরের পুরোনো রিপোর্ট Replace** করে, শুধু PDF-এ থাকা মাস নয়।

### Deploy

1. Code update এর পরে প্রথমে Firestore Rules Emulator / staging project-এ policy যাচাই করুন। একই Firebase database পুরোনো Kotlin app-ও ব্যবহার করলে বিশেষভাবে compatibility টেস্ট করুন।
2. `firebase deploy --only firestore:rules --project performance-tracker-66b42` (শুধু অনুমোদিত হলে)।
3. এরপর APK আপডেট করুন। নতুন Rules ছাড়াই নতুন PDF Replace অনুমতি পাবে না।
4. আগের ডেটার backup রাখুন; একবার ছোট test user দিয়ে শুরু করুন।

## ১৮৩ MB APK ছোট করার নিয়ম

আপনার আগের GitHub workflow `flutter build apk --debug` তৈরি করছিল। Debug APK-তে debugging runtime থাকায় file size বড় হয়; এটি production download size নয়।

নতুন GitHub Actions workflow: **Android Optimized APK (Small)**।

- Android Debug APK workflow অপরিবর্তিত আছে (testing-এর জন্য)।
- Optimized workflow `flutter build apk --release --split-per-abi --tree-shake-icons` চালায়।
- Artifacts-এ তিনটি আলাদা release APK: `app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk`, `app-x86_64-release.apk`। ARM64 ফোনে দ্বিতীয়টি ইনস্টল করুন।
- অ্যাপের বর্তমান ডিবাগ সংস্করণ থেকে Release APK-এ আপডেট করার সময় signing key ভিন্ন হলে Android installation conflict হতে পারে। User data backup করে উপযুক্ত signing setup করুন; প্রয়োজন হলে পুরোনো অ্যাপ uninstall করতে হয়।
- GitHub Actions-এ release APK-এর signing যদি default debug keystore ব্যবহার করে, সেটি **public distribution উপযোগী নয়**। নিজের keystore / GitHub Secrets দিয়ে সঠিক release signing করতে হবে। Production Firebase `google-services.json` private credentials নয়, তবে APK fingerprint সেটিংস ঠিক রাখতে হবে।
- `pdfrx`/PDF engine এবং print libraries native binaries যোগ করে। `flutter build apk --release --analyze-size` চালিয়ে কোন asset/library বেশি জায়গা নিচ্ছে যাচাই করুন। কোনো dependency বাদ দেওয়ার আগে PDF Import, Preview, Excel Export কাজ করছে কি না টেস্ট করুন।

**নোট:** এখানে Flutter SDK/ Firebase emulator দিয়ে বাস্তব build বা rules deploy পরীক্ষা করা হয়নি। সঠিক APK size পরের GitHub Actions run-এর artifact দিয়ে নিশ্চিত করতে হবে।
