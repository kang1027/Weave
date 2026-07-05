import Foundation

public enum ThemePreference: String, Codable, Sendable, CaseIterable {
    case system
    case slate
    case light
}

public enum LanguagePreference: String, Codable, Sendable, CaseIterable {
    case system
    case korean
    case english
}

public enum MenuBarFormat: String, Codable, Sendable, CaseIterable {
    /// `BTC $60,000 ▲1.23%`
    case full
    /// `BTC ▲1.23%`
    case compact
    /// `$60,000`
    case priceOnly
}

public enum DisplayCurrencyMode: String, Codable, Sendable, CaseIterable {
    /// 소스 통화 그대로 — BTC는 $, 삼성전자는 ₩ (기본)
    case source
    /// 기준 통화로 환산
    case base
}

public struct Hotkey: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var theme: ThemePreference
    public var language: LanguagePreference
    /// 총액·통합 차트 등 합산 계산에만 쓰는 기준 통화 — KRW/USD/JPY.
    public var baseCurrency: String
    public var displayCurrencyMode: DisplayCurrencyMode
    /// 시세 폴링 주기(초). 60~900.
    public var quoteRefreshSeconds: Int
    /// 메뉴바 로테이션 간격(초). 0 = 끔.
    public var rotationSeconds: Int
    public var menuBarFormat: MenuBarFormat
    public var privacyMode: Bool
    public var launchAtLogin: Bool
    public var autoUpdateCheck: Bool
    public var hotkey: Hotkey?

    public init(
        theme: ThemePreference = .system,
        language: LanguagePreference = .system,
        baseCurrency: String = "KRW",
        displayCurrencyMode: DisplayCurrencyMode = .source,
        quoteRefreshSeconds: Int = 300,
        rotationSeconds: Int = 10,
        menuBarFormat: MenuBarFormat = .full,
        privacyMode: Bool = false,
        launchAtLogin: Bool = false,
        autoUpdateCheck: Bool = true,
        hotkey: Hotkey? = nil
    ) {
        self.theme = theme
        self.language = language
        self.baseCurrency = baseCurrency
        self.displayCurrencyMode = displayCurrencyMode
        self.quoteRefreshSeconds = quoteRefreshSeconds
        self.rotationSeconds = rotationSeconds
        self.menuBarFormat = menuBarFormat
        self.privacyMode = privacyMode
        self.launchAtLogin = launchAtLogin
        self.autoUpdateCheck = autoUpdateCheck
        self.hotkey = hotkey
    }

    // 필드가 추가돼도 옛 JSON을 그대로 읽을 수 있게 전부 optional 디코딩.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        theme = try c.decodeIfPresent(ThemePreference.self, forKey: .theme) ?? d.theme
        language = try c.decodeIfPresent(LanguagePreference.self, forKey: .language) ?? d.language
        baseCurrency = try c.decodeIfPresent(String.self, forKey: .baseCurrency) ?? d.baseCurrency
        displayCurrencyMode = try c.decodeIfPresent(DisplayCurrencyMode.self, forKey: .displayCurrencyMode) ?? d.displayCurrencyMode
        quoteRefreshSeconds = try c.decodeIfPresent(Int.self, forKey: .quoteRefreshSeconds) ?? d.quoteRefreshSeconds
        rotationSeconds = try c.decodeIfPresent(Int.self, forKey: .rotationSeconds) ?? d.rotationSeconds
        menuBarFormat = try c.decodeIfPresent(MenuBarFormat.self, forKey: .menuBarFormat) ?? d.menuBarFormat
        privacyMode = try c.decodeIfPresent(Bool.self, forKey: .privacyMode) ?? d.privacyMode
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        autoUpdateCheck = try c.decodeIfPresent(Bool.self, forKey: .autoUpdateCheck) ?? d.autoUpdateCheck
        hotkey = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey)
    }
}
