# Not Submitted → Alert: সংশোধন ও যাচাই

## এই সংস্করণে কী ঠিক হয়েছে

1. **প্রতিবার SEND ALERTS চাপলে নতুন Inbox message** তৈরি হয়। আগের সংস্করণ একই `missing_YYYY-MM` ID ব্যবহার করত, ফলে দ্বিতীয়বার পাঠালে কিছুই তৈরি হতো না।
2. **প্রথম Inbox snapshot আর বাদ দেওয়া হবে না**। User অ্যাপ বন্ধ রেখে পরে খুললেও সাম্প্রতিক (৩০ দিনের মধ্যে) অবিতরিত বার্তাগুলো Android Notification হিসেবে দেখানোর চেষ্টা হবে। একবারে সর্বোচ্চ ৩টি পুরোনো ব্যানার দেখায়; বাকিগুলো Inbox-এ থাকে।
3. Android 13 বা পরের সংস্করণে **notification permission-এর সিদ্ধান্তের জন্য অপেক্ষা** করে। Android-এর Notification Channel এখন High Importance (ডিভাইস সেটিংসের ওপর ব্যানার নির্ভর করে)।
4. আগে দেখানো Notification ID ডিভাইসে নিরাপদভাবে (encrypted local storage) রাখা হয়, যেন প্রতিবার অ্যাপ খুললে একই বার্তা অকারণে বারবার না আসে। এই storage-এ বার্তার body রাখা হয় না।
5. Admin-এর Not Submitted স্ক্রিন প্রথমে **সর্বশেষ যে মাসের ১০ তারিখের deadline পার হয়েছে** সেটি দেখাবে। ১২ অক্টোবর ২০২৬ হলে প্রথমে সেপ্টেম্বর ২০২৬ দেখাবে।

## টেস্ট করার ধাপ

1. নতুন **Android APK** Build করে **Admin ও User**-এর ফোনে আপডেট করুন। পুরোনো APK-এর native notification channel কাজ না-ও করতে পারে।
2. User-এর ফোনে **Settings → Apps → Performance Tracker → Notifications → Allow** দিন। App-এর Notifications স্ক্রিনেও permission বোতাম আছে।
3. Admin → Not Submitted → আগের রিপোর্টিং মাস (যার পরের মাসের ১০ তারিখ পার হয়েছে) নির্বাচন করুন → উপরে **Alert** → **SEND ALERTS**।
4. Admin স্ক্রিনে `N reminder(s) delivered to employee inboxes` দেখা গেলে Firestore-এ Nটি বার্তা commit হয়েছে। শূন্য দেখালে ঐ সময়সীমায় কোনো eligible missing officer পাওয়া যায়নি। Permission error হলে Firestore Rules যাচাই করুন।
5. User অ্যাপ **চালু রাখলে** নতুন Notification ফোনে দেখা উচিত। User অ্যাপ বন্ধ রেখে পরে **খুললে** গত ৩০ দিনের অবিতরিত Reminder-ও Notification হিসেবে দেখানোর চেষ্টা হবে। সব বার্তাই অ্যাপের **Notifications** স্ক্রিনে দেখা যাবে।
6. একই মাসে আবার Admin Alert পাঠালে নতুন Inbox message তৈরি হবে (প্রতিটি পাঠানো একটি সচেতন Admin confirmation-এর মাধ্যমে হয়)। অকারণে বারবার পাঠাবেন না।

## Inbox-এ বার্তা না এলে

- `User Notifications` স্ক্রিনে `permission-denied` বা `Unable to read alerts` থাকলে অনুমান করে Firestore Rules পাল্টাবেন না। প্রকল্পের বর্তমান `backend/firestore.rules`-এর `user_notifications/{employeeId}/messages/{messageId}` অংশ আপনার প্রকৃত Firebase Project-এ Deploy হয়েছে কি না যাচাই করুন।
- Admin ও User-কে একই অনলাইন প্রকল্পে লগইন করান। User-এর `auth_users/{uid}.employeeId` এবং `employees/{employeeId}.authUid` সঠিকভাবে linked হতে হবে। Missing UID-এর ক্ষেত্রে আগে *trusted PC UID repair* করুন।
- User-এর Role `USER` ও Status `Approved` হতে হবে, এবং নির্বাচিত রিপোর্টিং মাসে কোনো গ্রহণযোগ্য submitted record থাকা চলবে না।
- ১০ তারিখের আগে Alert পাঠানোর চেষ্টা করলে নিয়ম অনুযায়ী বাতিল হবে।
- Admin-এর বার্তা `user_notifications/{employeeId}/messages`-এ লেখা হয়, ফোন নম্বরে SMS পাঠানো হয় না।

## গুরুত্বপূর্ণ সীমাবদ্ধতা

**অ্যাপ সম্পূর্ণ বন্ধ থাকা অবস্থায় সঙ্গে সঙ্গে ফোনে Remote Push পাঠানো এখনো সমর্থিত নয়।** এটি শুধু Firestore Inbox ও Android app-running/next-launch Local Notification। Closed-app instant Push-এর জন্য একটি আলাদা trusted Firebase Cloud Messaging sender/Server লাগবে, যেটির private credential কখনো Mobile APK-তে রাখা যাবে না।

## কোন ফাইলগুলো পরিবর্তিত

- `lib/services/api.dart` — প্রতি send-এ নতুন message, successful batch count।
- `lib/features/dashboard/home_screen.dart` — Inbox initial snapshot, missed alerts, due period।
- `lib/services/notification_service.dart` — delivery status ও secure seen IDs।
- `lib/features/notifications/notifications_screen.dart` — Inbox delivery নির্দেশনা।
- `tool/configure_firebase_android.py` — Android permission response এবং high-importance channel।

Flutter SDK অনুপস্থিত থাকলে `flutter analyze`, `flutter test` ও Android build GitHub Actions-এ যাচাই করুন।
