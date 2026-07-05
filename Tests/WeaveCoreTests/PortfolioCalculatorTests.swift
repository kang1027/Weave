import Foundation
import Testing
@testable import WeaveCore

@Suite struct PortfolioCalculatorTests {
    private func makeAsset(
        name: String,
        currency: String = "USD",
        colorIndex: Int = 0,
        provider: ProviderKind = .binance,
        manualValue: Decimal? = nil
    ) -> Asset {
        Asset(
            name: name,
            symbol: name,
            provider: provider,
            providerSymbol: name,
            market: .crypto,
            currency: currency,
            colorIndex: colorIndex,
            manualValue: manualValue
        )
    }

    private func buy(_ asset: Asset, qty: Decimal, price: Decimal) -> Trade {
        Trade(assetID: asset.id, side: .buy, quantity: qty, price: price,
              date: Date(timeIntervalSince1970: 0))
    }

    @Test func totalsAndReturnInBaseCurrency() {
        let btc = makeAsset(name: "BTC", currency: "USD")
        let sam = makeAsset(name: "SAM", currency: "KRW", provider: .naver)
        let trades = [
            buy(btc, qty: 1, price: 50_000),   // 현재 60,000 → +10,000 USD
            buy(sam, qty: 10, price: 50_000)   // 현재 61,200 → +112,000 KRW
        ]
        let quotes: [UUID: Quote] = [
            btc.id: Quote(price: 60_000, changePercent: 2, currency: "USD"),
            sam.id: Quote(price: 61_200, changePercent: -1, currency: "KRW")
        ]
        let fx: [String: Decimal] = ["USD": 1300, "KRW": 1]

        let (perAsset, portfolio) = PortfolioCalculator.compute(
            assets: [btc, sam], trades: trades, quotes: quotes,
            fxRates: fx, baseCurrency: "KRW"
        )

        // 총액 = 60,000×1300 + 612,000 = 78,612,000
        #expect(portfolio.totalValueBase == 78_612_000)
        // 미실현 = 10,000×1300 + 112,000 = 13,112,000, 원가 = 65,500,000
        #expect(portfolio.unrealizedPnLBase == 13_112_000)
        let expectedReturn = (Decimal(13_112_000) / Decimal(65_500_000) * 100).rounded(scale: 4)
        #expect(portfolio.totalReturnPercent == expectedReturn)
        // 평가금 내림차순 정렬
        #expect(perAsset.first?.asset.id == btc.id)
        #expect(abs(perAsset[0].weight + perAsset[1].weight - 1.0) < 0.0001)
    }

    @Test func dayChangeUsesSourcePercent() {
        let btc = makeAsset(name: "BTC")
        let trades = [buy(btc, qty: 1, price: 100)]
        let quotes = [btc.id: Quote(price: 110, changePercent: 10, currency: "USD")]
        let (_, portfolio) = PortfolioCalculator.compute(
            assets: [btc], trades: trades, quotes: quotes,
            fxRates: ["USD": 1], baseCurrency: "USD"
        )
        // 전일 100 → 오늘 110 ⇒ +10%
        #expect(portfolio.dayChangePercent == 10)
    }

    @Test func ringSegmentsKeepOnlySameSignContributors() {
        let win = makeAsset(name: "WIN", colorIndex: 0)
        let win2 = makeAsset(name: "WIN2", colorIndex: 1)
        let lose = makeAsset(name: "LOSE", colorIndex: 2)
        let trades = [
            buy(win, qty: 1, price: 100),    // +200
            buy(win2, qty: 1, price: 100),   // +100
            buy(lose, qty: 1, price: 100)    // -50
        ]
        let quotes: [UUID: Quote] = [
            win.id: Quote(price: 300, changePercent: 0, currency: "USD"),
            win2.id: Quote(price: 200, changePercent: 0, currency: "USD"),
            lose.id: Quote(price: 50, changePercent: 0, currency: "USD")
        ]
        let (_, portfolio) = PortfolioCalculator.compute(
            assets: [win, win2, lose], trades: trades, quotes: quotes,
            fxRates: ["USD": 1], baseCurrency: "USD"
        )
        // 총 +250 → 이득 기여 종목만, 기여 순 정렬(200, 100), 비율 200/300·100/300
        let segments = portfolio.returnSegments
        #expect(segments.count == 2)
        #expect(segments[0].assetID == win.id)
        #expect(abs(segments[0].fraction - 2.0 / 3.0) < 0.0001)
        #expect(abs(segments[1].fraction - 1.0 / 3.0) < 0.0001)
    }

