import Foundation
import Testing
@testable import WeaveCore

/// finestCovering — 거래 시점을 담을 수 있는 가장 촘촘한 인터벌 선택(마커 점프 시 인터벌 자동 전환용).
struct CandleIntervalTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func ago(days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    @Test func recentPicksFinestIntraday() {
        // 커버: m15 ~10.4일, h1 ~41.7일, h4 ~166.7일, day 400일.
        #expect(CandleInterval.finestCovering(ago(days: 5), now: now) == .m15)
        #expect(CandleInterval.finestCovering(ago(days: 20), now: now) == .h1)
        #expect(CandleInterval.finestCovering(ago(days: 100), now: now) == .h4)
    }

    @Test func oldTradeSteppsUpToDayOrCoarser() {
        #expect(CandleInterval.finestCovering(ago(days: 187), now: now) == .day)   // 1H 범위 밖 → 1D
        #expect(CandleInterval.finestCovering(ago(days: 1_000), now: now) == .week)
        #expect(CandleInterval.finestCovering(ago(days: 5_000), now: now) == .month)
    }

    @Test func futureTradeFallsToFinest() {
        #expect(CandleInterval.finestCovering(now.addingTimeInterval(86_400), now: now) == .m15)
    }
}
