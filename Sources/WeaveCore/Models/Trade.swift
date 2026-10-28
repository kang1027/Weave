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
    /// 연결된 계좌·지갑에서 가져온 거래면 그 연결 ID. nil이면 직접 입력.
    public var sourceID: UUID?
    /// 연결 소스가 준 체결 ID — 같은 체결을 두 번 가져오지 않게 한다.
    public var externalID: String?
    /// 기초 잔고 — 받아온 체결 이력보다 보유가 많을 때 채우는 시작 매수.
    public var openingBalance: Bool?

    public var amount: Decimal { quantity * price }
    /// 가져온 거래는 소스가 원본이라 앱에서 고치거나 지우지 않는다.
    public var isImported: Bool { sourceID != nil }
    public var isOpeningBalance: Bool { openingBalance == true }

    public init(
        id: UUID = UUID(),
        assetID: UUID,
        side: TradeSide,
        quantity: Decimal,
        price: Decimal,
        date: Date = Date(),
        note: String = "",
        sourceID: UUID? = nil,
        externalID: String? = nil,
        openingBalance: Bool? = nil
    ) {
        self.id = id
        self.assetID = assetID
        self.side = side
        self.quantity = quantity
        self.price = price
        self.date = date
        self.note = note
        self.sourceID = sourceID
        self.externalID = externalID
        self.openingBalance = openingBalance
    }
}
