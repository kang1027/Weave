import Foundation

/// 자산 보유 중 한 곳(연결한 계좌·지갑 또는 직접 입력)에 있는 몫.
public struct HoldingLocation: Equatable, Sendable {
    /// nil이면 직접 입력한 거래.
    public var sourceID: UUID?
    public var quantity: Decimal

    public init(sourceID: UUID?, quantity: Decimal) {
        self.sourceID = sourceID
        self.quantity = quantity
    }
}

public enum HoldingLocations {
    /// 거래를 출처별로 따로 재생해 어디에 얼마 있는지 나눈다. 비어 있는 곳은 뺀다.
    /// 많이 가진 곳부터, 직접 입력은 맨 뒤.
    public static func breakdown(trades: [Trade]) -> [HoldingLocation] {
        Dictionary(grouping: trades, by: \.sourceID)
            .map { HoldingLocation(sourceID: $0.key, quantity: PositionCalculator.snapshot(trades: $0.value).quantity) }
            .filter { $0.quantity > 0 }
            .sorted { lhs, rhs in
                if (lhs.sourceID == nil) != (rhs.sourceID == nil) { return rhs.sourceID == nil }
                return lhs.quantity > rhs.quantity
            }
    }
}
