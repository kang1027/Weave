import Foundation

/// 이자·스테이킹 토큰 시세 — 체인에서 원금 교환비를 읽고 원금 코인의 바이낸스 시세를 곱한다.
/// 차트는 원금 캔들에 지금 교환비를 곱해 그린다(지난 교환비는 조금 낮았지만 이자만큼의 차이다).
public actor OnchainVaultProvider: MarketDataProvider {
    public nonisolated let kind: ProviderKind = .onchain

    private let client: EVMClient
    private let underlying: any MarketDataProvider
    /// 상세 화면은 1초마다 시세를 부른다 — 교환비는 천천히 바뀌니 잠깐 기억한다.
    private let rateLifetime: TimeInterval
    private var rates: [String: (value: Decimal, fetchedAt: Date)] = [:]

    public init(http: any HTTPSending, underlying: any MarketDataProvider, rateLifetime: TimeInterval = 60) {
        self.client = EVMClient(http: http)
        self.underlying = underlying
        self.rateLifetime = rateLifetime
    }

    public nonisolated func search(query: String) async throws -> [SearchResult] { [] }

    public func quote(providerSymbol: String) async throws -> Quote {
        let (token, base) = try resolve(providerSymbol)
        let rate = try await rate(for: token)
        let quote = try await underlying.quote(providerSymbol: base)
        return Quote(price: quote.price * rate, changePercent: quote.changePercent, currency: quote.currency, updatedAt: quote.updatedAt)
    }

    public func candles(providerSymbol: String, interval: CandleInterval) async throws -> [Candle] {
        let (token, base) = try resolve(providerSymbol)
        let rate = try await rate(for: token)
        return try await underlying.candles(providerSymbol: base, interval: interval).map { $0.scaled(by: rate) }
    }

    public func candles(providerSymbol: String, interval: CandleInterval, endingAt endDate: Date) async throws -> [Candle] {
        let (token, base) = try resolve(providerSymbol)
        let rate = try await rate(for: token)
        return try await underlying.candles(providerSymbol: base, interval: interval, endingAt: endDate).map { $0.scaled(by: rate) }
    }

    private func resolve(_ providerSymbol: String) throws -> (EVMToken, String) {
        guard let token = EVMToken.yieldBearing(providerSymbol: providerSymbol), let base = token.underlying else {
            throw ProviderError.unsupportedSymbol(providerSymbol)
        }
        return (token, "\(base)USDT")
    }

    private func rate(for token: EVMToken) async throws -> Decimal {
        if let cached = rates[token.providerSymbol], Date().timeIntervalSince(cached.fetchedAt) < rateLifetime {
            return cached.value
        }
        let value = try await client.underlyingPerToken(token)
        rates[token.providerSymbol] = (value, Date())
        return value
    }
}

private extension Candle {
    func scaled(by rate: Decimal) -> Candle {
        var candle = self
        candle.open *= rate
        candle.high *= rate
        candle.low *= rate
        candle.close *= rate
        return candle
    }
}
