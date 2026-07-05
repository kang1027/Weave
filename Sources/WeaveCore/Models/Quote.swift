import Foundation

public struct Quote: Codable, Equatable, Sendable {
    public var price: Decimal
    /// 일간 변동 % — 소스 제공값 그대로(크립토 24h 롤링, 주식 전일比).
    public var changePercent: Decimal
    public var currency: String
    public var updatedAt: Date

    public init(price: Decimal, changePercent: Decimal, currency: String, updatedAt: Date = Date()) {
        self.price = price
        self.changePercent = changePercent
        self.currency = currency
        self.updatedAt = updatedAt
    }
}

public struct Candle: Codable, Equatable, Sendable {
    /// 봉 시작 시각(일봉이면 그날 자정, 소스 타임존 기준 절삭값).
    public var date: Date
    public var open: Decimal
    public var high: Decimal
    public var low: Decimal
    public var close: Decimal

    public init(date: Date, open: Decimal, high: Decimal, low: Decimal, close: Decimal) {
        self.date = date
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }
}

public enum CandleInterval: String, Codable, Sendable, CaseIterable {
    case day
    case week
    case month
}
