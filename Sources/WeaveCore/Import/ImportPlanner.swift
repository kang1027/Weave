import Foundation

/// 소스가 알려준 종목 — 시장 + 표시 심볼("005930", "AAPL", "BTC").
public struct ImportInstrument: Hashable, Sendable {
    public var market: Market
    public var symbol: String
    public var name: String
    public var currency: String

    public init(market: Market, symbol: String, name: String, currency: String) {
        self.market = market
        self.symbol = symbol.uppercased()
        self.name = name
        self.currency = currency.uppercased()
    }

    /// 이름·통화 표기가 소스마다 달라도 같은 종목으로 본다.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.market == rhs.market && lhs.symbol == rhs.symbol
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(market)
        hasher.combine(symbol)
    }

    public func matches(_ asset: Asset) -> Bool {
        asset.market == market && asset.symbol.uppercased() == symbol
    }
}

/// 소스의 현재 보유. 평단은 소스가 주는 계좌 평단(없으면 nil).
public struct ImportedHolding: Equatable, Sendable {
    public var instrument: ImportInstrument
    public var quantity: Decimal
    public var averageCost: Decimal?
    /// 평단이 없는 지갑용 현재가 — 직접 입력분에서 못 채운 만큼의 원가.
    public var marketPrice: Decimal?

    public init(instrument: ImportInstrument, quantity: Decimal, averageCost: Decimal?, marketPrice: Decimal? = nil) {
        self.instrument = instrument
        self.quantity = quantity
        self.averageCost = averageCost
        self.marketPrice = marketPrice
    }
}

/// 소스의 체결 한 건. externalID는 소스 안에서 유일해야 한다.
public struct ImportedExecution: Equatable, Sendable {
    public var externalID: String
    public var instrument: ImportInstrument
    public var side: TradeSide
    public var quantity: Decimal
    public var price: Decimal
    public var date: Date

    public init(
        externalID: String,
        instrument: ImportInstrument,
        side: TradeSide,
        quantity: Decimal,
        price: Decimal,
        date: Date
    ) {
        self.externalID = externalID
        self.instrument = instrument
        self.side = side
        self.quantity = quantity
        self.price = price
        self.date = date
    }
}

/// 한 번 동기화에서 소스가 준 전부.
public struct SourceSnapshot: Sendable {
    public var sourceID: UUID
    public var holdings: [ImportedHolding]
    public var executions: [ImportedExecution]
    /// 체결 내역을 받아온 시작 시각 — 증권사 API는 조회 기간에 한도가 있다.
    public var historyStart: Date
    /// 아직 체결 중인 주문이 있는 종목 — 보유엔 들어갔지만 체결 내역엔 아직 없어 이번엔 대조하지 않는다.
    public var unsettled: Set<ImportInstrument>
    /// 보유를 받은 시각 — 잔고 맞춤 거래의 날짜.
    public var takenAt: Date
    /// 지갑 — 체결 기록 없이 잔고만 있다. 늘고 준 만큼을 직접 입력분과 평단 그대로 주고받는다.
    public var inheritsManualHoldings: Bool
    /// 소액 잔고 — 이 소스가 아직 안 가진 종목이면 새로 들이지 않는다(이미 가진 종목은 그대로 대조해서 경계에서 오락가락하지 않는다).
    public var dust: Set<ImportInstrument>
    /// 지갑 — 이보다 작은 변화(시세 기준)는 기록하지 않고 쌓이게 둔다. 이자가 붙는 토큰이 매번 거래를 남기지 않게.
    public var minimumChangeValue: Decimal

    public init(
        sourceID: UUID,
        holdings: [ImportedHolding],
        executions: [ImportedExecution],
        historyStart: Date,
        unsettled: Set<ImportInstrument> = [],
        takenAt: Date = Date(),
        inheritsManualHoldings: Bool = false,
        dust: Set<ImportInstrument> = [],
        minimumChangeValue: Decimal = 0
    ) {
        self.sourceID = sourceID
        self.holdings = holdings
        self.executions = executions
        self.historyStart = historyStart
        self.unsettled = unsettled
        self.takenAt = takenAt
        self.inheritsManualHoldings = inheritsManualHoldings
        self.dust = dust
        self.minimumChangeValue = minimumChangeValue
    }
}

