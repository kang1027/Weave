import Foundation

extension Decimal {
    /// API가 주는 숫자 문자열("61,200", "1.23") → Decimal. 콤마 제거 후 en_US 파싱.
    public static func clean(_ raw: String) -> Decimal? {
        let stripped = raw
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }
        return Decimal(string: stripped, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Double → Decimal. 부동소수점 노이즈를 피하려고 문자열 경유.
    public static func fromDouble(_ value: Double) -> Decimal {
        guard value.isFinite else { return 0 }
        return Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    public var doubleValue: Double {
        (self as NSDecimalNumber).doubleValue
    }

    /// 지정 자리수로 반올림(bankers 아님, plain).
    public func rounded(scale: Int) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }
}
