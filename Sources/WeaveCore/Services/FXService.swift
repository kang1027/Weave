import Foundation

/// 환율 — Yahoo `USDKRW=X` 형태 페어 심볼. 현물 환율은 1시간 캐시.
public actor FXService {
    private let yahoo: YahooProvider
    private var rates: [String: (rate: Decimal, fetchedAt: Date)] = [:]
    private let now: @Sendable () -> Date

    public init(yahoo: YahooProvider, now: @escaping @Sendable () -> Date = { Date() }) {
        self.yahoo = yahoo
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

        let key = "\(from)->\(to)"
        if let cached = rates[key], now().timeIntervalSince(cached.fetchedAt) < 3600 {
            return cached.rate
        }
        do {
            let quote = try await yahoo.quote(providerSymbol: Self.pairSymbol(from: from, to: to))
            rates[key] = (quote.price, now())
            return quote.price
        } catch {
            // 실패 시 만료된 캐시라도 사용 — 환율은 급변하지 않는다.
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
}
