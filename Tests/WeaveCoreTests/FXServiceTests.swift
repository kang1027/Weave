import Foundation
import Testing
@testable import WeaveCore

/// 야후 차트 응답을 흉내 내고 호출 횟수를 센다.
private actor FakeYahooState {
    var calls = 0
    func record() -> Data {
        calls += 1
        let price = 1_340 + calls
        return Data("""
        {"chart":{"result":[{"meta":{"currency":"KRW","regularMarketPrice":\(price)},
        "timestamp":[1],"indicators":{"quote":[{"close":[\(price)]}]}}]}}
        """.utf8)
    }
}

private struct FakeYahooHTTP: HTTPClient {
    let state: FakeYahooState
    func get(_ url: URL, headers: [String: String]) async throws -> Data { await state.record() }
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
}
