import Foundation
import Testing
@testable import WeaveCore

private let samsung = ImportInstrument(market: .koreaStock, symbol: "005930", name: "삼성전자", currency: "KRW")
private let hynix = ImportInstrument(market: .koreaStock, symbol: "000660", name: "SK하이닉스", currency: "KRW")
private let penny = ImportInstrument(market: .crypto, symbol: "dust", name: "Dust", currency: "KRW")

private func date(_ value: String) -> Date {
    try! Date(value + "T01:00:00Z", strategy: .iso8601)
}

private func execution(_ id: String, _ instrument: ImportInstrument, _ side: TradeSide, _ quantity: Decimal, _ price: Decimal, _ day: String) -> ImportedExecution {
    ImportedExecution(externalID: id, instrument: instrument, side: side, quantity: quantity, price: price, date: date(day))
}

private func asset(_ instrument: ImportInstrument) -> Asset {
    Asset(name: instrument.name, symbol: instrument.symbol, provider: .naver, providerSymbol: instrument.symbol, market: instrument.market, currency: instrument.currency)
}

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

@Suite struct ImportTests {
    // 저장 형식(ISO8601)이 초 단위라 생성 시각도 초 단위로 둔다.
    let source = LinkedSource(kind: .koreaInvestment, name: "한국투자증권", label: "6412****-01", createdAt: date("2026-01-01"))

    private func document(assets: [Asset] = [], trades: [Trade] = []) -> PortfolioDocument {
        PortfolioDocument(assets: assets, trades: trades, sources: [source])
    }

    private func snapshot(holdings: [ImportedHolding] = [], executions: [ImportedExecution] = []) -> SourceSnapshot {
        SourceSnapshot(sourceID: source.id, holdings: holdings, executions: executions, historyStart: date("2026-01-01"))
    }

    // MARK: - 저장 형식

