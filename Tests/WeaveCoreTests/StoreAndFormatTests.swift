import Foundation
import Testing
@testable import WeaveCore

@Suite struct JSONPortfolioStoreTests {
    private func tempStore() -> JSONPortfolioStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("weave-tests-\(UUID().uuidString)")
            .appendingPathComponent("portfolio.json")
        return JSONPortfolioStore(fileURL: url)
    }

    @Test func missingFileLoadsEmptyDocument() throws {
        let store = tempStore()
        let doc = try store.load()
        #expect(doc == .empty)
    }

    @Test func roundTripPreservesDocument() throws {
        let store = tempStore()
        let asset = Asset(
            name: "Bitcoin", symbol: "BTC", provider: .binance,
            providerSymbol: "BTCUSDT", market: .crypto, currency: "USD",
            colorIndex: 3, createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let trade = Trade(
            assetID: asset.id, side: .buy, quantity: Decimal(string: "0.05")!,
            price: 60_000, date: Date(timeIntervalSince1970: 1_700_000_000), note: "첫 진입"
        )
        var settings = AppSettings()
        settings.baseCurrency = "USD"
        settings.rotationSeconds = 30
        let doc = PortfolioDocument(assets: [asset], trades: [trade], settings: settings)

        try store.save(doc)
        let loaded = try store.load()
        #expect(loaded == doc)
    }

    @Test func partialSettingsJSONDecodesWithDefaults() throws {
        let json = """
        {"version":1,"assets":[],"trades":[],"settings":{"baseCurrency":"USD"}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(PortfolioDocument.self, from: Data(json.utf8))
        #expect(doc.settings.baseCurrency == "USD")
        #expect(doc.settings.quoteRefreshSeconds == 300)
        #expect(doc.settings.theme == .system)
        #expect(doc.settings.privacyMode == false)
    }

    @Test func unknownEnumValuesFallBackWithoutFailingDocument() throws {
        // 신버전이 추가한 enum 값이 있어도 문서 전체가 깨지면 안 된다.
        let json = """
        {"version":1,"assets":[],"trades":[],
         "settings":{"theme":"midnight","menuBarFormat":"emoji","rotationSeconds":30}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(PortfolioDocument.self, from: Data(json.utf8))
        #expect(doc.settings.theme == .system)
        #expect(doc.settings.menuBarFormat == .full)
        #expect(doc.settings.rotationSeconds == 30)
    }

    @Test func unreadableFileIsBackedUpBeforeThrowing() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("not json at all".utf8).write(to: store.fileURL)
        #expect(throws: Error.self) { try store.load() }
        let backups = try FileManager.default
            .contentsOfDirectory(at: store.fileURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("portfolio-unreadable-") }
        #expect(backups.count == 1)
    }

    @Test func newerSchemaVersionFailsLoud() throws {
        let store = tempStore()
        let json = """
        {"version":99,"assets":[],"trades":[],"settings":{}}
        """
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: store.fileURL)
        #expect(throws: PortfolioMigrator.MigrationError.newerThanApp(99)) {
            try store.load()
        }
    }
}

@Suite struct MoneyFormatterTests {
    @Test func priceScalesByMagnitudeAndCurrency() {
        #expect(MoneyFormatter.price(60_000, currency: "USD") == "$60,000")
        #expect(MoneyFormatter.price(Decimal(string: "3.4567")!, currency: "USD") == "$3.46")
        #expect(MoneyFormatter.price(Decimal(string: "0.12345")!, currency: "USD") == "$0.1235")
        #expect(MoneyFormatter.price(Decimal(string: "61200.7")!, currency: "KRW") == "₩61,201")
        #expect(MoneyFormatter.price(1_234, currency: "JPY") == "¥1,234")
    }

    @Test func percentUsesTypographicMinus() {
        #expect(MoneyFormatter.percent(Decimal(string: "1.234")!) == "+1.23%")
        #expect(MoneyFormatter.percent(Decimal(string: "-0.845")!) == "−0.85%")
    }

    @Test func arrowPercent() {
        #expect(MoneyFormatter.arrowPercent(Decimal(string: "1.23")!) == "▲1.23%")
        #expect(MoneyFormatter.arrowPercent(Decimal(string: "-0.84")!) == "▼0.84%")
    }

    @Test func compactPrice() {
        #expect(MoneyFormatter.compactPrice(5_190_000, currency: "KRW") == "₩5.19M")
        #expect(MoneyFormatter.compactPrice(1_234, currency: "USD") == "$1.23K")
        #expect(MoneyFormatter.compactPrice(999, currency: "USD") == "$999")
    }

