#!/bin/bash
# 개발 실행 — 빌드한 바이너리를 Developer ID로 서명한 뒤 띄운다.
# 서명 없는 `swift run` 빌드는 빌드마다 서명이 바뀌어 키체인(연결한 계좌·지갑)이 매번 허용을 다시 묻는다.
# 같은 인증서·식별자로 서명하면 "항상 허용"을 한 번만 누르면 된다.
# 사용: scripts/run-dev.sh   (SIGN_IDENTITY로 인증서를 직접 지정할 수 있다)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
BIN="$(swift build --show-bin-path)/Weave"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -n "$IDENTITY" ]; then
  # 정식 앱(app.weave)과 키체인 허용을 섞지 않게 개발용 식별자를 쓴다.
  codesign --force --sign "$IDENTITY" --identifier app.weave.dev "$BIN"
else
  echo "▸ Developer ID 인증서가 없어 서명 없이 실행 — 키체인이 빌드마다 허용을 다시 묻는다" >&2
fi

exec "$BIN"
