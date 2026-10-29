import Foundation

/// 토스증권 계좌 → 가져오기 스냅샷.
public enum TossConnector {
    /// 다시 받을 때 겹쳐 받는 기간 — 늦게 끝난 주문도 놓치지 않게. 이미 가져온 체결은 플래너가 건너뛴다.
    static let overlap: TimeInterval = 7 * 86_400

    /// 동기화 한 번. `since`가 nil이면 계좌 개설 이후 주문 내역 전체를 받는다.
    /// 보유와 주문은 한 번에 받을 수 없다 — 받는 사이 체결이 끼면 보유와 이력이 어긋나 가짜 잔고 맞춤이 생기므로,
    /// 보유와 진행 중 주문을 앞뒤로 두 번 받아 그사이 움직인 종목은 이번엔 대조하지 않는다.
    public static func fetch(
        client: TossClient,
        sourceID: UUID,
        accountSeq: Int64,
        since: Date?,
        now: Date = Date()
    ) async throws -> SourceSnapshot {
        let from = since.map { $0.addingTimeInterval(-overlap) }
        let holdingsBefore = try await client.holdings(accountSeq: accountSeq)
        let openBefore = try await client.orders(accountSeq: accountSeq, group: .open)
        let closed = try await client.orders(accountSeq: accountSeq, group: .closed, from: from)
        let holdings = try await client.holdings(accountSeq: accountSeq)
        let openAfter = try await client.orders(accountSeq: accountSeq, group: .open)
        return snapshot(
            sourceID: sourceID, holdings: holdings, closed: closed, open: openBefore + openAfter,
            moving: movedSymbols(
                holdingsBefore: holdingsBefore, holdingsAfter: holdings,
                openBefore: openBefore, openAfter: openAfter
            ),
            from: from, now: now
        )
    }

    /// 두 번 받은 사이 보유 수량이 바뀌었거나 진행 중 주문이 생기고 끝난 종목.
    static func movedSymbols(
        holdingsBefore: [TossHolding],
        holdingsAfter: [TossHolding],
        openBefore: [TossOrder],
        openAfter: [TossOrder]
    ) -> Set<String> {
        let before = Dictionary(holdingsBefore.map { ($0.symbol, $0.quantity) }, uniquingKeysWith: +)
        let after = Dictionary(holdingsAfter.map { ($0.symbol, $0.quantity) }, uniquingKeysWith: +)
        let changedHoldings = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
        let openIDsBefore = Set(openBefore.map(\.orderID))
        let openIDsAfter = Set(openAfter.map(\.orderID))
        let changedOrders = (openBefore + openAfter)
            .filter { !openIDsBefore.contains($0.orderID) || !openIDsAfter.contains($0.orderID) }
            .map(\.symbol)
        return changedHoldings.union(changedOrders)
    }

    static func snapshot(
        sourceID: UUID,
        holdings: [TossHolding],
        closed: [TossOrder],
        open: [TossOrder],
        moving: Set<String> = [],
        from: Date?,
        now: Date
    ) -> SourceSnapshot {
        // 주문 내역엔 종목명이 없다 — 보유에 있는 이름을 쓴다.
        let names = Dictionary(holdings.map { ($0.symbol, $0.name) }, uniquingKeysWith: { first, _ in first })
        let currencies = Dictionary(
            (holdings.map { ($0.symbol, $0.currency) } + (closed + open).map { ($0.symbol, $0.currency) }),
            uniquingKeysWith: { first, _ in first }
        )
        func instrument(_ symbol: String, _ currency: String) -> ImportInstrument? {
            Self.instrument(symbol: symbol, currency: currency, name: names[symbol] ?? symbol)
        }

        let imported = holdings.compactMap { holding -> ImportedHolding? in
            guard let instrument = instrument(holding.symbol, holding.currency) else { return nil }
            return ImportedHolding(
                instrument: instrument, quantity: holding.quantity,
                averageCost: holding.averagePurchasePrice
            )
        }
        // 일부만 체결된 뒤 취소·정정된 주문도 체결분은 남는다. 취소·정정 거부는 원주문과 별도로 생기는 레코드라 뺀다.
        let executions = closed.compactMap { order -> ImportedExecution? in
            guard
                order.filledQuantity > 0,
                !order.status.hasSuffix("REJECTED"),
                let side = order.side,
                let price = order.averageFilledPrice,
                let instrument = instrument(order.symbol, order.currency)
            else { return nil }
            return ImportedExecution(
                externalID: order.orderID, instrument: instrument, side: side,
                quantity: order.filledQuantity, price: price,
                date: order.filledAt ?? order.orderedAt
            )
        }
        // 진행 중 주문의 체결분은 끝난 뒤에 한 건으로 들어온다 — 그때까지 그 종목은 대조하지 않는다.
        let filling = open.filter { $0.filledQuantity > 0 }.map(\.symbol)
        let unsettled = Set((filling + moving).compactMap { symbol in
            currencies[symbol].flatMap { instrument(symbol, $0) }
        })

        return SourceSnapshot(
            sourceID: sourceID,
            holdings: imported,
            executions: executions,
            historyStart: from ?? executions.map(\.date).min() ?? now,
            unsettled: unsettled,
            takenAt: now
        )
    }

    /// 원화 = 국내 주식, 달러 = 미국 주식. 미국 클래스 주식은 야후 표기("BRK-B")로 맞춘다.
    static func instrument(symbol: String, currency: String, name: String) -> ImportInstrument? {
        switch currency.uppercased() {
        case "KRW":
            return ImportInstrument(market: .koreaStock, symbol: symbol, name: name, currency: "KRW")
        case "USD":
            let ticker = symbol.replacingOccurrences(of: ".", with: "-")
            return ImportInstrument(market: .usStock, symbol: ticker, name: name, currency: "USD")
        default:
            return nil
        }
    }

    /// 표시용 계좌 요약 — 끝 4자리만 남긴다.
    public static func maskedAccount(_ accountNo: String) -> String {
        let digits = accountNo.filter(\.isNumber)
        return "••••" + String(digits.suffix(4))
    }
}
