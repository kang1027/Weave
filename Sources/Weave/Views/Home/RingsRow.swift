import SwiftUI
import WeaveCore

/// 홈 상단 링 3개 — Day · Return(크게) · Assets.
struct RingsRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let portfolio: PortfolioMetrics

    var body: some View {
        HStack(spacing: 22) {
            RingGauge(
                segments: scaledSegments(
                    portfolio.daySegments,
                    fill: RingScale.fillFraction(
                        percent: portfolio.dayChangePercent,
                        fullAt: RingScale.dayFullPercent
                    )
                ),
                size: 64,
                centerText: MoneyFormatter.percent(portfolio.dayChangePercent, fractionDigits: 1),
                centerColor: theme.upDown(portfolio.dayChangePercent >= 0),
                caption: model.t("Day")
            )

            RingGauge(
                segments: scaledSegments(
                    portfolio.returnSegments,
                    fill: RingScale.fillFraction(
                        percent: portfolio.totalReturnPercent,
                        fullAt: RingScale.returnFullPercent
                    )
                ),
                size: 96,
                centerText: MoneyFormatter.percent(portfolio.totalReturnPercent, fractionDigits: 1),
                centerColor: theme.upDown(portfolio.totalReturnPercent >= 0),
                caption: model.t("Return")
            )

            RingGauge(
                segments: donutSegments(portfolio.assetSegments),
                size: 64,
                centerText: "\(portfolio.assetCount)",
                centerColor: nil,
                caption: model.t("Assets")
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 4)
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

    private func contributionTooltip(_ segment: RingSegment) -> String {
        if model.settings.privacyMode {
            return segment.label
        }
        let amount = MoneyFormatter.signedPrice(
            segment.amountBase.rounded(scale: 0),
            currency: model.settings.baseCurrency
        )
        return model.t("\(segment.label) contribution \(amount)")
    }

    private func color(for segment: RingSegment) -> Color {
        guard let colorIndex = segment.colorIndex else { return theme.assetGray }
        return theme.paletteColor(colorIndex)
    }
}
