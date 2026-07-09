# 릴리즈 런북 (GitHub + Homebrew)

무료 채널(Developer ID 서명 + 공증 + Sparkle 자동업데이트 + Homebrew cask) 배포 절차.

## 0. 최초 1회 세팅

### 0.1 Apple Developer ID 인증서

`swift build`는 서명이 필요 없지만, 배포 zip은 **Developer ID Application**
인증서로 서명해야 Gatekeeper·공증을 통과한다.

1. Apple Developer 계정(유료 멤버십) 필요.
2. 인증서 발급 — 둘 중 하나:
   - **Xcode**: Settings → Accounts → Manage Certificates → `+` → *Developer ID Application*.
   - **수동**: Keychain Access → 인증서 지원 → 인증 기관에서 인증서 요청(CSR) →
     [developer.apple.com](https://developer.apple.com/account/resources/certificates)
     에서 *Developer ID Application* 생성 → 다운로드 → 더블클릭으로 키체인 설치.
3. 확인: `security find-identity -v -p codesigning` 에
   `Developer ID Application: ... (TEAMID)` 가 보이면 OK.

### 0.2 공증(notarytool) 자격 저장

App Store Connect에서 **앱 암호(app-specific password)** 발급 후:

```sh
xcrun notarytool store-credentials weave-notary \
  --apple-id "<APPLE_ID>" --team-id "<TEAM_ID>" --password "<APP_SPECIFIC_PW>"
```

### 0.3 Sparkle 키

이미 생성됨(개인키는 키체인, 공개키는 `scripts/bundle.sh`에 박힘). 재발급 시:

```sh
Vendor/Sparkle/bin/generate_keys        # 공개키 출력 → bundle.sh의 ED_KEY 갱신
```

## 1. 원커맨드 배포 (권장)

버전업 → 서명·공증 → GitHub Release → appcast → Homebrew cask 까지 한 번에:

```sh
scripts/publish.sh patch     # 0.1.0 → 0.1.1
scripts/publish.sh minor     # 0.1.0 → 0.2.0
scripts/publish.sh major     # 0.1.0 → 1.0.0
scripts/publish.sh 0.3.0     # 명시적 버전

# 릴리즈 노트 상단에 변경점 노출(권장): HIGHLIGHTS 에 Added/Fixed/Changed 를 준다.
HIGHLIGHTS='- Added: Japan stock support\n- Fixed: chart period sync' \
  scripts/publish.sh minor
```

하는 일:
1. `WeaveInfo.swift` 의 `version` 갱신
2. `scripts/release.sh` — 서명·공증·staple·Sparkle 서명 (`SIGN_IDENTITY` 자동 탐지)
3. `docs/appcast.xml` 에 새 `<item>` 삽입(최신이 위) + XML 유효성 검사
4. `chore: 릴리즈 v<X>` 커밋 · `v<X>` 태그 · push
5. `gh release create` — zip 업로드
6. `kang1027/homebrew-weave` cask 의 `version`/`sha256` 갱신 · push

옵션(env): `SIGN_IDENTITY`(미지정 시 키체인 자동 탐지) · `NOTARY_PROFILE`(기본
`weave-notary`) · `TAP_REPO`(기본 `kang1027/homebrew-weave`) · `NOTES` · `DRY_RUN=1`.

사전 조건: 워킹트리 clean · `main` 브랜치 · `gh` 인증. 실행 전 계획만 보려면:

```sh
DRY_RUN=1 scripts/publish.sh minor
```

배포 후 기존 사용자는 Sparkle로, brew 사용자는 `brew upgrade --cask weave-pt` 로 갱신.

## 2. 수동 단계 (문제 생겼을 때 참고)

`publish.sh` 없이 손으로 할 경우:

1. `WeaveInfo.swift` 버전 수정
2. `scripts/release.sh` → `dist/Weave-<v>.zip` + `dist/release-info.env`(sha256/length/edSignature)
3. `gh release create v<v> dist/Weave-<v>.zip`
4. `docs/appcast.xml` 의 `<!-- appcast:items -->` 아래에 `<item>` 추가 후 push
5. `homebrew-weave` 의 `Casks/weave-pt.rb` 에서 `version`/`sha256` 갱신 후 push
