import Foundation
import Testing
@testable import Weave
import WeaveCore

private struct MemoryStore: PortfolioStore {
    func load() throws -> PortfolioDocument { .empty }
    func save(_ document: PortfolioDocument) throws {}
}

private struct OfflineHTTP: HTTPClient {
    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        throw HTTPError.badStatus(500)
    }
}

private final class MemoryCredentials: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UUID: TossCredentials] = [:]

    func tossCredentials(for sourceID: UUID) -> TossCredentials? { lock.withLock { items[sourceID] } }
    func save(_ credentials: TossCredentials, for sourceID: UUID) throws { lock.withLock { items[sourceID] = credentials } }
    func delete(for sourceID: UUID) { lock.withLock { items[sourceID] = nil } }
    var count: Int { lock.withLock { items.count } }
}

/// 토스증권 서버 흉내 — 경로별 응답을 바꿔 가며 쓴다.
private final class FakeToss: HTTPSending, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: (Int, String)] = [:]

    subscript(path: String) -> (Int, String)? {
        get { lock.withLock { routes[path] } }
        set { lock.withLock { routes[path] = newValue } }
    }

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        var path = request.url!.path
        if path == "/api/v1/orders" {
            path += request.url!.query!.contains("status=OPEN") ? "?open" : "?closed"
        }
        let (status, body) = self[path] ?? (500, "{}")
        return (Data(body.utf8), status)
    }
}

private func order(_ id: String, _ symbol: String, _ side: String, _ quantity: String, _ price: String, _ currency: String, _ filledAt: String) -> String {
    """
    {"orderId":"\(id)","symbol":"\(symbol)","side":"\(side)","orderType":"LIMIT","timeInForce":"DAY","status":"FILLED",
     "price":"\(price)","quantity":"\(quantity)","orderAmount":null,"currency":"\(currency)","orderedAt":"\(filledAt)","canceledAt":null,
     "execution":{"filledQuantity":"\(quantity)","averageFilledPrice":"\(price)","filledAmount":null,"commission":null,"tax":null,"filledAt":"\(filledAt)","settlementDate":null}}
    """
}

