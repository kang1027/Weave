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
    case second = "1s"
    case m15 = "15m"
    case h1 = "1h"
    case h4 = "4h"
    case day
    case week
    case month

    /// 캔들 하나가 덮는 시간(월봉은 근사값 — 축 계산용).
    public var seconds: TimeInterval {
        switch self {
        case .second: return 1
        case .m15: return 15 * 60
        case .h1: return 3_600
        case .h4: return 4 * 3_600
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        }
    }

    public var isIntraday: Bool {
        switch self {
        case .second, .m15, .h1, .h4: return true
        case .day, .week, .month: return false
        }
    }

    /// 상세 차트 인터벌 pills 순서.
    public static let detailCases: [CandleInterval] = [.m15, .h1, .h4, .day, .week, .month]

    public var label: String {
        switch self {
        case .second: return "1s"
        case .m15: return "15m"
        case .h1: return "1H"
        case .h4: return "4H"
        case .day: return "1D"
        case .week: return "1W"
        case .month: return "1M"
        }
    }
}
