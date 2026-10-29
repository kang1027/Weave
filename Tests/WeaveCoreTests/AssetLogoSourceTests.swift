import Foundation
import Testing
@testable import WeaveCore

@Suite struct AssetLogoSourceTests {
    private let naver = "https://ssl.pstatic.net/imgstock/fn/real/logo/stock/Stock"

    @Test func koreaStockUsesSixDigitCode() throws {
        let source = try #require(AssetLogoSource(market: .koreaStock, symbol: "005930"))
        #expect(source.key == "koreaStock-005930")
        #expect(source.candidates.map(\.absoluteString) == ["\(naver)005930.svg"])
    }

    @Test func usStockTriesNasdaqThenNyse() throws {
        let source = try #require(AssetLogoSource(market: .usStock, symbol: "KO"))
        #expect(source.candidates.map(\.absoluteString) == ["\(naver)KO.O.svg", "\(naver)KO.svg"])
    }

    @Test func usClassShareUsesDotSeparator() throws {
        let source = try #require(AssetLogoSource(market: .usStock, symbol: "BRK-B"))
        #expect(source.key == "usStock-BRK.B")
        #expect(source.candidates.map(\.absoluteString) == ["\(naver)BRK.B.O.svg", "\(naver)BRK.B.svg"])
    }

    @Test func japanStockAddsTokyoSuffix() throws {
        let source = try #require(AssetLogoSource(market: .japanStock, symbol: "7203"))
        #expect(source.candidates.map(\.absoluteString) == ["\(naver)7203.T.svg"])
    }

    @Test func cryptoKeepsIconSetURL() throws {
        let source = try #require(AssetLogoSource(market: .crypto, symbol: "BTC"))
        #expect(source.key == "crypto-btc")
        #expect(source.candidates.map(\.absoluteString) == [
            "https://cdn.jsdelivr.net/gh/spothq/cryptocurrency-icons@master/128/color/btc.png"
        ])
    }

    @Test func unsupportedSymbolsHaveNoSource() {
        #expect(AssetLogoSource(market: .other, symbol: "GOLD") == nil)
        #expect(AssetLogoSource(market: .koreaStock, symbol: "12345") == nil)
        #expect(AssetLogoSource(market: .usStock, symbol: "^GSPC") == nil)
        #expect(AssetLogoSource(market: .usStock, symbol: "") == nil)
    }
}
