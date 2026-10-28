import Foundation
import Testing
@testable import Weave
import WeaveCore

private struct SeededStore: PortfolioStore {
    let document: PortfolioDocument
    func load() throws -> PortfolioDocument { document }
    func save(_ document: PortfolioDocument) throws {}
}

private struct OfflineHTTP: HTTPClient {
    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        throw HTTPError.badStatus(500)
    }
}

@Suite struct ImportedTradeLockTests {
    @MainActor
    @Test func importedTradesCannotBeEditedOrDeleted() {
        let source = LinkedSource(kind: .koreaInvestment, name: "한국투자증권", label: "6412****-01")
        let asset = Asset(name: "삼성전자", symbol: "005930", provider: .naver, providerSymbol: "005930", market: .koreaStock, currency: "KRW")
        let imported = Trade(assetID: asset.id, side: .buy, quantity: 10, price: 70_000, date: Date(timeIntervalSince1970: 1_780_000_000), sourceID: source.id, externalID: "E1")
        let manual = Trade(assetID: asset.id, side: .buy, quantity: 1, price: 71_000, date: Date(timeIntervalSince1970: 1_780_100_000))
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("weave-lock-tests-\(UUID().uuidString)")
        let naver = NaverProvider(http: OfflineHTTP())
        let model = AppModel(
            store: SeededStore(document: PortfolioDocument(assets: [asset], trades: [imported, manual], sources: [source])),
            quoteService: QuoteService(providers: [naver]),
            candleService: CandleService(providers: [naver], cacheDirectory: cacheDir),
            fxService: FXService(yahoo: YahooProvider(http: OfflineHTTP()), cacheDirectory: nil),
            searchService: SearchService(providers: [naver])
        )

        var edited = imported
        edited.quantity = 5
        #expect(model.updateTrade(edited) == .imported)
        model.deleteTrade(id: imported.id)
        #expect(model.document.trades.first { $0.id == imported.id }?.quantity == 10)

        // 직접 입력한 거래는 그대로 고치고 지울 수 있다.
        var editedManual = manual
        editedManual.quantity = 2
        #expect(model.updateTrade(editedManual) == nil)
        model.deleteTrade(id: manual.id)
        #expect(model.document.trades.map(\.id) == [imported.id])
    }
}