private func orders(_ items: [String]) -> (Int, String) {
    (200, #"{"result":{"orders":[\#(items.joined(separator: ","))],"nextCursor":null,"hasNext":false}}"#)
}

private func holdings(_ items: [(String, String, String, String, String)]) -> (Int, String) {
    let json = items.map { symbol, name, currency, quantity, average in
        #"{"symbol":"\#(symbol)","name":"\#(name)","marketCountry":"\#(currency == "KRW" ? "KR" : "US")","currency":"\#(currency)","quantity":"\#(quantity)","lastPrice":"1","averagePurchasePrice":"\#(average)"}"#
    }
    return (200, #"{"result":{"items":[\#(json.joined(separator: ","))]}}"#)
}

@MainActor
private func makeModel(toss: FakeToss, credentials: MemoryCredentials) -> AppModel {
    let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("weave-link-tests-\(UUID().uuidString)")
    let naver = NaverProvider(http: OfflineHTTP())
    return AppModel(
        store: MemoryStore(),
        quoteService: QuoteService(providers: [naver]),
        candleService: CandleService(providers: [naver], cacheDirectory: cacheDir),
        fxService: FXService(yahoo: YahooProvider(http: OfflineHTTP()), cacheDirectory: nil),
        searchService: SearchService(providers: [naver]),
        credentialStore: credentials,
        linkHTTP: toss
    )
}

@Suite struct TossLinkingTests {
    @MainActor
    @Test func linkReviewApplyResyncAndDisconnect() async throws {
        let toss = FakeToss()
        toss["/oauth2/token"] = (200, #"{"access_token":"T","token_type":"Bearer","expires_in":86400}"#)
        toss["/api/v1/accounts"] = (200, #"{"result":[{"accountNo":"12345678901","accountSeq":3,"accountType":"BROKERAGE"}]}"#)
        toss["/api/v1/holdings"] = holdings([("005930", "삼성전자", "KRW", "10", "70000"), ("AAPL", "Apple Inc.", "USD", "2", "150")])
        toss["/api/v1/orders?closed"] = orders([
            order("A", "005930", "BUY", "10", "70000", "KRW", "2026-03-28T09:31:15+09:00"),
            order("B", "000660", "BUY", "1", "200000", "KRW", "2026-03-29T09:31:15+09:00"),
            order("C", "000660", "SELL", "1", "210000", "KRW", "2026-03-30T09:31:15+09:00")
        ])
        toss["/api/v1/orders?open"] = orders([])
        let credentials = MemoryCredentials()
        let model = makeModel(toss: toss, credentials: credentials)

        // 1) 연결 — 키는 키체인에, 문서엔 가린 계좌번호만.
        let sourceID = try await model.connectToss(clientID: " tsck_live_id ", clientSecret: "secret").get()
        let source = try #require(model.document.source(id: sourceID))
        #expect(source.label == "••••8901")
        #expect(credentials.tossCredentials(for: sourceID) == TossCredentials(clientID: "tsck_live_id", clientSecret: "secret", accountSeq: 3))

        // 2) 첫 동기화는 검토 대기 — 아직 아무것도 들어가지 않았다.
        let pending = try #require(model.pendingImports[sourceID])
        #expect(pending.plan.newTradeCount == 1)
        #expect(pending.plan.openingBalances.map(\.instrument.symbol) == ["AAPL"])
        #expect(pending.plan.closedPositions.map(\.symbol) == ["000660"])
        #expect(model.document.trades.isEmpty)

        // 3) 적용 — 없는 자산을 만들고 거래를 넣는다.
        model.applyPendingImport(sourceID: sourceID)
        #expect(model.pendingImports[sourceID] == nil)
        #expect(Set(model.document.assets.map(\.symbol)) == ["005930", "AAPL"])
        #expect(model.document.assets.first { $0.symbol == "AAPL" }?.provider == .yahoo)
        #expect(model.document.trades.count == 2)
        #expect(model.document.source(id: sourceID)?.lastSyncedAt != nil)
        #expect(model.heldAssetCount(sourceID: sourceID) == 2)

        // 4) 다음 동기화는 검토 없이 새 체결만 넣는다.
        toss["/api/v1/holdings"] = holdings([("005930", "삼성전자", "KRW", "12", "70500"), ("AAPL", "Apple Inc.", "USD", "2", "150")])
        toss["/api/v1/orders?closed"] = orders([
            order("A", "005930", "BUY", "10", "70000", "KRW", "2026-03-28T09:31:15+09:00"),
            order("D", "005930", "BUY", "2", "73000", "KRW", "2026-04-02T09:31:15+09:00")
        ])
        await model.syncSource(id: sourceID)
        #expect(model.pendingImports[sourceID] == nil)
        #expect(model.document.trades.compactMap(\.externalID).sorted() == ["A", "D"])
        #expect(model.linkMismatches[sourceID]?.isEmpty == true)
        if case .synced = model.linkStatus[sourceID] {} else { Issue.record("expected synced") }

        // 5) 같은 키는 두 번 연결하지 않는다.
        #expect(await model.connectToss(clientID: "tsck_live_id", clientSecret: "secret") == .failure(.alreadyLinked))

        // 6) 해제 — 키, 가져온 거래, 이 계좌에만 있던 자산까지 지운다. 직접 입력한 자산은 남는다.
        let manualAsset = Asset(name: "Bitcoin", symbol: "BTC", provider: .binance, providerSymbol: "BTCUSDT", market: .crypto, currency: "USD")
        model.document.assets.append(manualAsset)
        model.disconnectSource(id: sourceID)
        #expect(model.document.sources.isEmpty)
        #expect(model.document.trades.isEmpty)
        #expect(model.document.assets.map(\.id) == [manualAsset.id])
        #expect(credentials.count == 0)
    }

    @MainActor
    @Test func blockedIPSavesNothingAndExplainsWhy() async {
        let toss = FakeToss()
        toss["/oauth2/token"] = (403, #"{"error":"access_denied","error_description":"IP address not allowed"}"#)
        let credentials = MemoryCredentials()
        let model = makeModel(toss: toss, credentials: credentials)

        let result = await model.connectToss(clientID: "id", clientSecret: "secret")
        #expect(result == .failure(.ipNotAllowed))
        #expect(model.document.sources.isEmpty)
        #expect(credentials.count == 0)
        #expect(model.linkFailureText(.ipNotAllowed).contains("WTS"))
    }

    @MainActor
    @Test func syncFailureKeepsTheLastSyncedData() async throws {
        let toss = FakeToss()
        toss["/oauth2/token"] = (200, #"{"access_token":"T","token_type":"Bearer","expires_in":86400}"#)
        toss["/api/v1/accounts"] = (200, #"{"result":[{"accountNo":"12345678901","accountSeq":3,"accountType":"BROKERAGE"}]}"#)
        toss["/api/v1/holdings"] = holdings([("005930", "삼성전자", "KRW", "10", "70000")])
        toss["/api/v1/orders?closed"] = orders([order("A", "005930", "BUY", "10", "70000", "KRW", "2026-03-28T09:31:15+09:00")])
        toss["/api/v1/orders?open"] = orders([])
        let model = makeModel(toss: toss, credentials: MemoryCredentials())
        let sourceID = try await model.connectToss(clientID: "id", clientSecret: "secret").get()
        model.applyPendingImport(sourceID: sourceID)

        // 다른 네트워크로 옮겨 IP가 막혔다.
        toss["/api/v1/holdings"] = (403, #"{"error":{"requestId":"x","code":"ip-not-allowed","message":""}}"#)
        await model.syncSource(id: sourceID)
        #expect(model.linkStatus[sourceID] == .failed(.ipNotAllowed))
        #expect(model.document.trades.map(\.externalID) == ["A"])
    }
}
