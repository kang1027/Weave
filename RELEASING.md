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

## 1. 버전 올리기

`Sources/WeaveCore/WeaveInfo.swift` 의 `version` 을 새 버전으로 수정 후 커밋.

## 2. 서명·공증·zip 생성

```sh
SIGN_IDENTITY="Developer ID Application: <NAME> (<TEAMID>)" scripts/release.sh
```

산출: `dist/Weave-<version>.zip` (서명+공증+staple 완료),
그리고 `sign_update` 이 출력한 `sparkle:edSignature`.

## 3. GitHub Release

```sh
gh release create v<version> dist/Weave-<version>.zip \
  --title "v<version>" --notes "..."
```

## 4. appcast 갱신 (Sparkle 자동업데이트)

`docs/appcast.xml` 에 `<item>` 추가:
- `sparkle:version` / `sparkle:shortVersionString` = 버전
- `enclosure url` = release zip 다운로드 URL
- `sparkle:edSignature` = 2단계 `sign_update` 출력
- `length` = zip 바이트 수 (`stat -f%z dist/Weave-<version>.zip`)

커밋·푸시하면 GitHub Pages(`kang1027.github.io/Weave/appcast.xml`)가 서빙 →
기존 사용자는 Sparkle로 자동 업데이트.

## 5. Homebrew cask 갱신

첫 릴리즈면 tap 리포 생성:

```sh
gh repo create kang1027/homebrew-weave --public -d "Homebrew tap for Weave"
```

`Casks/weave-pt.rb` 를 `packaging/weave-pt.rb` 기준으로 만들고 매 릴리즈마다:
- `version` 갱신
- `sha256` = `shasum -a 256 dist/Weave-<version>.zip`

푸시하면 사용자는 `brew install --cask kang1027/weave/weave-pt` 로 설치/업데이트.
