import Foundation
import Testing
@testable import WeaveCore

/// 호출 횟수를 세고 지정된 응답/에러를 돌려주는 페이크 프로바이더.
private actor FakeProviderState {
    var callCount = 0
    var shouldFail = false
    var candles: [Candle] = []

    func record() -> (fail: Bool, candles: [Candle]) {
        callCount += 1
        return (shouldFail, candles)
    }

    func set(fail: Bool) { shouldFail = fail }
    func set(candles: [Candle]) { self.candles = candles }
}

private struct FakeProvider: MarketDataProvider {
    let kind: ProviderKind = .binance
    let state: FakeProviderState

    func search(query: String) async throws -> [SearchResult] { [] }
    func quote(providerSymbol: String) async throws -> Quote {
        throw ProviderError.invalidResponse
    }
    func candles(providerSymbol: String, interval: CandleInterval) async throws -> [Candle] {
        let (fail, candles) = await state.record()
        if fail { throw HTTPError.badStatus(500) }
        return candles
    }
}

@Suite struct CandleServiceTests {
    private func makeService(
        state: FakeProviderState,
        now: @escaping @Sendable () -> Date
    ) -> CandleService {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("weave-candle-tests-\(UUID().uuidString)")
        return CandleService(
            providers: [FakeProvider(state: state)],
            cacheDirectory: dir,
            calendar: Calendar(identifier: .gregorian),
            now: now
        )
    }

    private let sample = [
        Candle(date: Date(timeIntervalSince1970: 0), open: 1, high: 1, low: 1, close: 1)
    ]

    @Test func sameDayCacheHitSkipsNetwork() async throws {
        let state = FakeProviderState()
        await state.set(candles: sample)
        let service = makeService(state: state) { Date(timeIntervalSince1970: 1_700_000_000) }

        let first = try await service.candles(provider: .binance, providerSymbol: "BTCUSDT", interval: .day)
        let second = try await service.candles(provider: .binance, providerSymbol: "BTCUSDT", interval: .day)

        #expect(first == sample)
        #expect(second == sample)
        #expect(await state.callCount == 1)
    }

    @Test func staleCacheRefreshesNextDay() async throws {
        let state = FakeProviderState()
        await state.set(candles: sample)

        let dayOne = Date(timeIntervalSince1970: 1_700_000_000)
        let service1 = makeServiceShared(state: state, now: dayOne)
        _ = try await service1.candles(provider: .binance, providerSymbol: "BTCUSDT", interval: .day)
        #expect(await state.callCount == 1)

        // 다음날 같은 캐시 디렉토리 → 재조회
        let dayTwo = dayOne.addingTimeInterval(86_400 * 2)
        let service2 = CandleService(
            providers: [FakeProvider(state: state)],
            cacheDirectory: sharedDir,
            now: { dayTwo }
        )
        _ = try await service2.candles(provider: .binance, providerSymbol: "BTCUSDT", interval: .day)
        #expect(await state.callCount == 2)
    }

    @Test func fetchFailureFallsBackToStaleCache() async throws {
        let state = FakeProviderState()
        await state.set(candles: sample)

        let dayOne = Date(timeIntervalSince1970: 1_700_000_000)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("weave-candle-stale-\(UUID().uuidString)")
        let service1 = CandleService(providers: [FakeProvider(state: state)], cacheDirectory: dir, now: { dayOne })
        _ = try await service1.candles(provider: .binance, providerSymbol: "BTCUSDT", interval: .day)

        await state.set(fail: true)
        let dayTwo = dayOne.addingTimeInterval(86_400 * 2)
        let service2 = CandleService(providers: [FakeProvider(state: state)], cacheDirectory: dir, now: { dayTwo })
        let candles = try await service2.candles(provider: .binance, providerSymbol: "BTCUSDT", interval: .day)

        #expect(candles == sample) // 어제 캐시 폴백
        #expect(await state.callCount == 2)
    }

