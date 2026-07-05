import Foundation
import WeaveCore

extension AppModel {
    enum TradeError: Error, Equatable {
        case exceedsHolding(available: Decimal)
        case invalidInput
    }

    /// 거래 추가/수정 공통 검증 — 매도는 그 시점 보유 수량 초과 불가.
    /// 과거 날짜 삽입/수정으로 "이후 매도"가 무효화되는 것도 전체 재생으로 막는다.
    func validateTrade(
        assetID: UUID,
        side: TradeSide,
        quantity: Decimal,
        price: Decimal,
        date: Date,
        editingID: UUID? = nil
    ) -> TradeError? {
        guard quantity > 0, price >= 0 else { return .invalidInput }

        let existing = document.trades(for: assetID).filter { $0.id != editingID }
        if side == .sell {
            let available = PositionCalculator.availableQuantity(at: date, trades: existing)
            if quantity > available {
                return .exceedsHolding(available: available)
            }
        }

        // 변경 반영 후 히스토리 전체가 일관된지 확인.
        // 단, 기존 데이터에 이미 있던 모순까지 새 입력 탓으로 돌리지는 않는다.
        let candidate = Trade(
            id: editingID ?? UUID(), assetID: assetID, side: side,
            quantity: quantity, price: price, date: date
        )
        if PositionCalculator.firstOversell(in: existing) == nil,
           let oversell = PositionCalculator.firstOversell(in: existing + [candidate]) {
            let available = PositionCalculator.availableQuantity(
                at: oversell.date, trades: existing
            )
            return .exceedsHolding(available: max(0, available))
        }
        return nil
    }

    @discardableResult
    func addTrade(
        assetID: UUID,
        side: TradeSide,
        quantity: Decimal,
        price: Decimal,
        date: Date,
        note: String
    ) -> TradeError? {
        if let error = validateTrade(
            assetID: assetID, side: side, quantity: quantity, price: price, date: date
        ) {
            return error
        }
        let trade = Trade(
            assetID: assetID, side: side, quantity: quantity,
            price: price, date: date, note: note
        )
        document.trades.append(trade)
        persist()
        invalidateHomeChart()
        return nil
    }

    @discardableResult
    func updateTrade(_ trade: Trade) -> TradeError? {
        if let error = validateTrade(
            assetID: trade.assetID, side: trade.side, quantity: trade.quantity,
            price: trade.price, date: trade.date, editingID: trade.id
        ) {
            return error
        }
        guard let index = document.trades.firstIndex(where: { $0.id == trade.id }) else {
            return .invalidInput
        }
        document.trades[index] = trade
        persist()
        invalidateHomeChart()
        return nil
    }

    func deleteTrade(id: UUID) {
        document.trades.removeAll { $0.id == id }
        persist()
        invalidateHomeChart()
    }

    /// 과거 날짜 선택 시 그날 종가 프리필 — 캔들 캐시 활용.
    func closingPrice(assetID: UUID, on date: Date) async -> Decimal? {
        guard let asset = asset(id: assetID), !asset.isManual else { return nil }
        guard let candles = try? await candleService.candles(
            provider: asset.provider,
            providerSymbol: asset.providerSymbol,
            interval: .day
        ) else {
            return nil
        }
        return SeriesLookupBox(candles: candles).value(onOrBefore: date)
    }

    /// 특정 매도 거래의 실현손익(자산 통화).
    func realizedPnL(of trade: Trade) -> Decimal? {
        PositionCalculator.realizedPnL(of: trade, in: document.trades(for: trade.assetID))
    }
}

/// WeaveCore 내부 SeriesLookup을 앱에서 재사용하기 위한 얇은 헬퍼.
struct SeriesLookupBox {
    private let sorted: [Candle]

    init(candles: [Candle]) {
        self.sorted = candles.sorted { $0.date < $1.date }
    }

    func value(onOrBefore date: Date) -> Decimal? {
        let cutoff = Calendar.current.startOfDay(for: date).addingTimeInterval(86_400 - 1)
        return sorted.last { $0.date <= cutoff }?.close ?? sorted.first?.close
    }
}