    @Test func quantityTrimsTrailingZeros() {
        #expect(MoneyFormatter.quantity(Decimal(string: "0.0500")!) == "0.05")
        #expect(MoneyFormatter.quantity(45) == "45")
        #expect(MoneyFormatter.quantity(Decimal(string: "1234.5")!) == "1,234.5")
    }

    @Test func signedPrice() {
        #expect(MoneyFormatter.signedPrice(105_000, currency: "KRW") == "+₩105,000")
        #expect(MoneyFormatter.signedPrice(-89_400, currency: "KRW") == "-₩89,400")
    }

    @Test func groupedInputTextAddsThousandsSeparators() {
        #expect(MoneyFormatter.groupedInputText("303000") == "303,000")
        #expect(MoneyFormatter.groupedInputText("29997000.5") == "29,997,000.5")
        #expect(MoneyFormatter.groupedInputText("1234.") == "1,234.")      // 입력 중 소수점 보존
        #expect(MoneyFormatter.groupedInputText("0.0500") == "0.0500")    // 소수부 그대로
        #expect(MoneyFormatter.groupedInputText(".5") == ".5")
        #expect(MoneyFormatter.groupedInputText("1,2,3") == "123")        // 재그룹
        #expect(MoneyFormatter.groupedInputText("1.2.3") == "1.23")       // 소수점 하나만
        #expect(MoneyFormatter.groupedInputText("abc12x3") == "123")      // 숫자만
        #expect(MoneyFormatter.groupedInputText("") == "")
        // 멱등 — 재적용해도 동일.
        let once = MoneyFormatter.groupedInputText("1234567.89")
        #expect(MoneyFormatter.groupedInputText(once) == once)
    }
}

@Suite struct MenuBarTitleBuilderTests {
    private let asset = Asset(
        name: "Bitcoin", symbol: "BTC", provider: .binance,
        providerSymbol: "BTCUSDT", market: .crypto, currency: "USD"
    )
    private let quote = Quote(price: 60_000, changePercent: Decimal(string: "1.23")!, currency: "USD")

    @Test func fullFormat() {
        let title = MenuBarTitleBuilder.title(asset: asset, quote: quote, format: .full, privacy: false)
        #expect(title == "BTC $60,000 ▲1.23%")
    }

    @Test func compactFormat() {
        let title = MenuBarTitleBuilder.title(asset: asset, quote: quote, format: .compact, privacy: false)
        #expect(title == "BTC ▲1.23%")
    }

    @Test func priceOnlyFormat() {
        let title = MenuBarTitleBuilder.title(asset: asset, quote: quote, format: .priceOnly, privacy: false)
        #expect(title == "$60,000")
    }

    @Test func privacyMasksAmountsButKeepsPercent() {
        let full = MenuBarTitleBuilder.title(asset: asset, quote: quote, format: .full, privacy: true)
        #expect(full == "BTC ••••• ▲1.23%")
        let priceOnly = MenuBarTitleBuilder.title(asset: asset, quote: quote, format: .priceOnly, privacy: true)
        #expect(priceOnly == "BTC ▲1.23%")
    }

    @Test func totalTitle() {
        let title = MenuBarTitleBuilder.totalTitle(
            totalBase: 12_345_678, baseCurrency: "KRW",
            dayChangePercent: Decimal(string: "1.23")!, privacy: false
        )
        #expect(title == "₩12,345,678 ▲1.23%")
    }

    @Test func totalTitlePrivacyMasksAmount() {
        let title = MenuBarTitleBuilder.totalTitle(
            totalBase: 12_345_678, baseCurrency: "KRW",
            dayChangePercent: Decimal(string: "1.23")!, privacy: true
        )
        #expect(title == "••••• ▲1.23%")
    }
}

@Suite struct TradeFormCalculatorTests {
    @Test func quantityAndPriceFillAmount() {
        let values = TradeFormCalculator.autofill(
            .init(quantity: 10, price: 100), edited: .price
        )
        #expect(values.amount == 1000)
    }

    @Test func amountAndPriceFillQuantity() {
        let values = TradeFormCalculator.autofill(
            .init(price: 100, amount: 1000), edited: .amount
        )
        #expect(values.quantity == 10)
    }

    @Test func amountAndQuantityFillPrice() {
        let values = TradeFormCalculator.autofill(
            .init(quantity: 8, amount: 1000), edited: .quantity
        )
        #expect(values.price == 125)
    }

    @Test func sellValidation() {
        #expect(TradeFormCalculator.validateSell(quantity: 5, available: 10))
        #expect(!TradeFormCalculator.validateSell(quantity: 11, available: 10))
        #expect(!TradeFormCalculator.validateSell(quantity: 0, available: 10))
    }
}
