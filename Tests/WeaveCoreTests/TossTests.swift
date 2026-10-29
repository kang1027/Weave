import Foundation
import Testing
@testable import WeaveCore

/// 경로별로 정해 둔 응답을 차례로 돌려주고, 받은 요청을 기록한다.
private actor ScriptedHTTP: HTTPSending {
    private var responses: [String: [(Int, String)]]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [String: [(Int, String)]]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        requests.append(request)
        let path = request.url!.path
        guard var queue = responses[path], !queue.isEmpty else {
            return (Data(#"{"error":{"requestId":"x","code":"not-scripted","message":""}}"#.utf8), 500)
        }
        let (status, body) = queue.count == 1 ? queue[0] : queue.removeFirst()
        responses[path] = queue
        return (Data(body.utf8), status)
    }

    func count(_ path: String) -> Int {
        requests.filter { $0.url!.path == path }.count
    }
}

private let tokenOK = (200, #"{"access_token":"T1","token_type":"Bearer","expires_in":86400}"#)
private let credentials = TossCredentials(clientID: "tsck_live_id", clientSecret: "s_a+b/c=", accountSeq: 1)

private func client(_ http: ScriptedHTTP, now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_790_000_000) }) -> TossClient {
    TossClient(credentials: credentials, http: http, pageDelay: .zero, now: now)
}

private func order(
    _ id: String, _ symbol: String, _ side: String, filled: String, price: String?, currency: String = "KRW",
    filledAt: String? = "2026-03-28T09:31:15+09:00"
) -> String {
    let priceJSON = price.map { "\"\($0)\"" } ?? "null"
    let filledAtJSON = filledAt.map { "\"\($0)\"" } ?? "null"
    return """
    {"orderId":"\(id)","symbol":"\(symbol)","side":"\(side)","orderType":"LIMIT","timeInForce":"DAY","status":"FILLED",
     "price":"1","quantity":"\(filled)","orderAmount":null,"currency":"\(currency)","orderedAt":"2026-03-28T09:30:00+09:00","canceledAt":null,
     "execution":{"filledQuantity":"\(filled)","averageFilledPrice":\(priceJSON),"filledAmount":null,"commission":null,"tax":null,"filledAt":\(filledAtJSON),"settlementDate":null}}
    """
}

@Suite struct TossTests {
    // MARK: - 토큰

