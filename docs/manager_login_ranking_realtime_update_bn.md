# PerformanceTracker — Manager Team, Login, Target, Ranking এবং Realtime Update

**Reference:** পুরোনো `PerformanceTracker(1)(1).zip`-এর `AdminDashboardActivity.showManagerTeamDialog()` এবং বর্তমানে ব্যবহৃত Flutter/Firebase Spark প্রকল্প।

## নতুন পরিবর্তন

1. **Manager Team**: `Sales Managers & Teams`, manager search, assigned officers, cards, branches; manager নির্বাচন করলে `VIEW OFFICERS` অথবা `FILTER DASHBOARD`। `managerId` থাকলে সেটি authoritative; পুরোনো `salesManager` নাম দিয়ে fallback grouping। Managers with zero reports remain visible.
2. **Login**: অনুমোদিত `employees/{ID}`, `auth_users/{UID}` এবং `login_index/{sha256(ID)}`-এর role/status/auth UID একই থাকতে হবে। পুরোনো Android app-এর legacy plaintext-password-to-Firebase-Auth migration নতুন client-এ নির্ভরযোগ্যভাবে করা যায় না; নিরাপদ local Admin SDK script যুক্ত।
3. **Targets**: একবার `employees/{employeeId}.monthlyTarget` এবং `.yearlyTarget` সেট করলে মাস ও বছর নির্বিশেষে default থাকবে। পূর্বের `targets/` historical override রেকর্ড মুছবে না। UI/exports monthly default পড়বে।
4. **Ranking**: প্রতি verified `906` new card-এ `performance/{recordId}`, ব্যক্তিগত `ranking_proofs/{randomId}` এবং public `leaderboard/{employeeId}` একই Firestore transaction-এ লেখা হয়। Firestore Rules দিয়ে score increase-এর সঙ্গে প্রকৃত নতুন card create মিলিয়ে দেখা হয়। Ranking real-time listener দিয়ে auto-refresh হয়, Admin Publish button নেই। সব approved USER/officers দেখায়, 0-card officer-ও।
5. **PDF Submit**: `CONFIRM & UPLOAD`-এর পর period অনুযায়ী Firebase-এ sequential idempotent transaction, প্রতি নতুন card server-acknowledged। Partial failure হলে পূর্বের সফল card দ্বিতীয়বার count হবে না; পুনরায় Import করা যায়।
6. **Read-only submitted reports**: USER নিজের রিপোর্ট দেখতে পারবেন, কিন্তু Edit/Delete পারবেন না। Admin Edit/Delete করতে পারবেন। Firestore Rules-এ USER update/delete নিষিদ্ধ, তবে নতুন আসল card submit করার সময় পুরোনো NIL marker সরানোর বিশেষ exception রয়েছে।
7. **Realtime**: Leaderboard stream-এর পরিবর্তনে Ranking, Dashboard, Month View, Reports, Targets ও Exports refresh হয়। Directory employee changes-এ refresh হয়। সব update Firebase Firestore-এর live connection-এর ওপর নির্ভরশীল। অফলাইনে server-side instant delivery সম্ভব নয়।
8. **Total Cards**: User Dashboard-এ সব বছরের verified 906 cards-এর Total Card দেখা যাবে। NIL, deleted ও একই reporting period-এর duplicate card বাদ।
9. **Specific Officer Export**: Monthly PDF / Export Excel/CSV-তে `Officer / Report Scope` থেকে নির্দিষ্ট officer বা সব permitted officer নির্বাচন করা যাবে।

## জরুরি Deploy ক্রম

**জরুরি:** পুরোনো Firebase-এর ডেটার নিরাপদ backup করুন। বিশেষ করে পুরোনো `employees` document-এ `password` field আছে কি না পরীক্ষা করুন। থাকলে সেটি Firestore directory rules দ্বারা পড়া যেতে পারে—মাইগ্রেশনের আগে permissive rules দেবেন না।

