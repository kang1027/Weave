#!/bin/bash
# Weave.app 번들 생성 — swift build(release) 결과물 + Info.plist + Sparkle.framework.
# 사용: scripts/bundle.sh
# 산출: dist/Weave.app
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/WeaveCore/WeaveInfo.swift)
# Sparkle EdDSA 공개키 — 앱에 박히는 값이라 공개해도 안전(개인키만 키체인 보관).
ED_KEY="${SPARKLE_ED_PUBLIC_KEY:-OYrjZVe89kag8gckegzrsPP/KEb63kRRphubPRzHpQQ=}"

echo "▸ swift build -c release (Weave ${VERSION})"
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)

APP="dist/Weave.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

echo "▸ 실행 파일/리소스 복사"
cp "$BIN_DIR/Weave" "$APP/Contents/MacOS/Weave"
# SwiftPM 리소스 번들(String Catalog 등) — Bundle.module이 Resources에서 찾는다.
if [ -d "$BIN_DIR/Weave_Weave.bundle" ]; then
  cp -R "$BIN_DIR/Weave_Weave.bundle" "$APP/Contents/Resources/"
fi

echo "▸ 앱 아이콘 복사"
if [ ! -f "assets/Weave.icns" ]; then
  echo "✗ assets/Weave.icns를 찾지 못함" >&2
  exit 1
fi
cp "assets/Weave.icns" "$APP/Contents/Resources/Weave.icns"

echo "▸ Sparkle.framework 복사"
SPARKLE_FRAMEWORK=""
for candidate in \
  "$BIN_DIR/Sparkle.framework" \
  "Vendor/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"; do
  if [ -d "$candidate" ]; then SPARKLE_FRAMEWORK="$candidate"; break; fi
done
if [ -z "$SPARKLE_FRAMEWORK" ]; then
  SPARKLE_FRAMEWORK=$(find .build/artifacts Vendor -name "Sparkle.framework" 2>/dev/null | head -1)
fi
if [ -n "$SPARKLE_FRAMEWORK" ]; then
  cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Weave" 2>/dev/null || true
else
  echo "  ⚠ Sparkle.framework를 찾지 못함 — 업데이트 기능 없이 번들됨"
fi

echo "▸ Info.plist 생성"
# ED_KEY(base64)에는 '/'가 들어갈 수 있어 sed 구분자를 '|'로 쓴다(base64엔 '|' 없음).
sed -e "s/__VERSION__/${VERSION}/g" \
    -e "s|__SPARKLE_ED_PUBLIC_KEY__|${ED_KEY}|g" \
    scripts/Info.plist.template > "$APP/Contents/Info.plist"

echo "✓ dist/Weave.app (${VERSION})"
echo "  서명/공증/릴리즈는 scripts/release.sh 참고"