/// 문서에 넣을 거래 한 건(자산 ID는 적용 단계에서 정해진다).
public struct PlannedTrade: Equatable, Sendable {
    public var instrument: ImportInstrument
    public var side: TradeSide
    public var quantity: Decimal
    public var price: Decimal
    public var date: Date
    /// 기초 잔고면 nil.
    public var externalID: String?
    /// 잔고 맞춤 — 계좌 보유와 이력의 차이를 메우는 거래.
    public var isAdjustment = false
    /// 직접 입력분과 지갑 사이 이동 — 지갑 쪽과 직접 입력 쪽 두 건이 짝으로 들어간다.
    public var isTransfer = false
    /// 이동의 직접 입력 쪽(문서엔 sourceID 없이 들어간다).
    public var isManualSide = false

    public var isOpeningBalance: Bool { externalID == nil }
}

/// 직접 입력한 거래와 같은 체결로 보이는 짝 — 기본은 가져온 기록으로 합친다.
public struct DuplicateCandidate: Equatable, Sendable {
    public var manualTradeID: UUID
    public var externalID: String
}

/// 사용자가 확인해야 하는 보유 불일치.
public struct HoldingMismatch: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// 받아온 체결로 계산한 보유가 실제 보유보다 많다 — 출금·이체 등 이력에 없는 움직임.
        case historyExceedsHolding
        /// 기초 잔고가 필요한데 소스가 평단을 주지 않았다.
        case missingAverageCost
        /// 이 계좌에서 이미 가져온 거래가 있는데 보유가 이력보다 많다 — 입고·분할 등 이력에 없는 움직임.
        case holdingExceedsHistory
        /// 직접 입력한 거래가 있어 기초 잔고와 겹칠 수 있다 — 조회 기간 전 매수를 손으로 넣어 둔 경우 등.
        case manualTradesMayOverlap
    }

    public var instrument: ImportInstrument
    /// 실제 보유 − 체결로 계산한 보유.
    public var difference: Decimal
    public var reason: Reason
    /// 잔고 맞춤으로 계좌 보유에 맞췄는지 — 아니면 사람이 봐야 한다.
    public var adjusted = false
}

public struct ImportPlan: Equatable, Sendable {
    public var sourceID: UUID
    /// 새 체결 + 기초 잔고.
    public var trades: [PlannedTrade]
    public var duplicates: [DuplicateCandidate]
    public var mismatches: [HoldingMismatch]
    /// 소액이라 건너뛴 종목(이미 자산으로 있는 종목은 건너뛰지 않는다).
    public var skippedDust: [ImportInstrument]
    /// 지금은 없고 자산도 없는 종목 — 다 팔고 끝난 지난 거래는 가져오지 않는다.
    public var closedPositions: [ImportInstrument]
    /// 아직 자산이 없는 종목 — 적용 전에 자산을 만들어야 한다.
    public var missingAssets: [ImportInstrument]

    public var newTradeCount: Int { trades.filter { !$0.isOpeningBalance && !$0.isAdjustment && !$0.isTransfer }.count }
    /// 직접 입력분과 지갑 사이 이동(지갑 쪽).
    public var transfers: [PlannedTrade] { trades.filter { $0.isTransfer && !$0.isManualSide } }
    public var openingBalances: [PlannedTrade] { trades.filter(\.isOpeningBalance) }
    public var adjustments: [PlannedTrade] { trades.filter(\.isAdjustment) }
    /// 자동으로 맞추지 못해 사람이 봐야 하는 차이.
    public var unresolved: [HoldingMismatch] { mismatches.filter { !$0.adjusted } }
    public var isEmpty: Bool { trades.isEmpty && duplicates.isEmpty && mismatches.isEmpty }
}

