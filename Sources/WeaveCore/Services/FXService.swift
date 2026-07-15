import Foundation

/// 환율 — Yahoo `USDKRW=X` 형태 페어 심볼.
/// 신선한 값은 1시간 캐시, 조회 실패 시 디스크에 남은 마지막 값으로 폴백한다
/// (환율이 0으로 계상되어 총액이 증발해 보이는 것보다 낡은 환율이 낫다).
public actor FXService {
    private let yahoo: YahooProvider
    private let cacheURL: URL?
    private var rates: [String: CachedRate] = [:]
    private var loadedDisk = false
    private let now: @Sendable () -> Date

    struct CachedRate: Codable {
        var rate: Decimal
        var fetchedAt: Date
    }

    public init(
        yahoo: YahooProvider,
        cacheDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.yahoo = yahoo
        self.cacheURL = cacheDirectory?.appendingPathComponent("fx-rates.json")
        self.now = now
    }

    public static func pairSymbol(from: String, to: String) -> String {
        "\(from.uppercased())\(to.uppercased())=X"
    }

    /// from 통화 1단위 = 반환값 × to 통화.
    public func rate(from: String, to: String) async throws -> Decimal {
        let from = from.uppercased()
        let to = to.uppercased()
        if from == to { return 1 }

        loadDiskIfNeeded()
        let key = "\(from)->\(to)"
        if let cached = rates[key], now().timeIntervalSince(cached.fetchedAt) < 3600 {
            return cached.rate
        }
        do {
            let quote = try await yahoo.quote(providerSymbol: Self.pairSymbol(from: from, to: to))
            rates[key] = CachedRate(rate: quote.price, fetchedAt: now())
            saveDisk()
            return quote.price
        } catch {
            // 실패 시 만료된 값이라도 사용 — 환율은 급변하지 않는다.
            if let cached = rates[key] { return cached.rate }
            throw error
        }
    }

    /// 필요한 통화쌍 환율을 한 번에 — [자산통화: 기준통화 환산율].
    public func rates(currencies: Set<String>, base: String) async -> [String: Decimal] {
        var result: [String: Decimal] = [base.uppercased(): 1]
        for currency in currencies where currency.uppercased() != base.uppercased() {
            if let rate = try? await rate(from: currency, to: base) {
                result[currency.uppercased()] = rate
            }
        }
        return result
    }

    public func clearCache() {
        rates = [:]
        loadedDisk = false
        if let cacheURL {
            try? FileManager.default.removeItem(at: cacheURL)
        }
    }

    // MARK: - 디스크 캐시

    private func loadDiskIfNeeded() {
        guard !loadedDisk else { return }
        loadedDisk = true
        guard
            let cacheURL,
            let data = try? Data(contentsOf: cacheURL)
        else {
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let disk = try? decoder.decode([String: CachedRate].self, from: data) {
            // 메모리에 이미 있는 값이 우선.
            rates.merge(disk) { memory, _ in memory }
        }
    }

    private func saveDisk() {
        guard let cacheURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(rates) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
    }
}
