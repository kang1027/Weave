import Foundation
import Testing
@testable import Weave
import WeaveCore

private struct NoopStore: PortfolioStore {
    func load() throws -> PortfolioDocument { .empty }
    func save(_ document: PortfolioDocument) throws {}
}

private struct FailingHTTPClient: HTTPClient {
    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        throw HTTPError.badStatus(500)
    }
}

private actor DelayedQuoteState {
    private var quoteContinuation: CheckedContinuation<Quote, Error>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var requested = false

    func quote() async throws -> Quote {
        requested = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters = []
        return try await withCheckedThrowingContinuation { continuation in
            quoteContinuation = continuation
        }
    }

    func waitForRequest() async {
        if requested { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func finish(with quote: Quote) {
        quoteContinuation?.resume(returning: quote)
        quoteContinuation = nil
    }
}

private struct DelayedQuoteProvider: MarketDataProvider {
    let kind: ProviderKind = .yahoo
    let state: DelayedQuoteState

    func search(query: String) async throws -> [SearchResult] { [] }

    func quote(providerSymbol: String) async throws -> Quote {
        try await state.quote()
    }

    func candles(providerSymbol: String, interval: CandleInterval) async throws -> [Candle] { [] }
}

@Suite struct AppModelMutationTests {
    @MainActor
    private func makeModel(provider: any MarketDataProvider) -> AppModel {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("weave-app-model-tests-\(UUID().uuidString)")
        return AppModel(
            store: NoopStore(),
            quoteService: QuoteService(providers: [provider]),
            candleService: CandleService(providers: [provider], cacheDirectory: cacheDir),
            fxService: FXService(
                yahoo: YahooProvider(http: FailingHTTPClient()),
                cacheDirectory: nil
            ),
            searchService: SearchService(providers: [provider]),
            updater: UpdaterHandle()
        )
    }

    @MainActor
    @Test func addAssetMakesAssetVisibleBeforeQuoteReturns() async {
        let state = DelayedQuoteState()
        let provider = DelayedQuoteProvider(state: state)
        let model = makeModel(provider: provider)
        let result = SearchResult(
            provider: .yahoo,
            providerSymbol: "^GSPC",
            symbol: "^GSPC",
            name: "S&P 500",
            market: .usStock,
            currency: "USD"
        )

        let task = Task { await model.addAsset(from: result) }
        await state.waitForRequest()

        #expect(model.document.assets.map(\.providerSymbol) == ["^GSPC"])

        await state.finish(with: Quote(price: 7503, changePercent: 1, currency: "USD"))
        _ = await task.value
    }

    @MainActor
    @Test func invalidateHomeChartClearsAssetReturnCandles() {
        let state = DelayedQuoteState()
        let model = makeModel(provider: DelayedQuoteProvider(state: state))
        let assetID = UUID()
        model.homeAssetCandles[assetID] = [
            Candle(date: Date(timeIntervalSince1970: 0), open: 1, high: 1, low: 1, close: 1)
        ]

        model.invalidateHomeChart()

        #expect(model.homeAssetCandles.isEmpty)
    }

    @MainActor
    @Test func togglesHomeChartAssetVisibilityInSettings() {
        let state = DelayedQuoteState()
        let model = makeModel(provider: DelayedQuoteProvider(state: state))
        let first = Asset(
            name: "Bitcoin",
            symbol: "BTC",
            provider: .binance,
            providerSymbol: "BTCUSDT",
            market: .crypto,
            currency: "USD"
        )
        let second = Asset(
            name: "Samsung",
            symbol: "005930",
            provider: .naver,
            providerSymbol: "005930",
            market: .koreaStock,
            currency: "KRW"
        )
        model.document.assets = [first, second]

        model.toggleHomeChartAssetVisibility(assetID: second.id)

        #expect(model.isHomeChartAssetHidden(second.id))
        #expect(model.settings.hiddenHomeChartAssetIDs == [second.id])

        model.toggleHomeChartAssetVisibility(assetID: second.id)

        #expect(!model.isHomeChartAssetHidden(second.id))
        #expect(model.settings.hiddenHomeChartAssetIDs.isEmpty)
    }
}
