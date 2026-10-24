# Performance Tracker — In-App Update System Setup

এই update systemটি GitHub Releases-কে update server হিসেবে ব্যবহার করে। App চালু হলে (Auto Check চালু থাকলে) GitHub-এর latest non-prerelease release check করবে। নতুন version পেলে ছবির reference flow-এর মতো Update Available dialog → Updates page → Download confirmation → progress → Android installer open হবে।

## App-এর ভিতরে যা যুক্ত হয়েছে

1. **Automatic update check** — login/dashboard open হওয়ার পরে background-এ latest GitHub Release check। Network/update error হলে dashboard block হবে না।
2. **Update Available dialog** — Installed এবং Latest version পাশাপাশি দেখাবে; `View Update` ও `Later` থাকবে।
3. **Settings → Updates** — update banner, installed/latest version card, `What's New`, publish date, `Download & Install`, `Compare Release Notes`, manual refresh এবং Auto Check toggle।
4. **Release notes** — GitHub Release-এর description/body app-এর `What's New` section-এ দেখাবে।
5. **Android download/install** — device ABI অনুযায়ী `arm64-v8a`, `armeabi-v7a` বা `x86_64` release APK নির্বাচন করবে, download progress দেখাবে এবং Android installer খুলবে। Public Downloads folder লেখা সম্ভব না হলে নিরাপদ app cache fallback ব্যবহার করবে।
6. **Other platforms** — Android ছাড়া সরাসরি APK install না করে release page খুলবে।

## একবার GitHub Secrets সেট করতে হবে

Repository → **Settings → Secrets and variables → Actions → New repository secret**:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

একই release keystore সব production version-এ ব্যবহার করতে হবে। Key হারালে ইতোমধ্যে installed app-এর ওপর নতুন APK update হিসেবে install করা যাবে না। Keystore repository-তে commit করবেন না।

Keystore Base64 তৈরি করার উদাহরণ:

```bash
base64 -w 0 release-keystore.jks > keystore-base64.txt
```

Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("release-keystore.jks")) | Set-Content keystore-base64.txt
```

## নতুন update publish করার নিয়ম

ধরা যাক বর্তমানে `1.2.0+2`, পরের version `1.3.0+3`:

1. `pubspec.yaml` এ লিখুন:

```yaml
version: 1.3.0+3
```

2. Code push করুন।
3. Tag তৈরি ও push করুন:

```bash
git tag v1.3.0
git push origin v1.3.0
```

4. `Android Optimized APK (Small)` workflow signed split APK build করবে এবং একই tag-এর GitHub Release-এ attach করবে।
5. GitHub Release-এর description edit করে প্রয়োজন হলে সুন্দর `What's New` লিখুন। Generated release notes-ও automatically enabled আছে।
6. পুরনো app চালু করলে নতুন release detect করবে।

**Version name অবশ্যই বাড়াতে হবে** (`1.3.0` > `1.2.0`) এবং Android build number/versionCode-ও বাড়াতে হবে (`+3` > `+2`)।

### প্রথম signed release-এর গুরুত্বপূর্ণ বিষয়

আগের installed APK যদি অন্য/debug certificate দিয়ে signed হয়ে থাকে, নতুন persistent keystore-এর প্রথম APK সেটির ওপর update হবে না। সে ক্ষেত্রে একবার পুরনো app uninstall করে নতুন signed release install করতে হবে। এরপর `ANDROID_KEYSTORE_BASE64`-এর একই keystore ব্যবহার করলে ভবিষ্যতের signed releases in-app update হিসেবে install হবে।

GitHub repository public হতে হবে যাতে client app authentication token ছাড়া Releases API পড়তে পারে। Private repository হলে public update metadata endpoint/proxy দরকার হবে; app-এর মধ্যে GitHub personal token রাখা নিরাপদ নয়।

## Local/AndroidIDE build-এ update source

GitHub Actions automatically repository নাম inject করে। Local build করলে নিজে দিন:

```bash
flutter build apk --release \
  --dart-define=UPDATE_GITHUB_REPOSITORY=OWNER/REPOSITORY
```

Debug run-এর উদাহরণ:

