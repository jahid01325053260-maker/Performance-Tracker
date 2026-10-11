# PerformanceTracker — Forgot Password, Remember Login, Month View, Role Editor

এই সংস্করণ Firebase **Spark (Free)**-এর মধ্যেই চলে। নতুন API server বা Firebase Cloud Functions প্রয়োজন নেই। Android package ID এবং পূর্বের Firebase database অপরিবর্তিত।

## ১. Password Reset

Login → **Forgot password?** → ১২ সংখ্যার ID অথবা **Firebase Authentication sign-in email** লিখুন। বাস্তব Firebase sign-in email থাকলে `FirebaseAuth.sendPasswordResetEmail()` চলবে। Auth account-এর অস্তিত্ব প্রকাশ না করে confirmation দেখানো হয়। Firebase Console → Authentication → Templates থেকে email template ঠিক করতে পারেন।

**খুব গুরুত্বপূর্ণ:** পুরোনো অ্যাপ ও নতুন Spark registration-এ Firebase Auth email অনেক সময় `pt-...@performance-tracker.invalid`; এমন ঠিকানায় ইমেইল পৌঁছাবে না। `employees/{id}.email`-এ যোগাযোগের real email থাকলেও সেটা স্বয়ংক্রিয়ভাবে Firebase Auth sign-in email হয় না। এ কারণে শুধু সেই real profile email লিখলে password reset কাজ করার নিশ্চয়তা নেই। Firebase Identity Platform-এর সুবিধা বা Cloud Functions ছাড়া অন্য কারও Auth password মোবাইল অ্যাপ থেকে reset করার চেষ্টা করবেন না।

`.invalid` অ্যাকাউন্টের জন্য **ব্যক্তিগতভাবে identity verified** Admin-কে স্থানীয় trusted operator utility চালাতে হবে:

```bat
cd <PerformanceTracker project folder>
cd backend
npm install
set "GOOGLE_APPLICATION_CREDENTIALS=C:\secure\service-account.json"
set "FIREBASE_PROJECT_ID=performance-tracker-66b42"
set "TARGET_EMPLOYEE_ID=123456789012"
node scripts\reset_employee_password.js
```

`TARGET_EMPLOYEE_ID`-এ প্রকৃত কর্মীর ID বসান; আগে dry run identity mapping যাচাই করুন। **শুধু যাচাইকৃত অধিকারপ্রাপ্ত Admin** নিজের নিরাপদ PC-তে Firebase Admin Service Account ব্যবহার করবেন। সার্ভিস অ্যাকাউন্ট JSON GitHub, APK, ফাইল শেয়ার বা ZIP-এ দেবেন না। বাস্তব পরিচয় যাচাইয়ের পর:

```bat
set "NEW_EMPLOYEE_PASSWORD=<unique 12+ char temporary password>"
node scripts\reset_employee_password.js --apply
set "NEW_EMPLOYEE_PASSWORD="
```

নতুন password ব্যক্তিগতভাবে দিন এবং Login → Settings → Change Password করতে বলুন। এটি অনলাইন Cloud Function deploy করে না, তবে Admin SDK local credentials দরকার। Admin recovery-কে unattended public self-service reset মনে করবেন না।

## ২. Device Remember Login

- **Remember ID** ডিফল্ট চালু; সফল Login-এর পরে protected storage-এ Employee ID সংরক্ষণ হয়।
- **Save password securely** ডিফল্ট বন্ধ। শুধু নিজের, PIN/স্ক্রিন লক দেওয়া ডিভাইসে সচেতনভাবে ON করুন। Android Keystore/secure storage দিয়ে password সংরক্ষণ হয়; Firestore, APK source বা SharedPreferences-এ নয়।
- লগআউট করলে সংরক্ষিত Login-এর অপশন অনুযায়ী ID/password থেকে যায় (কারণ ব্যবহারকারী সেটি সেভ করতে বলেছেন); ঝুঁকিপূর্ণ/shared ডিভাইসে Save Password OFF রাখুন। পরের Login-এ checkbox OFF করলে সেভ করা password মুছে যায়।
- Settings → Change Password সফল হলে পুরোনো সেভ করা password মুছে যায়। Android backup-এ encrypted secret নেওয়া বন্ধ রাখা হয়েছে।
- Password ভুলে গেলে saved password-কে recovery mechanism ভাববেন না।

