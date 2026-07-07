import Foundation
import WeaveCore

enum HomeChartMode: String, CaseIterable {
    case combined
    case perAsset
}

/// Assets 리스트 % 배지 기준 기간.
enum AssetReturnPeriod: String, CaseIterable, Identifiable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case year = "1Y"

    var id: String { rawValue }

    /// 비교 기준 시점까지의 일수(day는 전날 대비라 별도 처리).
    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }
}

/// 홈 Value History 표시 구간 — ASSETS 리스트 % 필터와 동일한 1D/1W/1M/1Y.
enum ChartPeriod: String, CaseIterable, Identifiable {
    case oneDay = "1D"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case oneYear = "1Y"

    var id: String { rawValue }

    static let homeCases: [ChartPeriod] = allCases

    /// 표시 구간 시작 시점. x 도메인은 항상 이 시점~now로 고정된다(데이터가 짧아도).
    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .oneDay: return calendar.date(byAdding: .hour, value: -24, to: now) ?? now
        case .oneWeek: return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .oneMonth: return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .oneYear: return calendar.date(byAdding: .year, value: -1, to: now) ?? now
        }
    }

    /// 캔들 조회 주기 — 1D만 시간봉(인트라데이), 나머지는 일봉.
    var candleInterval: CandleInterval {
        self == .oneDay ? .h1 : .day
    }

    var isIntraday: Bool { self == .oneDay }

    /// x축 눈금 간격 — 1D는 6시간(nn:00), 1W 일, 1M 주, 1Y 2개월.
    var axisStride: (component: Calendar.Component, count: Int) {
        switch self {
        case .oneDay: return (.hour, 6)
        case .oneWeek: return (.day, 1)
        case .oneMonth: return (.weekOfYear, 1)
        case .oneYear: return (.month, 2)
        }
    }

    /// x축 라벨 포맷 — 1D 시:분(24h), 1W·1M 월/일, 1Y 월.
    func axisFormat(locale: Locale) -> Date.FormatStyle {
        switch self {
        case .oneDay:
            return .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale)
        case .oneWeek, .oneMonth:
            return .dateTime.month(.defaultDigits).day().locale(locale)
        case .oneYear:
            return .dateTime.month(.abbreviated).locale(locale)
        }
    }
}

/// 자산별 모드 라인 하나 — 정규화 % 시계열.
struct AssetLineSeries: Identifiable, Equatable {
    let asset: Asset
    let points: [(date: Date, percent: Double)]

    var id: UUID { asset.id }

    static func == (lhs: AssetLineSeries, rhs: AssetLineSeries) -> Bool {
        lhs.asset.id == rhs.asset.id
            && lhs.points.map(\.date) == rhs.points.map(\.date)
            && lhs.points.map(\.percent) == rhs.points.map(\.percent)
    }
}

/// 통합 차트 위 매수 이벤트 로고 마커.
struct BuyMarker: Identifiable, Equatable {
    let trade: Trade
    let asset: Asset
    /// 그 날짜의 포트폴리오 가치 — 마커의 y 좌표(라인 위).
    let seriesValue: Decimal
    /// 현재가 대비 체결가 % — 툴팁용. 시세 없으면 nil.
    let vsCurrentPercent: Decimal?

    var id: UUID { trade.id }
}