    private let sharedDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("weave-candle-shared-\(UUID().uuidString)")

    private func makeServiceShared(state: FakeProviderState, now: Date) -> CandleService {
        CandleService(providers: [FakeProvider(state: state)], cacheDirectory: sharedDir, now: { now })
    }

    @Test func intradayCacheExpiresWithinDay() async throws {
        let state = FakeProviderState()
        await state.set(candles: sample)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("weave-candle-intraday-\(UUID().uuidString)")

        // 같은 날이라도 15m 캔들은 5분 TTL 이후 재조회.
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let service1 = CandleService(providers: [FakeProvider(state: state)], cacheDirectory: dir, now: { base })
        _ = try await service1.candles(provider: .binance, providerSymbol: "BTCUSDT", interval: .m15)
        #expect(await state.callCount == 1)

        let service2 = CandleService(
            providers: [FakeProvider(state: state)], cacheDirectory: dir,
            now: { base.addingTimeInterval(120) }
        )
        _ = try await service2.candles(provider: .binance, providerSymbol: "BTCUSDT", interval: .m15)
        #expect(await state.callCount == 1) // 2분 — 캐시 히트

        let service3 = CandleService(
            providers: [FakeProvider(state: state)], cacheDirectory: dir,
            now: { base.addingTimeInterval(360) }
        )
        _ = try await service3.candles(provider: .binance, providerSymbol: "BTCUSDT", interval: .m15)
        #expect(await state.callCount == 2) // 6분 — 만료
    }
}

@Suite struct CandleAggregatorTests {
    private func candle(minute: Int, open: Decimal, high: Decimal, low: Decimal, close: Decimal) -> Candle {
        Candle(
            date: Date(timeIntervalSince1970: TimeInterval(minute) * 60),
            open: open, high: high, low: low, close: close
        )
    }

    @Test func aggregatesHourlyIntoFourHourBuckets() {
        // 0h~7h 시간봉 8개 → 4h 버킷 2개
        var hourly: [Candle] = []
        for hour in 0..<8 {
            let date = Date(timeIntervalSince1970: TimeInterval(hour) * 3600)
            let open = Decimal(100 + hour)
            let high = Decimal(110 + hour)
            let low = Decimal(90 + hour)
            let close = Decimal(105 + hour)
            hourly.append(Candle(date: date, open: open, high: high, low: low, close: close))
        }
        let buckets = CandleAggregator.aggregate(hourly, bucketSeconds: 4 * 3600)
        #expect(buckets.count == 2)
        #expect(buckets[0].open == 100)   // 첫 캔들 시가
        #expect(buckets[0].close == 108)  // 마지막(3h) 종가
        #expect(buckets[0].high == 113)   // max(110...113)
        #expect(buckets[0].low == 90)     // min(90...93)
        #expect(buckets[1].date == Date(timeIntervalSince1970: 4 * 3600))
    }

    @Test func emptyAndSingleInputPassThrough() {
        #expect(CandleAggregator.aggregate([], bucketSeconds: 3600).isEmpty)
        let one = [candle(minute: 0, open: 1, high: 2, low: 1, close: 2)]
        let result = CandleAggregator.aggregate(one, bucketSeconds: 3600)
        #expect(result.count == 1)
        #expect(result[0].close == 2)
    }

    @Test func downsampleKeepsBoundsAndLastCandle() {
        let input = (0..<1000).map { minute in
            candle(minute: minute, open: 1, high: 1, low: 1, close: Decimal(minute))
        }
        let sampled = CandleAggregator.downsample(input, maxPoints: 300)
        #expect(sampled.count <= 302)
        #expect(sampled.count >= 300)
        #expect(sampled.first?.date == input.first?.date)
        #expect(sampled.last?.date == input.last?.date) // 마지막(현재가) 캔들 보존
        // 작은 입력은 그대로 통과.
        #expect(CandleAggregator.downsample(Array(input.prefix(100)), maxPoints: 300).count == 100)
    }
}
