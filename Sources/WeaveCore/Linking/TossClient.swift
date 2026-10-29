import Foundation

/// 토스증권 Open API 키. 키체인에 통째로 저장한다.
public struct TossCredentials: Codable, Equatable, Sendable {
    public var clientID: String
    public var clientSecret: String
    /// 연결한 계좌의 accountSeq — 계좌·자산 API의 `X-Tossinvest-Account` 헤더.
    public var accountSeq: Int64?

    public init(clientID: String, clientSecret: String, accountSeq: Int64? = nil) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.accountSeq = accountSeq
    }
}

public enum TossError: Error, Equatable, Sendable {
    /// client_id·client_secret이 틀렸거나 비활성.
    case invalidCredentials
    /// 지금 네트워크의 공인 IP가 허용 IP 목록에 없다.
    case ipNotAllowed
    case rateLimited
    /// 조회할 종합매매 계좌가 없다.
    case noAccount
    case server(status: Int, code: String)
    case invalidResponse
}

public struct TossAccount: Equatable, Sendable {
    public var accountNo: String
    public var accountSeq: Int64
}

public struct TossHolding: Equatable, Sendable {
    public var symbol: String
    public var name: String
    public var marketCountry: String
    public var currency: String
    public var quantity: Decimal
    /// 현재가(거래 통화 기준). 검토 화면 평가액에만 쓴다.
    public var lastPrice: Decimal?
    public var averagePurchasePrice: Decimal?
}

/// 주문 1건 = 1행. 나눠 체결된 주문은 평균 체결가·총 체결 수량으로 합쳐져 온다.
public struct TossOrder: Equatable, Sendable {
    public var orderID: String
    public var symbol: String
    /// `FILLED`, `CANCELED`, `REPLACED`, `CANCEL_REJECTED` 등 — 거부 레코드는 체결로 세지 않는다.
    public var status: String
    public var side: TradeSide?
    public var currency: String
    public var filledQuantity: Decimal
    public var averageFilledPrice: Decimal?
    public var orderedAt: Date
    /// 마지막 체결 시각.
    public var filledAt: Date?
}

/// 성공 응답 공통 봉투.
private struct TossEnvelope<T: Decodable>: Decodable {
    var result: T
}

