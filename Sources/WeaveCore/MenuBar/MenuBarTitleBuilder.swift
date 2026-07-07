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

    /// 메뉴바 이미지 렌더용 구성요소 — 등락%만 색칠하고 compact는 2줄로 쌓기 위함.
    public struct MenuBarParts: Equatable, Sendable {
        /// 앞부분(색 없음) — full: "이름 가격", compact: "이름", priceOnly: "가격".
        public var leading: String
        /// 색칠할 등락% 토큰(▲/▼). 없으면 nil.
        public var percent: String?
        public var isUp: Bool
        /// compact — 이름 위, 등락% 아래 2줄로.
        public var stacked: Bool

        public init(leading: String, percent: String?, isUp: Bool, stacked: Bool) {
            self.leading = leading
            self.percent = percent
            self.isUp = isUp
            self.stacked = stacked
        }
    }

    public static func parts(
        asset: Asset,
        quote: Quote?,
        format: MenuBarFormat,
        privacy: Bool
    ) -> MenuBarParts {
        let isNumericSymbol = !asset.symbol.isEmpty && asset.symbol.allSatisfy(\.isNumber)
        let name = isNumericSymbol ? asset.name : asset.symbol.uppercased()
        guard let quote else {
            return MenuBarParts(leading: name, percent: nil, isUp: true, stacked: false)
        }
        let price = privacy
            ? MoneyFormatter.masked
            : MoneyFormatter.price(quote.price, currency: quote.currency)
        let percent = MoneyFormatter.arrowPercent(quote.changePercent)
        let isUp = quote.changePercent >= 0
        switch format {
        case .full:
            return MenuBarParts(leading: "\(name) \(price)", percent: percent, isUp: isUp, stacked: false)
        case .compact:
            return MenuBarParts(leading: name, percent: percent, isUp: isUp, stacked: true)
        case .priceOnly:
            return privacy
                ? MenuBarParts(leading: name, percent: percent, isUp: isUp, stacked: false)
                : MenuBarParts(leading: price, percent: nil, isUp: isUp, stacked: false)
        }
    }

    /// 포트폴리오 총액 표시용 구성요소(1줄).
    public static func totalParts(
        totalBase: Decimal,
        baseCurrency: String,
        dayChangePercent: Decimal,
        privacy: Bool
    ) -> MenuBarParts {
        let price = privacy ? MoneyFormatter.masked : MoneyFormatter.price(totalBase, currency: baseCurrency)
        return MenuBarParts(
            leading: price,
            percent: MoneyFormatter.arrowPercent(dayChangePercent),
            isUp: dayChangePercent >= 0,
            stacked: false
        )
    }
}