    @Test func oldDocumentWithoutSourcesStillDecodes() throws {
        let json = """
        {"version":2,"assets":[],"settings":{},
         "trades":[{"id":"\(UUID())","assetID":"\(UUID())","side":"buy","quantity":1,"price":2,"date":"2026-01-01T00:00:00Z","note":""}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PortfolioDocument.self, from: Data(json.utf8))
        #expect(decoded.sources.isEmpty)
        #expect(decoded.trades.first?.isImported == false)
        #expect(decoded.trades.first?.isOpeningBalance == false)
    }

    @Test func storageVersionStaysReadableForOldAppsUntilSomethingIsLinked() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        func version(_ doc: PortfolioDocument) throws -> Int? {
            let object = try JSONSerialization.jsonObject(with: encoder.encode(doc)) as? [String: Any]
            return object?["version"] as? Int
        }
        #expect(try version(PortfolioDocument()) == 2)
        #expect(try version(PortfolioDocument(sources: [source])) == 3)
        let imported = Trade(assetID: UUID(), side: .buy, quantity: 1, price: 1, sourceID: source.id, externalID: "E")
        #expect(try version(PortfolioDocument(trades: [imported])) == 3)
    }

    @Test func sourcesAndImportFieldsRoundTrip() throws {
        let trade = Trade(assetID: UUID(), side: .buy, quantity: 1, price: 2, sourceID: source.id, externalID: "E1", openingBalance: true)
        let original = PortfolioDocument(trades: [trade], sources: [source])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PortfolioDocument.self, from: encoder.encode(original))
        #expect(decoded.sources == original.sources)
        #expect(decoded.trades.first?.externalID == "E1")
        #expect(decoded.trades.first?.isImported == true)
        #expect(decoded.trades.first?.isOpeningBalance == true)
    }

    // MARK: - 계획

    @Test func skipsAlreadyImportedAndRepeatedExecutions() {
        let samsungAsset = asset(samsung)
        let imported = Trade(assetID: samsungAsset.id, side: .buy, quantity: 1, price: 70_000, date: date("2026-03-01"), sourceID: source.id, externalID: "E1")
        let plan = ImportPlanner.plan(
            snapshot: snapshot(
                holdings: [ImportedHolding(instrument: samsung, quantity: 3, averageCost: 70_000)],
                executions: [
                    execution("E1", samsung, .buy, 1, 70_000, "2026-03-01"),
                    execution("E2", samsung, .buy, 2, 70_000, "2026-03-02"),
                    execution("E2", samsung, .buy, 2, 70_000, "2026-03-02")
                ]
            ),
            document: document(assets: [samsungAsset], trades: [imported])
        )
        #expect(plan.trades.map(\.externalID) == ["E2"])
        #expect(plan.openingBalances.isEmpty)
        #expect(plan.mismatches.isEmpty)
    }

    @Test func findsManualTradeForTheSameExecutionAndMergesIt() {
        let samsungAsset = asset(samsung)
        let manual = Trade(assetID: samsungAsset.id, side: .buy, quantity: 20, price: 68_000, date: date("2026-03-14"))
        var doc = document(assets: [samsungAsset], trades: [manual])
        let plan = ImportPlanner.plan(
            snapshot: snapshot(
                holdings: [ImportedHolding(instrument: samsung, quantity: 20, averageCost: 68_400)],
                executions: [execution("E9", samsung, .buy, 20, 68_400, "2026-03-14")]
            ),
            document: doc,
            calendar: utc
        )
        #expect(plan.duplicates == [DuplicateCandidate(manualTradeID: manual.id, externalID: "E9")])

        let result = ImportApplier.apply(plan, to: &doc)
        #expect(result == ImportResult(added: 1, openingBalances: 0, merged: 1, skippedWithoutAsset: 0))
        #expect(doc.trades.count == 1)
        #expect(doc.trades.first?.externalID == "E9")
        #expect(doc.trades.first?.isImported == true)
    }

    @Test func manualTradeOnAnotherDayIsNotADuplicate() {
        let samsungAsset = asset(samsung)
        let manual = Trade(assetID: samsungAsset.id, side: .buy, quantity: 20, price: 68_400, date: date("2026-03-13"))
        let plan = ImportPlanner.plan(
            snapshot: snapshot(executions: [execution("E9", samsung, .buy, 20, 68_400, "2026-03-14")]),
            document: document(assets: [samsungAsset], trades: [manual]),
            calendar: utc
        )
        #expect(plan.duplicates.isEmpty)
    }

    @Test func openingBalanceUsesTheSourceAverageWhenThereIsNoHistory() {
        let plan = ImportPlanner.plan(
            snapshot: snapshot(holdings: [ImportedHolding(instrument: hynix, quantity: 8, averageCost: 298_500)]),
            document: document()
        )
        let opening = try! #require(plan.openingBalances.first)
        #expect(opening.quantity == 8)
        #expect(opening.price == 298_500)
        #expect(opening.date == date("2026-01-01").addingTimeInterval(-1))
        #expect(plan.missingAssets == [hynix])
    }

    @Test func openingBalanceCostMakesTheReplayedAverageMatchTheSource() {
        // 보유 10주, 소스 평단 80. 이력엔 4주 @100 매수와 1주 매도뿐 — 나머지 7주가 기초 잔고.
        let plan = ImportPlanner.plan(
            snapshot: snapshot(
                holdings: [ImportedHolding(instrument: hynix, quantity: 10, averageCost: 80)],
                executions: [
                    execution("B1", hynix, .buy, 4, 100, "2026-02-01"),
                    execution("S1", hynix, .sell, 1, 120, "2026-02-10")
                ]
            ),
            document: document()
        )
        let opening = try! #require(plan.openingBalances.first)
        #expect(opening.quantity == 7)
        #expect(opening.date < date("2026-01-01"))

        let replay = PositionCalculator.snapshot(trades: plan.trades.map { $0.asTrade(assetID: UUID()) })
        #expect(replay.quantity == 10)
        #expect(replay.averageCost.rounded(scale: 4) == 80)
    }

    @Test func sellOfSharesBoughtBeforeTheHistoryIsCoveredByTheOpeningBalance() {
        // 보유 10주인데 이력엔 5주 매도뿐 — 기간 전에 15주가 있었다.
        let plan = ImportPlanner.plan(
            snapshot: snapshot(
                holdings: [ImportedHolding(instrument: hynix, quantity: 10, averageCost: 80)],
                executions: [execution("S1", hynix, .sell, 5, 120, "2026-02-10")]
            ),
            document: document()
        )
        #expect(plan.mismatches.isEmpty)
        #expect(plan.openingBalances.first?.quantity == 15)
        let replay = PositionCalculator.snapshot(trades: plan.trades.map { $0.asTrade(assetID: UUID()) })
        #expect(replay.quantity == 10)
        #expect(replay.averageCost == 80)
    }

    @Test func historyThatDipsBelowZeroGoesToReview() {
        // 5주 팔고 3주 사서 1주 보유 — 기초 잔고 3주를 얹어도 매도 시점에 모자란다(이력에 없는 출금).
        let plan = ImportPlanner.plan(
            snapshot: snapshot(
                holdings: [ImportedHolding(instrument: hynix, quantity: 1, averageCost: 80)],
                executions: [
                    execution("S1", hynix, .sell, 5, 120, "2026-02-10"),
                    execution("B1", hynix, .buy, 3, 90, "2026-02-20")
                ]
            ),
            document: document()
        )
        #expect(plan.openingBalances.isEmpty)
        #expect(plan.mismatches.map(\.reason) == [.historyExceedsHolding])
    }

    @Test func manualTradesBlockAnAutomaticOpeningBalance() {
        let hynixAsset = asset(hynix)
        let manual = Trade(assetID: hynixAsset.id, side: .buy, quantity: 8, price: 250_000, date: date("2025-06-01"))
        let plan = ImportPlanner.plan(
            snapshot: snapshot(holdings: [ImportedHolding(instrument: hynix, quantity: 8, averageCost: 298_500)]),
            document: document(assets: [hynixAsset], trades: [manual])
        )
        #expect(plan.openingBalances.isEmpty)
        #expect(plan.mismatches == [HoldingMismatch(instrument: hynix, difference: 8, reason: .manualTradesMayOverlap)])
    }

    @Test func flagsHoldingsThatTheHistoryCannotExplain() {
        let plan = ImportPlanner.plan(
            snapshot: snapshot(
                holdings: [
                    ImportedHolding(instrument: samsung, quantity: 3, averageCost: 70_000),
                    ImportedHolding(instrument: hynix, quantity: 2, averageCost: nil)
                ],
                executions: [execution("B1", samsung, .buy, 5, 70_000, "2026-02-01")]
            ),
            document: document()
        )
        // 계좌가 원본 — 이력보다 적게 가진 만큼은 평단으로 팔아 맞추고, 평단이 없어 못 채운 건 사람이 본다.
        #expect(plan.mismatches.contains(HoldingMismatch(instrument: samsung, difference: -2, reason: .historyExceedsHolding, adjusted: true)))
        #expect(plan.mismatches.contains(HoldingMismatch(instrument: hynix, difference: 2, reason: .missingAverageCost)))
        #expect(plan.unresolved.map(\.instrument) == [hynix])
        #expect(plan.openingBalances.isEmpty)
        #expect(plan.adjustments.map(\.side) == [.sell])
        #expect(plan.adjustments.map(\.quantity) == [2])
        #expect(plan.adjustments.map(\.price) == [70_000])
        #expect(plan.newTradeCount == 1)
    }

    @Test func balanceAdjustmentIsAppliedOnceAndSettlesTheHolding() {
        let samsungAsset = asset(samsung)
        let snap = SourceSnapshot(
            sourceID: source.id,
            holdings: [ImportedHolding(instrument: samsung, quantity: 3, averageCost: 70_000)],
            executions: [execution("B1", samsung, .buy, 5, 70_000, "2026-02-01")],
            historyStart: date("2026-01-01"),
            takenAt: date("2026-03-01")
        )
        var doc = document(assets: [samsungAsset])
        let plan = ImportPlanner.plan(snapshot: snap, document: doc)
        ImportApplier.apply(plan, to: &doc)
        ImportApplier.apply(plan, to: &doc)

        let adjustments = doc.trades.filter(\.isBalanceAdjustment)
        #expect(adjustments.count == 1)
        #expect(adjustments.first?.isImported == true)
        #expect(adjustments.first?.date == date("2026-03-01"))
        #expect(PositionCalculator.snapshot(trades: doc.trades).quantity == 3)
        #expect(PositionCalculator.realizedPnL(of: adjustments[0], in: doc.trades) == 0)

        // 다음 동기화는 더 맞출 게 없다.
        let next = ImportPlanner.plan(snapshot: snap, document: doc)
        #expect(next.trades.isEmpty)
        #expect(next.mismatches.isEmpty)
    }

    @Test func holdingGrowthAfterTheOpeningBalanceIsAdjusted() {
        let hynixAsset = asset(hynix)
        let opening = Trade(assetID: hynixAsset.id, side: .buy, quantity: 8, price: 298_500, date: date("2025-12-31"), sourceID: source.id, openingBalance: true)
        let plan = ImportPlanner.plan(
            snapshot: snapshot(holdings: [ImportedHolding(instrument: hynix, quantity: 10, averageCost: 300_000)]),
            document: document(assets: [hynixAsset], trades: [opening])
        )
        // 기초 잔고 뒤의 입고·분할은 잔고 맞춤으로 채운다. 단가는 얹은 뒤 평단이 계좌 평단이 되게 정한다.
        #expect(plan.openingBalances.isEmpty)
        #expect(plan.mismatches == [HoldingMismatch(instrument: hynix, difference: 2, reason: .holdingExceedsHistory, adjusted: true)])
        #expect(plan.adjustments.map(\.side) == [.buy])
        #expect(plan.adjustments.map(\.price) == [306_000])
    }

    @Test func splitAfterImportKeepsTheAccountAverage() {
        // 10주 @1,000을 가져온 뒤 10:1 분할 — 계좌는 100주 @100.
        let hynixAsset = asset(hynix)
        let bought = Trade(assetID: hynixAsset.id, side: .buy, quantity: 10, price: 1_000, date: date("2026-02-01"), sourceID: source.id, externalID: "B1")
        var doc = document(assets: [hynixAsset], trades: [bought])
        let plan = ImportPlanner.plan(
            snapshot: SourceSnapshot(
                sourceID: source.id,
                holdings: [ImportedHolding(instrument: hynix, quantity: 100, averageCost: 100)],
                executions: [], historyStart: date("2026-02-20"), takenAt: date("2026-03-01")
            ),
            document: doc
        )
        // 첫 가져오기가 아니라서 이력 앞으로 소급되는 기초 잔고가 아니라 그 시점의 잔고 맞춤이 된다.
        #expect(plan.openingBalances.isEmpty)
        #expect(plan.adjustments.map(\.quantity) == [90])
        #expect(plan.adjustments.map(\.price) == [0])
        #expect(plan.adjustments.map(\.date) == [date("2026-03-01")])
        ImportApplier.apply(plan, to: &doc)
        let position = PositionCalculator.snapshot(trades: doc.trades)
        #expect(position.quantity == 100)
        #expect(position.averageCost == 100)
    }

    @Test func skipsDustUnlessTheAssetAlreadyExists() {
        let snapshot = snapshot(
            holdings: [ImportedHolding(instrument: penny, quantity: 3, averageCost: 10)],
            executions: [execution("D1", penny, .buy, 3, 10, "2026-02-01")]
        )
        let skipped = ImportPlanner.plan(snapshot: snapshot, document: document(), dust: [penny])
        #expect(skipped.trades.isEmpty)
        #expect(skipped.skippedDust == [penny])

        let kept = ImportPlanner.plan(snapshot: snapshot, document: document(assets: [asset(penny)]), dust: [penny])
        #expect(kept.trades.count == 1)
        #expect(kept.skippedDust.isEmpty)
    }

    // MARK: - 적용

    @Test func applyNeedsAnAssetAndResyncIsANoOp() {
        let snap = snapshot(
            holdings: [ImportedHolding(instrument: hynix, quantity: 10, averageCost: 80)],
            executions: [execution("B1", hynix, .buy, 4, 100, "2026-02-01")]
        )
        var doc = document()
        let plan = ImportPlanner.plan(snapshot: snap, document: doc)

        let withoutAsset = ImportApplier.apply(plan, to: &doc)
        #expect(withoutAsset.skippedWithoutAsset == 2)
        #expect(doc.trades.isEmpty)

        let hynixAsset = asset(hynix)
        doc.assets.append(hynixAsset)
        let now = date("2026-03-01")
        let result = ImportApplier.apply(plan, to: &doc, assetIDs: [hynix: hynixAsset.id], now: now)
        #expect(result == ImportResult(added: 1, openingBalances: 1, merged: 0, skippedWithoutAsset: 0))
        #expect(doc.trades.allSatisfy { $0.sourceID == source.id && $0.assetID == hynixAsset.id })
        #expect(doc.sources.first?.lastSyncedAt == now)

        // 같은 스냅샷을 다시 받아도 넣을 게 없다.
        let again = ImportPlanner.plan(snapshot: snap, document: doc)
        #expect(again.isEmpty)
        #expect(ImportApplier.apply(plan, to: &doc).added == 0)
        #expect(doc.trades.count == 2)
    }

    // MARK: - 보유 위치

    @Test func breakdownSplitsHoldingsBySource() {
        let assetID = UUID()
        let wallet = UUID()
        let trades = [
            Trade(assetID: assetID, side: .buy, quantity: 2, price: 1, date: date("2026-01-01"), sourceID: source.id, externalID: "A"),
            Trade(assetID: assetID, side: .sell, quantity: 0.5, price: 1, date: date("2026-01-02"), sourceID: source.id, externalID: "B"),
            Trade(assetID: assetID, side: .buy, quantity: 3, price: 1, date: date("2026-01-03"), sourceID: wallet, externalID: "C"),
            Trade(assetID: assetID, side: .buy, quantity: 9, price: 1, date: date("2026-01-04")),
            Trade(assetID: assetID, side: .buy, quantity: 1, price: 1, date: date("2026-01-05"), sourceID: UUID(), externalID: "D"),
            Trade(assetID: assetID, side: .sell, quantity: 1, price: 1, date: date("2026-01-06"), sourceID: nil)
        ]
        let locations = HoldingLocations.breakdown(trades: trades.filter { $0.externalID != "D" })
        #expect(locations == [
            HoldingLocation(sourceID: wallet, quantity: 3),
            HoldingLocation(sourceID: source.id, quantity: 1.5),
            HoldingLocation(sourceID: nil, quantity: 8)
        ])
    }
}
