# PDF Import ও XLSX Export Dependency Build Fix (10 October 2026)

## ঘটনার সারাংশ

GitHub Actions-এ `flutter analyze` পাস হলেও `flutter test`-এ `pdfrx_engine 0.4.4`-এর `PdfFileCache?` nullable-access compilation error হয়। `kpi_pdf_parser_test.dart` ও `widget_test.dart` দুটিই এই dependency import করার ফলে ব্যর্থ হতে পারে। আগের `pdfrx: 2.4.5` ওই পুরোনো engine ব্যবহার করত।

## পরিবর্তন

- `pdfrx: 2.4.8` — `pdfrx_engine ^0.4.7` ব্যবহার করে, যেখানে nullable cache bug fix রয়েছে।
- `image: 4.8.0` — engine-এর নতুন dependency মেলে।
- `excel: ^4.0.6` → `excel_community: 2.5.2` — XLSX writer `archive 4.x` support করে, ফলে পুরোনো `archive 3.x` conflict থাকে না।
- `export_screen.dart`-এ import বদলে `excel.save()` ব্যবহার করা হয়েছে; Account Number-এর leading zeros রাখতে TextCellValue এবং count numeric রাখতে IntCellValue বজায় আছে।

## GitHub-এ পরীক্ষা

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

এগুলো একই ধারাবাহিকতায় GitHub Actions-এ চলবে। কোনো ধাপ ব্যর্থ হলে পুরো stdout/stderr লগ সংগ্রহ করুন। `pubspec.lock` যুক্ত না থাকলে solver একটি নতুন compatible transitive সংস্করণ বেছে নিতে পারে; successful `flutter pub get`-এর পরে lockfile commit করলে reproducibility বাড়বে।

## সতর্কতা

এখানে Flutter SDK না থাকায় বাস্তবে `flutter pub get`, `flutter test` বা APK build চালিয়ে সফলতা নিশ্চিত করা যায়নি। নতুন `excel_community`-এর Excel/LibreOffice export compatibility-ও বাস্তব ফাইলে পরীক্ষা করা উচিত। আগের PDF Import-এর `906-only` এবং Period অনুযায়ী মাসভাগের কোড অপরিবর্তিত রাখা হয়েছে। Firebase configuration বা security rules পরিবর্তন করা হয়নি।
