import Foundation
import Testing
@testable import WeaveCore

@Suite struct ProviderParserTests {
    // MARK: - Binance

    @Test func binanceKlines() throws {
        let json = """
        [[1704067200000,"42000.1","43000","41500","42500.5","1000",1704153599999,"0",1,"0","0","0"],
         [1704153600000,"42500.5","44000","42000","43800","900",1704239999999,"0",1,"0","0","0"]]
        """
        let candles = try BinanceProvider.parseKlines(Data(json.utf8))
        #expect(candles.count == 2)
        #expect(candles[0].close == Decimal(string: "42500.5"))
        #expect(candles[0].date == Date(timeIntervalSince1970: 1_704_067_200))
    }

    @Test func binanceExchangeInfoFiltersTradingUSDT() throws {
        let json = """
        {"symbols":[
          {"symbol":"BTCUSDT","status":"TRADING","baseAsset":"BTC","quoteAsset":"USDT"},
          {"symbol":"ETHBTC","status":"TRADING","baseAsset":"ETH","quoteAsset":"BTC"},
          {"symbol":"OLDUSDT","status":"BREAK","baseAsset":"OLD","quoteAsset":"USDT"}
        ]}
        """
        let pairs = try BinanceSymbolCatalog.parseExchangeInfo(Data(json.utf8))
        #expect(pairs == [BinancePair(symbol: "BTCUSDT", baseAsset: "BTC")])
    }

    // MARK: - Naver

    @Test func naverQuoteParsesCommaNumbersAndFallingSign() throws {
        let json = """
        {"datas":[{"closePrice":"61,200","fluctuationsRatio":"0.66",
          "compareToPreviousPrice":{"name":"FALLING"},"localTradedAt":"2026-07-03T15:30:00+09:00"}]}
        """
        let quote = try NaverProvider.parseQuote(Data(json.utf8))
        #expect(quote.price == 61_200)
        #expect(quote.changePercent == Decimal(string: "-0.66"))
        #expect(quote.currency == "KRW")
    }

    @Test func naverSearchKeepsSixDigitDomesticCodes() throws {
        let json = """
        {"items":[
          {"code":"005930","name":"삼성전자","typeCode":"KOSPI"},
          {"code":"AAPL","name":"애플","typeCode":"NASDAQ","nationCode":"USA"}
        ]}
        """
        let results = try NaverProvider.parseSearch(Data(json.utf8))
        #expect(results.count == 1)
        #expect(results[0].providerSymbol == "005930")
        #expect(results[0].market == .koreaStock)
        #expect(results[0].currency == "KRW")
    }

    @Test func naverFchartParsesPipeSeparatedItems() throws {
        let xml = """
        <protocol>
        <chartdata symbol="005930" count="2">
        <item data="20260701|60000|61500|59800|61000|12345678" />
        <item data="20260702|61000|62000|60500|61200|9876543" />
        </chartdata>
        </protocol>
        """
        let candles = try NaverProvider.parseFchart(Data(xml.utf8))
        #expect(candles.count == 2)
        #expect(candles[1].close == 61_200)
        #expect(candles[0].open == 60_000)
    }

    // MARK: - Yahoo

    @Test func yahooQuoteUsesMetaPreviousClose() throws {
        let json = """
        {"chart":{"result":[{
          "meta":{"currency":"KRW","regularMarketPrice":61200.0,"previousClose":60800.0,"regularMarketTime":1751500000},
          "timestamp":[1751400000,1751500000],
          "indicators":{"quote":[{"close":[60800.0,61200.0]}]}
        }]}}
        """
        let quote = try YahooProvider.parseQuote(Data(json.utf8))
        #expect(quote.price == Decimal(string: "61200"))
        #expect(quote.currency == "KRW")
        let expected = ((Decimal(61_200) - 60_800) / 60_800 * 100).rounded(scale: 4)
        #expect(quote.changePercent == expected)
    }

    @Test func yahooQuoteFallsBackToSecondLastClose() throws {
        let json = """
        {"chart":{"result":[{
          "meta":{"currency":"USD","regularMarketPrice":110.0},
          "timestamp":[1,2],
          "indicators":{"quote":[{"close":[100.0,110.0]}]}
        }]}}
        """
        let quote = try YahooProvider.parseQuote(Data(json.utf8))
        #expect(quote.changePercent == 10)
    }

    @Test func yahooCandlesSkipNullCloses() throws {
        let json = """
        {"chart":{"result":[{
          "meta":{"currency":"USD","regularMarketPrice":110.0},
          "timestamp":[86400,172800,259200],
          "indicators":{"quote":[{"close":[100.0,null,110.0],"open":[99.0,null,109.0],
            "high":[101.0,null,111.0],"low":[98.0,null,108.0]}]}
        }]}}
        """
        let candles = try YahooProvider.parseCandles(Data(json.utf8))
        #expect(candles.count == 2)
        #expect(candles[1].close == 110)
    }

