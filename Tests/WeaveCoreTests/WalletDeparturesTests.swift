import Foundation
import Testing
@testable import WeaveCore

private func day(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value + "T00:00:00Z")!
}

private func usdc(_ symbol: String) -> (ImportInstrument, Asset) {
    (
        ImportInstrument(market: .crypto, symbol: symbol, name: symbol, currency: "USD"),
        Asset(name: symbol, symbol: symbol, provider: .binance, providerSymbol: "\(symbol)USDT", market: .crypto, currency: "USD")
    )
}

private func snapshot(_ sourceID: UUID, _ holdings: [(ImportInstrument, Decimal)], on value: String) -> SourceSnapshot {
    SourceSnapshot(
        sourceID: sourceID,
        holdings: holdings.map { ImportedHolding(instrument: $0.0, quantity: $0.1, averageCost: nil, marketPrice: 1) },
        executions: [], historyStart: day(value), takenAt: day(value), inheritsManualHoldings: true
    )
}

private func position(_ document: PortfolioDocument, _ assetID: UUID) -> PositionSnapshot {
    PortfolioCalculator.compute(assets: document.assets, trades: document.trades, quotes: [:], fxRates: ["USD": 1], baseCurrency: "USD")
        .perAsset.first { $0.asset.id == assetID }!.position
}

private func manual(_ document: PortfolioDocument, _ assetID: UUID) -> Decimal {
    PositionCalculator.snapshot(trades: document.trades.filter { $0.assetID == assetID && $0.sourceID == nil }).quantity
}

@Suite struct WalletDeparturesTests {
    @Test func swappingThroughTokensAndSendingOutLeavesNothingBehind() {
        let wallet = LinkedSource(kind: .evmWallet, name: "Crypto", label: "0x…")
        let (stk, stkAsset) = usdc("STK")
        let (aToken, aAsset) = usdc("AUSDC")
        let (plain, plainAsset) = usdc("USDC")
        var doc = PortfolioDocument(assets: [stkAsset, aAsset, plainAsset], sources: [wallet])
        func sync(_ holdings: [(ImportInstrument, Decimal)], on value: String) {
            ImportApplier.apply(ImportPlanner.plan(snapshot: snapshot(wallet.id, holdings, on: value), document: doc), to: &doc)
            WalletDepartures.settle(&doc)
        }
        sync([(stk, 3_000)], on: "2026-10-01")
        // 스테이킹 2,000을 풀어 aToken으로, 그걸 다시 USDC로, 그 USDC를 지갑 밖으로 보냈다.
        sync([(stk, 1_000), (aToken, 2_000)], on: "2026-11-01")
        sync([(stk, 1_000), (plain, 2_000)], on: "2026-11-02")
        sync([(stk, 1_000)], on: "2026-11-03")

        #expect(position(doc, stkAsset.id).quantity == 1_000)
        #expect(position(doc, aAsset.id).quantity == 0)
        #expect(position(doc, plainAsset.id).quantity == 0)
        for asset in [stkAsset, aAsset, plainAsset] {
            #expect(manual(doc, asset.id) == 0)
            #expect(position(doc, asset.id).realizedPnL == 0)
        }
        #expect(!doc.trades.contains { $0.isTransfer })
        // 같은 잔고로 다시 동기화해도 바뀌지 않는다.
        let settled = doc.trades
        sync([(stk, 1_000)], on: "2026-11-04")
        #expect(doc.trades == settled)
    }

    @Test func onlyWhatCameFromManualGoesBackThere() {
        let wallet = LinkedSource(kind: .evmWallet, name: "Crypto", label: "0x…")
        let (coin, asset) = usdc("USDC")
        // 직접 입력 100을 지갑으로 옮겼고, 지갑엔 그 밖에 50이 더 들어왔다.
        var doc = PortfolioDocument(assets: [asset], trades: [
            Trade(assetID: asset.id, side: .buy, quantity: 100, price: 1, date: day("2026-01-01"))
        ], sources: [wallet])
        for (quantity, value) in [(Decimal(150), "2026-02-01"), (Decimal(0), "2026-03-01")] {
            ImportApplier.apply(ImportPlanner.plan(snapshot: snapshot(wallet.id, [(coin, quantity)], on: value), document: doc), to: &doc)
            WalletDepartures.settle(&doc)
        }
        // 다 내보냈다 — 직접 입력에서 온 100은 돌아오고 지갑에 새로 들어온 50만 빠진다.
        #expect(manual(doc, asset.id) == 100)
        #expect(position(doc, asset.id).quantity == 100)
        #expect(doc.trades.filter { $0.isBalanceAdjustment && $0.side == .sell }.map(\.quantity) == [50])
    }

    @Test func returnedCoinsAlreadySoldByHandStayAsTheyAre() {
        let wallet = LinkedSource(kind: .evmWallet, name: "Crypto", label: "0x…")
        let (_, asset) = usdc("USDC")
        // 예전 방식으로 직접 입력분에 돌아온 100을 직접 팔았다.
        let doc = PortfolioDocument(assets: [asset], trades: [
            Trade(assetID: asset.id, side: .buy, quantity: 100, price: 1, date: day("2026-01-01"), sourceID: wallet.id, openingBalance: true),
            Trade(assetID: asset.id, side: .sell, quantity: 100, price: 1, date: day("2026-02-01"), sourceID: wallet.id,
                  externalID: "move:USDC:1", transferSourceID: wallet.id),
            Trade(assetID: asset.id, side: .buy, quantity: 100, price: 1, date: day("2026-02-01"),
                  externalID: "move-manual:USDC:1", transferSourceID: wallet.id),
            Trade(assetID: asset.id, side: .sell, quantity: 100, price: 2, date: day("2026-03-01"))
        ], sources: [wallet])
        var settled = doc
        #expect(WalletDepartures.settle(&settled) == 0)
        #expect(settled == doc)
    }

    @Test func partOfAMoveCanLeave() {
        let wallet = LinkedSource(kind: .evmWallet, name: "Crypto", label: "0x…")
        let (_, asset) = usdc("USDC")
        // 예전 방식으로 100이 돌아왔고 그중 30을 직접 팔았다 — 남은 70만 빠진다.
        var doc = PortfolioDocument(assets: [asset], trades: [
            Trade(assetID: asset.id, side: .buy, quantity: 100, price: 1, date: day("2026-01-01"), sourceID: wallet.id, openingBalance: true),
            Trade(assetID: asset.id, side: .sell, quantity: 100, price: 1, date: day("2026-02-01"), sourceID: wallet.id,
                  externalID: "move:USDC:1", transferSourceID: wallet.id),
            Trade(assetID: asset.id, side: .buy, quantity: 100, price: 1, date: day("2026-02-01"),
                  externalID: "move-manual:USDC:1", transferSourceID: wallet.id),
            Trade(assetID: asset.id, side: .sell, quantity: 30, price: 2, date: day("2026-03-01"))
        ], sources: [wallet])
        #expect(WalletDepartures.settle(&doc) == 1)
        #expect(manual(doc, asset.id) == 0)
        #expect(position(doc, asset.id).quantity == 0)
        #expect(PositionCalculator.firstOversell(in: doc.trades.filter { $0.sourceID == nil }) == nil)
        #expect(PositionCalculator.snapshot(trades: doc.trades.filter { $0.sourceID == wallet.id }).quantity == 0)
        #expect(doc.trades.filter { $0.isTransfer }.map(\.quantity) == [30, 30])
    }
}
