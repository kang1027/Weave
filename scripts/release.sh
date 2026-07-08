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
# SIGN_IDENTITY 미지정 시 키체인의 Developer ID Application 인증서를 자동 탐지.
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -z "$SIGN_IDENTITY" ]; then
  echo "✗ Developer ID Application 인증서를 찾지 못함 — SIGN_IDENTITY로 직접 지정" >&2
  exit 1
fi
NOTARY_PROFILE="${NOTARY_PROFILE:-weave-notary}"

scripts/bundle.sh

APP="dist/Weave.app"
ZIP="dist/Weave-${VERSION}.zip"

# ED 공개키가 플레이스홀더면 배포 빌드의 업데이트 채널이 영구히 죽는다 — 하드 가드.
if /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP/Contents/Info.plist" 2>/dev/null | grep -q "__SPARKLE_ED_PUBLIC_KEY__"; then
  echo "✗ SUPublicEDKey가 플레이스홀더 상태 — SPARKLE_ED_PUBLIC_KEY 환경변수를 설정하고 다시 실행" >&2
  exit 1
fi

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
EDSIG=""
LENGTH=""
if [ -n "$SIGN_UPDATE" ]; then
  SIGN_OUT=$("$SIGN_UPDATE" "$ZIP")
  echo "  $SIGN_OUT"
  EDSIG=$(echo "$SIGN_OUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
  LENGTH=$(echo "$SIGN_OUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
else
  echo "  ⚠ sign_update 도구를 찾지 못함"
fi

# 후속 자동화(publish.sh)가 읽을 릴리즈 메타데이터 — dist/는 gitignore라 커밋 안 됨.
SHA256=$(shasum -a 256 "$ZIP" | awk '{print $1}')
[ -z "$LENGTH" ] && LENGTH=$(stat -f%z "$ZIP")
{
  echo "VERSION='${VERSION}'"
  echo "ZIP='${ZIP}'"
  echo "SHA256='${SHA256}'"
  echo "LENGTH='${LENGTH}'"
  echo "EDSIG='${EDSIG}'"
} > dist/release-info.env

echo "✓ ${ZIP}"
echo "  메타데이터: dist/release-info.env (sha256/length/edSignature)"
echo "  배포 자동화: scripts/publish.sh"
