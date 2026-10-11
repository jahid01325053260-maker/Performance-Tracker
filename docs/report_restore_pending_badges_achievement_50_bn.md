# Performance Tracker — পুনরায় রিপোর্ট জমা, Admin Alert Dot ও Achievement Color

## ১. Admin Delete করলে User আবার PDF আপলোড

আগে Admin একটি 906 Account-এর রিপোর্ট Delete করলে `performance/{employeeId}_{YYYY-MM}_{accountKey}` ডকুমেন্টটি `status: deleted` অবস্থায় থাকত। নতুন PDF-এর একই Account দেখে Import সেটি Duplicate ভেবে এড়িয়ে যেত।

এখন একই Officer + Month + 906 Account-এর `deleted` ডকুমেন্ট পাওয়া গেলে Import সেটি `confirmed` অবস্থায় ফিরিয়ে আনে। এটি নতুন Duplicate ডকুমেন্ট তৈরি করে না। নতুন `ranking_proofs` ডকুমেন্ট ও Leaderboard +1 একই Firestore transaction-এ হয়। ইতিমধ্যে `confirmed` রেকর্ড আবার Import করলে স্কোর বাড়ে না। পুরোনো Account Details অক্ষত থাকে; নতুন PDF দিয়ে পূর্বের নাম বা Limit ওভাররাইট করা হয় না। Admin দরকার হলে আলাদা Edit করবেন।

**অত্যন্ত জরুরি:** `backend/firestore.rules` Firebase-এ Deploy না করলে User-এর পুনরায় Upload-এ `permission-denied` আসতে পারে। Firebase CLI ব্যবহার করে:

```bash
firebase use performance-tracker-66b42
firebase deploy --only firestore:rules
```

মূল প্রজেক্ট ও Firebase Project ID আগে যাচাই করুন এবং Production-এ Deploy-এর আগে Backup ও Staging পরীক্ষা করুন। সংবেদনশীল Account Data এবং Service Account Credentials GitHub-এ Commit করবেন না।

### পরীক্ষা

1. User-কে একটি মাসে একটি 906 Account জমা দিতে দিন।
2. Admin থেকে ওই Account Delete করুন; Dashboard/Ranking Count কমার কথা।
3. User একই Account-সহ PDF আবার Upload করুন। আগের রিপোর্ট/Count পুনরায় দৃশ্যমান হওয়ার কথা।
4. আবার একই PDF Upload করুন; Count যেন আর না বাড়ে।
5. অন্য User যেন অন্যের `deleted` Account Restore করতে না পারে এবং NIL রিপোর্ট যেন কখনো Card হিসেবে না গণনা হয়।

## ২. ছোট লাল Notification Dot

Admin Dashboard-এ **Pending Approvals** ও **Sales Manager Change Requests** নামে সরাসরি Shortcut রাখা হয়েছে। নতুন Pending Request এলে সংশ্লিষ্ট Shortcut-এ এবং Settings-এর সংশ্লিষ্ট লাইনে লাল Dot দেখা যাবে। কোনো একটি Request pending থাকলে Settings Gear-এও Dot থাকবে। Request Approve/Reject হয়ে Pending না থাকলে Dot চলে যাবে।

Firestore Realtime Snapshot ও বিদ্যমান Admin Permissions ব্যবহার করা হয়েছে; নতুন Push Notification/Cloud Functions যুক্ত হয়নি।

## ৩. Achievement ৫০% বা তার নিচে

Monthly/Yearly Target-এর Achievement এবং Export Report-এর **Achievement** ঘর ০% থেকে **৫০.০%** পর্যন্ত লাল; ৫০%-এর বেশি হলে আগের সবুজ। PDF, Excel ও Report Preview-তে নিম্ন Achievement-এর ঘর হালকা লাল এবং লেখা গাঢ় লাল দেখায়। Target শূন্য বা নির্ধারিত না হলে `No Target Assigned` লাল দেখায় না।

## Build যাচাই

Flutter SDK এই পরিবেশে নেই বলে APK/Windows EXE Build এবং Firebase Emulator Permissions Test এখানে চালানো যায়নি। পরিবর্তিত Archive পরীক্ষা ও Node Backend Tests করা হয়েছে। GitHub Actions-এ `flutter analyze`, `flutter test` ও APK/Windows build চালিয়ে নিশ্চিত করুন।
