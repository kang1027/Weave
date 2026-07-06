import Foundation

/// 캔들 파일 캐시 — `Application Support/Weave/cache/` 아래 provider·심볼·주기별 파일.
/// 하루 1회 갱신, 네트워크 실패 시 stale 캐시 폴백.
public actor CandleService {
    public struct CachedSeries: Codable, Sendable {
        public var fetchedAt: Date
        public var candles: [Candle]
    }

    private let providers: [ProviderKind: any MarketDataProvider]
    private let cacheDirectory: URL
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var memory: [String: CachedSeries] = [:]
    private var inflight: [String: Task<[Candle], Error>] = [:]

    public init(
        providers: [any MarketDataProvider],
        cacheDirectory: URL,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.kind, $0) })
        self.cacheDirectory = cacheDirectory
        self.calendar = calendar
        self.now = now
    }

    public static func liveCacheDirectory() throws -> URL {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(WeaveInfo.appName, isDirectory: true)
            .appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func candles(
        provider: ProviderKind,
        providerSymbol: String,
        interval: CandleInterval
    ) async throws -> [Candle] {
        let key = cacheKey(provider: provider, symbol: providerSymbol, interval: interval)

        if let cached = memory[key] ?? loadDisk(key: key) {
            memory[key] = cached
            if isFresh(cached, interval: interval) {
                return cached.candles
            }
        }

        if let running = inflight[key] {
            do {
                return try await running.value
            } catch {
                // 합류한 요청도 stale 캐시 폴백을 받는다.
                if let stale = memory[key] ?? loadDisk(key: key) {
                    return stale.candles
                }
                throw error
            }
        }

        guard let dataProvider = providers[provider] else {
            throw ProviderError.unsupportedSymbol(providerSymbol)
        }

        let task = Task<[Candle], Error> {
            try await dataProvider.candles(providerSymbol: providerSymbol, interval: interval)
        }
        inflight[key] = task
        defer { inflight[key] = nil }

        do {
            let candles = try await task.value
            let cached = CachedSeries(fetchedAt: now(), candles: candles)
            memory[key] = cached
            saveDisk(key: key, series: cached)
            return candles
        } catch {
            // 갱신 실패 → 어제 캐시라도 반환.
            if let stale = memory[key] ?? loadDisk(key: key) {
                return stale.candles
            }
            throw error
        }
    }

    public func clearCache() {
        memory = [:]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// 일봉 이상은 하루 1회, 인트라데이는 짧은 TTL로 갱신.
    private func isFresh(_ cached: CachedSeries, interval: CandleInterval) -> Bool {
        let age = now().timeIntervalSince(cached.fetchedAt)
        switch interval {
        case .m15: return age < 5 * 60
        case .h1: return age < 15 * 60
        case .h4: return age < 30 * 60
        case .day, .week, .month:
            return calendar.isDate(cached.fetchedAt, inSameDayAs: now())
        }
    }

    private func cacheKey(provider: ProviderKind, symbol: String, interval: CandleInterval) -> String {
        let safeSymbol = symbol.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "_")
        return "candles-\(provider.rawValue)-\(safeSymbol)-\(interval.rawValue)"
    }

    private func fileURL(key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).json")
    }

    private func loadDisk(key: String) -> CachedSeries? {
        guard let data = try? Data(contentsOf: fileURL(key: key)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedSeries.self, from: data)
    }

    private func saveDisk(key: String, series: CachedSeries) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(series) else { return }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(key: key), options: .atomic)
    }
}
