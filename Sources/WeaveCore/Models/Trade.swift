import Foundation

public enum TradeSide: String, Codable, Sendable {
    case buy
    case sell
}

public struct Trade: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var assetID: UUID
    public var side: TradeSide
    public var quantity: Decimal
    /// 자산 통화 기준 체결 단가.
    public var price: Decimal
    public var date: Date
    public var note: String

    public var amount: Decimal { quantity * price }

    public init(
        id: UUID = UUID(),
        assetID: UUID,
        side: TradeSide,
        quantity: Decimal,
        price: Decimal,
        date: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.assetID = assetID
        self.side = side
        self.quantity = quantity
        self.price = price
        self.date = date
        self.note = note
    }
}
