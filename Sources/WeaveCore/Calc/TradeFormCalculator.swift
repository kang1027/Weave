import Foundation

/// 거래 입력 폼 — 수량/단가/총액 중 2개를 채우면 나머지를 자동 계산.
public enum TradeFormCalculator {
    public enum Field: Sendable, Hashable {
        case quantity
        case price
        case amount
    }

    public struct Values: Equatable, Sendable {
        public var quantity: Decimal?
        public var price: Decimal?
        public var amount: Decimal?

        public init(quantity: Decimal? = nil, price: Decimal? = nil, amount: Decimal? = nil) {
            self.quantity = quantity
            self.price = price
            self.amount = amount
        }
    }

    /// `edited`는 사용자가 방금 고친 필드. 이미 채워진 다른 필드와 조합해 남은 값을 계산한다.
    /// 유저 입력 필드를 덮어쓰지 않는 것이 원칙 — 파생 필드만 갱신.
    public static func autofill(_ values: Values, edited: Field) -> Values {
        var result = values
        switch edited {
        case .quantity:
            if let q = values.quantity, let p = values.price {
                result.amount = smartRounded(q * p)
            } else if let q = values.quantity, let a = values.amount, q > 0 {
                result.price = smartRounded(a / q)
            }
        case .price:
            if let p = values.price, let q = values.quantity {
                result.amount = smartRounded(p * q)
            } else if let p = values.price, let a = values.amount, p > 0 {
                result.quantity = smartRounded(a / p)
            }
        case .amount:
            if let a = values.amount, let p = values.price, p > 0 {
                result.quantity = smartRounded(a / p)
            } else if let a = values.amount, let q = values.quantity, q > 0 {
                result.price = smartRounded(a / q)
            }
        }
        return result
    }

    /// 파생값 반올림 — 1 이상은 소수 2자리(437.27740075 같은 노이즈 방지),
    /// 1 미만은 소수 코인 수량을 위해 8자리 유지.
    public static func smartRounded(_ value: Decimal) -> Decimal {
        abs(value) >= 1 ? value.rounded(scale: 2) : value.rounded(scale: 8)
    }

    /// 매도 검증 — 보유 수량 초과 불가.
    public static func validateSell(
        quantity: Decimal,
        available: Decimal
    ) -> Bool {
        quantity > 0 && quantity <= available
    }
}
