#!/usr/bin/env bash
# README용 스크린샷 자동 생성 (홈 Combined · 종목 세부 · 홈 By Asset 3장).
# 실제 데이터와 격리된 시드 포트폴리오(scripts/seed-portfolio.json)를 임시 스토어에 복사해
# 앱을 dev 실행하고, 팝오버가 열리면 그 창을 자체 렌더해 PNG로 저장한다.
# 화면 녹화 권한 불필요(앱이 자기 뷰를 비트맵으로 캡처).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DELAY="${WEAVE_SHOT_DELAY:-12}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/scripts/seed-portfolio.json" "$WORK/portfolio.json"

echo "▶ 빌드…"
swift build >/tmp/weave-shot-build.log 2>&1 || { tail -20 /tmp/weave-shot-build.log; exit 1; }

# $1=상태(home-combined|detail|home-byasset)  $2=출력 경로
capture() {
  local state="$1" out="$2"
  rm -f "$out"
  echo "▶ 캡처: ${state} (${DELAY}s 대기) → ${out}"
  WEAVE_STORE="$WORK/portfolio.json" \
  WEAVE_SHOT="$out" \
  WEAVE_SHOT_STATE="$state" \
  WEAVE_SHOT_DELAY="$DELAY" \
    swift run Weave >/tmp/weave-shot.log 2>&1 || true
  if [[ -f "$out" ]]; then echo "  ✓ ${out}"; else echo "  ✗ 실패 — 로그:"; tail -15 /tmp/weave-shot.log; fi
}

capture home-combined "$ROOT/assets/screenshot.png"
capture detail        "$ROOT/assets/screenshot-detail.png"
capture home-byasset  "$ROOT/assets/screenshot-byasset.png"
capture menubar       "$ROOT/assets/screenshot-menubar.png"

echo "완료."
