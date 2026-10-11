# Navigation bar, Manager team, Targets, Export — Update notes

## Bottom Android navigation overlap
`lib/main.dart` এখন MaterialApp.builder-এ `SafeArea(bottom: true, top: false)` ব্যবহার করে। এটি শুধু app navigation area-কে নিচের system bar থেকে উপরে রাখে। User keyboard, gesture navigation এবং 3-button navigation—তিন ক্ষেত্রেই APK-তে পরীক্ষা করুন।

## Manager access
- Officer Directory এবং Ranking সমস্ত অনুমোদিত officer-এর জন্য উন্মুক্ত থাকবে।
- Applicant details, Month View, Target achievement এবং PDF/Excel report শুধুমাত্র `managerId == loggedInSalesManager.employeeId` রেকর্ডে সীমাবদ্ধ।
- পুরোনো `salesManager` নাম দিয়ে পাওয়া team membership ব্যক্তিগত রিপোর্ট পড়ার অনুমতি **দেবে না**। নাম বদল বা একাধিক অভিন্ন নামের কারণে সেটি নিরাপদ নয়।
- Firebase Rules-এ manager-এর report permission একই `managerId` অনুযায়ী যাচাই হয়। নতুন submission-এ fake `managerId` আটকানোর অতিরিক্ত condition রয়েছে।
- ADMIN → Officer List → Officer Profile → **Assign Sales Manager** থেকে manager নির্ধারণ করুন। Confirmation দিলে profile ও আগের performance rows-এর managerId আপডেট হবে। **আগে Firebase ডেটার backup নিন**। বড় batch-এর সময় ত্রুটি হলে একই action আবার চালাতে পারবেন।

## Repeating targets
- `employees/{id}.monthlyTarget` মাসে একবার করে ব্যবহৃত default; বারবার Set Target দরকার নেই।
- `employees/{id}.yearlyTarget` পুরো বছরের জন্য আলাদা default; 12×monthlyTarget-এর বদলে ঐ সংরক্ষিত annual target ব্যবহার হচ্ছে।
- 0 target মানে `No Target Assigned`; সেটিকে ব্যর্থ target ধরে 0% alert দেওয়া যাবে না।
- Sales Manager Target Screen-এ শুধু নিজের team-এর officer achievement দেখতে পারবেন।

## Export corrections
- PDF, Excel এবং CSV একই `buildReportTable()` মডেল থেকে ডেটা নেবে।
- Officer Summary, Sales Manager Performance ও Card Application Details report type রয়েছে।
- Officer selection কেবল অনুমোদিত report scope দেখায়; manager অন্য team-এর applicant data নির্বাচন বা export করতে পারবেন না।
- PDF-এ সাতটির বেশি কলাম থাকলে A4 landscape ব্যবহৃত হয়, যাতে কাটা না পড়ে।
- `906 cards`-এ Verify N-ও থাকবে, কারণ বর্তমান app policy অনুযায়ী শুধু product code 906 গণনা হয়।
- বছরের রিপোর্টে annual target, এক মাসের রিপোর্টে monthly target দেখায়; রিপোর্টে কত officer row এবং কত card আছে আলাদা লেখা হবে।

## Firebase Rules deployment caution
**পুরোনো Android App একই Database ব্যবহার করলে আগে Staging Firebase Project-এ Rules পরীক্ষা করুন।** এই update-এর `backend/firestore.rules`-এ valid submission-এর `managerId`/`salesManager` Employee Profile থেকে আসা মানের সঙ্গে মেলাতে হবে। পুরোনো app যদি ঐ মান না পাঠায়, নতুন Rules-এর পর তার submission ব্যর্থ হতে পারে। Rules পরীক্ষা ছাড়া production-এ deploy করবেন না।

```bash
firebase emulators:start --only firestore,auth
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

এখানে Flutter SDK এবং Firebase Emulator দিয়ে end-to-end compilation/security test চালানো হয়নি; test outcome GitHub Actions-এ যাচাই করতে হবে।
