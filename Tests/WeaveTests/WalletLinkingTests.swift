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
    private(set) var reads = 0
    func data(for sourceID: UUID) throws -> Data? {
        // 키체인처럼 메인 스레드에서 불리면 안 된다 — 허용 창이 뜨면 거기서 앱 전체가 멈춘다.
        precondition(!Thread.isMainThread, "keychain read on the main thread")
        return lock.withLock { reads += 1; return items[sourceID] }
    }
    func save(_ data: Data, for sourceID: UUID) throws { lock.withLock { items[sourceID] = data } }
    func delete(for sourceID: UUID) { lock.withLock { items[sourceID] = nil } }
    var count: Int { lock.withLock { items.count } }
    /// 테스트가 확인용으로 읽는다(메인 스레드 검사 없이).
    func peek(_ sourceID: UUID) -> WalletConfig? {
        lock.withLock { items[sourceID] }.flatMap { try? JSONDecoder().decode(WalletConfig.self, from: $0) }
    }
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
        #expect(credentials.peek(sourceID)?.addresses == [address])
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

        // 지갑으로 옮긴 매수는 지울 수 없다 — 지우면 잠긴 이동이 직접 입력분을 마이너스로 만든다.
        #expect(model.deleteTrade(id: bought.id) == .neededByMove)

        // 해제 — 이동 기록이 지워지고 지갑에 남아 있던 0.3이 직접 입력분으로 돌아온다.
        model.disconnectSource(id: sourceID)
        #expect(model.document.trades.allSatisfy { $0.sourceID == nil && !$0.isTransfer })
        let manual = model.document.trades
        #expect(PositionCalculator.firstOversell(in: manual) == nil)
        #expect(PositionCalculator.snapshot(trades: manual).quantity == Decimal(string: "0.3")!)
        #expect(model.document.assets.map(\.id) == [bitcoin.id])
        #expect(credentials.count == 0)
    }

    @MainActor
    @Test func disconnectKeepsReturnedCoinsThatWereSoldLater() async throws {
        let mempool = FakeMempool()
        mempool.set(address, 100_000_000)
        let model = makeModel(.empty, mempool: mempool, credentials: MemoryCredentials())
        let sourceID = try await model.connectWallet(kind: .bitcoin, name: "", addresses: [address], chains: []).get()
        model.applyPendingImport(sourceID: sourceID)
        let bitcoin = try #require(model.document.assets.first)

        // 0.6을 거래소로 보내 직접 입력분으로 돌아왔고, 거기서 팔았다.
        mempool.set(address, 40_000_000)
        await model.syncSource(id: sourceID)
        #expect(model.addTrade(assetID: bitcoin.id, side: .sell, quantity: Decimal(string: "0.6")!, price: 90_000, date: Date(), note: "") == nil)

        // 돌아온 기록을 지우면 그 매도가 마이너스가 되니 일반 거래로 남긴다 — 실현손익도 그대로다.
        model.disconnectSource(id: sourceID)
        let trades = model.document.trades
        #expect(trades.count == 2)
        #expect(trades.allSatisfy { !$0.isLocked })
        #expect(PositionCalculator.firstOversell(in: trades) == nil)
        let sale = try #require(trades.first { $0.side == .sell })
        #expect(model.realizedPnL(of: sale) == 6_000)
        #expect(trades.contains { $0.note.hasPrefix("← ") })
    }

    @MainActor
    @Test func disconnectWithoutLaterSalesRestoresTheManualHoldings() async throws {
        let bitcoin = Asset(name: "Bitcoin", symbol: "BTC", provider: .binance, providerSymbol: "BTCUSDT", market: .crypto, currency: "USD")
        let bought = Trade(assetID: bitcoin.id, side: .buy, quantity: 1, price: 50_000, date: Date(timeIntervalSince1970: 1_750_000_000))
        let mempool = FakeMempool()
        mempool.set(address, 80_000_000)
        let model = makeModel(PortfolioDocument(assets: [bitcoin], trades: [bought]), mempool: mempool, credentials: MemoryCredentials())
        let sourceID = try await model.connectWallet(kind: .bitcoin, name: "", addresses: [address], chains: []).get()
        model.applyPendingImport(sourceID: sourceID)
        model.disconnectSource(id: sourceID)
        #expect(model.document.trades == [bought])
    }

    @MainActor
    @Test func coinsSentBetweenWalletsAreNotCountedTwice() async throws {
        let other = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
        let mempool = FakeMempool()
        mempool.set(address, 100_000_000)
        mempool.set(other, 0)
        let model = makeModel(.empty, mempool: mempool, credentials: MemoryCredentials())
        let first = try await model.connectWallet(kind: .bitcoin, name: "A", addresses: [address], chains: []).get()
        model.applyPendingImport(sourceID: first)
        let second = try await model.connectWallet(kind: .bitcoin, name: "B", addresses: [other], chains: []).get()
        if model.pendingImports[second] != nil { model.applyPendingImport(sourceID: second) }
        func total() -> Decimal {
            PortfolioCalculator.compute(assets: model.document.assets, trades: model.document.trades, quotes: [:], fxRates: ["USD": 1], baseCurrency: "USD")
                .perAsset.first?.position.quantity ?? 0
        }
        #expect(total() == 1)

        // A → B로 0.5를 옮겼다. B만 동기화해도 지갑 전체가 함께 돌아 줄어든 A부터 반영된다.
        mempool.set(address, 50_000_000)
        mempool.set(other, 50_000_000)
        await model.syncSource(id: second)
        #expect(total() == 1)
        #expect(model.document.trades.filter { $0.isBalanceAdjustment }.isEmpty)
    }

    @MainActor
    @Test func keychainIsReadOffTheMainThreadOncePerLaunch() async throws {
        // 앱을 다시 켠 상황 — 문서엔 연결이 있고 주소는 키체인에만 있다.
        let wallet = LinkedSource(kind: .bitcoinWallet, name: "콜드 월렛", label: "bc1qar…5mdq", lastSyncedAt: Date(timeIntervalSince1970: 1_780_000_000))
        let credentials = MemoryCredentials()
        try credentials.save(WalletConfig(kind: .bitcoin, addresses: [address]), for: wallet.id)
        let mempool = FakeMempool()
        mempool.set(address, 50_000_000)
        let model = makeModel(PortfolioDocument(sources: [wallet]), mempool: mempool, credentials: credentials)

        await model.syncSource(id: wallet.id)
        await model.syncSource(id: wallet.id)
        #expect(credentials.reads == 1)
        #expect(model.walletConfigs[wallet.id]?.addresses == [address])
        if case .synced = model.linkStatus[wallet.id] {} else { Issue.record("expected synced, got \(String(describing: model.linkStatus[wallet.id]))") }
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
