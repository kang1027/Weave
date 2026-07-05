import Foundation
import WeaveCore

extension AppModel {
    enum TradeError: Error, Equatable {
        case exceedsHolding(available: Decimal)
        case invalidInput
    }

    /// 거래 추가/수정 공통 검증 — 매도는 그 시점 보유 수량 초과 불가.
    func validateTrade(
        assetID: UUID,
        side: TradeSide,
        quantity: Decimal,
        price: Decimal,
        date: Date,
        editingID: UUID? = nil
    ) -> TradeError? {
        guard quantity > 0, price >= 0 else { return .invalidInput }
        if side == .sell {
            let available = PositionCalculator.availableQuantity(
                at: date,
                trades: document.trades(for: assetID),
                excluding: editingID
            )
            if quantity > available {
                return .exceedsHolding(available: available)
            }
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
