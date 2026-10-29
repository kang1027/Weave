import Foundation
import Testing
@testable import WeaveCore

private let owner = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
private let btc = ImportInstrument(market: .crypto, symbol: "BTC", name: "Bitcoin", currency: "USD")

private func date(_ value: String) -> Date {
    try! Date(value + "T01:00:00Z", strategy: .iso8601)
}

/// eth_call 한 번에 Multicall3 응답을 돌려주는 RPC 흉내. 받은 호출 수만큼 같은 잔고를 준다.
private actor FakeRPC: HTTPSending {
    var balance: UInt64
    var failIndex: Int?
    private(set) var calls = 0

    init(balance: UInt64, failIndex: Int? = nil) {
        self.balance = balance
        self.failIndex = failIndex
    }

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        calls += 1
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let params = body["params"] as! [Any]
        let call = Data(hex: (params[0] as! [String: String])["data"]!)!
        // aggregate3 인자의 배열 길이 = 셀렉터(4) + 오프셋(32) 뒤의 한 워드.
        let count = Int(call[(4 + 32 + 24)..<(4 + 64)].reduce(0) { $0 << 8 | UInt64($1) })
        var heads = Data()
        var tails = Data()
        for index in 0..<count {
            heads += word(UInt64(count * 32 + tails.count))
            tails += word(index == failIndex ? 0 : 1) + word(0x40) + word(32) + word(balance)
        }
        let result = word(0x20) + word(UInt64(count)) + heads + tails
        let response = #"{"jsonrpc":"2.0","id":1,"result":"0x\#(result.hex)"}"#
        return (Data(response.utf8), 200)
    }

    private func word(_ value: UInt64) -> Data {
        Data(repeating: 0, count: 24) + withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}



@Suite struct WalletTests {
    // MARK: - ABI

    @Test func aggregate3EncodesDynamicCallsAndDecodesResults() throws {
        let calls = [
            (target: EVMClient.multicall, data: EVMClient.getEthBalance(owner)),
            (target: "0xfc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a", data: EVMClient.balanceOf(owner))
        ]
        let encoded = EVMClient.aggregate3(calls)
        #expect(encoded.prefix(4).hex == "82ad56cb")
        // 셀렉터 + 오프셋 + 길이 + 오프셋 2개 + 원소 2개(각 192바이트).
        #expect(encoded.count == 4 + 32 + 32 + 64 + 2 * 192)
        #expect(EVMClient.balanceOf(owner).hex == "70a08231000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045")

        let returned = Data(hex: "0x"
            + "0000000000000000000000000000000000000000000000000000000000000020"
            + "0000000000000000000000000000000000000000000000000000000000000002"
            + "0000000000000000000000000000000000000000000000000000000000000040"
            + "00000000000000000000000000000000000000000000000000000000000000c0"
            + "0000000000000000000000000000000000000000000000000000000000000001"
            + "0000000000000000000000000000000000000000000000000000000000000040"
            + "0000000000000000000000000000000000000000000000000000000000000020"
            + "0000000000000000000000000000000000000000000000000de0b6b3a7640000"
            + "0000000000000000000000000000000000000000000000000000000000000000"
            + "0000000000000000000000000000000000000000000000000000000000000040"
            + "0000000000000000000000000000000000000000000000000000000000000000")!
        let results = try #require(EVMClient.decodeAggregate3(returned))
        #expect(results.map(\.success) == [true, false])
        #expect(EVMClient.uint(results[0].data) == 1_000_000_000_000_000_000)
        #expect(results[1].data.isEmpty)
    }

