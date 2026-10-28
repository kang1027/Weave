import Foundation
import Testing
@testable import WeaveCore

/// 야후 차트 응답을 흉내 내고 호출 횟수를 센다.
private actor FakeYahooState {
    var calls = 0
    var failing = false
    func fail() { failing = true }
    func record() throws -> Data {
        calls += 1
        if failing { throw HTTPError.badStatus(429) }
        let price = 1_340 + calls
        return Data("""
        {"chart":{"result":[{"meta":{"currency":"KRW","regularMarketPrice":\(price)},
        "timestamp":[1],"indicators":{"quote":[{"close":[\(price)]}]}}]}}
        """.utf8)
    }
}

private struct FakeYahooHTTP: HTTPClient {
    let state: FakeYahooState
    func get(_ url: URL, headers: [String: String]) async throws -> Data { try await state.record() }
}

/// 테스트에서 시간을 옮기기 위한 가변 시계.
private final class FXClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@Suite struct FXServiceTests {
    @Test func maxAgeShortensTheCacheOnlyForThatCall() async throws {
        let state = FakeYahooState()
        let clock = FXClock()
        let fx = FXService(yahoo: YahooProvider(http: FakeYahooHTTP(state: state)), now: { clock.now })

        #expect(try await fx.rate(from: "USD", to: "KRW") == 1_341)
        clock.now += 400
        // 기본 1시간 캐시는 그대로, 5분만 믿는 호출은 새로 받는다.
        #expect(try await fx.rate(from: "USD", to: "KRW") == 1_341)
        #expect(try await fx.rate(from: "USD", to: "KRW", maxAge: 300) == 1_342)
        #expect(await state.calls == 2)
    }

    @Test func staleLimitStopsTheFallbackToOldRates() async throws {
        let state = FakeYahooState()
        let clock = FXClock()
        let fx = FXService(yahoo: YahooProvider(http: FakeYahooHTTP(state: state)), now: { clock.now })
        #expect(try await fx.rate(from: "USD", to: "KRW") == 1_341)

        await state.fail()
        clock.now += 1_800
        // 30분 된 값은 1시간 한도 안이라 쓰고, 3일 된 값은 쓰지 않는다. 한도가 없으면 그대로 쓴다.
        #expect(try await fx.rate(from: "USD", to: "KRW", maxAge: 300, staleLimit: 3_600) == 1_341)
        clock.now += 3 * 86_400
        await #expect(throws: HTTPError.badStatus(429)) {
            try await fx.rate(from: "USD", to: "KRW", maxAge: 300, staleLimit: 3_600)
        }
        #expect(try await fx.rate(from: "USD", to: "KRW") == 1_341)
    }
}
