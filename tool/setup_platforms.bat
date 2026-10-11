@echo off
setlocal
cd /d "%~dp0.."
where flutter >nul 2>&1
if errorlevel 1 (
  echo Flutter not found. Install Flutter and add it to PATH.
  exit /b 1
)
flutter create --project-name performance_tracker_flutter --org com.performance --platforms=android,ios,windows,macos,linux .
if errorlevel 1 exit /b 1
py -3 tool\configure_firebase_android.py
if errorlevel 1 exit /b 1
flutter pub get
if errorlevel 1 exit /b 1
flutter analyze
if errorlevel 1 exit /b 1
flutter test
