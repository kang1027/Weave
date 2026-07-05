import Foundation

/// 거래 내역에서 파생되는 포지션 상태 — 평단은 이동평균법.
public struct PositionSnapshot: Equatable, Sendable {
    public var quantity: Decimal
    /// 이동평균 평단. 보유 0이면 0.
    public var averageCost: Decimal
    /// 실현손익 누계(자산 통화).
    public var realizedPnL: Decimal
    public var buyCount: Int
    public var sellCount: Int
    public var firstBuyDate: Date?

    public var costBasis: Decimal { quantity * averageCost }

    public init(
        quantity: Decimal = 0,
        averageCost: Decimal = 0,
        realizedPnL: Decimal = 0,
        buyCount: Int = 0,
        sellCount: Int = 0,
        firstBuyDate: Date? = nil
    ) {
        self.quantity = quantity
        self.averageCost = averageCost
        self.realizedPnL = realizedPnL
        self.buyCount = buyCount
        self.sellCount = sellCount
        self.firstBuyDate = firstBuyDate
    }
}

public enum PositionCalculator {
    /// 날짜순으로 거래를 재생해 스냅샷을 만든다.
    /// 매수: 평단 = (기존원가 + 체결금액) / 총수량. 매도: 실현손익 += (단가 − 평단) × 수량, 평단 유지.
    public static func snapshot(trades: [Trade]) -> PositionSnapshot {
        var state = PositionSnapshot()
        for trade in sorted(trades) {
            switch trade.side {
            case .buy:
                let newQuantity = state.quantity + trade.quantity
                if newQuantity > 0 {
                    state.averageCost =
                        (state.averageCost * state.quantity + trade.price * trade.quantity) / newQuantity
                }
                state.quantity = newQuantity
                state.buyCount += 1
                if state.firstBuyDate == nil {
                    state.firstBuyDate = trade.date
                }
            case .sell:
                let sellQuantity = min(trade.quantity, state.quantity)
                state.realizedPnL += (trade.price - state.averageCost) * sellQuantity
                state.quantity -= sellQuantity
                state.sellCount += 1
                if state.quantity == 0 {
                    state.averageCost = 0
                }
            }
        }
        return state
    }

    /// 특정 매도 거래의 실현손익 — 그 매도 "직전"까지 재생한 평단 기준.
    public static func realizedPnL(of sellTrade: Trade, in trades: [Trade]) -> Decimal? {
        guard sellTrade.side == .sell else { return nil }
        let ordered = sorted(trades)
        guard let index = ordered.firstIndex(where: { $0.id == sellTrade.id }) else { return nil }
        let before = snapshot(trades: Array(ordered[..<index]))
        let sellQuantity = min(sellTrade.quantity, before.quantity)
        return (sellTrade.price - before.averageCost) * sellQuantity
    }

    /// 해당 날짜(포함)까지의 보유 수량 — 가치 시계열용 스텝 함수.
    public static func quantity(onOrBefore date: Date, trades: [Trade]) -> Decimal {
        var quantity: Decimal = 0
        for trade in sorted(trades) where trade.date <= date {
            switch trade.side {
            case .buy: quantity += trade.quantity
            case .sell: quantity -= min(trade.quantity, quantity)
            }
        }
        return quantity
    }

    /// 매도 입력 검증용 — 이 거래를 반영하기 "직전" 보유 수량.
    /// `excluding`은 수정 중인 기존 거래(자기 자신 제외).
    public static func availableQuantity(
        at date: Date,
        trades: [Trade],
        excluding excludedID: UUID? = nil
    ) -> Decimal {
        let filtered = trades.filter { $0.id != excludedID }
        return quantity(onOrBefore: date, trades: filtered)
    }

    /// 히스토리 전체를 재생해 보유량을 초과하는 첫 매도를 찾는다.
    /// 앞 날짜에 매도를 끼워 넣어 "뒤 매도"가 무효가 되는 케이스를 잡는 데 쓴다.
    public static func firstOversell(in trades: [Trade]) -> Trade? {
        var quantity: Decimal = 0
        for trade in sorted(trades) {
            switch trade.side {
            case .buy:
                quantity += trade.quantity
            case .sell:
                if trade.quantity > quantity {
                    return trade
                }
                quantity -= trade.quantity
            }
        }
        return nil
    }

    /// 재생 순서: 날짜 → (같은 날짜면) 매수 먼저 → id 안정 정렬.
    static func sorted(_ trades: [Trade]) -> [Trade] {
        trades.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.side != rhs.side { return lhs.side == .buy }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
