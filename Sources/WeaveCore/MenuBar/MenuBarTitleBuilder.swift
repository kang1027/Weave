import Foundation

/// 메뉴바 타이틀 문자열 — `BTC $60,000 ▲1.23%`.
public enum MenuBarTitleBuilder {
    public static func title(
        asset: Asset,
        quote: Quote?,
        format: MenuBarFormat,
        privacy: Bool
    ) -> String {
        // 숫자 코드 심볼(국장 005930, 일장 7203 등)은 코드 대신 이름으로 표시.
        let isNumericSymbol = !asset.symbol.isEmpty && asset.symbol.allSatisfy(\.isNumber)
        let name = isNumericSymbol ? asset.name : asset.symbol.uppercased()
        guard let quote else { return name }

        let price = privacy
            ? MoneyFormatter.masked
            : MoneyFormatter.price(quote.price, currency: quote.currency)
        let percent = MoneyFormatter.arrowPercent(quote.changePercent)

        switch format {
        case .full:
            return "\(name) \(price) \(percent)"
        case .compact:
            return "\(name) \(percent)"
        case .priceOnly:
            return privacy ? "\(name) \(percent)" : price
        }
    }

    /// 표시할 자산이 없을 때 — 포트폴리오 총액.
    public static func totalTitle(
        totalBase: Decimal,
        baseCurrency: String,
        dayChangePercent: Decimal,
        privacy: Bool
    ) -> String {
        let percent = MoneyFormatter.arrowPercent(dayChangePercent)
        if privacy {
            return "\(MoneyFormatter.masked) \(percent)"
        }
        return "\(MoneyFormatter.price(totalBase, currency: baseCurrency)) \(percent)"
    }

    /// 자산 0개 or 시세 이전 초기 상태.
    public static let placeholder = WeaveInfo.appName
}
