#!/bin/bash
# 릴리즈 파이프라인 — 서명 → 공증 → zip → EdDSA 서명 → appcast 항목 출력.
#
# 사전 준비 (1회):
#   1. Sparkle 키 생성: `Vendor/Sparkle/bin/generate_keys` 실행
#      → 공개키를 SPARKLE_ED_PUBLIC_KEY 환경변수로, 개인키는 키체인에 보관
#   2. notarytool 자격 증명 저장:
#      xcrun notarytool store-credentials weave-notary \
#        --apple-id <APPLE_ID> --team-id <TEAM_ID> --password <APP_SPECIFIC_PW>
#
# 사용:
#   SIGN_IDENTITY="Developer ID Application: ..." scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/WeaveCore/WeaveInfo.swift)
SIGN_IDENTITY="${SIGN_IDENTITY:?Developer ID 서명 identity를 SIGN_IDENTITY로 지정}"
NOTARY_PROFILE="${NOTARY_PROFILE:-weave-notary}"

scripts/bundle.sh

APP="dist/Weave.app"
ZIP="dist/Weave-${VERSION}.zip"

echo "▸ codesign"
if [ -d "$APP/Contents/Frameworks/Sparkle.framework" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" 2>/dev/null || true
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" 2>/dev/null || true
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" 2>/dev/null || true
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" 2>/dev/null || true
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Frameworks/Sparkle.framework"
fi
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "▸ zip + notarize"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
# staple 반영해 zip 재생성.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Sparkle EdDSA 서명"
SIGN_UPDATE=$(find Vendor/Sparkle/bin .build/artifacts -name "sign_update" -type f 2>/dev/null | head -1)
if [ -n "$SIGN_UPDATE" ]; then
  "$SIGN_UPDATE" "$ZIP"
  echo "  위 서명을 appcast.xml의 sparkle:edSignature로 사용"
else
  echo "  ⚠ sign_update 도구를 찾지 못함"
fi

echo "✓ ${ZIP}"
echo "  1) GitHub Release v${VERSION}에 zip 업로드"
echo "  2) docs/appcast.xml 항목 추가 후 GitHub Pages 배포"
