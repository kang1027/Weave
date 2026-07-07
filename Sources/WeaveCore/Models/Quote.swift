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
    case m15 = "15m"
    case h1 = "1h"
    case h4 = "4h"
    case day
    case week
    case month

    /// 캔들 하나가 덮는 시간(월봉은 근사값 — 축 계산용).
    public var seconds: TimeInterval {
        switch self {
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
        case .m15, .h1, .h4: return true
        case .day, .week, .month: return false
        }
    }

    /// 상세 차트 인터벌 pills 순서.
    public static let detailCases: [CandleInterval] = [.m15, .h1, .h4, .day, .week, .month]

    public var label: String {
        switch self {
        case .m15: return "15m"
        case .h1: return "1H"
        case .h4: return "4H"
        case .day: return "1D"
        case .week: return "1W"
        case .month: return "1M"
        }
    }

    /// 이 인터벌이 대략 커버하는 과거 구간(캔들 개수 한계 × 캔들 폭).
    public var approximateCoverage: TimeInterval {
        Double(CandleFetchLimit.limit(for: self)) * seconds
    }

    /// 주어진 시점을 담을 수 있는 가장 촘촘한 상세 인터벌.
    /// 인트라데이 데이터엔 오래된 거래가 없으므로, 거래 마커로 점프할 때 인터벌 자동 전환에 쓴다.
    /// (detailCases는 촘촘→성긴 순이고 커버 범위도 그 순서로 커진다.)
    public static func finestCovering(_ date: Date, now: Date = Date()) -> CandleInterval {
        let age = now.timeIntervalSince(date)
        return detailCases.first { $0.approximateCoverage >= age } ?? .month
    }
}
