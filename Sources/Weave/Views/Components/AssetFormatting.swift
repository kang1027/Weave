import Foundation
import WeaveCore

extension Asset {
    /// 국장(005930)/일장(7203)처럼 심볼이 숫자 코드면 "99 066570" 표기가 어색하다 —
    /// 이런 자산은 "99주" 스타일로 표시한다.
    var hasNumericSymbol: Bool {
        !symbol.isEmpty && symbol.allSatisfy(\.isNumber)
    }
}
