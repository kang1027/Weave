import Foundation
import WeaveCore

extension Asset {
    /// 국장(005930)/일장(7203)처럼 심볼이 숫자 코드면 "99 066570" 표기가 어색하다 —
    /// 이런 자산은 "99주" 스타일로 표시한다.
    var hasNumericSymbol: Bool {
        !symbol.isEmpty && symbol.allSatisfy(\.isNumber)
    }

    /// 보유/거래 수량 표시 문자열 — 국장·일장은 정수, 그 외는 최대 8자리.
    func formattedQuantity(_ quantity: Decimal) -> String {
        MoneyFormatter.quantity(quantity, maxFractionDigits: market.tradesWholeShares ? 0 : 8)
    }
}
