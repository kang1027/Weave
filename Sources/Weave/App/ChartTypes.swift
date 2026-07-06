import Foundation
import WeaveCore

enum HomeChartMode: String, CaseIterable {
    case combined
    case perAsset
}

enum ChartPeriod: String, CaseIterable, Identifiable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case all = "ALL"

    var id: String { rawValue }

    /// 홈 차트는 ALL 미지원(1M~1Y), 상세는 전부.
    static let homeCases: [ChartPeriod] = [.oneMonth, .threeMonths, .sixMonths, .oneYear]

    var months: Int? {
        switch self {
        case .oneMonth: return 1
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .oneYear: return 12
        case .all: return nil
        }
    }

    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let months else { return nil }
        return calendar.date(byAdding: .month, value: -months, to: now)
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
