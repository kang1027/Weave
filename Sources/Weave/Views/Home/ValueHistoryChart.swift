import Charts
import SwiftUI
import WeaveCore

/// 홈 Value History 패널 — 통합/자산별 모드, 기간 세그먼트, 매수 로고 마커.
struct ValueHistoryChart: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        PanelCard {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    SegmentedPills(
                        options: [
                            (HomeChartMode.combined, model.t("Combined")),
                            (HomeChartMode.perAsset, model.t("By Asset"))
                        ],
                        selection: $model.homeChartMode,
                        fillsWidth: false
                    )
                }
                .padding(.bottom, 10)

                chartBody
                    .frame(height: 118)

                SegmentedPills(
                    options: ChartPeriod.homeCases.map { ($0, $0.rawValue) },
                    selection: $model.homeChartPeriod
                )
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        // 기간 변경 리로드는 HomeView의 .task(id:)가 담당한다.
    }

    @ViewBuilder
    private var chartBody: some View {
        if model.isHomeChartLoading && model.homeSeries.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.homeChartMode == .combined {
            if model.homeSeries.isEmpty {
                emptyChart
            } else {
                CombinedChart(series: model.homeSeries, markers: model.homeBuyMarkers)
            }
        } else {
            if model.homeAssetSeries.isEmpty {
                emptyChart
            } else {
                PerAssetChart(lines: model.homeAssetSeries)
            }
        }
    }

    private var emptyChart: some View {
        Text(model.t("No history yet"))
            .font(.system(size: 11))
            .foregroundStyle(theme.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 통합 모드

private struct CombinedChart: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let series: [ValuePoint]
    let markers: [BuyMarker]

    @State private var hoveredMarkerID: UUID?

    private var xAxisFormat: Date.FormatStyle {
        model.homeChartPeriod == .oneMonth
            ? .dateTime.month(.defaultDigits).day().locale(model.locale)
            : .dateTime.month(.abbreviated).locale(model.locale)
    }

    private var yDomain: ClosedRange<Double> {
        let values = series.map { $0.value.doubleValue }
        guard let min = values.min(), let max = values.max(), min < max else {
            let v = values.first ?? 0
            return (v * 0.95)...(v * 1.05 + 1)
        }
        let pad = (max - min) * 0.12
        return (min - pad)...(max + pad)
    }

    var body: some View {
        Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value.doubleValue)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [theme.green.opacity(0.28), theme.green.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value.doubleValue)
                )
                .foregroundStyle(theme.green)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(theme.grid)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: xAxisFormat, anchor: .top)
                    .font(.system(size: 9))
                    .foregroundStyle(theme.xLabel)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                markerOverlay(proxy: proxy, geo: geo)
            }
        }
    }

    @ViewBuilder
    private func markerOverlay(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let plotAnchor = proxy.plotFrame {
            let plot = geo[plotAnchor]
            ZStack(alignment: .topLeading) {
                ForEach(markers) { marker in
                    if let x = proxy.position(forX: Calendar.current.startOfDay(for: marker.trade.date)),
                       let y = proxy.position(forY: marker.seriesValue.doubleValue) {
                        MarkerDot(
                            marker: marker,
                            isHovered: hoveredMarkerID == marker.id,
                            plotSize: plot.size,
                            position: CGPoint(x: x, y: y),
                            onHover: { hovering in
                                hoveredMarkerID = hovering ? marker.id : nil
                            }
                        )
                        .position(x: plot.origin.x + x, y: plot.origin.y + y)
                    }
                }
            }
        }
    }
}

/// 매수 이벤트 로고 마커 + hover 툴팁/가이드라인.
private struct MarkerDot: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let marker: BuyMarker
    let isHovered: Bool
    let plotSize: CGSize
    let position: CGPoint
    let onHover: (Bool) -> Void

    var body: some View {
        let color = theme.paletteColor(marker.asset.colorIndex)
        ZStack {
            // 세로 가이드라인 — 마커 중심 기준 플롯 전체 높이.
            if isHovered {
                Rectangle()
                    .fill(theme.guide)
                    .frame(width: 1, height: plotSize.height)
                    .offset(y: plotSize.height / 2 - position.y)
                    .allowsHitTesting(false)
            }

            AssetLogoView(asset: marker.asset, size: 18, isCircle: true)
                .overlay(Circle().strokeBorder(color, lineWidth: 1.5))
                .background(Circle().fill(theme.pointBg))
                .scaleEffect(isHovered ? 1.18 : 1)
                .shadow(
                    color: isHovered ? color.opacity(0.4) : .black.opacity(0.25),
                    radius: isHovered ? 5 : 3, y: 1
                )
                .animation(.easeOut(duration: 0.15), value: isHovered)
                .onHover(perform: onHover)
                .onTapGesture {
                    model.push(.detail(marker.asset.id))
                }

            if isHovered {
                TooltipBubble(text: tooltipTitle, secondary: tooltipSub)
                    .offset(x: tooltipOffset, y: -34)
                    .allowsHitTesting(false)
                    .zIndex(20)
            }
        }
    }

    private var tooltipTitle: String {
        let qty = MoneyFormatter.quantity(marker.trade.quantity)
        let price = model.settings.privacyMode
            ? MoneyFormatter.masked
            : MoneyFormatter.price(marker.trade.price, currency: marker.asset.currency)
        return model.t("\(marker.asset.symbol) buy · \(qty) @ \(price)")
    }

    private var tooltipSub: String {
        let date = marker.trade.date.formatted(.dateTime.month(.defaultDigits).day().locale(model.locale))
        guard let vs = marker.vsCurrentPercent else { return date }
        return "\(date) · " + model.t("vs now \(MoneyFormatter.percent(vs))")
    }

    /// 차트 가장자리에서 툴팁이 잘리지 않게 좌우로 밀어준다.
    private var tooltipOffset: CGFloat {
        if position.x < 70 { return 55 }
        if position.x > plotSize.width - 70 { return -55 }
        return 0
    }
}

// MARK: - 자산별 모드

private struct PerAssetChart: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let lines: [AssetLineSeries]

    private var xAxisFormat: Date.FormatStyle {
        model.homeChartPeriod == .oneMonth
            ? .dateTime.month(.defaultDigits).day().locale(model.locale)
            : .dateTime.month(.abbreviated).locale(model.locale)
    }

    var body: some View {
        Chart {
            ForEach(lines) { line in
                ForEach(Array(line.points.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Percent", point.percent),
                        series: .value("Asset", line.asset.name)
                    )
                    .foregroundStyle(theme.paletteColor(line.asset.colorIndex))
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(theme.grid)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: xAxisFormat, anchor: .top)
                    .font(.system(size: 9))
                    .foregroundStyle(theme.xLabel)
            }
        }
    }
}
