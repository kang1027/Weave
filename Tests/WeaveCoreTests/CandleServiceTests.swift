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
}
