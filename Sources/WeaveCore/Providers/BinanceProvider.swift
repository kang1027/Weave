import Foundation

/// Binance 공개 API. 검색은 exchangeInfo 심볼 카탈로그를 로컬 캐시해서 필터한다.
public struct BinanceProvider: MarketDataProvider {
    public let kind: ProviderKind = .binance

    private let http: any HTTPClient
    private let catalog: BinanceSymbolCatalog

    public init(http: any HTTPClient, cacheDirectory: URL? = nil) {
        self.http = http
        self.catalog = BinanceSymbolCatalog(http: http, cacheDirectory: cacheDirectory)
    }

    // MARK: - Search

    public func search(query: String) async throws -> [SearchResult] {
        let pairs = try await catalog.usdtPairs()
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return [] }

        let scored: [(BinancePair, Int)] = pairs.compactMap { pair in
            let base = pair.baseAsset
            let name = CryptoNames.name(for: base).uppercased()
            if base == q { return (pair, 0) }
            if base.hasPrefix(q) { return (pair, 1) }
            if name.hasPrefix(q) { return (pair, 2) }
            if name.contains(q) { return (pair, 3) }
            return nil
        }
        return scored
            .sorted { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.0.baseAsset < rhs.0.baseAsset : lhs.1 < rhs.1
            }
            .prefix(15)
            .map { pair, _ in
                SearchResult(
                    provider: .binance,
                    providerSymbol: pair.symbol,
                    symbol: pair.baseAsset,
                    name: CryptoNames.name(for: pair.baseAsset),
                    market: .crypto,
                    currency: "USD"
                )
            }
    }

    // MARK: - Quote

    public func quote(providerSymbol: String) async throws -> Quote {
        guard
            let encoded = providerSymbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "https://api.binance.com/api/v3/ticker/24hr?symbol=\(encoded)")
        else {
            throw ProviderError.unsupportedSymbol(providerSymbol)
        }
        let data = try await http.get(url)
        let response = try JSONDecoder().decode(TickerResponse.self, from: data)
        guard
            let price = Decimal.clean(response.lastPrice),
            let changePercent = Decimal.clean(response.priceChangePercent)
        else {
            throw ProviderError.invalidResponse
        }
        return Quote(
            price: price,
            changePercent: changePercent,
            currency: "USD",
            updatedAt: Date(timeIntervalSince1970: TimeInterval(response.closeTime) / 1000)
        )
    }

    // MARK: - Candles

    public func candles(providerSymbol: String, interval: CandleInterval) async throws -> [Candle] {
        try await fetchKlines(providerSymbol: providerSymbol, interval: interval, endDate: nil)
    }

    public func candles(
        providerSymbol: String,
        interval: CandleInterval,
        endingAt endDate: Date
    ) async throws -> [Candle] {
        try await fetchKlines(providerSymbol: providerSymbol, interval: interval, endDate: endDate)
    }

    private func fetchKlines(
        providerSymbol: String,
        interval: CandleInterval,
        endDate: Date?
    ) async throws -> [Candle] {
        let binanceInterval: String
        switch interval {
        case .second: throw ProviderError.unsupportedSymbol(providerSymbol)
        case .m15: binanceInterval = "15m"
        case .h1: binanceInterval = "1h"
        case .h4: binanceInterval = "4h"
        case .day: binanceInterval = "1d"
        case .week: binanceInterval = "1w"
        case .month: binanceInterval = "1M"
        }
        let limit = min(CandleFetchLimit.limit(for: interval), 1000)
        guard let encoded = providerSymbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw ProviderError.unsupportedSymbol(providerSymbol)
        }
        var query = "symbol=\(encoded)&interval=\(binanceInterval)&limit=\(limit)"
        if let endDate {
            // klines는 endTime(ms) 이하 캔들 중 최근 limit개를 준다.
            query += "&endTime=\(Int(endDate.timeIntervalSince1970 * 1000))"
        }
        guard let url = URL(string: "https://api.binance.com/api/v3/klines?\(query)") else {
            throw ProviderError.unsupportedSymbol(providerSymbol)
        }
        let data = try await http.get(url)
        return try Self.parseKlines(data)
    }

    /// klines 응답: [[openTime, open, high, low, close, volume, ...], ...]
    static func parseKlines(_ data: Data) throws -> [Candle] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            throw ProviderError.invalidResponse
        }
        return rows.compactMap { row in
            guard
                row.count >= 5,
                let openTime = row[0] as? Double,
                let open = (row[1] as? String).flatMap(Decimal.clean),
                let high = (row[2] as? String).flatMap(Decimal.clean),
                let low = (row[3] as? String).flatMap(Decimal.clean),
                let close = (row[4] as? String).flatMap(Decimal.clean)
            else {
                return nil
            }
            return Candle(
                date: Date(timeIntervalSince1970: openTime / 1000),
                open: open, high: high, low: low, close: close
            )
        }
    }

    private struct TickerResponse: Decodable {
        var lastPrice: String
        var priceChangePercent: String
        var closeTime: Int64
    }
}

