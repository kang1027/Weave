import Foundation
import Testing
@testable import WeaveCore

@Suite struct ValueSeriesBuilderTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func day(_ n: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(n) * 86_400)
    }

    private func candle(day n: Int, close: Decimal) -> Candle {
        Candle(date: day(n), open: close, high: close, low: close, close: close)
    }

    @Test func seriesStartsAtFirstBuyAndStepsHoldings() {
        let asset = Asset(
            name: "BTC", symbol: "BTC", provider: .binance,
            providerSymbol: "BTCUSDT", market: .crypto, currency: "USD"
        )
        let trades = [
            Trade(assetID: asset.id, side: .buy, quantity: 1, price: 100, date: day(10)),
            Trade(assetID: asset.id, side: .buy, quantity: 1, price: 110, date: day(12))
        ]
        let candles = (8...14).map { candle(day: $0, close: Decimal(100 + $0)) }

        let points = ValueSeriesBuilder.portfolioSeries(
            assets: [asset], trades: trades,
            candlesByAsset: [asset.id: candles],
            fxSeriesByCurrency: [:],
            baseCurrency: "USD",
            from: day(5), to: day(14),
            calendar: calendar
        )

        // 첫 매수일(10일)부터 시작 — 그 이전은 없음
        #expect(points.first?.date == day(10))
        #expect(points.count == 5)
        // 10일: 1 × 110 = 110
        #expect(points[0].value == 110)
        // 12일: 2 × 112 = 224 (매수 당일부터 반영)
        #expect(points[2].value == 224)
        // 14일: 2 × 114 = 228
        #expect(points[4].value == 228)
    }

    @Test func forwardFillsMissingCandleDays() {
        let asset = Asset(
            name: "SAM", symbol: "005930", provider: .naver,
            providerSymbol: "005930", market: .koreaStock, currency: "KRW"
        )
        let trades = [
            Trade(assetID: asset.id, side: .buy, quantity: 10, price: 100, date: day(10))
        ]
        // 주말처럼 11, 12일 캔들 없음
        let candles = [candle(day: 10, close: 100), candle(day: 13, close: 130)]

        let points = ValueSeriesBuilder.portfolioSeries(
            assets: [asset], trades: trades,
            candlesByAsset: [asset.id: candles],
            fxSeriesByCurrency: [:],
            baseCurrency: "KRW",
            from: nil, to: day(13),
            calendar: calendar
        )

        #expect(points.count == 4)
        #expect(points[1].value == 1000) // 11일 → 10일 종가 유지
        #expect(points[2].value == 1000)
        #expect(points[3].value == 1300)
    }

    @Test func convertsWithDailyFxSeries() {
        let asset = Asset(
            name: "BTC", symbol: "BTC", provider: .binance,
            providerSymbol: "BTCUSDT", market: .crypto, currency: "USD"
        )
        let trades = [
            Trade(assetID: asset.id, side: .buy, quantity: 1, price: 100, date: day(10))
        ]
        let candles = [candle(day: 10, close: 100), candle(day: 11, close: 100)]
        let fx = [candle(day: 10, close: 1300), candle(day: 11, close: 1400)]

        let points = ValueSeriesBuilder.portfolioSeries(
            assets: [asset], trades: trades,
            candlesByAsset: [asset.id: candles],
            fxSeriesByCurrency: ["USD": fx],
            baseCurrency: "KRW",
            from: nil, to: day(11),
            calendar: calendar
        )

        #expect(points[0].value == 130_000)
        #expect(points[1].value == 140_000)
    }

    @Test func manualAssetAddsFlatValueWhenIncluded() {
        let btc = Asset(
            name: "BTC", symbol: "BTC", provider: .binance,
            providerSymbol: "BTCUSDT", market: .crypto, currency: "USD"
        )
        var manual = Asset(
            name: "부동산", symbol: "MANUAL", provider: .manual,
            providerSymbol: "", market: .other, currency: "USD",
            manualValue: 500
        )
        let trades = [
            Trade(assetID: btc.id, side: .buy, quantity: 1, price: 100, date: day(10))
        ]
        let candles = [candle(day: 10, close: 100)]

        let included = ValueSeriesBuilder.portfolioSeries(
            assets: [btc, manual], trades: trades,
            candlesByAsset: [btc.id: candles], fxSeriesByCurrency: [:],
            baseCurrency: "USD", from: nil, to: day(10), calendar: calendar
        )
        #expect(included[0].value == 600)

        manual.includeInChart = false
        let excluded = ValueSeriesBuilder.portfolioSeries(
            assets: [btc, manual], trades: trades,
            candlesByAsset: [btc.id: candles], fxSeriesByCurrency: [:],
            baseCurrency: "USD", from: nil, to: day(10), calendar: calendar
        )
        #expect(excluded[0].value == 100)
    }

    @Test func emptyWithoutAnyBuy() {
        let points = ValueSeriesBuilder.portfolioSeries(
            assets: [], trades: [], candlesByAsset: [:], fxSeriesByCurrency: [:],
            baseCurrency: "KRW", from: nil, to: day(10), calendar: calendar
        )
        #expect(points.isEmpty)
    }

    private func hour(_ n: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(n) * 3_600)
    }

    private func hourCandle(_ n: Int, close: Decimal) -> Candle {
        Candle(date: hour(n), open: close, high: close, low: close, close: close)
    }

    @Test func intradaySamplesAtCandleTimestampsWithSpotFX() {
        let btc = Asset(
            name: "BTC", symbol: "BTC", provider: .binance,
            providerSymbol: "BTCUSDT", market: .crypto, currency: "USD"
        )
        let sam = Asset(
            name: "SAM", symbol: "005930", provider: .naver,
            providerSymbol: "005930", market: .koreaStock, currency: "KRW"
        )
        let trades = [
            Trade(assetID: btc.id, side: .buy, quantity: 2, price: 100, date: hour(0)),
            Trade(assetID: sam.id, side: .buy, quantity: 10, price: 1_000, date: hour(0))
        ]
        // BTC는 매시간 캔들, 삼성은 h1·h2만(그 뒤 휴장 → forward-fill).
        let btcCandles = [hourCandle(1, close: 100), hourCandle(2, close: 110), hourCandle(3, close: 120)]
        let samCandles = [hourCandle(1, close: 1_000), hourCandle(2, close: 1_100)]

        let points = ValueSeriesBuilder.intradayPortfolioSeries(
            assets: [btc, sam], trades: trades,
            candlesByAsset: [btc.id: btcCandles, sam.id: samCandles],
            fxSpotByCurrency: ["KRW": Decimal(string: "0.001")!],  // 1000 KRW = 1 USD
            baseCurrency: "USD",
            from: hour(0), to: hour(3)
        )

        // 샘플 격자 = 캔들 타임스탬프 합집합 ∪ {to} = h1,h2,h3
        #expect(points.map(\.date) == [hour(1), hour(2), hour(3)])
        // h1: BTC 2×100 + SAM 10×1000×0.001 = 200 + 10 = 210
        #expect(points[0].value == 210)
        // h2: BTC 2×110 + SAM 10×1100×0.001 = 220 + 11 = 231
        #expect(points[1].value == 231)
        // h3: BTC 2×120 + SAM(휴장, forward-fill 1100) 10×1100×0.001 = 240 + 11 = 251
        #expect(points[2].value == 251)
    }

    @Test func normalizedSeriesStartsAtZeroPercent() {
        let candles = [
            candle(day: 10, close: 200),
            candle(day: 11, close: 220),
            candle(day: 12, close: 180)
        ]
        let series = ValueSeriesBuilder.normalizedSeries(candles: candles, from: day(10), to: day(12))
        #expect(series.count == 3)
        #expect(series[0].percent == 0)
        #expect(abs(series[1].percent - 10) < 0.0001)
        #expect(abs(series[2].percent - -10) < 0.0001)
    }
}
