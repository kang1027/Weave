# Weave

macOS 메뉴바 포트폴리오 트래커.

메뉴바에서 보유 자산 시세를 로테이션으로 보여주고, 클릭하면 팝오버에서
포트폴리오 전체(링 게이지 · 가치 히스토리 차트 · 자산별 상세 · 거래 내역)를 관리한다.

- 크립토(Binance) · 국내주식(Naver) · 해외주식(Yahoo Finance) 심볼 검색 지원
- 매수/매도 기록 기반 평단·수익률·실현손익 계산
- 가치 히스토리 차트(통합/자산별, 1D·1W·1M·1Y), 링 게이지, 매수 마커
- 프라이버시 모드(금액 마스킹, 등락률 유지) — 팝오버·메뉴바 동시 적용
- Slate / Light 테마, 한국어 / English
- Sparkle 자동 업데이트

## 설치

### Homebrew (권장)

```sh
brew install --cask kang1027/weave/weave-pt
```

Developer ID로 서명 + Apple 공증되어 Gatekeeper 경고 없이 실행되고,
Sparkle로 자동 업데이트된다.

### 소스 빌드

macOS 14+ 와 Swift 툴체인 필요.

```sh
git clone https://github.com/kang1027/Weave.git
cd Weave
scripts/fetch-sparkle.sh  # 최초 1회 — Sparkle 벤더링
swift run Weave           # 개발 실행
swift test                # 단위 테스트
scripts/bundle.sh         # dist/Weave.app 번들 생성
```

## 데이터 · 프라이버시

포트폴리오는 이 맥 로컬(Application Support)에만 저장되고 외부로 전송되지 않는다.
Binance / Naver / Yahoo Finance의 공개 시세·캔들만 조회하며, 계정·API 키·텔레메트리 없음.

## 후원

Weave는 무료 오픈소스다. 개발을 후원하고 싶으면 Mac App Store에서 유료 빌드로도
받을 수 있다 — 같은 앱, 그냥 마음 보태는 용도.

## 문서

[기능 명세](docs/FEATURES.md) · [동작 플로우](docs/FLOWS.md)

## 라이선스

[MIT](LICENSE) © 2026 kang1027
