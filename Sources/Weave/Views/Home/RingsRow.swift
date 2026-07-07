import SwiftUI
import WeaveCore

/// 홈 상단 링 3개 — Day · Return(크게) · Assets.
struct RingsRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let portfolio: PortfolioMetrics

    /// hover 중인 세그먼트 툴팁 텍스트 + 링 인덱스(0=Day, 1=Return, 2=Assets).
    @State private var hoveredTooltip: (text: String, ring: Int)?
    /// 행 좌표계 기준 커서 위치 — 툴팁을 마우스 옆에 붙이기 위함.
    @State private var cursor = CGPoint.zero
    @State private var tooltipSize = CGSize.zero

    var body: some View {
        HStack(spacing: 22) {
            RingGauge(
                segments: scaledSegments(
                    portfolio.daySegments,
                    fill: RingScale.lapRatio(
                        percent: portfolio.dayChangePercent,
                        fullAt: Decimal(model.settings.dayRingFullPercent)
                    )
                ),
                size: 64,
                centerText: MoneyFormatter.percent(portfolio.dayChangePercent, fractionDigits: 1),
                centerColor: theme.upDown(portfolio.dayChangePercent >= 0),
                caption: "Day",
                onHoverTooltip: { hoveredTooltip = $0.map { ($0, 0) } }
            )

            RingGauge(
                segments: scaledSegments(
                    portfolio.returnSegments,
                    fill: RingScale.lapRatio(
                        percent: portfolio.totalReturnPercent,
                        fullAt: Decimal(model.settings.returnRingFullPercent)
                    )
                ),
                size: 96,
                centerText: MoneyFormatter.percent(portfolio.totalReturnPercent, fractionDigits: 1),
                centerColor: theme.upDown(portfolio.totalReturnPercent >= 0),
                caption: "Return",
                centerTooltip: returnCenterTooltip,
                onHoverTooltip: { hoveredTooltip = $0.map { ($0, 1) } }
            )

            RingGauge(
                segments: donutSegments(portfolio.assetSegments),
                size: 64,
                centerText: "\(portfolio.assetCount)",
                centerColor: nil,
                caption: "Assets",
                onHoverTooltip: { hoveredTooltip = $0.map { ($0, 2) } }
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 4)
        // 커서 위치 추적 — 툴팁을 마우스 바로 아래에 붙인다.
        .onContinuousHover { phase in
            if case .active(let point) = phase {
                cursor = point
            }
        }
        .overlay(alignment: .topLeading) {
            if let hoveredTooltip {
                GeometryReader { geo in
                    TooltipBubble(text: hoveredTooltip.text)
                        .onGeometryChange(for: CGSize.self, of: \.size) { tooltipSize = $0 }
                        .position(
                            x: clampedTooltipX(rowWidth: geo.size.width),
                            y: cursor.y + 14 + tooltipSize.height / 2
                        )
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// 툴팁이 팝오버 좌우로 잘리지 않게 커서 x를 중심으로 클램프.
    private func clampedTooltipX(rowWidth: CGFloat) -> CGFloat {
        let half = tooltipSize.width / 2
        guard rowWidth > tooltipSize.width + 12 else { return rowWidth / 2 }
        return min(max(cursor.x, half + 6), rowWidth - half - 6)
    }

    /// Day/Return — 채움 비율(fill)을 세그먼트 기여 비율로 분할.
    private func scaledSegments(_ segments: [RingSegment], fill: Double) -> [RingGauge.Segment] {
        segments.map { segment in
            RingGauge.Segment(
                id: segment.id,
                fraction: fill * segment.fraction,
                color: color(for: segment),
                tooltip: contributionTooltip(segment)
            )
        }
    }

    /// Assets 도넛 — 전체 원을 비중대로.
    private func donutSegments(_ segments: [RingSegment]) -> [RingGauge.Segment] {
        segments.map { segment in
            let percent = Int((segment.fraction * 100).rounded())
            let label = segment.assetID == nil ? model.t("Others") : segment.label
            let amount = MoneyFormatter.compactPrice(segment.amountBase, currency: model.settings.baseCurrency)
            let text = model.settings.privacyMode
                ? "\(label) \(percent)%"
                : "\(label) \(percent)% · \(amount)"
            return RingGauge.Segment(
                id: segment.id,
                fraction: segment.fraction,
                color: color(for: segment),
                tooltip: text
            )
        }
    }

    /// Return 링 중앙/트랙 호버 시 — 총액 기준 손익 금액.
    private var returnCenterTooltip: String? {
        guard !model.settings.privacyMode else { return nil }
        let amount = MoneyFormatter.signedPrice(
            portfolio.unrealizedPnLBase,
            currency: model.settings.baseCurrency
        )
        return model.t("Total P&L \(amount)")
    }

    private func contributionTooltip(_ segment: RingSegment) -> String {
        if model.settings.privacyMode {
            return segment.label
        }
        let amount = MoneyFormatter.signedPrice(
            segment.amountBase,
            currency: model.settings.baseCurrency
        )
        return model.t("\(segment.label) contribution \(amount)")
    }

    private func color(for segment: RingSegment) -> Color {
        guard let colorIndex = segment.colorIndex else { return theme.assetGray }
        return theme.paletteColor(colorIndex)
    }
}
