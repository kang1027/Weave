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

    /// 가격/금액. USD 등은 소수 2자리 고정(1 미만 코인은 4자리), KRW/JPY는 항상 정수.
    public static func price(_ value: Decimal, currency: String) -> String {
        let scale = decimalScale(for: value, currency: currency)
        let minScale = moneyMinScale(for: currency)
        let sign = value < 0 ? "-" : ""
        return sign + symbol(for: currency) + grouped(abs(value), scale: scale, minScale: minScale)
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
    public static func quantity(_ value: Decimal, maxFractionDigits: Int = 8) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.usesGroupingSeparator = true
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }

    /// 프라이버시 모드 금액 마스킹.
    public static let masked = "•••••"

    /// 숫자 입력 필드용 라이브 포맷 — 숫자·소수점만 남기고 정수부에 천단위 콤마.
    /// 소수부는 1 이상 값이면 2자리, 1 미만(소수 코인 수량)이면 8자리까지. 멱등.
    public static func groupedInputText(_ raw: String) -> String {
        var cleaned = raw.filter { "0123456789.".contains($0) }
        // 소수점은 첫 번째 것만 유지.
        if let firstDot = cleaned.firstIndex(of: ".") {
            let afterDot = cleaned.index(after: firstDot)
            cleaned = String(cleaned[..<afterDot])
                + cleaned[afterDot...].replacingOccurrences(of: ".", with: "")
        }
        guard !cleaned.isEmpty else { return "" }
        let parts = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let intPart = String(parts.first ?? "")
        let grouped = groupDigits(intPart)
        if parts.count > 1 {
            let maxFraction = maxFractionDigits(integerPart: intPart)
            return grouped + "." + parts[1].prefix(maxFraction)
        }
        return grouped
    }

    /// 1 이상이면 소수 2자리로 충분, 1 미만이면 소수 코인 수량을 위해 8자리.
    private static func maxFractionDigits(integerPart: String) -> Int {
        integerPart.contains(where: { $0 != "0" }) ? 2 : 8
    }

    private static func groupDigits(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 {
                result.append(",")
            }
            result.append(character)
        }
        return result
    }

    private static func decimalScale(for value: Decimal, currency: String) -> Int {
        if ["KRW", "JPY"].contains(currency.uppercased()) { return 0 }
        // USD 등: 1 이상은 2자리 고정, 1 미만(소수 코인)은 4자리.
        return abs(value) >= 1 ? 2 : 4
    }

    /// 금액 최소 소수 자리 — USD 등은 2자리를 항상 보이게(₩919 → $919.00), KRW/JPY는 0.
    private static func moneyMinScale(for currency: String) -> Int {
        ["KRW", "JPY"].contains(currency.uppercased()) ? 0 : 2
    }

    private static func grouped(_ value: Decimal, scale: Int, minScale: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = min(minScale, scale)
        formatter.maximumFractionDigits = scale
        formatter.usesGroupingSeparator = true
        return formatter.string(from: value.rounded(scale: scale) as NSDecimalNumber) ?? "0"
    }
}
