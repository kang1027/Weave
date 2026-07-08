#!/usr/bin/env bash
# README용 스크린샷 자동 생성.
# 실제 데이터와 격리된 시드 포트폴리오(scripts/seed-portfolio.json)를 임시 스토어에 복사해
# 앱을 dev 실행하고, 팝오버가 열리면 그 창을 자체 렌더해 PNG로 저장한다.
# 화면 녹화 권한 불필요(앱이 자기 뷰를 비트맵으로 캡처).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-$ROOT/assets/screenshot.png}"
DELAY="${WEAVE_SHOT_DELAY:-11}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp "$ROOT/scripts/seed-portfolio.json" "$WORK/portfolio.json"
rm -f "$OUT"

echo "▶ 빌드…"
swift build >/tmp/weave-shot-build.log 2>&1 || { tail -20 /tmp/weave-shot-build.log; exit 1; }

echo "▶ 실행 + 캡처 (${DELAY}s 대기: 시세·차트 로드)…"
WEAVE_STORE="$WORK/portfolio.json" \
WEAVE_SHOT="$OUT" \
WEAVE_SHOT_DELAY="$DELAY" \
  swift run Weave >/tmp/weave-shot.log 2>&1 || true

if [[ -f "$OUT" ]]; then
  echo "✓ 저장됨: $OUT"
else
  echo "✗ 스크린샷 실패 — 로그:"
  tail -25 /tmp/weave-shot.log
  exit 1
fi
