import Foundation

/// 시세 소스 추상화 — Naver/Yahoo는 비공식 API라 스펙이 바뀌면 어댑터만 교체한다.
public protocol MarketDataProvider: Sendable {
    var kind: ProviderKind { get }
    func search(query: String) async throws -> [SearchResult]
    func quote(providerSymbol: String) async throws -> Quote
    func candles(providerSymbol: String, interval: CandleInterval) async throws -> [Candle]
}

public enum ProviderError: Error, Equatable {
    case invalidResponse
    case unsupportedSymbol(String)
}

/// 일봉/주봉/월봉 공통 조회 한도 — 캐시가 이 만큼 받아 화면에서 잘라 쓴다.
public enum CandleFetchLimit {
    public static func limit(for interval: CandleInterval) -> Int {
        switch interval {
        case .day: return 400      // 1Y + 여유
        case .week: return 520     // 10년
        case .month: return 240    // 20년
        }
    }
}