/// 동기화 결과를 문서와 맞대서 무엇을 넣을지 정한다. 문서는 바꾸지 않는다.
public enum ImportPlanner {
    /// - dust: 소액이라 숨길 종목 — 시세가 필요해서 호출부가 고른다.
    /// - calendar: 직접 입력 거래와 같은 날인지 볼 달력(사용자 달력).
    public static func plan(
        snapshot: SourceSnapshot,
        document: PortfolioDocument,
        dust: Set<ImportInstrument> = [],
        calendar: Calendar = .current,
        onlyDecreases: Bool = false
    ) -> ImportPlan {
        let sourceID = snapshot.sourceID
        let assetFor: (ImportInstrument) -> Asset? = { instrument in
            document.assets.first(where: instrument.matches)
        }
        let heldBySource = Set(document.trades.filter { $0.sourceID == sourceID }.map(\.assetID))
        let skipped = dust.filter { assetFor($0) == nil }
            .union(snapshot.dust.filter { instrument in
                assetFor(instrument).map { !heldBySource.contains($0.id) } ?? true
            })
        let held = Set(snapshot.holdings.filter { $0.quantity > 0 }.map(\.instrument))
        let closed = Set(snapshot.executions.map(\.instrument)).filter { !held.contains($0) && assetFor($0) == nil }

        // 1) 이미 가져온 체결과 같은 스냅샷 안의 중복은 건너뛴다.
        let imported = Set(
            document.trades.filter { $0.sourceID == sourceID }.compactMap(\.externalID)
        )
        var seen = Set<String>()
        let executions = snapshot.executions
            .filter { !skipped.contains($0.instrument) && !closed.contains($0.instrument) }
            .filter { !imported.contains($0.externalID) && seen.insert($0.externalID).inserted }
            .sorted { $0.date < $1.date }

        // 2) 직접 입력한 같은 체결 찾기 — 같은 자산·방향·수량, 같은 날, 단가 1% 이내.
        var claimedManual = Set<UUID>()
        var duplicates: [DuplicateCandidate] = []
        for execution in executions {
            guard let asset = assetFor(execution.instrument) else { continue }
            let match = document.trades.first { trade in
                trade.assetID == asset.id
                    && !trade.isLocked
                    && !claimedManual.contains(trade.id)
                    && trade.side == execution.side
                    && trade.quantity == execution.quantity
                    && calendar.isDate(trade.date, inSameDayAs: execution.date)
                    && isClose(trade.price, execution.price, tolerance: Decimal(string: "0.01")!)
            }
            if let match {
                claimedManual.insert(match.id)
                duplicates.append(DuplicateCandidate(manualTradeID: match.id, externalID: execution.externalID))
            }
        }

        var trades = executions.map {
            PlannedTrade(
                instrument: $0.instrument, side: $0.side, quantity: $0.quantity,
                price: $0.price, date: $0.date, externalID: $0.externalID
            )
        }

        // 3) 보유와 이력 맞추기 — 이 소스의 기존 거래 + 새 체결을 재생해 보유와 비교한다.
        var mismatches: [HoldingMismatch] = []
        let existingBySource = document.trades.filter { $0.sourceID == sourceID }
        var instruments: [ImportInstrument] = snapshot.holdings.map(\.instrument)
        for instrument in executions.map(\.instrument) + existingBySource.compactMap({ trade in
            document.assets.first { $0.id == trade.assetID }.map {
                ImportInstrument(market: $0.market, symbol: $0.symbol, name: $0.name, currency: $0.currency)
            }
        }) where !instruments.contains(instrument) {
            instruments.append(instrument)
        }

        for instrument in instruments where !skipped.contains(instrument) && !snapshot.unsettled.contains(instrument) {
            let holding = snapshot.holdings.first { $0.instrument == instrument }
            let existing = assetFor(instrument).map { asset in
                existingBySource.filter { $0.assetID == asset.id }
            } ?? []
            // 재생용이라 자산 ID는 아무 값이나 쓴다 — PositionCalculator는 보지 않는다.
            let history = existing + trades.filter { $0.instrument == instrument }.map { $0.asTrade(assetID: UUID()) }
            // 매도를 보유로 자르지 않은 순수량 — 기간 전에 산 걸 기간 안에 판 만큼도 기초 잔고로 채워야 한다.
            let net = history.reduce(Decimal(0)) { $0 + ($1.side == .buy ? $1.quantity : -$1.quantity) }
            let gap = (holding?.quantity ?? 0) - net
            func flag(_ reason: HoldingMismatch.Reason, adjusted: Bool = false) {
                mismatches.append(HoldingMismatch(instrument: instrument, difference: gap, reason: reason, adjusted: adjusted))
            }
            func adjust(_ side: TradeSide, _ quantity: Decimal, at price: Decimal) {
                // 계좌가 원본 — 같은 동기화를 두 번 적용해도 한 번만 들어가게 받은 시각(ms)으로 ID를 만든다.
                // 초 단위면 연달아 누른 두 동기화가 같은 ID가 돼서 뒤의 것이 빠진다.
                let stamp = Int(snapshot.takenAt.timeIntervalSince1970 * 1000)
                trades.append(PlannedTrade(
                    instrument: instrument, side: side, quantity: quantity, price: price,
                    date: snapshot.takenAt, externalID: "adjust:\(instrument.symbol):\(stamp)", isAdjustment: true
                ))
            }
            // 지갑 — 매수 기록이 없다. 들어온 만큼은 직접 입력분에서 평단 그대로 옮겨 오고, 모자라면 그때 시세로 잡는다.
            // 나간 만큼은 직접 입력분으로 평단 그대로 돌려놓는다 — 거래소로 옮겨 팔면 그 매도를 직접 입력하면 된다.
            if snapshot.inheritsManualHoldings {
                // 이미 가진 코인의 작은 변화(이자 등)는 쌓였다가 한 번에 기록한다. 다 빠져나간 건(시세 없음) 바로 기록한다.
                if !existing.isEmpty, let price = holding?.marketPrice, abs(gap) * price < snapshot.minimumChangeValue {
                    continue
                }
                let stamp = Int(snapshot.takenAt.timeIntervalSince1970 * 1000)
                // side는 지갑 쪽 방향. 직접 입력 쪽은 반대 방향으로 같은 수량·단가가 들어간다.
                func move(_ side: TradeSide, _ quantity: Decimal, at price: Decimal) {
                    trades.append(PlannedTrade(
                        instrument: instrument, side: side, quantity: quantity, price: price, date: snapshot.takenAt,
                        externalID: "move:\(instrument.symbol):\(stamp)", isTransfer: true
                    ))
                    trades.append(PlannedTrade(
                        instrument: instrument, side: side == .buy ? .sell : .buy, quantity: quantity, price: price,
                        date: snapshot.takenAt, externalID: "move-manual:\(instrument.symbol):\(stamp)",
                        isTransfer: true, isManualSide: true
                    ))
                }
                if gap < 0 {
                    move(.sell, -gap, at: PositionCalculator.snapshot(trades: history).averageCost)
                } else if gap > 0, !onlyDecreases {
                    let manual = assetFor(instrument).map { asset in
                        document.trades.filter { $0.assetID == asset.id && $0.sourceID == nil }
                    } ?? []
                    let manualPosition = PositionCalculator.snapshot(trades: manual)
                    let moved = min(gap, max(0, manualPosition.quantity))
                    if moved > 0 {
                        move(.buy, moved, at: manualPosition.averageCost)
                    }
                    let rest = gap - moved
                    if rest > 0 {
                        guard let price = holding?.marketPrice, price > 0 else {
                            flag(.missingAverageCost)
                            continue
                        }
                        if existing.isEmpty {
                            trades.append(PlannedTrade(
                                instrument: instrument, side: .buy, quantity: rest, price: price,
                                date: snapshot.takenAt.addingTimeInterval(-1), externalID: nil
                            ))
                        } else {
                            adjust(.buy, rest, at: price)
                        }
                    }
                }
                continue
            }
            if gap < 0 {
                // 이력에 없는 출고·시간외 매도 — 줄어든 만큼 평단으로 팔아 실현손익 없이 계좌 보유에 맞춘다.
                // 중간에 이미 마이너스가 되는 이력은 끝에서 맞춰도 틀리니 사람이 본다.
                let consistent = PositionCalculator.firstOversell(in: history) == nil
                if consistent {
                    adjust(.sell, -gap, at: PositionCalculator.snapshot(trades: history).averageCost)
                }
                flag(.historyExceedsHolding, adjusted: consistent)
                continue
            }
            guard gap > 0 else {
                // 수량은 맞아도 중간에 가진 것보다 많이 판 기록이 있으면 이력이 빠진 것이다.
                if PositionCalculator.firstOversell(in: history) != nil { flag(.historyExceedsHolding) }
                continue
            }
            // 기초 잔고는 첫 가져오기에만 — 이미 가져온 거래 뒤에 생긴 입고·분할은 그 시점의 잔고 맞춤으로 채운다.
            // 기초 잔고로 넣으면 이력 맨 앞으로 소급돼 지난 차트와 실현손익이 바뀐다.
            if !existing.isEmpty {
                adjust(.buy, gap, at: adjustmentCost(gap: gap, history: history, targetAverage: holding?.averageCost))
                flag(.holdingExceedsHistory, adjusted: true)
                continue
            }
            if let asset = assetFor(instrument), document.trades.contains(where: {
                $0.assetID == asset.id && !$0.isLocked && !claimedManual.contains($0.id)
            }) {
                flag(.manualTradesMayOverlap)
                continue
            }
            guard let averageCost = holding?.averageCost, averageCost > 0 else {
                flag(.missingAverageCost)
                continue
            }
            let date = min(history.map(\.date).min() ?? snapshot.historyStart, snapshot.historyStart)
                .addingTimeInterval(-1)
            let opening = Trade(
                assetID: UUID(), side: .buy, quantity: gap,
                price: openingCost(gap: gap, history: history, targetAverage: averageCost), date: date
            )
            // 기초 잔고를 얹어도 중간에 마이너스가 되면 이력에 없는 출금이 있다.
            if PositionCalculator.firstOversell(in: [opening] + history) != nil {
                flag(.historyExceedsHolding)
                continue
            }
            trades.append(PlannedTrade(
                instrument: instrument, side: .buy, quantity: gap,
                price: opening.price, date: date, externalID: nil
            ))
        }

        let missing = uniqued(trades.map(\.instrument)).filter { assetFor($0) == nil }
        return ImportPlan(
            sourceID: sourceID,
            trades: trades.sorted { $0.date < $1.date },
            duplicates: duplicates,
            mismatches: mismatches,
            skippedDust: skipped.sorted { $0.symbol < $1.symbol },
            closedPositions: closed.sorted { $0.symbol < $1.symbol },
            missingAssets: missing
        )
    }

