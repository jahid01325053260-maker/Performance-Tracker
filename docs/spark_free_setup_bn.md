# PerformanceTracker — Firebase Spark (Free) Setup

এটি **Android-এ পরীক্ষার জন্য তৈরি সোর্স সংস্করণ**। সম্পূর্ণ APK compile, live login এবং Firestore Security Rules emulator পরীক্ষা এখানে করা যায়নি। Production-এ ব্যবহারের আগে যাচাই করুন।

## কী ফ্রি, কী নয়

- Firebase Authentication **Email/Password**, Cloud Firestore এবং স্থানীয় PDF/XLSX/CSV export Spark-এর সীমার মধ্যে ব্যবহার করা যায়। **Cloud Functions, Cloud Run, Firebase Cloud Storage বা paid billing দরকার নেই।**
- Firestore-এর ফ্রি quota আছে (দৈনিক reads/writes ও storage সীমা)। সীমা অতিক্রম করলে Spark-এ অনুরোধ ব্যর্থ হতে পারে।
- Login-এর জন্য আগের Android Project-এর `firebase_config/android/google-services.json` আছে; নতুন Project নয়। `com.performance.tracker` Android package অবশ্যই একই রাখতে হবে।
- অন্যান্য প্ল্যাটফর্মে `google-services.json` কাজ করে না; আলাদা FlutterFire config দরকার। Linux-এর জন্য Firestore plugin support পুনরায় যাচাই করুন।

## নতুন করে GitHub Repository তৈরি করবেন না

1. `PerformanceTracker_Spark_Only_Modified_Files.zip` Extract করে আপনার **বর্তমান GitHub Repository-র root-এ** একই path-এ ফাইলগুলো overwrite করুন। নতুন file-গুলো add করুন। `firebase.json` অবশ্যই overwrite করবেন: সেখানে Cloud Functions source নেই।
2. পুরোনো `backend/`-এর Node Functions কোড Repository-তে থাকতে পারে, কিন্তু Spark সংস্করণে **ব্যবহার বা deploy হয় না**। Source-এ রাখা হলে `firebase deploy --only functions` চালাবেন না।
3. নতুন APK build করুন: GitHub → Actions → Android Debug APK → Run workflow। Workflow `tool/configure_firebase_android.py` দিয়ে JSON কপি/Gradle setup করে।
4. Login বা Registration কাজ করানোর জন্য **Firestore Rules deploy করা অপরিহার্য**। কিন্তু production rules একবার deploy করলে পুরোনো Android অ্যাপের login/migration/registration ভেঙে যেতে পারে। পরের ধাপ আগে পড়ুন।

## Firebase Console

1. Firebase Console-এ পুরোনো `performance-tracker-66b42` Project খুলুন। Spark Free-তেই থাকুন।
2. Authentication → Sign-in method → Email/Password **Enable** করুন।
3. Firestore Database → `(default)` database আছে কিনা নিশ্চিত করুন। **Test mode security rules ব্যবহার করবেন না।**
4. পুরোনো database-এর **backup/export** এর ব্যবস্থা আগে করুন; Spark-এ managed backup/PITR free নয়। প্রয়োজন হলে Emulator/test Project-এ non-sensitive sample data দিয়ে পরীক্ষা করুন।

## Firestore Rules: নিরাপদে deploy

**প্রথমে test project / Firebase Emulator দিয়ে যাচাই করুন।** পুরোনো Kotlin Android ক্লায়েন্টের rules এক নয়, তাই একই production database-এ rules বদলালে পুরোনো app কাজ না-ও করতে পারে। পুরোনো app ব্যবহার বন্ধ বা migrate করার পরিকল্পনা নিশ্চিত করুন।

Windows CMD:

```bat
npm install -g firebase-tools
firebase login
cd PerformanceTracker_Flutter
firebase use performance-tracker-66b42
firebase deploy --only firestore:rules --project performance-tracker-66b42
```

এই deploy **Cloud Functions deploy নয়**—এতে Blaze লাগবে না। `backend/firestore.rules` এবং `firebase.json`-এ direct Firestore setup আছে। Firestore Rules deployment না করলে নতুন UI দেখালেও permission-denied আসবে।

## Login এবং Admin Approval

