# Performance Tracker — Sales Manager Picker ও 6-Month PDF/Excel

## কী পরিবর্তন হয়েছে

1. **Registration:** Approved Sales Manager-এর নাম/ID dropdown-এ দেখা যায়। নাম হাতে লিখতে হয় না। UI-তে Manager ID নির্বাচন বাধ্যতামূলক।
2. **My Profile:** Officer `Change Sales Manager` থেকে নতুন Manager নির্বাচন করে request পাঠাতে পারবেন। অ্যাডমিন `Settings → Sales Manager Change Requests` থেকে অনুমোদন দিলে Officer profile ও historical report-এর team assignment পরিবর্তিত হবে। এতে অন্য ম্যানেজার ভুল করে ব্যক্তিগত আবেদনকারীর তথ্য পান না।
3. **Admin Create New ID:** USER-এর পূর্বের প্রয়োজনীয় ফিল্ড বজায় আছে, সাথে Manager picker। Sales Manager-এর জন্য Employee ID, Full Name, Mobile, Recovery Email, Official Number, Branch, Zone, Temporary Password, Confirm Password। AGM/DGM-এর জন্য Employee ID, Full Name, Mobile, Recovery Email, Official Number, Branch, Temporary Password, Confirm Password। প্রতিটি দৃশ্যমান ফিল্ড required।
4. **Export:** PDF, Excel (XLSX); CSV বাদ। Officer Performance টেবিলে Branch, Branch Official, ঐচ্ছিক Sales Manager, ঐচ্ছিক Zone, Total, Target, SHORT, Achievement। Black gridlines, bold numeric column, সবুজ percentage। Report Header এবং period দেখানো হয়।
5. **Month Range:** `Select Month Range` দিয়ে January–June (বা অন্য inclusive range) নির্বাচন। Range target = repeating Monthly Target × মাসের সংখ্যা; Annual mode-এ আলাদা Yearly Target; একটি মাসে Monthly Target।
6. **সুরক্ষা:** Sales Manager কেবল নিজের `managerId`-যুক্ত Officer-এর private report দেখতে পাবেন; Ranking/Directory সবার জন্য আগের মতো।

## বাধ্যতামূলক Firebase Setup (Spark Free)

1. পুরোনো Firebase Database ও Rules backup নিন।
2. নতুন `backend/firestore.rules` আলাদা test Firebase Project বা Emulator-এ পরীক্ষা করুন। পুরোনো Android অ্যাপ একই database ব্যবহার করলে আগে compatibility যাচাই করুন।
3. Rules deploy করুন:

   ```bash
   firebase deploy --only firestore:rules --project performance-tracker-66b42
   ```

4. পুরোনো Sales Manager accounts `sales_manager_directory`-তে আগে নেই। Administrator হিসেবে Login → Settings → Create New User / Management ID → **Sync Approved Sales Managers** একবার চালান। এতে **শুধু Manager নাম ও 12-digit ID** pre-login dropdown-এ প্রকাশিত হয়; ফোন, ইমেইল বা credentials প্রকাশিত হয় না।
5. নতুন approved Sales Manager তৈরি বা role edit করলে directory স্বয়ংক্রিয় update হয়। কেউ ম্যানেজারের নাম পরিবর্তন করলে Admin আবার sync করুন।
6. GitHub Actions থেকে `flutter analyze`, `flutter test` এবং নতুন APK build চালিয়ে Android-এ Login, Registration, Role, PDF/XLSX ও Report scope পরীক্ষা করুন।

## গুরুত্বপূর্ণ সীমাবদ্ধতা

- Self profile-এর Manager update **সরাসরি live team বদলায় না**; ADMIN approval লাগে। এটি report permissions ভুল ব্যক্তির কাছে চলে যাওয়ার ঝুঁকি কমায়।
- নতুন Firebase catalog অপরিহার্য। Rules deploy করার আগে নতুন Registration-এ Manager list কাজ করবে না।
- Flutter SDK ও Firebase Emulator ছাড়া এই environment-এ end-to-end APK/Firebase permission build নিশ্চিত করা যায়নি।
- PDF/Excel-এ ছবির table style অনুসরণ করা হয়েছে, কিন্তু ফন্ট/বর্ডারের pixel-perfect identity ডিভাইসের renderer অনুযায়ী ভিন্ন হতে পারে।