## ৩. নতুন Month View

Admin/Manager Dashboard → Month View: Year, Month, Branch, Zone, Search; Unique Cards, Report Groups, Employees, NIL Summary; ১২ মাসের bar trend; প্রতিটি রিপোর্টে tap করে Details। Card Count একবারই গণনা হয় একই employee+period+account অনুযায়ী, NIL গণনা হয় না। `managerId` অনুযায়ী Firestore Rules-এ সীমাবদ্ধতার কারণে Managers শুধু অনুমোদিত data দেখতে পারবেন।

## ৪. Admin Role Editor

Employee Directory → কর্মীর 3-dot menu → **Change role**, অথবা Profile → **Change employee role**। USER, Sales Manager, AGM, DGM, ADMIN নির্বাচন করতে পারবেন। Confirmation পরে Firestore transaction-এ `employees/{id}.role`, `auth_users/{uid}.role` এবং `role_change_logs` অডিট ইভেন্ট update হয়। নতুন role-সহ অ্যাপ রিফ্রেশ/রিস্টার্ট করলে menu পরিবর্তন দেখা যাবে।

- শুধুমাত্র Approved কর্মীদের role পরিবর্তন হবে; Pending হলে **Pending Approvals** থেকে role বেছে Approve করুন।
- কোনো ADMIN নিজের role পরিবর্তন করতে পারবেন না, যাতে শেষ ADMIN দুর্ঘটনাক্রমে হারিয়ে না যায়। অন্য Admin-এর role পরিবর্তন করা যায়।
- UI-তে শুধু Admin দেখানো যথেষ্ট নয়: Firestore Rules আপডেট deploy এবং live rules যাচাই করতে হবে।

## ৫. GitHub / Firestore Setup

১. `Only_Modified_Files.zip` Extract করে আগের GitHub Repository-তে একই path অনুযায়ী **Replace/Add** করুন। নতুন Repository নয়।

২. GitHub → Actions → Android Debug APK → Run workflow; `flutter analyze` / `flutter test` / `flutter build apk` ফল দেখুন। নতুন `flutter_secure_storage: 11.2.0` dependency নিতে হবে। Android SDK min 23 প্রয়োজন।

৩. **আগে ব্যাকআপ এবং staging / Firebase Rules Emulator-এ পরীক্ষা করুন**। আগের Kotlin অ্যাপ একই Firestore ব্যবহার করলে নতুন Rules তার read/write প্রভাবিত করতে পারে।

৪. যাচাই শেষে live Rules deploy করুন:

```bat
firebase deploy --only firestore:rules --project performance-tracker-66b42
```

৫. APK পুনরায় ইনস্টল করে Login, Forgot Password, saved details, Month View, Admin Role Editor পরীক্ষা করুন। পুরোনো Firestore document-এ `authUid`, `auth_users` mapping না থাকলে role edit ব্যর্থ হবে; অনুমান করে UID বসাবেন না।

### Known limits

- এই পরিবেশে Flutter SDK বা Firebase Rules Emulator নেই; local Dart analyzer, APK compilation, live Firestore rules test চালানো যায়নি।
- `.invalid` alias account-এ reset email **পাঠানো যায় না**। Local Admin SDK recovery-ই fallback; সেটিতে ব্যক্তি যাচাই বাধ্যতামূলক।
- Firestore rules দিয়ে audit create অনুমোদন থাকলেও trusted server-side append-only audit guarantee দেওয়া যায় না। নিরাপদ enterprise audit-এর জন্য trusted backend দরকার।
- Android build প্রধান target; iOS/macOS/desktop FlutterFire/secure-storage native setup পৃথকভাবে যাচাই করতে হবে।
