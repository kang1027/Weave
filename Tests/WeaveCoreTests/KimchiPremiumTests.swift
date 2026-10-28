import Foundation
import Testing
@testable import WeaveCore

/// 업비트 URL별 응답을 정해 두고 호출 횟수를 센다. 정해지지 않은 URL은 404.
private actor FakeUpbitState {
    var responses: [String: Data] = [:]
    var tickerCalls = 0

    func set(_ path: String, _ json: String) { responses[path] = Data(json.utf8) }

    func respond(to url: URL) throws -> Data {
        if url.path.hasSuffix("/ticker") { tickerCalls += 1 }
        guard let data = responses[url.path] else { throw HTTPError.badStatus(404) }
        return data
    }
}

private struct FakeUpbitHTTP: HTTPClient {
    let state: FakeUpbitState
    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        try await state.respond(to: url)
    }
}

private struct FakeMarket: MarketDataProvider {
    let kind: ProviderKind = .binance
    var price: Decimal = 0
    var candles: [Candle] = []

    func search(query: String) async throws -> [SearchResult] { [] }
    func quote(providerSymbol: String) async throws -> Quote {
        Quote(price: price, changePercent: 0, currency: "USD")
    }
    func candles(providerSymbol: String, interval: CandleInterval) async throws -> [Candle] { candles }
}

private func day(_ value: String) -> Date {
    try! Date(value + "T00:00:00Z", strategy: .iso8601)
}

private func candle(_ date: Date, _ close: Decimal) -> Candle {
    Candle(date: date, open: close, high: close, low: close, close: close)
}

@Suite struct KimchiPremiumTests {
    @Test func percentComparesUpbitWithConvertedBinancePrice() {
        // 1,000달러 × 1,400원 = 1,400,000원. 업비트 1,410,000원이면 약 +0.714%.
        let premium = KimchiPremium(upbitPrice: 1_410_000, binancePrice: 1_000, usdKRW: 1_400)
        #expect(premium.binancePriceKRW == 1_400_000)
        #expect(premium.percent.rounded(scale: 2) == Decimal(string: "0.71"))
        #expect(KimchiPremium.percent(upbitKRW: 1, binanceUSD: 0, usdKRW: 1_400) == nil)
    }

    @Test func dailyHistoryMatchesDaysAndCarriesFXOverWeekend() {
        let upbit = [
            candle(day("2026-10-23"), 1_420_000), // 금
            candle(day("2026-10-24"), 1_400_000), // 토 — 환율 일봉 없음
            candle(day("2026-10-26"), 1_430_000)  // 월 — 바이낸스 일봉 없음
        ]
        let binance = [
            candle(day("2026-10-23"), 1_000),
            candle(day("2026-10-24"), 1_000)
        ]
        // 서머타임 중 야후 환율 일봉은 전날 23:00Z에 찍힌다.
        let fx = [
            candle(day("2026-10-22").addingTimeInterval(23 * 3_600), 1_400),
            candle(day("2026-10-25").addingTimeInterval(23 * 3_600), 1_500)
        ]
        let points = KimchiPremium.dailyHistory(upbit: upbit, binance: binance, usdKRW: fx)
        #expect(points.map(\.date) == [day("2026-10-23"), day("2026-10-24")])
        #expect(points.map { $0.percent.rounded(scale: 2) } == [Decimal(string: "1.43"), 0])
    }

    @Test func upbitParsesTickerAndCandlesOldestFirst() throws {
        let ticker = #"[{"market":"KRW-BTC","trade_price":109298000.0}]"#
        #expect(try UpbitProvider.parseTickerPrice(Data(ticker.utf8)) == 109_298_000)

        let candles = """
        [{"candle_date_time_utc":"2026-10-28T00:00:00","opening_price":1,"high_price":3,"low_price":1,"trade_price":2},
         {"candle_date_time_utc":"2026-10-27T00:00:00","opening_price":1,"high_price":2,"low_price":1,"trade_price":1.5}]
        """
        let parsed = try UpbitProvider.parseCandles(Data(candles.utf8))
        #expect(parsed.map(\.date) == [day("2026-10-27"), day("2026-10-28")])
        #expect(parsed.last?.close == 2)
    }

    @Test func unlistedCoinReturnsNilAndIsRememberedForADay() async throws {
        let state = FakeUpbitState()
        let clock = Clock(day("2026-10-28"))
        let service = KimchiPremiumService(
            upbit: UpbitProvider(http: FakeUpbitHTTP(state: state)),
            binance: FakeMarket(price: 1),
            yahoo: FakeMarket(),
            usdKRW: { 1_400 },
            now: { clock.now }
        )
        #expect(try await service.premium(symbol: "NOPE", binanceSymbol: "NOPEUSDT") == nil)
        #expect(try await service.premium(symbol: "NOPE", binanceSymbol: "NOPEUSDT") == nil)
        #expect(await state.tickerCalls == 1)

        clock.now = day("2026-10-29").addingTimeInterval(60)
        _ = try await service.premium(symbol: "NOPE", binanceSymbol: "NOPEUSDT")
        #expect(await state.tickerCalls == 2)
    }

    @Test func premiumEndsHistoryWithTheCurrentValue() async throws {
        let state = FakeUpbitState()
        await state.set("/v1/ticker", #"[{"trade_price":1428000}]"#)
        await state.set("/v1/candles/days", """
        [{"candle_date_time_utc":"2026-10-28T00:00:00","opening_price":1,"high_price":1,"low_price":1,"trade_price":1400000},
         {"candle_date_time_utc":"2026-10-27T00:00:00","opening_price":1,"high_price":1,"low_price":1,"trade_price":1414000}]
        """)
        let now = day("2026-10-28").addingTimeInterval(12 * 3_600)
        let service = KimchiPremiumService(
            upbit: UpbitProvider(http: FakeUpbitHTTP(state: state)),
            binance: FakeMarket(price: 1_000, candles: [
                candle(day("2026-10-27"), 1_000),
                candle(day("2026-10-28"), 1_000)
            ]),
            yahoo: FakeMarket(candles: [candle(day("2026-10-27"), 1_400)]),
            usdKRW: { 1_400 },
            now: { now }
        )
        let premium = try #require(try await service.premium(symbol: "btc", binanceSymbol: "BTCUSDT"))
        #expect(premium.percent == 2)
        // 10/27 +1%, 진행 중인 10/28 일봉은 현재 김프(+2%)로 바뀐다.
        #expect(premium.history.map(\.percent) == [1, 2])
        #expect(premium.history.last?.date == now)
    }
}

/// 테스트에서 시간을 옮기기 위한 가변 시계.
private final class Clock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}
