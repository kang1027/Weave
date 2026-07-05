import Foundation

/// 금액·수량·퍼센트 표시 규칙. 뷰와 메뉴바 타이틀이 공유한다.
public enum MoneyFormatter {
    public static func symbol(for currency: String) -> String {
        switch currency.uppercased() {
        case "USD": return "$"
        case "KRW": return "₩"
        case "JPY": return "¥"
        case "EUR": return "€"
        case "GBP": return "£"
        default: return currency.uppercased() + " "
        }
    }

    /// 가격/금액. 크기에 따라 소수 자리 조절: ≥1000 → 0, ≥1 → 2, <1 → 4.
    /// KRW/JPY는 항상 정수.
    public static func price(_ value: Decimal, currency: String) -> String {
        let scale = decimalScale(for: value, currency: currency)
        let sign = value < 0 ? "-" : ""
        return sign + symbol(for: currency) + grouped(abs(value), scale: scale)
    }

    /// 링 툴팁용 축약 금액 — ₩5.19M, $1.2K.
    public static func compactPrice(_ value: Decimal, currency: String) -> String {
        let sign = value < 0 ? "-" : ""
        let a = abs(value)
        let (scaled, suffix): (Decimal, String) =
            a >= 1_000_000_000 ? (a / 1_000_000_000, "B")
            : a >= 1_000_000 ? (a / 1_000_000, "M")
            : a >= 1_000 ? (a / 1_000, "K")
            : (a, "")
        let scale = suffix.isEmpty ? decimalScale(for: value, currency: currency) : 2
        return sign + symbol(for: currency) + grouped(scaled, scale: scale) + suffix
    }

    /// 부호 포함 손익액 — +₩105,000.
    public static func signedPrice(_ value: Decimal, currency: String) -> String {
        let prefix = value >= 0 ? "+" : "-"
        return prefix + price(abs(value), currency: currency)
    }

    /// "+1.23%" / "−0.84%" (마이너스는 U+2212).
    public static func percent(_ value: Decimal, fractionDigits: Int = 2) -> String {
        let prefix = value >= 0 ? "+" : "−"
        return prefix + grouped(abs(value).rounded(scale: fractionDigits), scale: fractionDigits) + "%"
    }

    /// 메뉴바용 "▲1.23%" / "▼0.84%".
    public static func arrowPercent(_ value: Decimal) -> String {
        let arrow = value >= 0 ? "▲" : "▼"
        return arrow + grouped(abs(value).rounded(scale: 2), scale: 2) + "%"
    }

    /// 수량 — 뒤쪽 0 제거, 최대 8자리. "0.05", "45"
    public static func quantity(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        formatter.usesGroupingSeparator = true
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }

    /// 프라이버시 모드 금액 마스킹.
    public static let masked = "•••••"

    private static func decimalScale(for value: Decimal, currency: String) -> Int {
        if ["KRW", "JPY"].contains(currency.uppercased()) { return 0 }
        let a = abs(value)
        if a >= 1000 { return 0 }
        if a >= 1 { return 2 }
        return 4
    }

    private static func grouped(_ value: Decimal, scale: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = scale
        formatter.usesGroupingSeparator = true
        return formatter.string(from: value.rounded(scale: scale) as NSDecimalNumber) ?? "0"
    }
}
