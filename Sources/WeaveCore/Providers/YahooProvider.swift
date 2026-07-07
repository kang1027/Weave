import Foundation

/// Yahoo Finance 비공식 API — 미장/일장/기타 글로벌 + 환율 전담.
public struct YahooProvider: MarketDataProvider {
    public let kind: ProviderKind = .yahoo

    private let http: any HTTPClient
    private static let headers = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"]

    public init(http: any HTTPClient) {
        self.http = http
    }

    // MARK: - Search

    public func search(query: String) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard
            !trimmed.isEmpty,
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(
                string: "https://query1.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=12&newsCount=0&listsCount=0"
            )
        else {
            return []
        }
        let data = try await http.get(url, headers: Self.headers)
        return try Self.parseSearch(data)
    }

    static func parseSearch(_ data: Data) throws -> [SearchResult] {
        struct Response: Decodable {
            struct Item: Decodable {
                var symbol: String
                var shortname: String?
                var longname: String?
                var quoteType: String?
                var exchDisp: String?
            }
            var quotes: [Item]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.quotes
            .filter { item in
                let type = item.quoteType?.uppercased() ?? ""
                return ["EQUITY", "ETF", "CRYPTOCURRENCY", "INDEX", "MUTUALFUND"].contains(type)
            }
            .prefix(12)
            .map { item in
                let market = Self.market(symbol: item.symbol, quoteType: item.quoteType)
                return SearchResult(
                    provider: .yahoo,
                    providerSymbol: item.symbol,
                    symbol: Self.displaySymbol(item.symbol),
                    name: item.longname ?? item.shortname ?? item.symbol,
                    market: market,
                    currency: Self.guessCurrency(symbol: item.symbol, market: market)
                )
            }
    }

    static func market(symbol: String, quoteType: String?) -> Market {
        if quoteType?.uppercased() == "CRYPTOCURRENCY" { return .crypto }
        if symbol.hasSuffix(".KS") || symbol.hasSuffix(".KQ") { return .koreaStock }
        if symbol.hasSuffix(".T") { return .japanStock }
        if !symbol.contains(".") { return .usStock }
        // 클래스 주식(BRK.B 등) — 한 글자 서픽스는 미장 티커.
        let parts = symbol.split(separator: ".")
        if parts.count == 2, parts[1].count == 1 { return .usStock }
        return .other
    }

    static func displaySymbol(_ symbol: String) -> String {
        // 거래소 서픽스만 제거: "005930.KS" → "005930", "7203.T" → "7203".
        // "BRK.B" 같은 클래스 주식 심볼은 그대로 둔다.
        for suffix in [".KS", ".KQ", ".T"] where symbol.hasSuffix(suffix) {
            return String(symbol.dropLast(suffix.count))
        }
        if symbol.hasSuffix("-USD") { return String(symbol.dropLast(4)) }
        return symbol
    }

    /// 검색 단계 추정 통화 — 추가 시 chart meta의 실제 통화로 확정한다.
    static func guessCurrency(symbol: String, market: Market) -> String? {
        switch market {
        case .koreaStock: return "KRW"
        case .japanStock: return "JPY"
        case .usStock, .crypto: return "USD"
        case .other: return nil
        }
    }

    // MARK: - Quote

    public func quote(providerSymbol: String) async throws -> Quote {
        let data = try await chartData(symbol: providerSymbol, range: "5d", interval: "1d")
        return try Self.parseQuote(data)
    }

    static func parseQuote(_ data: Data) throws -> Quote {
        let result = try chartResult(data)
        guard let price = result.meta.regularMarketPrice.map(Decimal.fromDouble) else {
            throw ProviderError.invalidResponse
        }
        let closes = result.closes
        let previousClose: Decimal? = result.meta.previousClose.map(Decimal.fromDouble)
            ?? (closes.count >= 2 ? closes[closes.count - 2] : nil)
        var changePercent: Decimal = 0
        if let previousClose, previousClose != 0 {
            changePercent = ((price - previousClose) / previousClose * 100).rounded(scale: 4)
        }
        let updatedAt = result.meta.regularMarketTime
            .map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        return Quote(
            price: price,
            changePercent: changePercent,
            currency: result.meta.currency?.uppercased() ?? "USD",
            updatedAt: updatedAt
        )
    }

    // MARK: - Candles

    public func candles(providerSymbol: String, interval: CandleInterval) async throws -> [Candle] {
        let (range, yahooInterval): (String, String)
        switch interval {
        case .m15: (range, yahooInterval) = ("1mo", "15m")   // 야후 15m 한도 60일
        case .h1: (range, yahooInterval) = ("3mo", "1h")
        case .h4: (range, yahooInterval) = ("6mo", "1h")     // 4h 미지원 — 1h 합성
        case .day: (range, yahooInterval) = ("2y", "1d")
        case .week: (range, yahooInterval) = ("10y", "1wk")
        case .month: (range, yahooInterval) = ("max", "1mo")
        }
        let data = try await chartData(symbol: providerSymbol, range: range, interval: yahooInterval)
        let candles = try Self.parseCandles(data)
        if interval == .h4 {
            return CandleAggregator.aggregate(candles, bucketSeconds: interval.seconds)
        }
        return candles
    }

    public func candles(
        providerSymbol: String,
        interval: CandleInterval,
        endingAt endDate: Date
    ) async throws -> [Candle] {
        // 과거 구간은 range 대신 period1/period2(epoch초)로 조회.
        // (야후 15m은 소스가 최근 60일만 제공 — 그 이전은 빈 결과일 수 있다.)
        let (spanSeconds, yahooInterval): (TimeInterval, String)
        switch interval {
        case .m15: (spanSeconds, yahooInterval) = (60 * 86_400, "15m")
        case .h1: (spanSeconds, yahooInterval) = (90 * 86_400, "1h")
        case .h4: (spanSeconds, yahooInterval) = (180 * 86_400, "1h")
        case .day: (spanSeconds, yahooInterval) = (730 * 86_400, "1d")
        case .week: (spanSeconds, yahooInterval) = (3_650 * 86_400, "1wk")
        case .month: (spanSeconds, yahooInterval) = (7_300 * 86_400, "1mo")
        }
        let period2 = Int(endDate.timeIntervalSince1970)
        let period1 = period2 - Int(spanSeconds)
        let data = try await chartData(
            symbol: providerSymbol, period1: period1, period2: period2, interval: yahooInterval
        )
        let candles = try Self.parseCandles(data)
        if interval == .h4 {
            return CandleAggregator.aggregate(candles, bucketSeconds: interval.seconds)
        }
        return candles
    }

    static func parseCandles(_ data: Data) throws -> [Candle] {
        let result = try chartResult(data)
        guard
            let timestamps = result.timestamp,
            let quote = result.indicators.quote.first
        else {
            throw ProviderError.invalidResponse
        }
        var candles: [Candle] = []
        for (index, ts) in timestamps.enumerated() {
            guard
                let close = quote.close?[safe: index] ?? nil,
                close.isFinite
            else {
                continue
            }
            let open = quote.open?[safe: index].flatMap { $0 } ?? close
            let high = quote.high?[safe: index].flatMap { $0 } ?? close
            let low = quote.low?[safe: index].flatMap { $0 } ?? close
            candles.append(
                Candle(
                    date: Date(timeIntervalSince1970: TimeInterval(ts)),
                    open: Decimal.fromDouble(open),
                    high: Decimal.fromDouble(high),
                    low: Decimal.fromDouble(low),
                    close: Decimal.fromDouble(close)
                )
            )
        }
        guard !candles.isEmpty else { throw ProviderError.invalidResponse }
        return candles
    }

    // MARK: - Chart 응답 공통

    private func chartData(symbol: String, range: String, interval: String) async throws -> Data {
        guard
            let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(
                string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=\(range)&interval=\(interval)"
            )
        else {
            throw ProviderError.unsupportedSymbol(symbol)
        }
        return try await http.get(url, headers: Self.headers)
    }

    private func chartData(symbol: String, period1: Int, period2: Int, interval: String) async throws -> Data {
        guard
            let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(
                string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?period1=\(period1)&period2=\(period2)&interval=\(interval)"
            )
        else {
            throw ProviderError.unsupportedSymbol(symbol)
        }
        return try await http.get(url, headers: Self.headers)
    }

    struct ChartResult: Decodable {
        struct Meta: Decodable {
            var currency: String?
            var regularMarketPrice: Double?
            var previousClose: Double?
            var regularMarketTime: Int?
        }
        struct Indicators: Decodable {
            struct QuoteBlock: Decodable {
                var open: [Double?]?
                var high: [Double?]?
                var low: [Double?]?
                var close: [Double?]?
            }
            var quote: [QuoteBlock]
        }
        var meta: Meta
        var timestamp: [Int]?
        var indicators: Indicators

        var closes: [Decimal] {
            (indicators.quote.first?.close ?? [])
                .compactMap { $0 }
                .filter(\.isFinite)
                .map(Decimal.fromDouble)
        }
    }

    static func chartResult(_ data: Data) throws -> ChartResult {
        struct Response: Decodable {
            struct Chart: Decodable {
                var result: [ChartResult]?
            }
            var chart: Chart
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let result = response.chart.result?.first else {
            throw ProviderError.invalidResponse
        }
        return result
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
