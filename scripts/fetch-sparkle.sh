#!/bin/bash
# Sparkle xcframework 벤더링 — SwiftPM 원격 아티팩트 다운로드가 안 되는 환경 대비.
# 사용: scripts/fetch-sparkle.sh  (최초 빌드 전 1회)
set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION="2.9.4"
DEST="Vendor/Sparkle"

if [ -d "$DEST/Sparkle.xcframework" ]; then
  echo "✓ 이미 존재: $DEST/Sparkle.xcframework"
  exit 0
fi

echo "▸ Sparkle ${SPARKLE_VERSION} 다운로드"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -sSL -o "$TMP/sparkle-spm.zip" \
  "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"
unzip -q "$TMP/sparkle-spm.zip" -d "$TMP/spm"

mkdir -p "$DEST"
FRAMEWORK=$(find "$TMP/spm" -name "Sparkle.xcframework" -maxdepth 3 | head -1)
[ -n "$FRAMEWORK" ] || { echo "✗ zip 안에서 Sparkle.xcframework를 찾지 못함"; exit 1; }
cp -R "$FRAMEWORK" "$DEST/"

# EdDSA 키/서명 도구도 함께 벤더링(있으면).
BIN_DIR=$(find "$TMP/spm" -type d -name bin -maxdepth 3 | head -1)
if [ -n "$BIN_DIR" ]; then
  cp -R "$BIN_DIR" "$DEST/bin"
fi

echo "✓ $DEST/Sparkle.xcframework (${SPARKLE_VERSION})"
