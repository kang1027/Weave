import Foundation
import Testing
@testable import WeaveCore

@Suite struct PositionCalculatorTests {
    private let assetID = UUID()

    private func trade(
        _ side: TradeSide,
        qty: Decimal,
        price: Decimal,
        day: Int,
        id: UUID = UUID()
    ) -> Trade {
        Trade(
            id: id,
            assetID: assetID,
            side: side,
            quantity: qty,
            price: price,
            date: Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
        )
    }

    @Test func movingAverageCost() {
        // 10주 @100 → 10주 @200 ⇒ 평단 150
        let snapshot = PositionCalculator.snapshot(trades: [
            trade(.buy, qty: 10, price: 100, day: 1),
            trade(.buy, qty: 10, price: 200, day: 2)
        ])
        #expect(snapshot.quantity == 20)
        #expect(snapshot.averageCost == 150)
        #expect(snapshot.buyCount == 2)
        #expect(snapshot.firstBuyDate == Date(timeIntervalSince1970: 86_400))
    }

    @Test func sellKeepsAverageAndRealizesPnL() {
        // 평단 150에서 5주 @180 매도 ⇒ 실현 +150, 평단 유지
        let snapshot = PositionCalculator.snapshot(trades: [
            trade(.buy, qty: 10, price: 100, day: 1),
            trade(.buy, qty: 10, price: 200, day: 2),
            trade(.sell, qty: 5, price: 180, day: 3)
        ])
        #expect(snapshot.quantity == 15)
        #expect(snapshot.averageCost == 150)
        #expect(snapshot.realizedPnL == 150)
        #expect(snapshot.sellCount == 1)
    }

    @Test func buyAfterSellRecomputesAverage() {
        // 매도 후 재매수 시 남은 원가와 신규 체결로 평단 재계산
        let snapshot = PositionCalculator.snapshot(trades: [
            trade(.buy, qty: 10, price: 100, day: 1),
            trade(.sell, qty: 5, price: 120, day: 2),
            trade(.buy, qty: 5, price: 200, day: 3)
        ])
        #expect(snapshot.quantity == 10)
        #expect(snapshot.averageCost == 150)
        #expect(snapshot.realizedPnL == 100)
    }

    @Test func fullExitResetsAverage() {
        let snapshot = PositionCalculator.snapshot(trades: [
            trade(.buy, qty: 10, price: 100, day: 1),
            trade(.sell, qty: 10, price: 150, day: 2)
        ])
        #expect(snapshot.quantity == 0)
        #expect(snapshot.averageCost == 0)
        #expect(snapshot.realizedPnL == 500)
    }

    @Test func oversellClampsToHolding() {
        // 저장 데이터가 어긋나도 음수 보유가 되지 않게 클램프
        let snapshot = PositionCalculator.snapshot(trades: [
            trade(.buy, qty: 5, price: 100, day: 1),
            trade(.sell, qty: 10, price: 150, day: 2)
        ])
        #expect(snapshot.quantity == 0)
        #expect(snapshot.realizedPnL == 250)
    }

    @Test func perTradeRealizedPnLUsesAverageAtSellTime() {
        let sell = trade(.sell, qty: 5, price: 180, day: 3)
        let trades = [
            trade(.buy, qty: 10, price: 100, day: 1),
            trade(.buy, qty: 10, price: 200, day: 2),
            sell,
            trade(.buy, qty: 10, price: 300, day: 4)
        ]
        #expect(PositionCalculator.realizedPnL(of: sell, in: trades) == 150)
        #expect(PositionCalculator.realizedPnL(of: trades[0], in: trades) == nil)
    }

    @Test func stepQuantityByDate() {
        let trades = [
            trade(.buy, qty: 10, price: 100, day: 10),
            trade(.sell, qty: 4, price: 100, day: 20)
        ]
        let day = { (d: Int) in Date(timeIntervalSince1970: TimeInterval(d) * 86_400) }
        #expect(PositionCalculator.quantity(onOrBefore: day(5), trades: trades) == 0)
        #expect(PositionCalculator.quantity(onOrBefore: day(10), trades: trades) == 10)
        #expect(PositionCalculator.quantity(onOrBefore: day(15), trades: trades) == 10)
        #expect(PositionCalculator.quantity(onOrBefore: day(25), trades: trades) == 6)
    }

    @Test func availableQuantityExcludesEditedTrade() {
        let editing = trade(.sell, qty: 4, price: 100, day: 20)
        let trades = [
            trade(.buy, qty: 10, price: 100, day: 10),
            editing
        ]
        let at = Date(timeIntervalSince1970: 25 * 86_400)
        #expect(PositionCalculator.availableQuantity(at: at, trades: trades) == 6)
        #expect(PositionCalculator.availableQuantity(at: at, trades: trades, excluding: editing.id) == 10)
    }

    @Test func sameDayBuyBeforeSell() {
        // 같은 날짜면 매수를 먼저 재생 — 당일 매수분 매도 허용
        let snapshot = PositionCalculator.snapshot(trades: [
            trade(.sell, qty: 5, price: 120, day: 1),
            trade(.buy, qty: 10, price: 100, day: 1)
        ])
        #expect(snapshot.quantity == 5)
        #expect(snapshot.realizedPnL == 100)
    }
}