/// 조회 전용 클라이언트 — 토큰, 계좌, 보유, 주문 내역만 부른다. 주문 API는 쓰지 않는다.
public actor TossClient {
    public enum OrderGroup: String, Sendable {
        case open = "OPEN"
        case closed = "CLOSED"
    }

    public static let baseURL = URL(string: "https://openapi.tossinvest.com")!

    private let credentials: TossCredentials
    private let http: any HTTPSending
    private let pageDelay: Duration
    private let now: @Sendable () -> Date
    /// 토큰은 클라이언트당 1개만 유효하다 — 새로 받으면 이전 토큰이 바로 무효가 되니 만료 전까지 재사용한다.
    private var token: (value: String, expiresAt: Date)?

    public init(
        credentials: TossCredentials,
        http: any HTTPSending,
        pageDelay: Duration = .milliseconds(250),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.http = http
        self.pageDelay = pageDelay
        self.now = now
    }

    // MARK: - 조회

    public func accounts() async throws -> [TossAccount] {
        struct Item: Decodable {
            var accountNo: String
            var accountSeq: Int64
        }
        let items: [Item] = try await get("/api/v1/accounts", accountSeq: nil)
        return items.map { TossAccount(accountNo: $0.accountNo, accountSeq: $0.accountSeq) }
    }

    public func holdings(accountSeq: Int64) async throws -> [TossHolding] {
        struct Result: Decodable {
            struct Item: Decodable {
                var symbol: String
                var name: String
                var marketCountry: String
                var currency: String
                var quantity: String
                var lastPrice: String?
                var averagePurchasePrice: String?
            }
            var items: [Item]
        }
        let result: Result = try await get("/api/v1/holdings", accountSeq: accountSeq)
        return try result.items.map { item in
            guard let quantity = Decimal.clean(item.quantity) else { throw TossError.invalidResponse }
            return TossHolding(
                symbol: item.symbol, name: item.name,
                marketCountry: item.marketCountry, currency: item.currency,
                quantity: quantity,
                lastPrice: item.lastPrice.flatMap(Decimal.clean),
                averagePurchasePrice: item.averagePurchasePrice.flatMap(Decimal.clean)
            )
        }
    }

    /// 주문 목록 — 끝난 주문은 커서로 끝까지 넘긴다. `from`은 주문 생성일(KST) 기준.
    public func orders(accountSeq: Int64, group: OrderGroup, from: Date? = nil) async throws -> [TossOrder] {
        struct Page: Decodable {
            struct Item: Decodable {
                struct Execution: Decodable {
                    var filledQuantity: String
                    var averageFilledPrice: String?
                    var filledAt: String?
                }
                var orderId: String
                var symbol: String
                var status: String
                var side: String
                var currency: String
                var orderedAt: String
                var execution: Execution
            }
            var orders: [Item]
            var nextCursor: String?
            var hasNext: Bool
        }
        var query = [URLQueryItem(name: "status", value: group.rawValue)]
        if let from {
            query.append(URLQueryItem(name: "from", value: Self.kstDay(from)))
        }
        if group == .closed {
            query.append(URLQueryItem(name: "limit", value: "100"))
        }
        var orders: [TossOrder] = []
        var cursor: String?
        repeat {
            let pageQuery = query + (cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
            let page: Page = try await get("/api/v1/orders", query: pageQuery, accountSeq: accountSeq)
            for item in page.orders {
                guard
                    let filled = Decimal.clean(item.execution.filledQuantity),
                    let orderedAt = Self.parseDate(item.orderedAt)
                else { throw TossError.invalidResponse }
                orders.append(TossOrder(
                    orderID: item.orderId, symbol: item.symbol, status: item.status,
                    side: TradeSide(rawValue: item.side.lowercased()),
                    currency: item.currency, filledQuantity: filled,
                    averageFilledPrice: item.execution.averageFilledPrice.flatMap(Decimal.clean),
                    orderedAt: orderedAt,
                    filledAt: item.execution.filledAt.flatMap(Self.parseDate)
                ))
            }
            cursor = page.hasNext ? page.nextCursor : nil
            if cursor != nil {
                // ORDER_HISTORY 그룹은 초당 5회 — 페이지 사이를 띄운다.
                try await Task.sleep(for: pageDelay)
            }
        } while cursor != nil
        return orders
    }

    // MARK: - 요청

    private func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        accountSeq: Int64?
    ) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        if let accountSeq {
            request.setValue(String(accountSeq), forHTTPHeaderField: "X-Tossinvest-Account")
        }

        // 다른 곳에서 같은 키로 토큰을 새로 받으면 이 토큰은 바로 무효가 된다 — 한 번만 다시 받는다.
        for attempt in 0..<2 {
            request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
            let (data, status) = try await http.send(request)
            if 200..<300 ~= status {
                do {
                    return try JSONDecoder().decode(TossEnvelope<T>.self, from: data).result
                } catch {
                    throw TossError.invalidResponse
                }
            }
            if status == 401, attempt == 0 {
                token = nil
                continue
            }
            throw Self.apiError(status: status, data: data)
        }
        throw TossError.invalidResponse
    }

    private func accessToken() async throws -> String {
        if let token, token.expiresAt > now() { return token.value }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("/oauth2/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            ("grant_type", "client_credentials"),
            ("client_id", credentials.clientID),
            ("client_secret", credentials.clientSecret)
        ])
        let (data, status) = try await http.send(request)
        guard 200..<300 ~= status else { throw Self.tokenError(status: status, data: data) }

        struct Response: Decodable {
            var access_token: String
            var expires_in: Int64
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw TossError.invalidResponse
        }
        // 만료 직전에 쓰다 401을 받지 않게 1분 일찍 버린다.
        let lifetime = max(0, TimeInterval(response.expires_in) - 60)
        token = (response.access_token, now().addingTimeInterval(lifetime))
        return response.access_token
    }

    // MARK: - 오류

    /// 토큰 발급은 OAuth2 표준 형식(`error`가 문자열)으로 실패한다.
    static func tokenError(status: Int, data: Data) -> TossError {
        struct Body: Decodable { var error: String }
        let code = (try? JSONDecoder().decode(Body.self, from: data))?.error ?? ""
        switch (status, code) {
        case (400, _), (401, _): return .invalidCredentials
        case (403, "access_denied"): return .ipNotAllowed
        case (429, _): return .rateLimited
        default: return .server(status: status, code: code)
        }
    }

    /// 나머지 API는 `{"error": {"code": ...}}` 형식으로 실패한다.
    static func apiError(status: Int, data: Data) -> TossError {
        struct Body: Decodable {
            struct Detail: Decodable { var code: String }
            var error: Detail
        }
        let code = (try? JSONDecoder().decode(Body.self, from: data))?.error.code ?? ""
        switch (status, code) {
        case (403, "ip-not-allowed"): return .ipNotAllowed
        case (429, _): return .rateLimited
        default: return .server(status: status, code: code)
        }
    }

    // MARK: - 형식

    static func formBody(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").utf8)
    }

    static func parseDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }

    static func kstDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
