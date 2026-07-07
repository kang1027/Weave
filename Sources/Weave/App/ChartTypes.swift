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

    /// 표시 구간 시작 시점 — 실제 시작은 max(이 값, 첫 매수일)로 클램프된다.
    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .oneDay: return calendar.date(byAdding: .day, value: -1, to: now)
        case .oneWeek: return calendar.date(byAdding: .day, value: -7, to: now)
        case .oneMonth: return calendar.date(byAdding: .month, value: -1, to: now)
        case .oneYear: return calendar.date(byAdding: .year, value: -1, to: now)
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