    /// 기초 잔고 단가 — 이후 체결을 재생했을 때 평단이 소스 평단과 같아지게 역산한다.
    /// 이동평균이라 최종 평단은 시작 단가 c의 1차식(α·c + β)이다.
    static func openingCost(gap: Decimal, history: [Trade], targetAverage: Decimal) -> Decimal {
        let start = (history.map(\.date).min() ?? Date()).addingTimeInterval(-1)
        func finalAverage(_ cost: Decimal) -> Decimal {
            let opening = Trade(assetID: UUID(), side: .buy, quantity: gap, price: cost, date: start)
            return PositionCalculator.snapshot(trades: [opening] + history).averageCost
        }
        let beta = finalAverage(0)
        let alpha = finalAverage(1) - beta
        guard alpha > 0 else { return targetAverage }
        // 이력 단가가 소스 평단보다 높으면(분할 등) 음수가 나온다 — 평단이 c에 따라 늘어나니 0이 가장 가깝다.
        return max(0, (targetAverage - beta) / alpha).rounded(scale: 8)
    }

    /// 늘어난 수량의 단가 — 얹은 뒤 평단이 소스 평단과 같아지게 한다(분할이면 0). 소스 평단이 없으면 지금 평단.
    static func adjustmentCost(gap: Decimal, history: [Trade], targetAverage: Decimal?) -> Decimal {
        let position = PositionCalculator.snapshot(trades: history)
        guard let targetAverage, targetAverage > 0 else { return position.averageCost }
        let cost = (targetAverage * (position.quantity + gap) - position.quantity * position.averageCost) / gap
        return max(0, cost).rounded(scale: 8)
    }

    private static func isClose(_ lhs: Decimal, _ rhs: Decimal, tolerance: Decimal) -> Bool {
        guard rhs != 0 else { return lhs == 0 }
        return abs(lhs - rhs) / abs(rhs) <= tolerance
    }

    private static func uniqued(_ instruments: [ImportInstrument]) -> [ImportInstrument] {
        var seen = Set<ImportInstrument>()
        return instruments.filter { seen.insert($0).inserted }
    }
}

extension PlannedTrade {
    /// 문서에 넣을 거래. 이동의 직접 입력 쪽은 sourceID 없이 직접 입력분에 들어가고 이동 표시만 남는다.
    func asTrade(assetID: UUID, sourceID: UUID? = nil) -> Trade {
        Trade(
            assetID: assetID, side: side, quantity: quantity, price: price, date: date,
            sourceID: isManualSide ? nil : sourceID, externalID: externalID,
            openingBalance: isOpeningBalance ? true : nil,
            balanceAdjustment: isAdjustment ? true : nil,
            transferSourceID: isTransfer ? sourceID : nil
        )
    }
}
