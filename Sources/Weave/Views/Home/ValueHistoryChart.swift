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

                if model.homeChartMode == .perAsset, !model.homeAssetSeries.isEmpty {
                    assetLegend
                }

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

    /// 자산별 모드 범례 — 라인 색과 종목명 매핑(ASSETS 리스트 점과 동일 색).
    private var assetLegend: some View {
        HStack(spacing: 10) {
            ForEach(model.homeAssetSeries) { line in
                HStack(spacing: 4) {
                    Circle()
                        .fill(theme.paletteColor(line.asset.colorIndex))
                        .frame(width: 6, height: 6)
                    Text(line.asset.name)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(theme.text2)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - 통합 모드

private struct CombinedChart: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let series: [ValuePoint]
    let markers: [BuyMarker]

    @State private var hoveredMarkerID: UUID?
    @State private var hoveredDate: Date?

    private var spanDays: Double {
        guard let first = series.first?.date, let last = series.last?.date else { return 0 }
        return last.timeIntervalSince(first) / 86_400
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
                // yStart를 도메인 하단에 고정 — 기본값(0)이면 필이 플롯 밖까지 뻗는다.
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Base", yDomain.lowerBound),
                    yEnd: .value("Value", point.value.doubleValue)
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

            // hover 크로스헤어 — 세로 가이드 + 그 시점 값 포인트.
            if hoveredMarkerID == nil, let hoveredDate, let point = nearestPoint(to: hoveredDate) {
                RuleMark(x: .value("Date", point.date))
                    .foregroundStyle(theme.guide)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value.doubleValue)
                )
                .symbolSize(40)
                .foregroundStyle(theme.green)
            }
        }
        .chartYScale(domain: yDomain)
        .chartPlotStyle { $0.clipped() }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(theme.grid)
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(
                            model.settings.privacyMode
                                ? "•••"
                                : MoneyFormatter.compactPrice(
                                    Decimal.fromDouble(doubleValue),
                                    currency: model.settings.baseCurrency
                                )
                        )
                        .font(.system(size: 8.5))
                        .foregroundStyle(theme.xLabel)
                    }
                }
            }
        }
        .chartXAxis {
            // automatic — 데이터 구간이 짧아도 항상 눈금을 만든다(.stride는 월 경계가 없으면 0개).
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel(anchor: .top) {
                    if let date = value.as(Date.self) {
                        Text(date, format: ChartAxis.xFormat(spanDays: spanDays, locale: model.locale))
                            .font(.system(size: 9))
                            .foregroundStyle(theme.xLabel)
                    }
                }
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
                // hover 캡처(마커 아래).
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(width: plot.width, height: plot.height)
                    .position(x: plot.midX, y: plot.midY)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            hoveredDate = proxy.value(atX: point.x - plot.origin.x, as: Date.self)
                        case .ended:
                            hoveredDate = nil
                        }
                    }

                ForEach(markers) { marker in
                    if let rawX = proxy.position(forX: Calendar.current.startOfDay(for: marker.trade.date)),
                       let rawY = proxy.position(forY: marker.seriesValue.doubleValue) {
                        // 구간 경계의 마커가 패널 밖으로 반쯤 잘리지 않게 클램프.
                        let x = min(max(rawX, 9), plot.width - 9)
                        let y = min(max(rawY, 9), plot.height - 9)
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

                // 값 툴팁 — 날짜·평가액·등락률(마커 hover 중이 아닐 때).
                if hoveredMarkerID == nil, let hoveredDate, let point = nearestPoint(to: hoveredDate),
                   let x = proxy.position(forX: point.date) {
                    valueTooltip(point)
                        .fixedSize()
                        .position(
                            x: min(max(plot.origin.x + x, plot.origin.x + 56), plot.maxX - 56),
                            y: plot.origin.y + 20
                        )
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func nearestPoint(to date: Date) -> ValuePoint? {
        series.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// hover 값 툴팁 — 날짜 + 총 평가액 + 구간 시작 대비 등락률.
    private func valueTooltip(_ point: ValuePoint) -> some View {
        let base = model.settings.baseCurrency
        let baseline = series.first(where: { $0.value > 0 })?.value ?? point.value
        let pct = baseline > 0 ? ((point.value - baseline) / baseline * 100).rounded(scale: 2) : 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(point.date.formatted(.dateTime.year().month().day().locale(model.locale)))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.text2)
            HStack(spacing: 6) {
                Text(MoneyFormatter.price(point.value, currency: base))
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                    .privacyBlur(model.settings.privacyMode)
                Text(MoneyFormatter.percent(pct))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.upDown(pct >= 0))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.tooltipBg)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.tooltipBorder))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
        )
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
        return model.t("\(marker.asset.symbol) buy · \(qty) @ \(price)") + convertedSuffix
    }

    /// 자산 통화 ≠ 기준 통화면 현재 환율 환산가를 병기.
    private var convertedSuffix: String {
        let assetCurrency = marker.asset.currency.uppercased()
        let base = model.settings.baseCurrency.uppercased()
        guard
            !model.settings.privacyMode,
            assetCurrency != base,
            let rate = model.fxRates[assetCurrency]
        else {
            return ""
        }
        let converted = marker.trade.price * rate
        return " (≈ \(MoneyFormatter.price(converted, currency: base)))"
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

    @State private var hoveredDate: Date?

    private var spanDays: Double {
        let dates = lines.flatMap { $0.points.map(\.date) }
        guard let first = dates.min(), let last = dates.max() else { return 0 }
        return last.timeIntervalSince(first) / 86_400
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

            // hover 크로스헤어 — 세로 가이드 + 각 종목 라인 위 포인트.
            if let hoveredDate {
                RuleMark(x: .value("Date", hoveredDate))
                    .foregroundStyle(theme.guide)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(lines) { line in
                    if let point = nearestPoint(line, to: hoveredDate) {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Percent", point.percent)
                        )
                        .symbolSize(38)
                        .foregroundStyle(theme.paletteColor(line.asset.colorIndex))
                    }
                }
            }
        }
        .chartPlotStyle { $0.clipped() }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(theme.grid)
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(MoneyFormatter.percent(Decimal.fromDouble(doubleValue), fractionDigits: 0))
                            .font(.system(size: 8.5))
                            .foregroundStyle(theme.xLabel)
                    }
                }
            }
        }
        .chartXAxis {
            // automatic — 데이터 구간이 짧아도 항상 눈금을 만든다(.stride는 월 경계가 없으면 0개).
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel(anchor: .top) {
                    if let date = value.as(Date.self) {
                        Text(date, format: ChartAxis.xFormat(spanDays: spanDays, locale: model.locale))
                            .font(.system(size: 9))
                            .foregroundStyle(theme.xLabel)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotAnchor = proxy.plotFrame {
                    let plot = geo[plotAnchor]
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .frame(width: plot.width, height: plot.height)
                            .position(x: plot.midX, y: plot.midY)
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let point):
                                    hoveredDate = proxy.value(atX: point.x - plot.origin.x, as: Date.self)
                                case .ended:
                                    hoveredDate = nil
                                }
                            }
                        if let hoveredDate, let x = proxy.position(forX: hoveredDate) {
                            hoverTooltip(at: hoveredDate)
                                .fixedSize()
                                .position(
                                    x: min(max(plot.origin.x + x, plot.origin.x + 60), plot.maxX - 60),
                                    y: plot.origin.y + 28
                                )
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
    }

    /// hover 시점의 날짜 + 종목별 색·이름·수익률 툴팁.
    private func hoverTooltip(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date.formatted(.dateTime.year().month().day().locale(model.locale)))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.text2)
            ForEach(lines) { line in
                if let point = nearestPoint(line, to: date) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(theme.paletteColor(line.asset.colorIndex))
                            .frame(width: 6, height: 6)
                        Text(line.asset.name)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        Spacer(minLength: 10)
                        Text(MoneyFormatter.percent(Decimal.fromDouble(point.percent)))
                            .font(.system(size: 9.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.upDown(point.percent >= 0))
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.tooltipBg)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.tooltipBorder))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
        )
    }

    private func nearestPoint(_ line: AssetLineSeries, to date: Date) -> (date: Date, percent: Double)? {
        line.points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }
}

/// x축 라벨 포맷 — 실제 데이터 구간 길이에 맞춰 선택(짧으면 월/일이라 라벨이 안 겹침).
enum ChartAxis {
    static func xFormat(spanDays: Double, locale: Locale) -> Date.FormatStyle {
        if spanDays > 2 * 365 {
            return .dateTime.year().locale(locale)
        }
        if spanDays > 300 {
            return .dateTime.year(.twoDigits).month(.abbreviated).locale(locale)
        }
        if spanDays > 55 {
            return .dateTime.month(.abbreviated).locale(locale)
        }
        return .dateTime.month(.defaultDigits).day().locale(locale)
    }
}
