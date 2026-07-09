import Charts
import SwiftUI
import WeaveCore

/// 홈 Value History 패널 — 통합/자산별 모드, 기간 세그먼트, 매수 로고 마커.
struct ValueHistoryChart: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    /// 범례로 켜둔(표시할) 자산 라인.
    private var visibleLines: [AssetLineSeries] {
        model.homeAssetSeries.filter { !model.isHomeChartAssetHidden($0.asset.id) }
    }

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
            } else if visibleLines.isEmpty {
                // 범례로 전부 껐을 때.
                Text(model.t("Select an asset below"))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PerAssetChart(lines: visibleLines)
            }
        }
    }

    private var emptyChart: some View {
        Text(model.t("No history yet"))
            .font(.system(size: 11))
            .foregroundStyle(theme.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 자산별 모드 범례 — 클릭하면 그 자산 라인을 차트에서 보이기/가리기 토글.
    /// 자산이 많으면 여러 줄로 자동 줄바꿈(가로로 안 잘림).
    private var assetLegend: some View {
        FlowLayout(spacing: 10, rowSpacing: 5, alignment: .center) {
            ForEach(model.homeAssetSeries) { line in
                let hidden = model.isHomeChartAssetHidden(line.asset.id)
                Button {
                    model.toggleHomeChartAssetVisibility(assetID: line.asset.id)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(theme.paletteColor(line.asset.colorIndex))
                            .frame(width: 6, height: 6)
                        Text(line.asset.name)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(theme.text2)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .opacity(hidden ? 0.35 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(hidden ? model.t("Show in chart") : model.t("Hide from chart"))
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

    private var period: ChartPeriod { model.homeChartPeriod }

    /// x 도메인 — 선택 기간 전체(모델에서 고정). 없으면 데이터 범위로 폴백.
    private var xDomain: ClosedRange<Date> {
        if let domain = model.homeChartDomain { return domain }
        let first = series.first?.date ?? Date()
        let last = series.last?.date ?? first
        return first <= last ? first...last : first...first.addingTimeInterval(1)
    }

    private var yDomain: ClosedRange<Double> {
        let values = series.map { $0.value.doubleValue }
        guard let min = values.min(), let max = values.max(), min < max else {
            // 값이 하나뿐/전부 동일 — 부호와 무관하게 항상 오름차순 범위(역전 방지).
            let v = values.first ?? 0
            let margin = Swift.abs(v) * 0.05 + 1
            return (v - margin)...(v + margin)
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
        .chartXScale(domain: xDomain)
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
            // 도메인이 기간 전체로 고정돼 있어 .stride가 항상 눈금을 만든다(1D 6h·1W 일·1M 주·1Y 2개월).
            AxisMarks(values: .stride(by: period.axisStride.component, count: period.axisStride.count)) { value in
                AxisGridLine().foregroundStyle(theme.grid.opacity(0.5))
                AxisValueLabel(anchor: .top) {
                    if let date = value.as(Date.self) {
                        Text(date, format: period.axisFormat(locale: model.locale))
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

                // 툴팁 — 상단 고정 + 폭 측정 클램프라 패널 밖으로 잘리지 않는다.
                // 마커 hover 우선, 아니면 hover 지점 값 툴팁.
                if let marker = hoveredMarkerID.flatMap({ id in markers.first(where: { $0.id == id }) }),
                   let x = proxy.position(forX: Calendar.current.startOfDay(for: marker.trade.date)) {
                    ClampedTooltip(anchorX: plot.origin.x + x, top: plot.origin.y + 6, bounds: plot) {
                        TooltipBubble(text: markerTitle(marker), secondary: markerSub(marker))
                    }
                } else if hoveredMarkerID == nil, let hoveredDate, let point = nearestPoint(to: hoveredDate),
                          let x = proxy.position(forX: point.date) {
                    ClampedTooltip(anchorX: plot.origin.x + x, top: plot.origin.y + 6, bounds: plot) {
                        valueTooltip(point)
                    }
                }
            }
        }
    }

    // MARK: 마커 툴팁 텍스트

    private func markerTitle(_ marker: BuyMarker) -> String {
        let qty = marker.asset.formattedQuantity(marker.trade.quantity)
        let price = model.settings.privacyMode
            ? MoneyFormatter.masked
            : MoneyFormatter.price(marker.trade.price, currency: marker.asset.currency)
        return model.t("\(marker.asset.name) buy · \(qty) @ \(price)") + convertedSuffix(marker)
    }

    /// 자산 통화 ≠ 기준 통화면 현재 환율 환산가를 병기.
    private func convertedSuffix(_ marker: BuyMarker) -> String {
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

    private func markerSub(_ marker: BuyMarker) -> String {
        let date = marker.trade.date.formatted(.dateTime.month(.defaultDigits).day().locale(model.locale))
        guard let vs = marker.vsCurrentPercent else { return date }
        return "\(date) · " + model.t("vs now \(MoneyFormatter.percent(vs))")
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
            Text(point.date, format: tooltipDateFormat(period: period, locale: model.locale))
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
        }
    }
}

// MARK: - 자산별 모드

private struct PerAssetChart: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let lines: [AssetLineSeries]

    // 커서 근처(겹친 것 포함) 종목들을 하이라이트한다.
    @State private var hoveredLineIDs: [UUID] = []
    @State private var hoveredDate: Date?

    private var hoveredLines: [AssetLineSeries] {
        hoveredLineIDs.compactMap { id in lines.first(where: { $0.id == id }) }
    }

    private var period: ChartPeriod { model.homeChartPeriod }

    private var xDomain: ClosedRange<Date> {
        if let domain = model.homeChartDomain { return domain }
        let dates = lines.flatMap { $0.points.map(\.date) }
        let first = dates.min() ?? Date()
        let last = dates.max() ?? first
        return first <= last ? first...last : first...first.addingTimeInterval(1)
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
                    // hover 중인 종목만 강조, 나머지는 흐리게.
                    .foregroundStyle(
                        theme.paletteColor(line.asset.colorIndex)
                            .opacity(hoveredLineIDs.isEmpty || hoveredLineIDs.contains(line.id) ? 1 : 0.28)
                    )
                    .lineStyle(StrokeStyle(lineWidth: hoveredLineIDs.contains(line.id) ? 2.4 : 1.8))
                }
                // 오늘 산 종목은 데이터가 한 점뿐 → 선이 안 그려지니 점으로 표시.
                if line.points.count == 1, let point = line.points.first {
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Percent", point.percent)
                    )
                    .symbolSize(30)
                    .foregroundStyle(theme.paletteColor(line.asset.colorIndex))
                }
            }

            // hover 크로스헤어 — 세로 가이드 + 겹친 종목들 라인 위 포인트.
            if let hoveredDate, !hoveredLines.isEmpty {
                RuleMark(x: .value("Date", hoveredDate))
                    .foregroundStyle(theme.guide)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(hoveredLines) { line in
                    if let point = interpolated(line, at: hoveredDate) {
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
        .chartXScale(domain: xDomain)
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
            AxisMarks(values: .stride(by: period.axisStride.component, count: period.axisStride.count)) { value in
                AxisGridLine().foregroundStyle(theme.grid.opacity(0.5))
                AxisValueLabel(anchor: .top) {
                    if let date = value.as(Date.self) {
                        Text(date, format: period.axisFormat(locale: model.locale))
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
                                    updateHover(point: point, proxy: proxy, plot: plot)
                                case .ended:
                                    hoveredLineIDs = []
                                    hoveredDate = nil
                                }
                            }
                        if let hoveredDate, !hoveredLines.isEmpty, let x = proxy.position(forX: hoveredDate) {
                            ClampedTooltip(anchorX: plot.origin.x + x, top: plot.origin.y + 6, bounds: plot) {
                                lineTooltip(hoveredLines, at: hoveredDate)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 커서 y와 각 라인의 y(그 x에서 보간값)를 비교해, 임계값 안 라인을 전부 선택(겹친 것 모두).
    private func updateHover(point: CGPoint, proxy: ChartProxy, plot: CGRect) {
        let localX = point.x - plot.origin.x
        let localY = point.y - plot.origin.y
        guard let date = proxy.value(atX: localX, as: Date.self) else {
            hoveredLineIDs = []
            hoveredDate = nil
            return
        }
        var hits: [(id: UUID, dist: CGFloat)] = []
        for line in lines {
            // 커서 날짜에 실제 데이터가 있는 라인만 후보(늦게 산 종목이 그 이전 구간에서
            // 클램프된 값으로 잘못 잡히는 것 방지).
            guard let first = line.points.first?.date, let last = line.points.last?.date,
                  date >= first, date <= last,
                  let ip = interpolated(line, at: date),
                  let lineY = proxy.position(forY: ip.percent) else { continue }
            let dist = abs(lineY - localY)
            // 커서 포인트에 딱 붙게(좁게). 겹친 선들은 서로 가까워 이 범위에 함께 들어온다.
            if dist <= 6 { hits.append((line.id, dist)) }
        }
        guard !hits.isEmpty else {
            hoveredLineIDs = []
            hoveredDate = nil
            return
        }
        // 가까운 순 정렬 — 겹친 것 전부 표시. 날짜는 가장 가까운 라인의 데이터 포인트에 스냅.
        hits.sort { $0.dist < $1.dist }
        hoveredLineIDs = hits.map(\.id)
        let closest = lines.first { $0.id == hits[0].id }
        hoveredDate = closest?.points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }?.date ?? date
    }

    /// hover 시점의 날짜 + 겹친 종목들의 색·이름·수익률 툴팁.
    private func lineTooltip(_ tooltipLines: [AssetLineSeries], at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date, format: tooltipDateFormat(period: period, locale: model.locale))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.text2)
            ForEach(tooltipLines) { line in
                let percent = interpolated(line, at: date)?.percent ?? 0
                HStack(spacing: 5) {
                    Circle()
                        .fill(theme.paletteColor(line.asset.colorIndex))
                        .frame(width: 6, height: 6)
                    Text(line.asset.name)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 10)
                    Text(MoneyFormatter.percent(Decimal.fromDouble(percent)))
                        .font(.system(size: 9.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.upDown(percent >= 0))
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

    /// 주어진 날짜에서 라인의 % 값을 인접 두 점 선형보간으로 계산(구간 밖은 양끝값).
    private func interpolated(_ line: AssetLineSeries, at date: Date) -> (date: Date, percent: Double)? {
        let pts = line.points
        guard let first = pts.first, let last = pts.last else { return nil }
        if date <= first.date { return first }
        if date >= last.date { return last }
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            if date >= a.date && date <= b.date {
                let span = b.date.timeIntervalSince(a.date)
                let t = span > 0 ? date.timeIntervalSince(a.date) / span : 0
                return (date, a.percent + (b.percent - a.percent) * t)
            }
        }
        return last
    }
}

/// 툴팁 날짜 헤더 포맷 — 1D는 월/일 시:분(24시간제 강제), 그 외는 연/월/일.
private func tooltipDateFormat(period: ChartPeriod, locale: Locale) -> Date.FormatStyle {
    period.isIntraday
        ? .dateTime.month(.defaultDigits).day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            .locale(ChartPeriod.hour24Locale(locale))
        : .dateTime.year().month().day().locale(locale)
}

/// 차트 위 툴팁 — 자기 폭을 측정해 플롯 좌우 안쪽으로 클램프(패널 밖으로 안 잘림).
/// anchorX는 원하는 중심 x(절대), top은 상단 y(절대), bounds는 플롯 사각형.
private struct ClampedTooltip<Content: View>: View {
    let anchorX: CGFloat
    let top: CGFloat
    let bounds: CGRect
    @ViewBuilder let content: Content
    @State private var width: CGFloat = 0

    private var clampedX: CGFloat {
        let half = width / 2
        let lo = bounds.minX + half + 2
        let hi = bounds.maxX - half - 2
        guard lo <= hi else { return bounds.midX }
        return min(max(anchorX, lo), hi)
    }

    var body: some View {
        content
            .fixedSize()
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: TooltipWidthKey.self, value: g.size.width)
                }
            )
            .onPreferenceChange(TooltipWidthKey.self) { width = $0 }
            .position(x: clampedX, y: top + 20)
            .allowsHitTesting(false)
    }
}

private struct TooltipWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
