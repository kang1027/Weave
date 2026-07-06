import Foundation

/// 자산 하나의 파생 지표. 금액은 자산 통화(`value…`)와 기준통화(`…Base`) 둘 다 든다.
public struct AssetMetrics: Identifiable, Equatable, Sendable {
    public var asset: Asset
    public var position: PositionSnapshot
    public var quote: Quote?

    /// 평가금(자산 통화). manual이면 manualValue.
    public var value: Decimal
    public var valueBase: Decimal
    /// 미실현손익(자산 통화). manual이면 0.
    public var unrealizedPnL: Decimal
    public var unrealizedPnLBase: Decimal
    /// 총 수익률 %. 원가 0이면 nil.
    public var returnPercent: Decimal?
    /// 일간 변동 % — 소스 제공값. manual/시세없음이면 nil.
    public var dayChangePercent: Decimal?
    /// 일간 변동액(기준통화).
    public var dayChangeAmountBase: Decimal
    /// 포트폴리오 내 평가금 비중 0...1.
    public var weight: Double

    public var id: UUID { asset.id }
}

/// 링 게이지 세그먼트 하나 — Day/Return은 손익 기여, Assets는 평가금 비중.
public struct RingSegment: Identifiable, Equatable, Sendable {
    /// nil이면 "기타"(회색) 묶음.
    public var assetID: UUID?
    public var label: String
    /// 링에서 차지하는 비율 0...1 (세그먼트끼리 합이 1).
    public var fraction: Double
    /// 툴팁용 금액(기준통화) — Day/Return은 기여액, Assets는 평가금.
    public var amountBase: Decimal
    public var colorIndex: Int?

    public var id: String { assetID?.uuidString ?? "etc" }

    public init(assetID: UUID?, label: String, fraction: Double, amountBase: Decimal, colorIndex: Int?) {
        self.assetID = assetID
        self.label = label
        self.fraction = fraction
        self.amountBase = amountBase
        self.colorIndex = colorIndex
    }
}

public struct PortfolioMetrics: Equatable, Sendable {
    /// 총 평가금(기준통화).
    public var totalValueBase: Decimal
    /// 일간 변동 %.
    public var dayChangePercent: Decimal
    /// 총 수익률 % (미실현, manual 제외).
    public var totalReturnPercent: Decimal
    /// 미실현손익 합(기준통화).
    public var unrealizedPnLBase: Decimal
    /// 투자 원금 합(기준통화, manual 제외) — 홈 총액 아래 "원금" 표시용.
    public var costBasisBase: Decimal
    /// Day 링 세그먼트 — 포트폴리오 일간 손익과 같은 부호 종목만.
    public var daySegments: [RingSegment]
    /// Return 링 세그먼트 — 총 손익과 같은 부호 종목만.
    public var returnSegments: [RingSegment]
    /// Assets 도넛 — 비중 상위 4 + 기타.
    public var assetSegments: [RingSegment]
    public var assetCount: Int
}

/// 링 채움 스케일 — Day ±2% = 풀링, Return ±25% = 풀링.
public enum RingScale {
    public static let dayFullPercent: Decimal = 2
    public static let returnFullPercent: Decimal = 25

    public static func fillFraction(percent: Decimal, fullAt: Decimal) -> Double {
        guard fullAt > 0 else { return 0 }
        let ratio = abs(percent).doubleValue / fullAt.doubleValue
        return min(max(ratio, 0), 1)
    }
}