    @Test func balancesAreBatchedSummedBySymbolAndFailLoudly() async throws {
        let rpc = FakeRPC(balance: 2_000_000)
        let tokens = (0..<160).map { index in
            EVMToken(chain: .arbitrum, contract: String(format: "0x%040x", index), symbol: index.isMultiple(of: 2) ? "USDC" : "GMX", decimals: 6)
        }
        let balances = try await EVMClient(http: rpc).balances(owner: owner, chain: .arbitrum, tokens: tokens)
        // 가스 코인 + 토큰 160개 = 161개를 150개씩 두 번에 나눠 부른다.
        #expect(await rpc.calls == 2)
        #expect(balances["USDC"] == 160)
        #expect(balances["GMX"] == 160)
        #expect(balances["ETH"] == Decimal(string: "0.000000000002"))

        // 일부가 실패하면 0으로 보지 않고 멈춘다 — 0으로 보면 지갑에서 빠져나간 걸로 기록된다.
        let failing = FakeRPC(balance: 1, failIndex: 3)
        await #expect(throws: WalletError.partialFailure(chain: "Arbitrum")) {
            try await EVMClient(http: failing).balances(owner: owner, chain: .arbitrum, tokens: Array(tokens.prefix(5)))
        }
    }

    @Test func yieldTokensKeepTheirOwnSymbolAndAreValuedThroughTheVault() async throws {
        let staked = try #require(EVMToken.yieldBearing(providerSymbol: "ethereum:0x6bf183243fdd1e306ad2c4450bc7dcf6f0bf8aa6"))
        #expect(staked.symbol == "stkwaEthUSDC.v1")
        #expect(staked.underlying == "USDC")
        let plain = EVMToken(chain: .ethereum, contract: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", symbol: "USDC", decimals: 6)

        // 잔고는 토큰 단위 그대로 — 스테이킹분을 USDC에 섞지 않는다.
        let rpc = FakeRPC(balance: 3_000_000)
        let balances = try await EVMClient(http: rpc).balances(owner: owner, chain: .ethereum, tokens: [plain, staked])
        #expect(balances["USDC"] == 3)
        #expect(balances["stkwaEthUSDC.v1"] == 3)
        #expect(await rpc.calls == 1)

        // 1개가 원금 몇 개인지는 금고 두 단계를 차례로 부른다(가짜 RPC는 늘 3,000,000을 준다).
        let perToken = try await EVMClient(http: rpc).underlyingPerToken(staked)
        #expect(perToken == 3)
        #expect(await rpc.calls == 3)
        #expect(EVMClient.word(decimal: 1_000_000).hex.hasSuffix("0f4240"))

        // 스냅샷 — 토큰 자체가 종목이고, 시세 출처가 실려 자산을 만들 때 onchain으로 만든다.
        let snapshot = WalletConnector.snapshot(
            sourceID: UUID(), amounts: ["stkwaEthUSDC.v1": Decimal(string: "3096.668")!],
            quotes: ["stkwaEthUSDC.v1": Decimal(string: "1.1915")!], now: date("2026-03-01")
        )
        let holding = try #require(snapshot.holdings.first)
        #expect(holding.instrument.displaySymbol == "stkwaEthUSDC.v1")
        #expect(holding.instrument.name == "Aave Umbrella USDC")
        #expect(holding.instrument.provider == .onchain)
        #expect(holding.instrument.providerSymbol == "ethereum:0x6bf183243fdd1e306ad2c4450bc7dcf6f0bf8aa6")
        #expect(holding.marketPrice == Decimal(string: "1.1915"))
        #expect(EVMToken.all.contains { $0.contract == staked.contract })
    }

    @Test func onchainQuotesScaleTheUnderlyingByTheVaultRate() async throws {
        struct FixedUnderlying: MarketDataProvider {
            let kind: ProviderKind = .binance
            func search(query: String) async throws -> [SearchResult] { [] }
            func quote(providerSymbol: String) async throws -> Quote {
                #expect(providerSymbol == "USDCUSDT")
                return Quote(price: 1, changePercent: Decimal(string: "0.01")!, currency: "USD")
            }
            func candles(providerSymbol: String, interval: CandleInterval) async throws -> [Candle] {
                [Candle(date: Date(timeIntervalSince1970: 0), open: 1, high: 2, low: 1, close: 2)]
            }
        }
        let rpc = FakeRPC(balance: 1_191_538)
        let provider = OnchainVaultProvider(http: rpc, underlying: FixedUnderlying())
        let symbol = "ethereum:0xd4fa2d31b7968e448877f69a96de69f5de8cd23e"
        let quote = try await provider.quote(providerSymbol: symbol)
        #expect(quote.price == Decimal(string: "1.191538"))
        #expect(quote.currency == "USD")
        let candles = try await provider.candles(providerSymbol: symbol, interval: .day)
        #expect(candles.first?.close == Decimal(string: "2.383076"))
        // 교환비는 잠깐 기억한다 — 두 번째 시세에서 체인을 다시 부르지 않는다.
        #expect(await rpc.calls == 1)
        await #expect(throws: ProviderError.unsupportedSymbol("ethereum:0xdead")) {
            try await provider.quote(providerSymbol: "ethereum:0xdead")
        }
    }

    @Test func smallWalletChangesWaitUntilTheyAddUp() {
        let wallet = LinkedSource(kind: .evmWallet, name: "메인 지갑", label: "0x…")
        let usdc = ImportInstrument(market: .crypto, symbol: "USDC", name: "USD Coin", currency: "USD")
        let asset = Asset(name: "USD Coin", symbol: "USDC", provider: .binance, providerSymbol: "USDCUSDT", market: .crypto, currency: "USD")
        let doc = PortfolioDocument(assets: [asset], trades: [
            Trade(assetID: asset.id, side: .buy, quantity: 3_690, price: 1, date: date("2026-01-01"), sourceID: wallet.id, openingBalance: true)
        ], sources: [wallet])
        func plan(_ quantity: Decimal) -> ImportPlan {
            ImportPlanner.plan(snapshot: SourceSnapshot(
                sourceID: wallet.id,
                holdings: [ImportedHolding(instrument: usdc, quantity: quantity, averageCost: nil, marketPrice: 1)],
                executions: [], historyStart: date("2026-03-01"), takenAt: date("2026-03-01"),
                inheritsManualHoldings: true, minimumChangeValue: 5
            ), document: doc)
        }
        // 이자로 $0.4 늘었다 — 기록하지 않고 쌓이게 둔다.
        #expect(plan(Decimal(string: "3690.4")!).trades.isEmpty)
        // $6 넘게 쌓이면 한 번에 기록한다.
        #expect(plan(Decimal(string: "3696.2")!).adjustments.map(\.quantity) == [Decimal(string: "6.2")!])
    }

    @Test func addressesAreCheckedAndShortened() {
        #expect(WalletConfig.isEVMAddress(owner))
        #expect(!WalletConfig.isEVMAddress("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA9604"))
        #expect(WalletConfig.isBitcoinAddress("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"))
        #expect(WalletConfig.isBitcoinAddress("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"))
        #expect(WalletConfig.isBitcoinAddress("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"))
        #expect(!WalletConfig.isBitcoinAddress("tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx"))
        #expect(!WalletConfig.isBitcoinAddress("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNO"))
        #expect(WalletConfig(kind: .bitcoin, addresses: ["bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"]).label == "bc1qar…5mdq +1")
        #expect(WalletConfig(kind: .evm, addresses: [owner], chains: [.ethereum, .arbitrum]).label == "0xd8dA…6045")
    }

    @Test func snapshotMarksDustAndCoinsWithoutAPrice() async throws {
        let snapshot = WalletConnector.snapshot(
            sourceID: UUID(),
            amounts: ["BTC": Decimal(string: "0.5")!, "PEPE": 100, "ETH": Decimal(string: "0.004")!, "ARB": 0],
            quotes: ["BTC": 80_000, "ETH": 2_000],
            now: date("2026-03-01")
        )
        // 시세 없는 PEPE도 수량은 남긴다(연결 상세에 보여 준다) — 대조는 unsettled로 건너뛴다.
        #expect(snapshot.holdings.map(\.instrument.symbol) == ["BTC", "ETH", "PEPE"])
        #expect(snapshot.holdings.last?.marketPrice == nil)
        #expect(snapshot.holdings.first?.marketPrice == 80_000)
        #expect(snapshot.holdings.first?.averageCost == nil)
        // ETH 0.004개는 $8이라 먼지, PEPE는 잔고가 있는데 시세가 없어 이번엔 대조하지 않는다.
        #expect(snapshot.dust.map(\.symbol) == ["ETH"])
        #expect(snapshot.unsettled.map(\.symbol) == ["PEPE"])
        #expect(snapshot.inheritsManualHoldings)
    }

    @Test func dustAndUnpricedCoinsNeverEmptyAWallet() {
        let wallet = LinkedSource(kind: .evmWallet, name: "메인 지갑", label: "0x…")
        let usdc = ImportInstrument(market: .crypto, symbol: "USDC", name: "USD Coin", currency: "USD")
        let asset = Asset(name: "USD Coin", symbol: "USDC", provider: .binance, providerSymbol: "USDCUSDT", market: .crypto, currency: "USD")
        let pepe = ImportInstrument(market: .crypto, symbol: "PEPE", name: "Pepe", currency: "USD")
        let pepeAsset = Asset(name: "Pepe", symbol: "PEPE", provider: .binance, providerSymbol: "PEPEUSDT", market: .crypto, currency: "USD")
        let held = [
            Trade(assetID: asset.id, side: .buy, quantity: Decimal(string: "1.2")!, price: 1, date: date("2026-01-01"), sourceID: wallet.id, openingBalance: true),
            Trade(assetID: pepeAsset.id, side: .buy, quantity: 1_000_000, price: Decimal(string: "0.00001")!, date: date("2026-01-01"), sourceID: wallet.id, openingBalance: true)
        ]
        let doc = PortfolioDocument(assets: [asset, pepeAsset], trades: held, sources: [wallet])
        // USDC가 $0.9로 줄어 먼지가 됐고, PEPE는 시세를 못 받았다.
        let snapshot = SourceSnapshot(
            sourceID: wallet.id,
            holdings: [ImportedHolding(instrument: usdc, quantity: Decimal(string: "0.9")!, averageCost: nil, marketPrice: 1)],
            executions: [], historyStart: date("2026-03-01"), unsettled: [pepe], takenAt: date("2026-03-01"),
            inheritsManualHoldings: true, dust: [usdc]
        )
        let plan = ImportPlanner.plan(snapshot: snapshot, document: doc)
        // 이미 가진 USDC는 먼지여도 그대로 대조하고(0.3 돌려놓기), PEPE는 건드리지 않는다.
        #expect(plan.transfers.map(\.instrument.symbol) == ["USDC"])
        #expect(plan.transfers.map(\.quantity) == [Decimal(string: "0.3")!])

        // 처음 보는 먼지는 들이지 않는다.
        let fresh = ImportPlanner.plan(snapshot: snapshot, document: PortfolioDocument(sources: [wallet]))
        #expect(fresh.trades.isEmpty)
    }

    @Test func movesStayOutOfTheAssetAverageAndRealizedPnL() {
        let wallet = LinkedSource(kind: .bitcoinWallet, name: "콜드 월렛", label: "bc1q…")
        let asset = Asset(name: "Bitcoin", symbol: "BTC", provider: .binance, providerSymbol: "BTCUSDT", market: .crypto, currency: "USD")
        // 직접 입력 1 BTC @30,000, 지갑엔 3 BTC, 시세 60,000.
        var doc = PortfolioDocument(assets: [asset], trades: [
            Trade(assetID: asset.id, side: .buy, quantity: 1, price: 30_000, date: date("2025-01-01"))
        ], sources: [wallet])
        let plan = ImportPlanner.plan(snapshot: walletSnapshot(wallet.id, quantity: 3, price: 60_000, on: "2026-03-01"), document: doc)
        ImportApplier.apply(plan, to: &doc)
        let result = PortfolioCalculator.compute(assets: [asset], trades: doc.trades, quotes: [:], fxRates: ["USD": 1], baseCurrency: "USD")
        let position = try! #require(result.perAsset.first).position
        #expect(position.quantity == 3)
        #expect(position.averageCost == 50_000)
        #expect(position.realizedPnL == 0)
    }

    @Test func garbageMulticallResponsesFailWithoutCrashing() {
        let huge = String(repeating: "f", count: 64)
        let cases = [
            "", "00",
            String(repeating: "0", count: 62) + "20" + huge,
            String(repeating: "0", count: 62) + "20" + String(repeating: "0", count: 48) + "7fffffffffffffff",
            String(repeating: "0", count: 62) + "20" + String(repeating: "0", count: 63) + "1" + String(repeating: "0", count: 48) + "7fffffffffffffe0"
        ]
        for hex in cases {
            #expect(EVMClient.decodeAggregate3(Data(hex: hex) ?? Data()) == nil)
        }
        #expect(!WalletConfig.isEVMAddress("0x" + String(repeating: "０", count: 40)))
    }

    @Test func tradeQuantitiesSurviveTheJSONRoundTrip() throws {
        let trade = Trade(assetID: UUID(), side: .buy, quantity: Decimal(string: "3.527077482689935715")!, price: Decimal(string: "0.000000000000062433")!)
        let decoded = try JSONDecoder().decode(Trade.self, from: JSONEncoder().encode(trade))
        #expect(decoded.quantity == trade.quantity)
        #expect(decoded.price == trade.price)
    }

    // MARK: - 직접 입력분과 주고받기

    private func walletSnapshot(_ sourceID: UUID, quantity: Decimal, price: Decimal = 80_000, on day: String) -> SourceSnapshot {
        SourceSnapshot(
            sourceID: sourceID,
            holdings: quantity > 0 ? [ImportedHolding(instrument: btc, quantity: quantity, averageCost: nil, marketPrice: price)] : [],
            executions: [], historyStart: date(day), takenAt: date(day), inheritsManualHoldings: true
        )
    }

    @Test func walletTakesOverManualCoinsAndReturnsThemWhenTheyLeave() {
        let wallet = LinkedSource(kind: .bitcoinWallet, name: "콜드 월렛", label: "bc1q…")
        let asset = Asset(name: "Bitcoin", symbol: "BTC", provider: .binance, providerSymbol: "BTCUSDT", market: .crypto, currency: "USD")
        // 업비트에서 사서 직접 입력해 둔 1 BTC(평단 50,000) 중 0.8을 지갑으로 옮겼다.
        var doc = PortfolioDocument(assets: [asset], trades: [
            Trade(assetID: asset.id, side: .buy, quantity: 1, price: 50_000, date: date("2025-01-01"))
        ], sources: [wallet])

        let first = ImportPlanner.plan(snapshot: walletSnapshot(wallet.id, quantity: Decimal(string: "0.8")!, on: "2026-03-01"), document: doc)
        #expect(first.transfers.map(\.side) == [.buy])
        #expect(first.transfers.map(\.quantity) == [Decimal(string: "0.8")!])
        #expect(first.transfers.map(\.price) == [50_000])
        #expect(first.openingBalances.isEmpty)
        #expect(first.mismatches.isEmpty)
        ImportApplier.apply(first, to: &doc)
        ImportApplier.apply(first, to: &doc)
        #expect(doc.trades.count == 3)
        let manualSide = doc.trades.filter { $0.sourceID == nil && $0.isTransfer }
        #expect(manualSide.map(\.side) == [.sell])
        #expect(manualSide.allSatisfy { $0.isLocked })
        func position(_ trades: [Trade]) -> PositionSnapshot { PositionCalculator.snapshot(trades: trades) }
        #expect(position(doc.trades.filter { $0.sourceID == nil }).quantity == Decimal(string: "0.2")!)
        #expect(position(doc.trades.filter { $0.sourceID == wallet.id }).averageCost == 50_000)

        // 0.3을 거래소로 다시 보냈다 — 평단 그대로 직접 입력분으로 돌아가서 거기서 매도를 입력할 수 있다.
        let next = ImportPlanner.plan(snapshot: walletSnapshot(wallet.id, quantity: Decimal(string: "0.5")!, on: "2026-03-02"), document: doc)
        #expect(next.transfers.map(\.side) == [.sell])
        #expect(next.transfers.map(\.quantity) == [Decimal(string: "0.3")!])
        ImportApplier.apply(next, to: &doc)
        #expect(position(doc.trades.filter { $0.sourceID == nil }).quantity == Decimal(string: "0.5")!)
        #expect(position(doc.trades.filter { $0.sourceID == nil }).averageCost == 50_000)
        #expect(position(doc.trades.filter { $0.sourceID == wallet.id }).quantity == Decimal(string: "0.5")!)
        // 총 보유와 원가는 그대로 — 옮기기만 했다.
        #expect(position(doc.trades).quantity == 1)
        #expect(position(doc.trades).averageCost == 50_000)
        #expect(doc.trades.filter { $0.side == .sell }.allSatisfy { PositionCalculator.realizedPnL(of: $0, in: doc.trades) == 0 })
    }

    @Test func coinsWithoutManualHistoryStartAtTheMarketPrice() {
        let wallet = LinkedSource(kind: .evmWallet, name: "메인 지갑", label: "0x…")
        var doc = PortfolioDocument(sources: [wallet])
        let first = ImportPlanner.plan(snapshot: walletSnapshot(wallet.id, quantity: Decimal(string: "0.5")!, price: 80_000, on: "2026-03-01"), document: doc)
        #expect(first.openingBalances.map(\.price) == [80_000])
        #expect(first.missingAssets == [btc])
        let asset = Asset(name: "Bitcoin", symbol: "BTC", provider: .binance, providerSymbol: "BTCUSDT", market: .crypto, currency: "USD")
        doc.assets.append(asset)
        ImportApplier.apply(first, to: &doc)

        // 나중에 외부에서 0.1이 더 들어오면(직접 입력분 없음) 그때 시세로 잔고 맞춤.
        let later = ImportPlanner.plan(snapshot: walletSnapshot(wallet.id, quantity: Decimal(string: "0.6")!, price: 90_000, on: "2026-04-01"), document: doc)
        #expect(later.adjustments.map(\.price) == [90_000])
        #expect(later.adjustments.map(\.quantity) == [Decimal(string: "0.1")!])
        #expect(later.transfers.isEmpty)
    }
}
