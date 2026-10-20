#!/usr/bin/env bash
# Build release APK + App Bundle against the production VPS API.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEFINES=(--dart-define-from-file=dart_defines.production.json)

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test"
flutter test

echo "==> release APK"
flutter build apk --release "${DEFINES[@]}"

echo "==> release App Bundle"
flutter build appbundle --release "${DEFINES[@]}"

echo ""
echo "APK:  $ROOT/build/app/outputs/flutter-apk/app-release.apk"
echo "AAB:  $ROOT/build/app/outputs/bundle/release/app-release.aab"
echo "API:  https://apiapnasociety.skylinetv.in (API_ENV=production)"
