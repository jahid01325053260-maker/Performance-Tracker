# PerformanceTracker Flutter — Pending Approval, Directory, Support, Backup/Reset এবং Admin ID

এই update-এ **নতুন Firebase Project বা Blaze/Cloud Functions লাগবে না**। Android `com.performance.tracker`-এর আগের `google-services.json` রাখা হয়েছে। আগের Firestore ডেটা সরাসরি মুছে দেওয়া হয় না। তবে সার্ভারে Firestore Rules আপডেট আলাদাভাবে করতে হবে।

## কী পরিবর্তন হয়েছে

1. **Pending Approvals:** Admin সব `employees` ডকুমেন্ট পড়ে `Pending`/`pending` পার্থক্য বিবেচনা করে। Approve/Reject-এ Future আর `setState` callback থেকে ফেরে না; একসঙ্গে দুইটি request আটকানো হয়, status ও role Firestore-এর `employees` এবং `auth_users`-এ একই batch-এ update হয়। পুরোনো record-এ `authUid` না থাকলে অনুমোদন নিরাপদে সম্ভব নয়; প্রকৃত Firebase Auth UID linking করতে হবে।
2. **Employee Directory:** পুরোনো Android অ্যাপের মতো `Approved`, `APPROVED`, `approved`, `''` (ফাঁকা) status-সহ রেকর্ড দেখা যায়; Admin পুরোনো *status field অনুপস্থিত* records-ও পর্যালোচনার জন্য দেখতে পারেন। সাধারণ ব্যবহারকারীদের জন্য `whereIn` query এবং matching Security Rules। `Pending/Rejected/Disabled` দেখায় না। Manager/AGM/DGM-ও `All` এবং নিজ নিজ filter-এ থাকবে। Status field **অনুপস্থিত** records সাধারণ ব্যবহারকারী দেখতে পাবেন না যতক্ষণ Admin নিয়মিতভাবে যাচাই/মাইগ্রেট করছেন।
3. **Help & Support:** পুরোনো Android reference-এর ফোন, ইমেইল, Created By, WhatsApp URL এবং `OPEN WHATSAPP / OK` option। `url_launcher` ব্যবহার করে ফোন/ইমেইল/WhatsApp action।
4. **Backup:** Admin Firestore থেকে `employees`, `auth_users`, `performance`, `targets`, `leaderboard` collection-এর JSON snapshot Save As করতে পারবেন। Firebase Authentication-এর password, provider record, `login_index` (Firestore read-restricted) বা রিমোট file store-এর binary data এতে থাকে না। এটিকে নিরাপদ জায়গায় রাখুন—অন্যের তথ্য রয়েছে। Restore স্বয়ংক্রিয় নয়।
5. **Reset:** আগে সফল Backup Save + type `RESET REPORTS` + বর্তমান Admin Password দিয়ে reauthenticate করতে হবে। কেবল `performance`, `targets`, `leaderboard` মুছে দেয়। **কখনো `employees`, `auth_users`, `login_index` বা Firebase Auth user account মুছে দেয় না**। এটি Full Database Reset নয়। বহু batch-এর মাঝে network error এলে কিছু ডকুমেন্ট মুছে যেতে পারে; Restore করার জন্য পৃথক যাচাইকৃত প্রক্রিয়া প্রয়োজন।
6. **Exit:** Home screen-এ Android Back চাপলে `CANCEL / LOGOUT / EXIT` confirmation। Settings থেকে Logout-এ `Exit / Logout` confirmation। Exit শুধু app বন্ধ করে; Logout Firebase session sign out করে।
7. **Create New User/Management ID:** Admin `USER`, `Sales Manager`, `AGM`, `DGM` role-সহ নতুন ID তৈরি করবেন। Secondary Firebase app-এর Auth-এ নতুন ID + temporary password তৈরি হয়; Firestore Rules অনুযায়ী নতুন record প্রথমে **USER + Pending**, এবং আসল Admin-এর Auth session দিয়ে role approve করা হয়। Admin নিজের Login হারাবেন না। কোনো প্রক্রিয়া আংশিক ব্যর্থ হলে অ্যাকাউন্ট Pending থাকতে পারে—Pending Approvals যাচাই করুন। Password ব্যক্তিগতভাবে শেয়ার করে User-কে Change Password ব্যবহার করতে বলুন। **Admin role কখনো self-registration দিয়ে দেওয়া যাবে না**। Firebase Authentication Email/Password enabled থাকতে হবে।

## GitHub-এ replace

1. `PerformanceTracker_Admin_Settings_Only_Modified_Files.zip` Extract করে সব ফাইল current Repository-তে একই relative path-এ replace/add করুন। বিশেষ করে `pubspec.yaml`, `backend/firestore.rules`, `lib/services/api.dart`, `lib/features/settings/*`।
2. GitHub → Actions → Android Debug APK build চালান। এতে `flutter pub get`, `flutter analyze`, `flutter test` স্বাভাবিকভাবেই চলছে।
3. **আগে Firebase test project / Rules emulator-এ যাচাই করুন**। বিদ্যমান পুরোনো Android অ্যাপ একই Firebase backend ব্যবহার করে থাকলে live Firestore Rules পরিবর্তনে পুরোনো workflow ক্ষতিগ্রস্ত হতে পারে।
4. যাচাইয়ের পরে Windows CMD-তে project root থেকে `firebase deploy --only firestore:rules --project performance-tracker-66b42`। Spark Free-তে Firestore Rules deploy করা যায়; Cloud Functions deploy করার প্রয়োজন নেই।
5. নতুন APK ইনস্টল করে Approved Admin দিয়ে Login → Settings → Pending Approvals, Create New User, Help & Support এবং Officer List পরীক্ষা করুন।

## নিরাপত্তা ও সীমাবদ্ধতা

- Firestore Rules প্রতিটি read/write-এর permission নিয়ন্ত্রণ করে; শুধু UI-এ `Admin` দেখানো নিরাপত্তা নয়। Admin `auth_users/{uid}` ও `employees/{id}`-এর role/status ঠিকমতো linked থাকতে হবে।
- প্রথম Admin Account বা পুরোনো orphan/legacy authentication record স্বয়ংক্রিয়ভাবে bootstrap বা migration হয় না।
- `google-services.json` Firebase Project configuration; Rules বা Auth identity mapping-এর বিকল্প নয়।
- Firebase Spark-এর ফ্রি quota-এর মধ্যে থাকলে Login, Firestore, Export চলবে। `url_launcher` package নতুন dependency, তাই network-dependent `flutter pub get` লাগবে।
- এখানে SDK দিয়ে Flutter APK ও Firestore Rules Emulator পরীক্ষা করা যায়নি। Deploy-এর আগে CI ও পরীক্ষার ফল দেখুন; failure log দিলে সংশোধন করা যাবে।