    @Test func donutGroupsBeyondTopFourIntoEtc() {
        let assets = (0..<6).map { makeAsset(name: "A\($0)", colorIndex: $0) }
        var trades: [Trade] = []
        var quotes: [UUID: Quote] = [:]
        for (index, asset) in assets.enumerated() {
            trades.append(buy(asset, qty: 1, price: 100))
            // 가치 600, 500, 400, 300, 200, 100
            quotes[asset.id] = Quote(price: Decimal((6 - index) * 100), changePercent: 0, currency: "USD")
        }
        let (_, portfolio) = PortfolioCalculator.compute(
            assets: assets, trades: trades, quotes: quotes,
            fxRates: ["USD": 1], baseCurrency: "USD"
        )
        let donut = portfolio.assetSegments
        #expect(donut.count == 5)
        #expect(donut.last?.assetID == nil)     // 기타
        #expect(donut.last?.amountBase == 300)  // 200+100
        #expect(portfolio.assetCount == 6)
    }

    @Test func manualAssetCountsInValueButNotReturn() {
        let btc = makeAsset(name: "BTC")
        let manual = makeAsset(name: "부동산", currency: "KRW", provider: .manual, manualValue: 1_000_000)
        let trades = [buy(btc, qty: 1, price: 100)]
        let quotes = [btc.id: Quote(price: 200, changePercent: 5, currency: "USD")]
        let (_, portfolio) = PortfolioCalculator.compute(
            assets: [btc, manual], trades: trades, quotes: quotes,
            fxRates: ["USD": 1000, "KRW": 1], baseCurrency: "KRW"
        )
        #expect(portfolio.totalValueBase == 1_200_000)
        // 수익률은 manual 제외: 100,000/100,000 = 100%
        #expect(portfolio.totalReturnPercent == 100)
    }

    @Test func hiddenAssetsAreExcluded() {
        let btc = makeAsset(name: "BTC")
        var hidden = makeAsset(name: "HIDE")
        hidden.isHidden = true
        let trades = [buy(btc, qty: 1, price: 100), buy(hidden, qty: 1, price: 100)]
        let quotes: [UUID: Quote] = [
            btc.id: Quote(price: 100, changePercent: 0, currency: "USD"),
            hidden.id: Quote(price: 100, changePercent: 0, currency: "USD")
        ]
        let (perAsset, portfolio) = PortfolioCalculator.compute(
            assets: [btc, hidden], trades: trades, quotes: quotes,
            fxRates: ["USD": 1], baseCurrency: "USD"
        )
        #expect(perAsset.count == 1)
        #expect(portfolio.totalValueBase == 100)
    }

    @Test func missingQuoteFallsBackToCost() {
        let btc = makeAsset(name: "BTC")
        let trades = [buy(btc, qty: 2, price: 100)]
        let (perAsset, portfolio) = PortfolioCalculator.compute(
            assets: [btc], trades: trades, quotes: [:],
            fxRates: ["USD": 1], baseCurrency: "USD"
        )
        #expect(perAsset[0].value == 200)
        #expect(perAsset[0].dayChangePercent == nil)
        #expect(portfolio.totalReturnPercent == 0)
    }

    @Test func ringScaleClampsToFull() {
        #expect(RingScale.fillFraction(percent: 1, fullAt: 2) == 0.5)
        #expect(RingScale.fillFraction(percent: -1, fullAt: 2) == 0.5)
        #expect(RingScale.fillFraction(percent: 5, fullAt: 2) == 1)
        #expect(RingScale.fillFraction(percent: 0, fullAt: 25) == 0)
    }
}
