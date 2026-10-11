# Performance Tracker — Individual View, Manager Permissions, JSON Upload ও Autofill

## এই আপডেটের মূল পরিবর্তন

- Settings → Backup / Reset → **Upload JSON File**: শুধু এই অ্যাপের নিজস্ব `PerformanceTracker_Spark_JSON_v1` backup-এর **performance, targets, leaderboard** collection থেকে *অনুপস্থিত* ডকুমেন্ট restore করবে। আগে ফাইল যাচাই ও record count preview হবে। Admin password এবং `RESTORE REPORTS` লিখে নিশ্চিত করতে হবে। বিদ্যমান ডকুমেন্ট, Employee profile, Login, Role, Firebase Auth account কখনো overwrite করা হয় না। পুরোনো অসামঞ্জস্যপূর্ণ schema থাকলে import বন্ধ হবে; মাইগ্রেশনের জন্য trusted PC ব্যবহার করুন। Restore চলার সময় connection বন্ধ হলে আংশিক restore হতে পারে; আবার চালালে বিদ্যমান ডকুমেন্ট skip করে।
- নতুন ID / Registration: সব দৃশ্যমান তথ্য পূরণ করতে হবে, recovery email ও official number সহ। Management user-এর ক্ষেত্রে Supervisor/Sales Manager ঘরে `N/A` লিখতে পারবেন। Firebase Auth sign-in alias এখনো `.invalid`; recovery email-কে sign-in email হিসেবে ব্যবহার করা হচ্ছে না।
- Login Screen-এ Android Autofill/Google Password Manager-কে সফল Login-এর পরে credential save করার অনুরোধ জানানো হবে। **Prompt দেখানো বা Password Google account-এ save করা Android ও নির্বাচিত Password Manager-এর নিয়ন্ত্রণে**; অ্যাপ নিজে Google account-এ password পাঠায় না। ফোনে Settings → Google → Password Manager / Autofill service চালু থাকতে হবে। আগের local opt-in encrypted saving অপরিবর্তিত।
- Android Launcher Name `Performance Tracker` হবে। Workflow-এর `tool/configure_firebase_android.py` স্টেপ চালু থাকতে হবে।
- Ranking label `Live Ranking`।
- Manager Team: ADMIN, AGM, DGM সব Sales Manager-এর দল দেখতে পারবেন; Sales Manager শুধু নিজের Team। Legacy name-based membership Officer List-এ দেখা যেতে পারে, কিন্তু গোপন report access-এর জন্য managerId নির্ধারণ করতে হবে।
- Individual View: শুধু Officer-এর তালিকা; Officer বাছলে তাঁর January, February ইত্যাদি মাসভিত্তিক রিপোর্ট; মাসে চাপলে বিস্তারিত। **ADMIN/AGM/DGM সব অফিসারের**, Sales Manager কেবল তাঁর সঙ্গে `managerId` দ্বারা যুক্ত অফিসারের রিপোর্ট দেখতে পারবেন। পাবলিক Officer List ও Ranking সকল অনুমোদিত ব্যবহারকারীর জন্য অপরিবর্তিত।
- Monthly PDF / Export ও Export Excel উভয় ক্ষেত্রেই Role অনুযায়ী একই permitted Officer scope; `Officer / Report Scope` থেকে নির্দিষ্ট Officer বেছে নিতে পারবেন। Report Type, Year/Month, All Months/Annual Target অনুযায়ী PDF, Excel, CSV হিসাব হবে।

## Deployment

1. বর্তমান Repository-তে আপডেট করা ফাইলগুলি একই path-এ Replace/Add করে commit করুন। নতুন GitHub Repository বা Firebase Project লাগবে না।
2. GitHub Actions-এ `flutter pub get`, `flutter analyze`, `flutter test` ও APK Build পরীক্ষা করুন। Android app name শুধুমাত্র নতুন APK ইনস্টল করার পর বদলাবে।
3. **গুরুত্বপূর্ণ:** Firestore Rules পরিবর্তিত হয়েছে। বিদ্যমান Rules-এর backup ও Firebase Emulator/Staging Project-এ approval, role, manager team, exports, JSON restore পরীক্ষা করুন। পুরোনো Android অ্যাপ একই database ব্যবহার করলে Compatibility না দেখে production rules deploy করবেন না।
4. Staging-এ নিশ্চিত হলে (প্রজেক্টের মূল folder থেকে):
   `firebase deploy --only firestore:rules --project performance-tracker-66b42`
5. Sales Manager-এর টিম রিপোর্ট শূন্য দেখা গেলে Admin Officer Profile-এ **Assign Sales Manager** দিয়ে সঠিক Manager ID যুক্ত করুন।

## গুরুত্বপূর্ণ সীমাবদ্ধতা

- Firebase Spark Free-এর read/write quota প্রযোজ্য। বড় JSON restore-এ অনেক server read/write হতে পারে। 25 MB এবং 10,000 document limit রয়েছে। JSON backup নিরাপদে রাখুন: এতে আবেদনকারীর ব্যক্তিগত তথ্য আছে।
- Restore সম্পূর্ণ Database Reset-এর বিপরীত নয়; শুধু reporting collections-এর missing records নিয়ে কাজ করে।
- Google Password Manager-এর UI বাধ্যতামূলকভাবে প্রদর্শন করানো যায় না; এটি ডিভাইস/Google settings ও Autofill support-এর উপর নির্ভর করে।
- এখানে Flutter SDK এবং Firestore Emulator অনুপস্থিত; build ও বাস্তব permissions যাচাই বাকি।
