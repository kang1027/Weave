# Weave

macOS 메뉴바 포트폴리오 트래커. 메뉴바에 핀 자산 시세를 상시 표시하고,
클릭하면 360×720 팝오버에서 포트폴리오 전체를 관리한다.

## 기준 문서

- **기능 명세**: `docs/FEATURES.md` — 유일한 기능 기준. 정책 충돌 시 이 문서가 이긴다.
- **디자인 기준**: `design/mockups-v5.html` — 색 토큰·레이아웃·인터랙션의 시각 기준.
- **동작 플로우**: `docs/FLOWS.md` — 사용자 플로우 전수 목록(리뷰/QA 기준).

## 스택 & 구조

- SwiftUI(MenuBarExtra) + Swift Charts, macOS 14+, SwiftPM.
- `Sources/WeaveCore` — 플랫폼 독립 로직(모델·스토어·프로바이더·계산기). 단위 테스트 대상.
- `Sources/Weave` — 앱 타겟(뷰·테마·메뉴바·업데이트).
- `Tests/WeaveCoreTests` — 코어 단위 테스트.

## 빌드 & 테스트

```sh
scripts/fetch-sparkle.sh  # 최초 1회 — Sparkle xcframework 벤더링
swift build               # 컴파일 확인
swift test                # WeaveCore 단위 테스트
swift run Weave           # 개발 실행 (메뉴바 앱)
scripts/bundle.sh         # Weave.app 번들 생성
scripts/release.sh        # 서명·공증·zip·EdDSA 서명 (SIGN_IDENTITY 필요)
```

Sparkle은 `Vendor/Sparkle` 로컬 패키지로 참조한다(SwiftPM 원격 binaryTarget
다운로드가 막힌 환경 대응). xcframework 바이너리는 git에 커밋하지 않는다.

## 컨벤션

- 데이터 소스는 Binance/Naver/Yahoo 3개 고정. provider는 프로토콜로 추상화 —
  비공식 API 스펙이 바뀌면 어댑터만 교체한다.
- 금액 계산은 `Decimal`, 차트 좌표는 `Double`.
- 아이콘은 SF Symbols만 사용(이모지 금지), 색은 `Theme` 시맨틱 토큰만 사용.
- 문자열은 String Catalog(`Localizable.xcstrings`) 경유 — 하드코딩 한글/영어 금지.
- 커밋 메시지는 한글, `<type>: <설명>` 형식. 마일스톤/레이어 단위로 쪼갠다.
- 저장 스키마를 바꿀 땐 `PortfolioDocument.version`을 올리고 마이그레이션을 추가한다.