    @Test func tokenIsIssuedOnceWithAFormBodyAndReused() async throws {
        let http = ScriptedHTTP([
            "/oauth2/token": [tokenOK],
            "/api/v1/accounts": [(200, #"{"result":[{"accountNo":"12345678901","accountSeq":1,"accountType":"BROKERAGE"}]}"#)]
        ])
        let toss = client(http)
        _ = try await toss.accounts()
        let accounts = try await toss.accounts()

        #expect(accounts == [TossAccount(accountNo: "12345678901", accountSeq: 1)])
        #expect(await http.count("/oauth2/token") == 1)
        let requests = await http.requests
        let tokenRequest = try #require(requests.first)
        #expect(tokenRequest.httpMethod == "POST")
        #expect(tokenRequest.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(String(decoding: tokenRequest.httpBody ?? Data(), as: UTF8.self)
            == "grant_type=client_credentials&client_id=tsck_live_id&client_secret=s_a%2Bb%2Fc%3D")
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer T1")
        #expect(requests.last?.value(forHTTPHeaderField: "X-Tossinvest-Account") == nil)
    }

    @Test func revokedTokenIsReissuedOnce() async throws {
        let http = ScriptedHTTP([
            "/oauth2/token": [tokenOK, (200, #"{"access_token":"T2","token_type":"Bearer","expires_in":86400}"#)],
            "/api/v1/accounts": [
                (401, #"{"error":{"requestId":"x","code":"token-revoked","message":""}}"#),
                (200, #"{"result":[]}"#)
            ]
        ])
        let accounts = try await client(http).accounts()
        #expect(accounts.isEmpty)
        #expect(await http.count("/oauth2/token") == 2)
        #expect(await http.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer T2")
    }

    @Test func expiredTokenIsRenewedBeforeUse() async throws {
        let http = ScriptedHTTP([
            "/oauth2/token": [(200, #"{"access_token":"T1","token_type":"Bearer","expires_in":120}"#)],
            "/api/v1/accounts": [(200, #"{"result":[]}"#)]
        ])
        let clock = Clock(Date(timeIntervalSince1970: 1_790_000_000))
        let toss = client(http, now: { clock.now })
        _ = try await toss.accounts()
        clock.now = clock.now.addingTimeInterval(61)
        _ = try await toss.accounts()
        #expect(await http.count("/oauth2/token") == 2)
    }

    @Test func errorsMapToWhatTheUserCanFix() async {
        #expect(TossClient.tokenError(status: 401, data: Data(#"{"error":"invalid_client"}"#.utf8)) == .invalidCredentials)
        #expect(TossClient.tokenError(status: 400, data: Data(#"{"error":"invalid_request"}"#.utf8)) == .invalidCredentials)
        #expect(TossClient.tokenError(status: 403, data: Data(#"{"error":"access_denied","error_description":"IP address not allowed"}"#.utf8)) == .ipNotAllowed)
        #expect(TossClient.apiError(status: 403, data: Data(#"{"error":{"requestId":"x","code":"ip-not-allowed","message":""}}"#.utf8)) == .ipNotAllowed)
        #expect(TossClient.apiError(status: 429, data: Data()) == .rateLimited)

        let http = ScriptedHTTP(["/oauth2/token": [(403, #"{"error":"access_denied"}"#)]])
        await #expect(throws: TossError.ipNotAllowed) { try await client(http).accounts() }
    }

    // MARK: - 조회

    @Test func holdingsSendTheAccountHeaderAndParseDecimals() async throws {
        let http = ScriptedHTTP([
            "/oauth2/token": [tokenOK],
            "/api/v1/holdings": [(200, #"""
            {"result":{"items":[
              {"symbol":"005930","name":"삼성전자","marketCountry":"KR","currency":"KRW","quantity":"100","lastPrice":"72000","averagePurchasePrice":"65000"},
              {"symbol":"AAPL","name":"Apple Inc.","marketCountry":"US","currency":"USD","quantity":"0.123456","lastPrice":"178.5","averagePurchasePrice":"155.3"}
            ]}}
            """#)]
        ])
        let holdings = try await client(http).holdings(accountSeq: 7)
        #expect(holdings.map(\.quantity) == [100, Decimal(string: "0.123456")!])
        #expect(holdings.last?.averagePurchasePrice == Decimal(string: "155.3"))
        #expect(await http.requests.last?.value(forHTTPHeaderField: "X-Tossinvest-Account") == "7")
    }

    @Test func closedOrdersFollowTheCursorToTheEnd() async throws {
        let http = ScriptedHTTP([
            "/oauth2/token": [tokenOK],
            "/api/v1/orders": [
                (200, #"{"result":{"orders":[\#(order("A", "005930", "BUY", filled: "10", price: "70000"))],"nextCursor":"C1","hasNext":true}}"#),
                (200, #"{"result":{"orders":[\#(order("B", "005930", "SELL", filled: "4", price: "71000"))],"nextCursor":null,"hasNext":false}}"#)
            ]
        ])
        let from = try Date("2026-03-01T00:30:00+09:00", strategy: .iso8601)
        let orders = try await client(http).orders(accountSeq: 1, group: .closed, from: from)

        #expect(orders.map(\.orderID) == ["A", "B"])
        #expect(orders.map(\.side) == [.buy, .sell])
        #expect(orders.first?.filledAt == (try Date("2026-03-28T00:31:15Z", strategy: .iso8601)))
        let queries = await http.requests.filter { $0.url!.path == "/api/v1/orders" }.map { $0.url!.query ?? "" }
        #expect(queries == [
            "status=CLOSED&from=2026-03-01&limit=100",
            "status=CLOSED&from=2026-03-01&limit=100&cursor=C1"
        ])
    }

    // MARK: - 스냅샷

    @Test func snapshotKeepsFilledOrdersAndNamesThemFromHoldings() throws {
        let sourceID = UUID()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let filledAt = try Date("2026-03-28T00:31:15Z", strategy: .iso8601)
        let orderedAt = try Date("2026-03-28T00:30:00Z", strategy: .iso8601)
        func make(_ id: String, _ symbol: String, _ side: TradeSide?, _ filled: Decimal, _ price: Decimal?, _ currency: String = "KRW") -> TossOrder {
            TossOrder(orderID: id, symbol: symbol, status: "FILLED", side: side, currency: currency, filledQuantity: filled,
                      averageFilledPrice: price, orderedAt: orderedAt, filledAt: filled > 0 ? filledAt : nil)
        }
        let snapshot = TossConnector.snapshot(
            sourceID: sourceID,
            holdings: [
                TossHolding(symbol: "005930", name: "삼성전자", marketCountry: "KR", currency: "KRW", quantity: 6, averagePurchasePrice: 70_000),
                TossHolding(symbol: "BRK.B", name: "Berkshire Hathaway", marketCountry: "US", currency: "USD", quantity: 1, averagePurchasePrice: 410),
                TossHolding(symbol: "AAPL", name: "Apple Inc.", marketCountry: "US", currency: "USD", quantity: 3, averagePurchasePrice: 150)
            ],
            closed: [
                make("A", "005930", .buy, 10, 70_000),
                make("B", "005930", .sell, 4, 71_000),
                make("C", "005930", .buy, 0, nil),          // 취소돼 체결 없음
                make("D", "BRK.B", .buy, 1, 410, "USD")
            ],
            open: [make("E", "AAPL", .buy, 2, 150, "USD"), make("F", "005930", .sell, 0, nil)],
            from: nil,
            now: now
        )

        #expect(snapshot.executions.map(\.externalID) == ["A", "B", "D"])
        #expect(snapshot.executions.first?.instrument.name == "삼성전자")
        #expect(snapshot.executions.first?.date == filledAt)
        #expect(snapshot.holdings.map(\.instrument.symbol) == ["005930", "BRK-B", "AAPL"])
        #expect(snapshot.unsettled.map(\.symbol) == ["AAPL"])
        #expect(snapshot.historyStart == filledAt)
        #expect(TossConnector.maskedAccount("123-45-678901") == "••••8901")
    }

    @Test func rejectedRecordsAndMidSyncMovesAreLeftAlone() throws {
        let at = try Date("2026-03-28T00:31:15Z", strategy: .iso8601)
        func make(_ id: String, _ symbol: String, _ status: String, _ filled: Decimal) -> TossOrder {
            TossOrder(orderID: id, symbol: symbol, status: status, side: .buy, currency: "KRW", filledQuantity: filled,
                      averageFilledPrice: filled > 0 ? 70_000 : nil, orderedAt: at, filledAt: filled > 0 ? at : nil)
        }
        func holding(_ symbol: String, _ quantity: Decimal) -> TossHolding {
            TossHolding(symbol: symbol, name: symbol, marketCountry: "KR", currency: "KRW", quantity: quantity, averagePurchasePrice: 70_000)
        }
        // 받는 사이 000660 보유가 늘었고, 035720의 진행 중 주문이 끝났다.
        let moving = TossConnector.movedSymbols(
            holdingsBefore: [holding("005930", 10), holding("000660", 1)],
            holdingsAfter: [holding("005930", 10), holding("000660", 2)],
            openBefore: [make("O1", "035720", "PENDING", 0), make("O2", "005930", "PENDING", 0)],
            openAfter: [make("O2", "005930", "PENDING", 0)]
        )
        #expect(moving == ["000660", "035720"])

        let snapshot = TossConnector.snapshot(
            sourceID: UUID(),
            holdings: [holding("005930", 10), holding("000660", 2)],
            closed: [
                make("A", "005930", "FILLED", 10),
                make("R", "005930", "CANCEL_REJECTED", 10),
                make("P", "005930", "REPLACED", 3),
                make("O1", "035720", "FILLED", 1)
            ],
            open: [],
            moving: moving,
            from: nil,
            now: at
        )
        #expect(snapshot.executions.map(\.externalID) == ["A", "P", "O1"])
        #expect(Set(snapshot.unsettled.map(\.symbol)) == ["000660", "035720"])
        #expect(snapshot.takenAt == at)
    }

    // MARK: - 플래너 규칙

    @Test func unsettledInstrumentsAreNotReconciledYet() {
        let sourceID = UUID()
        let apple = ImportInstrument(market: .usStock, symbol: "AAPL", name: "Apple Inc.", currency: "USD")
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        // 일부 체결된 매수 2주가 보유엔 있지만 체결 내역엔 아직 없다.
        let snapshot = SourceSnapshot(
            sourceID: sourceID,
            holdings: [ImportedHolding(instrument: apple, quantity: 5, averageCost: 150)],
            executions: [ImportedExecution(externalID: "A", instrument: apple, side: .buy, quantity: 3, price: 150, date: start)],
            historyStart: start,
            unsettled: [apple]
        )
        let plan = ImportPlanner.plan(snapshot: snapshot, document: PortfolioDocument(sources: [LinkedSource(id: sourceID, kind: .toss, name: "토스증권", label: "")]))
        #expect(plan.trades.map(\.externalID) == ["A"])
        #expect(plan.openingBalances.isEmpty)
        #expect(plan.mismatches.isEmpty)
    }

    @Test func soldOutPositionsWithoutAnAssetAreLeftOut() {
        let sourceID = UUID()
        let samsung = ImportInstrument(market: .koreaStock, symbol: "005930", name: "삼성전자", currency: "KRW")
        let hynix = ImportInstrument(market: .koreaStock, symbol: "000660", name: "SK하이닉스", currency: "KRW")
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let snapshot = SourceSnapshot(
            sourceID: sourceID,
            holdings: [ImportedHolding(instrument: samsung, quantity: 1, averageCost: 70_000)],
            executions: [
                ImportedExecution(externalID: "A", instrument: samsung, side: .buy, quantity: 1, price: 70_000, date: start),
                ImportedExecution(externalID: "B", instrument: hynix, side: .buy, quantity: 2, price: 200_000, date: start),
                ImportedExecution(externalID: "C", instrument: hynix, side: .sell, quantity: 2, price: 210_000, date: start.addingTimeInterval(86_400))
            ],
            historyStart: start
        )
        let source = LinkedSource(id: sourceID, kind: .toss, name: "토스증권", label: "")
        let plan = ImportPlanner.plan(snapshot: snapshot, document: PortfolioDocument(sources: [source]))
        #expect(plan.trades.map(\.externalID) == ["A"])
        #expect(plan.closedPositions == [hynix])
        #expect(plan.missingAssets == [samsung])

        // 이미 자산으로 있으면 다 판 거래도 가져온다.
        let existing = Asset(name: "SK하이닉스", symbol: "000660", provider: .naver, providerSymbol: "000660", market: .koreaStock, currency: "KRW")
        let withAsset = ImportPlanner.plan(snapshot: snapshot, document: PortfolioDocument(assets: [existing], sources: [source]))
        #expect(withAsset.trades.map(\.externalID) == ["A", "B", "C"])
        #expect(withAsset.closedPositions.isEmpty)
        #expect(withAsset.mismatches.isEmpty)
    }
}

/// 테스트용 시계 — 토큰 만료를 앞당겨 본다.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