```bash
flutter run --dart-define=UPDATE_GITHUB_REPOSITORY=OWNER/REPOSITORY
```

## Android installer বিষয়ে

প্রথমবার app থেকে APK install করার সময় Android `Allow from this source` অনুমতি চাইতে পারে। User নিজে অনুমতি দিলে installer চালু হবে। বর্তমান app uninstall করা যাবে না; নতুন APK **উপর দিয়ে update** করতে হবে। Signature বা package name বদলালে update ব্যর্থ হবে।

## Release asset rule

Updater debug APK ignore করে। Production release-এ নিম্নের মতো release APK থাকতে হবে:

- `PerformanceTracker-arm64-v8a.apk`
- `PerformanceTracker-armeabi-v7a.apk`
- `PerformanceTracker-x86_64.apk`

Workflow বর্তমানে এই ফাইলগুলোই তৈরি করে।

## GitHub/Play policy note

এই implementation GitHub/sideload distribution-এর জন্য। Android 8+ এ app থেকে package installer request করতে `REQUEST_INSTALL_PACKAGES` declaration লাগে; included CI script generated Android manifest-এ এটি যোগ করে। Google Play-এ publish করলে এই permission-এর policy আলাদা—Play distribution-এর জন্য Google Play In-App Updates ব্যবহার করাই উপযুক্ত।

## Windows EXE release + in-app update

Windows-এর raw Flutter `.exe` একা distribute করা যাবে না, কারণ একই folder-এর DLL এবং `data` directory-ও দরকার। Desktop workflow এখন পুরো Windows release bundle-কে Inno Setup দিয়ে একটি self-contained installer বানায়:

- `PerformanceTracker-windows-x64-setup.exe` — normal install/update-এর জন্য; Windows updater এটিই ব্যবহার করে।
- `PerformanceTracker-windows-x64-portable.zip` — manual/portable fallback; updater এটি install করে না।

### Release করার নিয়ম

Tag push করলে `v*` এবং `V*` দুটো format-ই support করে, যেমন `v1.3.0` বা `V1.3`। Windows workflow tag থেকে app-এর internal version নির্ধারণ করে (`V1.3` → `1.3.0`), তাই install-এর পর একই update বারবার দেখাবে না।

আগে তৈরি করা release-এ Windows files যোগ করতে:

1. GitHub → **Actions** → **Desktop Builds** → **Run workflow**।
2. `release_tag`-এ existing tag লিখুন, যেমন `V1.3`।
3. Windows job সফল হলে ওই GitHub Release-এর Assets-এ setup EXE এবং portable ZIP যোগ হবে।

### Windows app-এর update flow

- App launch-এর সময় Auto Check enabled থাকলে GitHub latest release check হবে।
- Logged-out অবস্থায় Windows Login screen থেকেও check হবে; logged-in অবস্থায় Dashboard-এর existing auto-check চলবে।
- নতুন version থাকলে Android-এর মতো Update Available dialog দেখাবে।
- Updates screen-এ **Download & Install** চাপলে `PerformanceTracker-windows-x64-setup.exe` download হবে।
- Download শেষে installer silent mode-এ চালু হবে, পুরনো app বন্ধ হবে, files replace হবে, এবং updated Performance Tracker আবার চালু হবে।
- Installer current user-এর `%LOCALAPPDATA%\\Programs\\PerformanceTracker` path ব্যবহার করে, তাই সাধারণভাবে Administrator permission প্রয়োজন হয় না।

প্রথমবার কোনো পুরনো portable Windows build থেকে updater ব্যবহার করলে installer নতুন stable install location তৈরি করবে। এরপর Start Menu/Desktop shortcut-এর installed copy ব্যবহার করুন; পুরনো portable copy আলাদাভাবে রেখে চালালে সেটি আবার পুরনো version হিসেবেই update চাইতে পারে।

### Windows security note

Installer code-signing certificate না থাকলে Windows SmartScreen প্রথম install-এ warning দেখাতে পারে। এটি updater-এর version/download logic-এর failure নয়। Public distribution-এর জন্য trusted Windows code-signing certificate দিয়ে setup EXE sign করা ভালো।
