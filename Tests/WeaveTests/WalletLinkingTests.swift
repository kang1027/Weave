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
    func get(_ url: URL, headers: [String: String]) async throws -> Data { throw HTTPError.badStatus(500) }
}

private final class MemoryCredentials: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UUID: Data] = [:]
    func data(for sourceID: UUID) throws -> Data? { lock.withLock { items[sourceID] } }
    func save(_ data: Data, for sourceID: UUID) throws { lock.withLock { items[sourceID] = data } }
    func delete(for sourceID: UUID) { lock.withLock { items[sourceID] = nil } }
    var count: Int { lock.withLock { items.count } }
}

/// mempool.space 흉내 — 주소별 사토시 잔고.
private final class FakeMempool: HTTPSending, @unchecked Sendable {
    private let lock = NSLock()
    private var satoshis: [String: Int64] = [:]
    func set(_ address: String, _ value: Int64) { lock.withLock { satoshis[address] = value } }
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let address = request.url!.lastPathComponent
        let value = lock.withLock { satoshis[address] ?? 0 }
        let body = #"{"address":"\#(address)","chain_stats":{"funded_txo_sum":\#(value),"spent_txo_sum":0}}"#
        return (Data(body.utf8), 200)
    }
}

private struct FixedPrices: CryptoPriceSource {
    var price: Decimal
    func usdtBaseAssets() async throws -> Set<String> { ["BTC", "ETH"] }
    func prices(baseAssets: [String]) async throws -> [String: Decimal] {
        Dictionary(uniqueKeysWithValues: baseAssets.map { ($0, price) })
    }
}

private let address = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"

@MainActor
private func makeModel(_ document: PortfolioDocument, mempool: FakeMempool, credentials: MemoryCredentials) -> AppModel {
    let naver = NaverProvider(http: OfflineHTTP())
    let model = AppModel(
        store: SeededStore(document: document),
        quoteService: QuoteService(providers: [naver]),
        candleService: CandleService(providers: [naver], cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        fxService: FXService(yahoo: YahooProvider(http: OfflineHTTP()), cacheDirectory: nil),
        searchService: SearchService(providers: [naver])
    )
    model.credentialStore = credentials
    model.linkHTTP = mempool
    model.cryptoPrices = FixedPrices(price: 80_000)
    return model
}

@Suite struct WalletLinkingTests {
    @MainActor
    @Test func walletTakesOverManualBitcoinAndHandsItBack() async throws {
        let bitcoin = Asset(name: "Bitcoin", symbol: "BTC", provider: .binance, providerSymbol: "BTCUSDT", market: .crypto, currency: "USD")
        let bought = Trade(assetID: bitcoin.id, side: .buy, quantity: 1, price: 50_000, date: Date(timeIntervalSince1970: 1_750_000_000))
        let mempool = FakeMempool()
        mempool.set(address, 80_000_000)
        let credentials = MemoryCredentials()
        let model = makeModel(PortfolioDocument(assets: [bitcoin], trades: [bought]), mempool: mempool, credentials: credentials)

        #expect(await model.connectWallet(kind: .bitcoin, name: "", addresses: ["not-an-address"], chains: []) == .failure(.invalidAddress))

        let sourceID = try await model.connectWallet(kind: .bitcoin, name: "콜드 월렛", addresses: [address, " \(address) "], chains: []).get()
        #expect(try credentials.walletConfig(for: sourceID)?.addresses == [address])
        #expect(model.document.source(id: sourceID)?.label == "bc1qar…5mdq")
        let pending = try #require(model.pendingImports[sourceID])
        #expect(pending.plan.transfers.map(\.quantity) == [Decimal(string: "0.8")!])

        model.applyPendingImport(sourceID: sourceID)
        #expect(model.hasLinkedHoldings(assetID: bitcoin.id))
        // 직접 입력분엔 0.2만 남아 그 이상은 직접 입력 매도로 팔 수 없다.
        #expect(model.addTrade(assetID: bitcoin.id, side: .sell, quantity: Decimal(string: "0.3")!, price: 90_000, date: Date(), note: "") == .exceedsHolding(available: Decimal(string: "0.2")!))
        // 이동 기록은 잠겨 있다.
        let moved = try #require(model.document.trades.first { $0.sourceID == nil && $0.isTransfer })
        model.deleteTrade(id: moved.id)
        #expect(model.document.trades.contains { $0.id == moved.id })

        // 0.5를 거래소로 보냈다 — 직접 입력분으로 돌아와 그 매도를 입력할 수 있다.
        mempool.set(address, 30_000_000)
        await model.syncSource(id: sourceID)
        #expect(model.addTrade(assetID: bitcoin.id, side: .sell, quantity: Decimal(string: "0.7")!, price: 90_000, date: Date(), note: "") == nil)

        // 같은 주소는 두 번 연결하지 않는다.
        #expect(await model.connectWallet(kind: .bitcoin, name: "", addresses: [address], chains: []) == .failure(.alreadyLinked))

        // 해제하면 이동 기록이 지워지고 직접 입력분이 그대로 남는다(자산도 남는다).
        model.disconnectSource(id: sourceID)
        #expect(model.document.trades.allSatisfy { $0.sourceID == nil && !$0.isTransfer })
        #expect(model.document.assets.map(\.id) == [bitcoin.id])
        #expect(credentials.count == 0)
    }

    @MainActor
    @Test func newCoinsBecomeBinanceAssetsAtTheMarketPrice() async throws {
        let mempool = FakeMempool()
        mempool.set(address, 50_000_000)
        let model = makeModel(.empty, mempool: mempool, credentials: MemoryCredentials())
        let sourceID = try await model.connectWallet(kind: .bitcoin, name: "", addresses: [address], chains: []).get()
        #expect(model.document.source(id: sourceID)?.name == "Bitcoin wallet")
        model.applyPendingImport(sourceID: sourceID)
        let asset = try #require(model.document.assets.first)
        #expect(asset.provider == .binance)
        #expect(asset.providerSymbol == "BTCUSDT")
        #expect(model.document.trades.map(\.price) == [80_000])
        #expect(model.document.trades.first?.isOpeningBalance == true)
    }
}
