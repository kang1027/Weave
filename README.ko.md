<div align="center">

<img src="assets/logo.svg" width="112" height="112" alt="Weave">

# Weave

**macOS 메뉴바 포트폴리오 트래커 — 크립토·국장·해외주식을 한눈에.**

[![Release](https://img.shields.io/github/v/release/kang1027/Weave?label=release&color=6366F1)](https://github.com/kang1027/Weave/releases)
[![License](https://img.shields.io/github/license/kang1027/Weave?color=6366F1)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org)

[English](README.md) · **한국어**

<br>

<img src="assets/screenshot-menubar.png" width="300" alt="macOS 메뉴바의 Weave"><br>
<sub>메뉴바에 상주</sub>

<br><br>

<table align="center">
  <tr>
    <td align="center"><img src="assets/screenshot.png" width="230" alt="포트폴리오 개요"><br><sub><b>포트폴리오</b></sub></td>
    <td align="center"><img src="assets/screenshot-detail.png" width="230" alt="종목 세부"><br><sub><b>종목 세부</b></sub></td>
    <td align="center"><img src="assets/screenshot-byasset.png" width="230" alt="자산별 차트"><br><sub><b>자산별</b></sub></td>
  </tr>
</table>

</div>

## 기능

- **메뉴바에 상주.** 보유 자산을 로테이션으로 보여주고, 클릭하면 팝오버가 열린다.
- **크립토·국장·해외주식.** Binance·Naver·Yahoo Finance 심볼 검색을 한 곳에서.
- **진짜 평단·손익.** 매수/매도 기록을 기반으로 평단, 미실현·실현 수익률을 계산한다.
- **가치 히스토리 차트.** 통합·자산별(1D / 1W / 1M / 1Y), 링 게이지, 매수 마커까지.
- **수동 자산.** 티커 없는 것도 추적 — 부동산, 현금 등 원하는 건 뭐든 합산.
- **프라이버시 모드.** 금액은 가리고 등락률은 유지 — 팝오버와 메뉴바에 동시 적용.
- **온전히 로컬.** 계정도 텔레메트리도 없이 데이터는 이 맥을 벗어나지 않는다. `.weave` 백업은 커스텀 로고까지 포함한 자기완결형.
- **네이티브 & 깔끔.** Slate / Light 테마, 한국어 / English, 서명·공증 완료, Sparkle 자동 업데이트.

## 설치

### Homebrew (권장)

```sh
brew install --cask kang1027/weave/weave-pt
```

한 줄이면 tap과 설치가 한 번에 된다. Developer ID로 서명 + Apple 공증되어 Gatekeeper 경고 없이 실행되고, Sparkle로 자동 업데이트된다. 업데이트는 `brew upgrade --cask weave-pt`.

### 직접 다운로드

Homebrew가 싫으면 [releases](https://github.com/kang1027/Weave/releases/latest)에서 최신 `.dmg`를 받아 열고 **Weave**를 Applications 폴더로 드래그하면 된다. 서명·공증돼 있어 Gatekeeper 경고 없음.

### 소스 빌드

macOS 14+ 와 Swift 툴체인 필요.

```sh
git clone https://github.com/kang1027/Weave.git
cd Weave
scripts/fetch-sparkle.sh   # 최초 1회 — Sparkle 벤더링
swift run Weave            # 개발 실행
swift test                 # 단위 테스트
scripts/bundle.sh          # dist/Weave.app 번들 생성
```

## 데이터 · 프라이버시

포트폴리오는 이 맥 로컬(`Application Support/Weave`)에만 저장되고 외부로 전송되지 않는다. Binance·Naver·Yahoo Finance의 공개 시세·캔들만 조회하며 계정·API 키·텔레메트리는 없다.

## 후원

Weave는 무료 오픈소스다. 개발을 후원하고 싶으면 Mac App Store에서 유료 빌드로도 받을 수 있다 — 같은 앱, 그냥 마음 보태는 용도.

## 문서

[기능 명세](docs/FEATURES.ko.md) · [동작 플로우](docs/FLOWS.ko.md)

## 라이선스

[MIT](LICENSE) © 2026 kang1027
