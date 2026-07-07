import Foundation

/// 메뉴바 라벨 — 접근성용 1줄 문자열(title)과 이미지 렌더용 구성요소(parts).
public enum MenuBarTitleBuilder {
    /// 접근성/폴백용 1줄 문자열.
    public static func title(
        asset: Asset,
        quote: Quote?,
        format: MenuBarFormat,
        privacy: Bool
    ) -> String {
        let name = displayName(asset)
        guard let quote else { return name }

        let price = privacy
            ? MoneyFormatter.masked
            : MoneyFormatter.price(quote.price, currency: quote.currency)
        let percent = MoneyFormatter.arrowPercent(quote.changePercent)

        switch format {
        case .full, .inline:
            return "\(name) \(price) \(percent)"
        case .compact:
            return "\(name) \(percent)"
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

    // MARK: - 이미지 렌더용 구성요소

    /// 한 줄 = 색 없는 앞부분 + 색칠할 등락%(옵션).
    public struct Line: Equatable, Sendable {
        public var text: String
        /// 초록/빨강으로 색칠할 등락% 토큰(앞 공백 포함). 없으면 nil.
        public var percent: String?

        public init(text: String, percent: String? = nil) {
            self.text = text
            self.percent = percent
        }
    }

    /// 1줄 왼쪽 배지(inline 포맷) — 팔레트 색 원 + 이니셜.
    public struct Badge: Equatable, Sendable {
        public var initial: String
        public var colorIndex: Int

        public init(initial: String, colorIndex: Int) {
            self.initial = initial
            self.colorIndex = colorIndex
        }
    }

    public struct MenuBarParts: Equatable, Sendable {
        public var line1: Line
        /// nil이면 1줄, 있으면 2줄.
        public var line2: Line?
        public var isUp: Bool
        /// inline 포맷의 앞 배지.
        public var badge: Badge?

        public init(line1: Line, line2: Line? = nil, isUp: Bool, badge: Badge? = nil) {
            self.line1 = line1
            self.line2 = line2
            self.isUp = isUp
            self.badge = badge
        }
    }

    public static func parts(
        asset: Asset,
        quote: Quote?,
        format: MenuBarFormat,
        privacy: Bool
    ) -> MenuBarParts {
        let name = displayName(asset)
        guard let quote else {
            let badge = format == .inline ? Badge(initial: badgeInitial(asset), colorIndex: asset.colorIndex) : nil
            return MenuBarParts(line1: Line(text: name), isUp: true, badge: badge)
        }
        let price = privacy
            ? MoneyFormatter.masked
            : MoneyFormatter.price(quote.price, currency: quote.currency)
        let percent = MoneyFormatter.arrowPercent(quote.changePercent)
        let isUp = quote.changePercent >= 0

        switch format {
        case .full:
            // 이름(위) / 가격 등락%(아래)
            return MenuBarParts(
                line1: Line(text: name),
                line2: Line(text: price, percent: " " + percent),
                isUp: isUp
            )
        case .compact:
            // 이름(위) / 등락%(아래)
            return MenuBarParts(
                line1: Line(text: name),
                line2: Line(text: "", percent: percent),
                isUp: isUp
            )
        case .inline:
            // [로고 배지] 가격 등락%  (1줄)
            return MenuBarParts(
                line1: Line(text: price, percent: " " + percent),
                isUp: isUp,
                badge: Badge(initial: badgeInitial(asset), colorIndex: asset.colorIndex)
            )
        }
    }

    /// 포트폴리오 총액 표시용 구성요소(항상 1줄, 배지 없음).
    public static func totalParts(
        totalBase: Decimal,
        baseCurrency: String,
        dayChangePercent: Decimal,
        privacy: Bool
    ) -> MenuBarParts {
        let price = privacy ? MoneyFormatter.masked : MoneyFormatter.price(totalBase, currency: baseCurrency)
        return MenuBarParts(
            line1: Line(text: price, percent: " " + MoneyFormatter.arrowPercent(dayChangePercent)),
            isUp: dayChangePercent >= 0
        )
    }

    // MARK: - 헬퍼

    /// 숫자 코드 심볼(국장 005930 등)은 이름, 그 외는 심볼 대문자.
    private static func displayName(_ asset: Asset) -> String {
        let isNumericSymbol = !asset.symbol.isEmpty && asset.symbol.allSatisfy(\.isNumber)
        return isNumericSymbol ? asset.name : asset.symbol.uppercased()
    }

    private static func badgeInitial(_ asset: Asset) -> String {
        String(asset.name.prefix(1)).uppercased()
    }
}