1. **Staging/test Firebase project**-এ `backend/firestore.rules` অনুকরণ করে পরীক্ষা করুন। `firebase deploy --only firestore:rules --project YOUR_PROJECT_ID` চালানোর আগে legacy Android app-এর permission compatibility যাচাই করতে হবে।
2. Trusted Windows/Linux PC-তে Node.js 22 ও Admin SDK-এর dependency প্রস্তুত করুন। `GOOGLE_APPLICATION_CREDENTIALS` environment variable-এ **লোকাল প্রাইভেট Service Account JSON-এর path** দিন (GitHub-এ commit/upload করবেন না)। `cd backend && npm install`।
3. প্রথমে dry-run: `node scripts/repair_legacy_auth_and_ranking.cjs`। এটি ডেটা পরিবর্তন করে না; UID mismatch, missing credentials, ranking numbers শনাক্ত করবে। Admin privilege / proper IAM role প্রয়োজন।
4. Dry-run রিপোর্টে প্রতিটি পরিবর্তন ও snapshot backup যাচাইয়ের পরেই `APPLY=1 BACKUP_CONFIRMED=1 node scripts/repair_legacy_auth_and_ranking.cjs` চালানো যাবে (Linux/macOS)। Windows PowerShell-এ `$env:APPLY='1'; $env:BACKUP_CONFIRMED='1'; node scripts/repair_legacy_auth_and_ranking.cjs`। পুরোনো UID conflict হলে script সেটি overwrite না করে manual review চায়।
5. পুরোনো Report-এর `reportingPeriod` বা `managerId` অনুপস্থিত থাকলে সঠিক period/team mapping আগে audit করুন; এগুলো অনুমান করে স্বয়ংক্রিয় মাইগ্রেশন করা হচ্ছে না।
6. তারপর Rules deploy করুন, GitHub-এ পরিবর্তিত Flutter files দিয়ে APK build করুন, এবং staging-এ পরীক্ষা সফল হলে production-এ যান।

## সীমাবদ্ধতা ও সতর্কতা

- **পুরোনো Login 100% স্বয়ংক্রিয়ভাবে পুনরুদ্ধার সম্ভব নয়।** Firebase Auth User না থাকলে এবং পুরোনো Password না পাওয়া গেলে Admin-verified recovery প্রয়োজন। অ্যাপ থেকে পুরোনো plaintext passwords পড়ার ব্যবস্থা যোগ করা হয়নি।
- **পুরোনো Ranking** সঠিক করতে একবার dry-run/backup/মাইগ্রেশন করতে হবে। নতুন submission-গুলো মাইগ্রেশনের পরে স্বয়ংক্রিয়ভাবে update হবে। ওই সময়ে অন্য ডিভাইসে submission চললে historical migration overwrite করতে পারে; maintenance window ব্যবহার করুন।
- **ম্যানেজার সম্পর্ক:** পুরোনো data `salesManager`-এর display name দিয়ে মিলত; নতুন secure manager scoping-এর জন্য `managerId` প্রয়োজন। এই ফিল্ড সঠিকভাবে map না হলে কোনো manager-এর কিছু পূর্বের রিপোর্ট দৃশ্যমান নাও হতে পারে।
- **Spark Free:** Cloud Functions লাগে না; তবে Firestore-এর read/write quota ও device connectivity সীমাবদ্ধতা প্রযোজ্য। বহু PDF card-এর জন্য প্রতি card-এ transaction লাগে, এবং মাঝপথে error হলে আংশিক upload হতে পারে; সেই রেকর্ডগুলো Firebase-এ সংরক্ষিত থাকে।
- **Firebase Rules tests and Flutter builds have not been run in this workspace.** `flutter pub get && flutter analyze && flutter test && flutter build apk --debug` চালিয়ে compile/permission/migration integration যাচাই করুন।
- **Old native app compatibility:** নতুন Rules-এ USER report edit নিষিদ্ধ; তাই পুরোনো Android app-এর কিছু edit action আর কাজ করবে না। Rollout-এর আগে সেটি যাচাই করুন।
