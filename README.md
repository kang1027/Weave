# Weave

macOS 메뉴바 포트폴리오 트래커.

메뉴바에서 보유 자산 시세를 로테이션으로 보여주고, 클릭하면 팝오버에서
포트폴리오 전체(링 게이지 · 가치 히스토리 차트 · 자산별 상세 · 거래 내역)를 관리한다.

- 크립토(Binance) · 국내주식(Naver) · 해외주식(Yahoo Finance) 심볼 검색 지원
- 매수/매도 기록 기반 평단·수익률·실현손익 계산
- Slate / Light 테마, 한국어 / English
- Sparkle 자동 업데이트

## 개발

```sh
scripts/fetch-sparkle.sh  # 최초 1회 — Sparkle 벤더링
swift run Weave           # 개발 실행
swift test                # 단위 테스트
scripts/bundle.sh         # Weave.app 번들 생성
```

문서: [기능 명세](docs/FEATURES.md) · [동작 플로우](docs/FLOWS.md)

## 요구 사항

- macOS 14+
