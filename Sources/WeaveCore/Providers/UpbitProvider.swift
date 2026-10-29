import Foundation

/// 업비트 공개 시세 API — 김프 계산용 원화 시세만 받는다. 키 없이 쓰는 quotation 엔드포인트.
public struct UpbitProvider: Sendable {
    private let http: any HTTPClient

    public init(http: any HTTPClient) {
        self.http = http
    }

    public static func market(symbol: String) -> String {
        "KRW-\(symbol.uppercased())"
    }

    /// 원화 마켓 현재가. 업비트 원화 마켓에 없는 코인이면 nil.
    public func price(symbol: String) async throws -> Decimal? {
        let url = try Self.url(path: "ticker", query: [URLQueryItem(name: "markets", value: Self.market(symbol: symbol))])
        do {
            return try Self.parseTickerPrice(try await http.get(url))
        } catch HTTPError.badStatus(404) {
            // 업비트는 없는 마켓을 404 "Code not found"로 답한다.
            return nil
        }
    }

    /// 원화 마켓 일봉(오래된 순). 업비트 일봉은 UTC 자정(KST 09:00)에 시작한다.
    public func dailyCandles(symbol: String, count: Int) async throws -> [Candle] {
        let url = try Self.url(path: "candles/days", query: [
            URLQueryItem(name: "market", value: Self.market(symbol: symbol)),
            URLQueryItem(name: "count", value: String(count))
        ])
        return try Self.parseCandles(try await http.get(url))
    }

    static func parseTickerPrice(_ data: Data) throws -> Decimal {
        let tickers = try decoder.decode([Ticker].self, from: data)
        guard let price = tickers.first?.tradePrice, price > 0 else {
            throw ProviderError.invalidResponse
        }
        return Decimal.fromDouble(price)
    }

    static func parseCandles(_ data: Data) throws -> [Candle] {
        let rows = try decoder.decode([DayCandle].self, from: data)
        let candles = rows.compactMap { row -> Candle? in
            // "2026-10-28T00:00:00" — 시간대 표기가 없는 UTC 시각.
            guard let date = try? Date(row.candleDateTimeUtc + "Z", strategy: .iso8601) else { return nil }
            return Candle(
                date: date,
                open: Decimal.fromDouble(row.openingPrice),
                high: Decimal.fromDouble(row.highPrice),
                low: Decimal.fromDouble(row.lowPrice),
                close: Decimal.fromDouble(row.tradePrice)
            )
        }
        guard !candles.isEmpty else { throw ProviderError.invalidResponse }
        return candles.sorted { $0.date < $1.date }
    }

    private static func url(path: String, query: [URLQueryItem]) throws -> URL {
        var components = URLComponents(string: "https://api.upbit.com/v1/\(path)")
        components?.queryItems = query
        guard let url = components?.url else { throw ProviderError.invalidResponse }
        return url
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private struct Ticker: Decodable {
        var tradePrice: Double
    }

    private struct DayCandle: Decodable {
        var candleDateTimeUtc: String
        var openingPrice: Double
        var highPrice: Double
        var lowPrice: Double
        var tradePrice: Double
    }
}