    @Test func yahooClassShareKeepsFullSymbolAndUSMarket() {
        #expect(YahooProvider.market(symbol: "BRK.B", quoteType: "EQUITY") == .usStock)
        #expect(YahooProvider.displaySymbol("BRK.B") == "BRK.B")
        #expect(YahooProvider.displaySymbol("005930.KS") == "005930")
        #expect(YahooProvider.displaySymbol("7203.T") == "7203")
        #expect(YahooProvider.displaySymbol("BTC-USD") == "BTC")
    }

    @Test func naverLowerLimitStaysNegative() throws {
        let json = """
        {"datas":[{"closePrice":"7,000","fluctuationsRatio":"-29.90",
          "compareToPreviousPrice":{"name":"LOWER_LIMIT"}}]}
        """
        let quote = try NaverProvider.parseQuote(Data(json.utf8))
        #expect(quote.changePercent == Decimal(string: "-29.90"))
    }

    @Test func yahooSearchMapsMarkets() throws {
        let json = """
        {"quotes":[
          {"symbol":"AAPL","shortname":"Apple Inc.","quoteType":"EQUITY","exchDisp":"NASDAQ"},
          {"symbol":"005930.KS","shortname":"Samsung Electronics","quoteType":"EQUITY"},
          {"symbol":"7203.T","shortname":"Toyota Motor","quoteType":"EQUITY"},
          {"symbol":"BTC-USD","shortname":"Bitcoin USD","quoteType":"CRYPTOCURRENCY"},
          {"symbol":"^GSPC","shortname":"S&P 500","quoteType":"INDEX"},
          {"symbol":"XYZ","shortname":"Some Future","quoteType":"FUTURE"}
        ]}
        """
        let results = try YahooProvider.parseSearch(Data(json.utf8))
        #expect(results.count == 5) // FUTURE 제외
        #expect(results[0].market == .usStock)
        #expect(results[1].market == .koreaStock)
        #expect(results[1].currency == "KRW")
        #expect(results[2].market == .japanStock)
        #expect(results[2].currency == "JPY")
        #expect(results[3].market == .crypto)
        #expect(results[3].symbol == "BTC")
    }

    // MARK: - SearchMerger

    @Test func mergePrefersNaverForKoreaAndBinanceForCrypto() {
        let naver = [SearchResult(provider: .naver, providerSymbol: "005930", symbol: "005930",
                                  name: "삼성전자", market: .koreaStock, currency: "KRW")]
        let binance = [SearchResult(provider: .binance, providerSymbol: "BTCUSDT", symbol: "BTC",
                                    name: "Bitcoin", market: .crypto, currency: "USD")]
        let yahoo = [
            SearchResult(provider: .yahoo, providerSymbol: "005930.KS", symbol: "005930",
                         name: "Samsung Electronics", market: .koreaStock, currency: "KRW"),
            SearchResult(provider: .yahoo, providerSymbol: "BTC-USD", symbol: "BTC",
                         name: "Bitcoin USD", market: .crypto, currency: "USD"),
            SearchResult(provider: .yahoo, providerSymbol: "AAPL", symbol: "AAPL",
                         name: "Apple Inc.", market: .usStock, currency: "USD")
        ]
        let merged = SearchMerger.merge(query: "sam", binance: binance, naver: naver, yahoo: yahoo)
        #expect(merged.filter { $0.market == .koreaStock }.count == 1)
        #expect(merged.first { $0.market == .koreaStock }?.provider == .naver)
        #expect(merged.filter { $0.symbol == "BTC" }.count == 1)
        #expect(merged.first { $0.symbol == "BTC" }?.provider == .binance)
        #expect(merged.contains { $0.providerSymbol == "AAPL" })
    }

    @Test func mergeKeepsYahooKoreaWhenNaverEmpty() {
        let yahoo = [SearchResult(provider: .yahoo, providerSymbol: "005930.KS", symbol: "005930",
                                  name: "Samsung Electronics", market: .koreaStock, currency: "KRW")]
        let merged = SearchMerger.merge(query: "sam", binance: [], naver: [], yahoo: yahoo)
        #expect(merged.count == 1)
    }

    @Test func mergeRanksExactSymbolFirst() {
        let binance = [
            SearchResult(provider: .binance, providerSymbol: "ETHUSDT", symbol: "ETH",
                         name: "Ethereum", market: .crypto, currency: "USD"),
            SearchResult(provider: .binance, providerSymbol: "BTCUSDT", symbol: "BTC",
                         name: "Bitcoin", market: .crypto, currency: "USD")
        ]
        let merged = SearchMerger.merge(query: "btc", binance: binance, naver: [], yahoo: [])
        #expect(merged.first?.symbol == "BTC")
    }
}
