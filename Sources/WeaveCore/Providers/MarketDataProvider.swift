import Foundation

/// 시세 소스 추상화 — Naver/Yahoo는 비공식 API라 스펙이 바뀌면 어댑터만 교체한다.
public protocol MarketDataProvider: Sendable {
    var kind: ProviderKind { get }
    func search(query: String) async throws -> [SearchResult]
    func quote(providerSymbol: String) async throws -> Quote
    func candles(providerSymbol: String, interval: CandleInterval) async throws -> [Candle]
    /// endDate로 끝나는 과거 구간 조회 — 오래된 거래로 점프할 때 그 시점 캔들을 받는다.
    /// 미지원 소스는 최근 구간으로 폴백한다.
    func candles(providerSymbol: String, interval: CandleInterval, endingAt endDate: Date) async throws -> [Candle]
}

public extension MarketDataProvider {
    func candles(providerSymbol: String, interval: CandleInterval, endingAt endDate: Date) async throws -> [Candle] {
        try await candles(providerSymbol: providerSymbol, interval: interval)
    }
}

public enum ProviderError: Error, Equatable {
    case invalidResponse
    case unsupportedSymbol(String)
}

/// 인터벌별 조회 한도 — 캐시가 이 만큼 받아 팬/줌으로 탐색한다.
public enum CandleFetchLimit {
    public static func limit(for interval: CandleInterval) -> Int {
        switch interval {
        case .m15: return 1000     // ~10일
        case .h1: return 1000      // ~41일
        case .h4: return 1000      // ~166일
        case .day: return 400      // 1Y + 여유
        case .week: return 520     // 10년
        case .month: return 240    // 20년
        }
    }
}

/// 저인터벌 캔들을 상위 버킷으로 합성 — 소스가 해당 인터벌을 직접 안 줄 때 사용(야후 4H 등).
public enum CandleAggregator {
    /// 렌더링용 다운샘플 — 균등 간격으로 추리되 마지막 캔들은 반드시 보존.
    public static func downsample(_ input: [Candle], maxPoints: Int) -> [Candle] {
        guard maxPoints > 0, input.count > maxPoints else { return input }
        let stride = Double(input.count) / Double(maxPoints)
        var result: [Candle] = []
        result.reserveCapacity(maxPoints + 1)
        var cursor = 0.0
        while Int(cursor) < input.count {
            result.append(input[Int(cursor)])
            cursor += stride
        }
        if result.last?.date != input.last?.date, let last = input.last {
            result.append(last)
        }
        return result
    }

    public static func aggregate(_ candles: [Candle], bucketSeconds: TimeInterval) -> [Candle] {
        guard bucketSeconds > 0, !candles.isEmpty else { return candles }
        let sorted = candles.sorted { $0.date < $1.date }
        var buckets: [Candle] = []
        var current: Candle?
        var currentBucketStart: TimeInterval = 0

        for candle in sorted {
            let bucketStart = (candle.date.timeIntervalSince1970 / bucketSeconds).rounded(.down) * bucketSeconds
            if var open = current, bucketStart == currentBucketStart {
                open.high = max(open.high, candle.high)
                open.low = min(open.low, candle.low)
                open.close = candle.close
                current = open
            } else {
                if let finished = current {
                    buckets.append(finished)
                }
                current = Candle(
                    date: Date(timeIntervalSince1970: bucketStart),
                    open: candle.open, high: candle.high,
                    low: candle.low, close: candle.close
                )
                currentBucketStart = bucketStart
            }
        }
        if let finished = current {
            buckets.append(finished)
        }
        return buckets
    }
}
