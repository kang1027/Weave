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
    /// 2줄 — 이름(위) / 가격 등락%(아래)
    case full
    /// 2줄 — 이름(위) / 등락%(아래)
    case compact
    /// 1줄 — 로고 배지 · 가격 · 등락%
    case inline
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
    /// Day 링이 꽉 차는 절대 등락%(만점). 초과분은 색을 달리해 다음 바퀴로.
    public var dayRingFullPercent: Int
    /// Return 링이 꽉 차는 절대 수익률%(만점).
    public var returnRingFullPercent: Int

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
        hotkey: Hotkey? = nil,
        dayRingFullPercent: Int = 2,
        returnRingFullPercent: Int = 25
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
        self.dayRingFullPercent = dayRingFullPercent
        self.returnRingFullPercent = returnRingFullPercent
    }

    enum CodingKeys: String, CodingKey {
        case theme, language, baseCurrency, displayCurrencyMode
        case quoteRefreshSeconds, rotationSeconds, menuBarFormat
        case privacyMode, launchAtLogin, autoUpdateCheck, hotkey
        case dayRingFullPercent, returnRingFullPercent
    }

    // 필드 추가·미지의 enum 값·타입 불일치가 있어도 문서 전체 로드가 깨지지 않게
    // 전부 관대하게 디코딩한다(설정 하나 때문에 포트폴리오가 날아가면 안 된다).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        theme = Self.lenientEnum(c, .theme, d.theme)
        language = Self.lenientEnum(c, .language, d.language)
        baseCurrency = (try? c.decodeIfPresent(String.self, forKey: .baseCurrency)) ?? nil ?? d.baseCurrency
        displayCurrencyMode = Self.lenientEnum(c, .displayCurrencyMode, d.displayCurrencyMode)
        quoteRefreshSeconds = (try? c.decodeIfPresent(Int.self, forKey: .quoteRefreshSeconds)) ?? nil ?? d.quoteRefreshSeconds
        rotationSeconds = (try? c.decodeIfPresent(Int.self, forKey: .rotationSeconds)) ?? nil ?? d.rotationSeconds
        menuBarFormat = Self.lenientEnum(c, .menuBarFormat, d.menuBarFormat)
        privacyMode = (try? c.decodeIfPresent(Bool.self, forKey: .privacyMode)) ?? nil ?? d.privacyMode
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? nil ?? d.launchAtLogin
        autoUpdateCheck = (try? c.decodeIfPresent(Bool.self, forKey: .autoUpdateCheck)) ?? nil ?? d.autoUpdateCheck
        hotkey = (try? c.decodeIfPresent(Hotkey.self, forKey: .hotkey)) ?? nil
        dayRingFullPercent = (try? c.decodeIfPresent(Int.self, forKey: .dayRingFullPercent)) ?? nil ?? d.dayRingFullPercent
        returnRingFullPercent = (try? c.decodeIfPresent(Int.self, forKey: .returnRingFullPercent)) ?? nil ?? d.returnRingFullPercent
    }

    private static func lenientEnum<T: RawRepresentable>(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        _ fallback: T
    ) -> T where T.RawValue == String {
        guard let raw = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil else {
            return fallback
        }
        return T(rawValue: raw) ?? fallback
    }
}