// MARK: - 심볼 카탈로그 (exchangeInfo 로컬 캐시)

struct BinancePair: Codable, Equatable, Sendable {
    var symbol: String     // "BTCUSDT"
    var baseAsset: String  // "BTC"
}

/// exchangeInfo 전체(수 MB)를 매 검색마다 받지 않도록 하루 단위 파일 캐시.
actor BinanceSymbolCatalog {
    private let http: any HTTPClient
    private let cacheURL: URL?
    private var cached: [BinancePair]?
    private var fetchedAt: Date?

    init(http: any HTTPClient, cacheDirectory: URL?) {
        self.http = http
        self.cacheURL = cacheDirectory?.appendingPathComponent("binance-symbols.json")
    }

    func usdtPairs() async throws -> [BinancePair] {
        if let cached, let fetchedAt, Date().timeIntervalSince(fetchedAt) < 86_400 {
            return cached
        }
        if let disk = loadDisk(), Date().timeIntervalSince(disk.fetchedAt) < 86_400 {
            cached = disk.pairs
            fetchedAt = disk.fetchedAt
            return disk.pairs
        }
        do {
            let url = URL(string: "https://api.binance.com/api/v3/exchangeInfo")!
            let data = try await http.get(url)
            let pairs = try Self.parseExchangeInfo(data)
            cached = pairs
            fetchedAt = Date()
            saveDisk(pairs: pairs)
            return pairs
        } catch {
            // 네트워크 실패 시 만료된 캐시라도 사용.
            if let disk = loadDisk() { return disk.pairs }
            if let cached { return cached }
            throw error
        }
    }

    static func parseExchangeInfo(_ data: Data) throws -> [BinancePair] {
        struct Response: Decodable {
            struct Symbol: Decodable {
                var symbol: String
                var status: String
                var baseAsset: String
                var quoteAsset: String
            }
            var symbols: [Symbol]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.symbols
            .filter { $0.status == "TRADING" && $0.quoteAsset == "USDT" }
            .map { BinancePair(symbol: $0.symbol, baseAsset: $0.baseAsset) }
    }

    private struct DiskCache: Codable {
        var fetchedAt: Date
        var pairs: [BinancePair]
    }

    private func loadDisk() -> (fetchedAt: Date, pairs: [BinancePair])? {
        guard
            let cacheURL,
            let data = try? Data(contentsOf: cacheURL),
            let cache = try? JSONDecoder().decode(DiskCache.self, from: data)
        else {
            return nil
        }
        return (cache.fetchedAt, cache.pairs)
    }

    private func saveDisk(pairs: [BinancePair]) {
        guard let cacheURL else { return }
        let cache = DiskCache(fetchedAt: Date(), pairs: pairs)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
    }
}
