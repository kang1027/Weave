#!/bin/bash
# 원커맨드 배포 — 버전업 → 서명·공증 릴리즈 → GitHub Release → appcast → Homebrew cask.
#
# 사용:
#   scripts/publish.sh 0.2.0            # 명시적 버전
#   scripts/publish.sh patch            # 0.1.0 → 0.1.1
#   scripts/publish.sh minor            # 0.1.0 → 0.2.0
#   scripts/publish.sh major            # 0.1.0 → 1.0.0
#
# 옵션(env):
#   SIGN_IDENTITY   미지정 시 키체인의 Developer ID Application 자동 탐지
#   NOTARY_PROFILE  기본 weave-notary
#   TAP_REPO        기본 kang1027/homebrew-weave
#   NOTES           릴리즈 노트(미지정 시 자동 생성)
#   DRY_RUN=1       서명·공증·푸시·릴리즈 없이 계획 출력 + appcast 주입만 검증
set -euo pipefail
cd "$(dirname "$0")/.."

INFO="Sources/WeaveCore/WeaveInfo.swift"
APPCAST="docs/appcast.xml"
TAP_REPO="${TAP_REPO:-kang1027/homebrew-weave}"
CASK_PATH="Casks/weave-pt.rb"
DRY_RUN="${DRY_RUN:-0}"

die() { echo "✗ $*" >&2; exit 1; }
run() { if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] $*"; else eval "$*"; fi; }

# ── 1. 버전 계산 ───────────────────────────────────────────────
arg="${1:-}"
[ -n "$arg" ] || die "사용: scripts/publish.sh <version|patch|minor|major>"
CUR=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' "$INFO")
IFS=. read -r MA MI PA <<<"$CUR"
case "$arg" in
  major) NEW="$((MA + 1)).0.0" ;;
  minor) NEW="${MA}.$((MI + 1)).0" ;;
  patch) NEW="${MA}.${MI}.$((PA + 1))" ;;
  [0-9]*.[0-9]*.[0-9]*) NEW="$arg" ;;
  *) die "버전 형식 오류: '$arg' (X.Y.Z 또는 patch/minor/major)" ;;
esac
[ "$NEW" != "$CUR" ] || die "버전이 그대로임: $NEW"
echo "▸ 버전 $CUR → $NEW"

# ── 2. 사전 점검 ───────────────────────────────────────────────
command -v gh >/dev/null || die "gh CLI 필요"
gh auth status >/dev/null 2>&1 || die "gh 인증 필요 (gh auth login)"
git rev-parse "v$NEW" >/dev/null 2>&1 && die "태그 v$NEW 이미 존재"
if [ "$DRY_RUN" != 1 ]; then
  git diff --quiet && git diff --cached --quiet || die "커밋 안 된 변경 있음 — 정리 후 재실행"
  [ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "main 브랜치에서 실행할 것"
fi

# ── 3. 버전 파일 갱신 ──────────────────────────────────────────
if [ "$DRY_RUN" = 1 ]; then
  echo "  [dry-run] $INFO 의 version → $NEW"
else
  sed -i '' "s/static let version = \".*\"/static let version = \"$NEW\"/" "$INFO"
fi

# ── 4. 서명·공증 릴리즈 (dry-run은 건너뜀) ─────────────────────
if [ "$DRY_RUN" = 1 ]; then
  echo "  [dry-run] scripts/release.sh (서명·공증 생략)"
  SHA256="DRYRUN_SHA256"; LENGTH="0"; EDSIG="DRYRUN_EDSIG"; ZIP="dist/Weave-$NEW.zip"
else
  scripts/release.sh
  # shellcheck disable=SC1091
  source dist/release-info.env
  [ "$VERSION" = "$NEW" ] || die "release-info 버전 불일치: $VERSION != $NEW"
fi

# ── 5. appcast <item> 삽입 (마커 바로 아래 = 최신이 위) ────────
PUBDATE=$(LC_TIME=en_US.UTF-8 date '+%a, %d %b %Y %H:%M:%S %z')
ITEMFILE=$(mktemp)
cat > "$ITEMFILE" <<EOF
    <item>
      <title>$NEW</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$NEW</sparkle:version>
      <sparkle:shortVersionString>$NEW</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <link>https://github.com/kang1027/Weave/releases/tag/v$NEW</link>
      <enclosure
        url="https://github.com/kang1027/Weave/releases/download/v$NEW/Weave-$NEW.zip"
        sparkle:edSignature="$EDSIG"
        length="$LENGTH"
        type="application/octet-stream"/>
    </item>
EOF
# getline으로 삽입 — edSignature의 / + = 같은 특수문자 이스케이프 걱정 없음.
TARGET="$APPCAST"; [ "$DRY_RUN" = 1 ] && TARGET=$(mktemp) && cp "$APPCAST" "$TARGET"
awk -v f="$ITEMFILE" '
  { print }
  /appcast:items/ { while ((getline line < f) > 0) print line; close(f) }
' "$TARGET" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
xmllint --noout "$TARGET" || die "appcast XML 깨짐 — 삽입 중단"
echo "▸ appcast에 $NEW 항목 삽입 (XML 유효)"
rm -f "$ITEMFILE"

# ── 6. 커밋 · 태그 · 푸시 ──────────────────────────────────────
run "git add '$INFO' '$APPCAST'"
run "git commit -q -m 'chore: 릴리즈 v$NEW'"
run "git tag v$NEW"
run "git push origin main"
run "git push origin v$NEW"

# ── 7. GitHub Release ──────────────────────────────────────────
NOTES="${NOTES:-Weave $NEW

설치/업데이트:
\`\`\`sh
brew upgrade --cask weave-pt   # 또는: brew install --cask kang1027/weave/weave-pt
\`\`\`
기존 사용자는 Sparkle로 자동 업데이트됩니다.}"
if [ "$DRY_RUN" = 1 ]; then
  echo "  [dry-run] gh release create v$NEW $ZIP"
else
  gh release create "v$NEW" "$ZIP" --title "Weave $NEW" --notes "$NOTES"
fi

# ── 8. Homebrew cask 갱신 (fresh clone → version/sha256 → push) ─
if [ "$DRY_RUN" = 1 ]; then
  echo "  [dry-run] $TAP_REPO/$CASK_PATH → version $NEW, sha256 $SHA256"
else
  TAP_DIR=$(mktemp -d)
  gh repo clone "$TAP_REPO" "$TAP_DIR" -- -q
  cask="$TAP_DIR/$CASK_PATH"
  sed -i '' "s/version \".*\"/version \"$NEW\"/" "$cask"
  sed -i '' "s/sha256 \".*\"/sha256 \"$SHA256\"/" "$cask"
  git -C "$TAP_DIR" add "$CASK_PATH"
  git -C "$TAP_DIR" commit -q -m "feat: weave-pt cask $NEW"
  git -C "$TAP_DIR" push -q origin main
  rm -rf "$TAP_DIR"
fi

echo
echo "✅ v$NEW 배포 완료"
echo "  Release: https://github.com/kang1027/Weave/releases/tag/v$NEW"
echo "  설치:    brew install --cask kang1027/weave/weave-pt"
echo "  업데이트: brew upgrade --cask weave-pt"