- পুরোনো অ্যাপে login index ছিল `login_index/{sha256(Employee ID)}`; সেখানে Firebase Authentication-এর আসল login email পাওয়া যায়। Spark app single-document `get` দিয়ে পুরোনো index পড়ে। Security limitation: pre-login lookup-এর মাধ্যমে পরিচিত Employee ID-এর auth email বের করা যায়; এই পদ্ধতির ঝুঁকি review করুন।
- নতুন Registration deterministic private email alias `pt-<sha256-id-first-40>@performance-tracker.invalid` দিয়ে Firebase Auth অ্যাকাউন্ট তৈরি করে, `employees/{ID}`, `auth_users/{UID}`-তে **USER + Pending** লেখে। **Password Firestore-এ রাখা হয় না**। 
- পরে Admin → Settings → Pending Approvals-এ USER / Sales Manager / AGM / DGM নির্বাচন করে Approve করবেন। Approval একই batch-এ employee ও auth_users role/status আপডেট করে। 
- নতুন Admin account অ্যাপ থেকে নিজে বানানো সম্ভব নয়; **আগে থেকে নিরাপদে প্রতিষ্ঠিত Approved ADMIN** থাকতে হবে। প্রথম Admin প্রস্তুত করতে Firebase Console/Admin SDK-এর মাধ্যমে বিশ্বস্ত অ্যাডমিন যাচাই ও UID/role mapping সেট করতে হবে। কোনো user registration থেকে ADMIN পাওয়া যাবে না।
- পুরোনো যে account এখনো **Firestore plaintext password** ব্যবহার করে কিন্তু Firebase Authentication-এ migrate হয়নি, সেটি এই সংস্করণে সরাসরি Login করবে না। কেবল verified Admin-controlled migration করুন; কখনো client দিয়ে Firestore password compare করবেন না।
- `.invalid` alias ইমেইলে Password Reset যাবে না; প্রশাসনিক যাচাই বা ভবিষ্যতে নিরাপদ recovery ব্যবস্থা প্রয়োজন।

## Spark সংস্করণের সীমাবদ্ধতা

- PDF KPI text extraction পুরোনো Cloud Function নির্ভর ছিল। বর্তমানে **Upload PDF বোতামে স্পষ্ট Unavailable** বার্তা আসবে; manual submission চালু আছে। PDF/XLSX/CSV **export** পুরোনো মতো client-side রাখা হয়েছে।
- Ranking অন্যের sensitive Applicant data দিয়ে সাধারণ ইউজারের ডিভাইসে হিসাব করা হয় না। Admin → Ranking → **Publish Verified Leaderboard** চাপলে aggregate গণনা করে `leaderboard/`-এ লেখে; তাই প্রকাশের মাঝামাঝি সময়ে ranking পুরোনো হতে পারে।
- USER কেবল নিজের applicant records পড়তে পারে; Sales Manager `managerId`-ভিত্তিক assigned team's records পড়তে পারে; Admin সব। **পুরোনো records-এ managerId না থাকলে Manager view-তে দেখা যাবে না**। AGM/DGM data scope এই build-এ সীমিত, অনুমতি বাড়াতে সংগঠনের access model design প্রয়োজন।
- **নতুন NIL record ও real submission-এর cross-document race condition client-side থেকে পুরোপুরি ঠেকানো যায় না**; ম্যানুয়াল review/cleanup policy প্রয়োজন।
- Profile photo compressed Base64 Firestore document-এ সংরক্ষিত, paid Cloud Storage প্রয়োজন হয় না; প্রতিটি Firestore document এর size limit মেনে চলতে হবে।
- অন্যের নামে Firebase Auth password set করা **Admin-এর ক্লায়েন্টে নিরাপদ নয়**। Management account বানাতে ব্যক্তিকে Register করতে বলুন; Admin পরে role নির্ধারণ করুন।
- নতুন অ্যাপের feature coverage মূল Master Prompt-এর পুরো production specification নয়। সব platform build/test, multi-month PDF OCR, backup/reset ও offline conflict resolution অসম্পূর্ণ।

## দ্রুত ট্রাবলশুটিং

- `permission-denied`: matching Firestore Rules deploy হয়েছে কি না, uid-এর `auth_users`, `employees` status/role মিলছে কি না দেখুন।
- `invalid-credential`: Password, legacy login_index alias, Firebase Authentication User যাচাই করুন।
- `Account not linked`: `auth_users/{uid}.employeeId`, `employees/{id}.authUid`, role/status consistency যাচাই করুন।
- `Account Pending`: ADMIN-কে Approve করতে হবে।
- Firebase connection কাজ করছে কিন্তু Login নয়: Email/Password enable, existing Firebase Auth UID/link যাচাই করুন।
- Flutter compile সমস্যা হলে **GitHub Actions-এর সম্পূর্ণ log** দিন। এখানে Flutter SDK নেই, তাই APK build success দাবি করা হচ্ছে না।

সরাসরি এই links ব্যবহার করতে পারবেন:
- Firebase Console: https://console.firebase.google.com/project/performance-tracker-66b42/overview
- Firestore free quota: https://firebase.google.com/docs/firestore/pricing
- Spark pricing plans: https://firebase.google.com/docs/projects/billing/firebase-pricing-plans
