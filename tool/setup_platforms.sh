#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v flutter >/dev/null || { echo 'Install Flutter and add it to PATH first.' >&2; exit 1; }
flutter create --project-name performance_tracker_flutter --org com.performance \
  --platforms=android,ios,windows,macos,linux .
python3 tool/configure_firebase_android.py
flutter pub get
flutter analyze
flutter test
