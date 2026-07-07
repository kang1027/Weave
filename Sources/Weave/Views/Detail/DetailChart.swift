import Charts
import SwiftUI
import WeaveCore

/// 상세 차트 — 종가 라인+그라디언트, 평단 점선, B/S 마커, 크로스헤어.
/// 팬: 드래그/가로 스크롤 · 줌: 세로 스크롤/핀치/버튼 · 더블클릭: 거래 프리필.
///
/// 성능: 보이는 구간(+버퍼)만 렌더하고, hover 상호작용은 Chart 밖 오버레이에서
/// 처리해 1000캔들 인터벌에서도 마크 리빌드가 일어나지 않게 한다.
struct DetailChart: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let asset: Asset
    let trades: [Trade]
    let position: PositionSnapshot
    /// B/S 마커 클릭 → Trades 리스트의 해당 행 포커스.
    var onSelectTrade: (UUID) -> Void = { _ in }
    /// 거래 행 클릭 → 차트의 해당 마커 포커스 요청(처리 후 nil로 리셋).
    @Binding var focusRequest: UUID?

    @State private var focusedTradeID: UUID?
    @State private var panAnimationTask: Task<Void, Never>?
    /// 슬라이드 중 렌더할 구간(시작·도착 창의 합집합). nil이면 평상시.
    @State private var renderSpanOverride: ClosedRange<Date>?

    @State private var hoveredDate: Date?
    @State private var hoveredTradeID: UUID?
    /// 보이는 창의 왼쪽 끝.
    @State private var scrollX = Date.distantPast
    /// 보이는 창의 길이(초). 0이면 아직 초기화 전.
    @State private var visibleSeconds: Double = 0
    @State private var magnifyStartSeconds: Double?
    @State private var dragStartScrollX: Date?
    @State private var isHoveringChart = false
    @State private var scrollMonitor: Any?
    /// 차트 플롯 영역(차트 뷰 로컬 좌표) — 오버레이 좌표 계산용.
    @State private var plotFrame = CGRect.zero

    private var candles: [Candle] { model.detailCandles }
    private var color: Color { theme.paletteColor(asset.colorIndex) }
    private var interval: CandleInterval { model.detailInterval }

    // MARK: - 창(window) 계산

    private var defaultWindowSeconds: Double { interval.seconds * 90 }
    private var minWindowSeconds: Double { interval.seconds * 15 }

    private var dataSpanSeconds: Double {
        guard let first = candles.first?.date, let last = candles.last?.date else { return 0 }
        return last.timeIntervalSince(first) + interval.seconds
    }

    private var effectiveVisibleSeconds: Double {
        visibleSeconds > 0 ? visibleSeconds : min(defaultWindowSeconds, max(dataSpanSeconds, minWindowSeconds))
    }

    private var windowEnd: Date { scrollX.addingTimeInterval(effectiveVisibleSeconds) }

    /// 렌더 대상 — 보이는 창 ± 15% 버퍼, 최대 500포인트로 다운샘플.
    /// 슬라이드 중에는 지나갈 구간(renderSpanOverride)을 통째로 렌더해 라인이 끊기지 않게.
    private var renderCandles: [Candle] {
        let from: Date
        let to: Date
        if let span = renderSpanOverride {
            from = span.lowerBound
            to = span.upperBound
        } else {
            let buffer = effectiveVisibleSeconds * 0.15
            from = scrollX.addingTimeInterval(-buffer)
            to = windowEnd.addingTimeInterval(buffer)
        }
        let slice = candles.filter { $0.date >= from && $0.date <= to }
        return CandleAggregator.downsample(slice.isEmpty ? candles : slice, maxPoints: 500)
    }

    private var visibleCandles: [Candle] {
        let window = candles.filter { $0.date >= scrollX && $0.date <= windowEnd }
        return window.isEmpty ? candles : window
    }

    /// y 도메인은 보이는 캔들에 맞춰 자동 피팅.
    /// 마커는 가격선 위에 얹으므로(체결가 아님) 체결가는 도메인 계산에서 뺀다 —
    /// 그래야 평단에서 크게 벗어난 체결가 하나가 라인을 찌그러뜨리지 않는다.
    private var yDomain: ClosedRange<Double> {
        let values = visibleCandles.map { $0.close.doubleValue }
        guard let min = values.min(), let max = values.max(), min < max else {
            let v = values.first ?? 1
            return (v * 0.9)...(v * 1.1)
        }
        let pad = (max - min) * 0.12
        return (min - pad)...(max + pad)
    }

    private var visibleTrades: [Trade] {
        guard let first = candles.first?.date else { return [] }
        return trades.filter { $0.date >= first }
    }

    // MARK: - body

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if candles.isEmpty {
                    placeholder
                } else {
                    chartWithOverlay
                }
            }
            .frame(height: 190)
            .padding(.horizontal, 8)

            controlsRow
                .padding(.horizontal, 16)
        }
        .onChange(of: candles) { resetWindow() }
        .onChange(of: focusRequest) { _, request in
            guard let request else { return }
            focusMarker(tradeID: request)
            focusRequest = nil
        }
        .onAppear {
            // 주식인데 인트라데이가 선택돼 있으면(크립토서 넘어온 경우) 1D로 스냅.
            if !asset.market.supportsIntraday, interval.isIntraday {
                model.detailInterval = .day
            }
            resetWindow()
            installScrollZoomMonitor()
        }
        .onDisappear {
            removeScrollZoomMonitor()
            endPanAnimation()
        }
        .onHover { isHoveringChart = $0 }
    }

    /// 거래 행 클릭 → 해당 마커가 창 밖이면 그 시점까지 좌/우로 스르륵 슬라이드하고 잠깐 강조.
    private func focusMarker(tradeID: UUID) {
        guard let trade = trades.first(where: { $0.id == tradeID }) else { return }
        guard trade.date < scrollX || trade.date > windowEnd else {
            highlightMarker(tradeID)
            return
        }
        let target = clampScroll(
            trade.date.addingTimeInterval(-effectiveVisibleSeconds / 2)
        )
        slideWindow(to: target) { highlightMarker(tradeID) }
    }

    private func highlightMarker(_ tradeID: UUID) {
        focusedTradeID = tradeID
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if focusedTradeID == tradeID {
                withAnimation(.easeOut(duration: 0.3)) { focusedTradeID = nil }
            }
        }
    }

    /// 창 길이는 그대로 두고 scrollX만 목표로 좌/우 슬라이드.
    /// 리셋 버튼과 동일하게 Swift Charts 스케일 애니메이션에 맡겨 라인·마커가 함께 미끄러진다.
    /// 지나갈 구간을 한 번에 렌더해 중간이 비지 않게 하고(데이터 재조회 없음), 사용자 팬/줌이
    /// 들어오면 즉시 중단한다.
    private func slideWindow(to target: Date, completion: @escaping () -> Void = {}) {
        endPanAnimation()
        let start = scrollX
        let delta = target.timeIntervalSince(start)
        guard abs(delta) > 1 else {
            completion()
            return
        }
        // 시작·도착 창을 모두 덮는 구간을 렌더 대상으로 잡는다.
        let buffer = effectiveVisibleSeconds * 0.15
        let low = min(start, target).addingTimeInterval(-buffer)
        let high = max(start, target).addingTimeInterval(effectiveVisibleSeconds + buffer)
        renderSpanOverride = low...high

        // 멀리 갈수록 조금 더 길게 (0.35s ~ 0.7s).
        let windows = abs(delta) / max(effectiveVisibleSeconds, 1)
        let duration = min(0.7, 0.35 + windows * 0.05)
        withAnimation(.easeOut(duration: duration)) {
            scrollX = target
        }
        panAnimationTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            renderSpanOverride = nil
            completion()
        }
    }

    /// 진행 중인 슬라이드를 멈추고 렌더 구간 오버라이드를 해제(사용자 팬/줌/리셋/재조회 시).
    private func endPanAnimation() {
        panAnimationTask?.cancel()
        panAnimationTask = nil
        renderSpanOverride = nil
    }

    private var placeholder: some View {
        Group {
            if model.isDetailChartLoading {
                ProgressView().controlSize(.small)
            } else {
                Text(model.t("No chart data"))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chartWithOverlay: some View {
        PriceChartBody(
            candles: renderCandles,
            xDomain: scrollX...windowEnd,
            yDomain: yDomain,
            avgCost: (position.quantity > 0 && position.averageCost > 0)
                ? position.averageCost.doubleValue : nil,
            avgText: avgLabel,
            color: color,
            currency: asset.currency,
            interval: interval,
            windowSeconds: effectiveVisibleSeconds,
            locale: model.locale,
            gridColor: theme.grid,
            refLineColor: theme.refLine,
            labelColor: theme.xLabel,
            annotationColor: theme.text2
        )
        .equatable()
        .onPreferenceChange(PlotFramePreferenceKey.self) { plotFrame = $0 }
        .overlay(alignment: .topLeading) {
            if plotFrame.width > 0 {
                interactionLayer
            }
        }
        .simultaneousGesture(magnification)
    }

    // MARK: - 컨트롤 (인터벌 pills + 줌)

    /// 크립토는 전체, 주식은 인트라데이 제외(1D부터) — 장중만 거래라 갭이 심함.
    private var intervalOptions: [CandleInterval] {
        asset.market.supportsIntraday
            ? CandleInterval.detailCases
            : CandleInterval.detailCases.filter { !$0.isIntraday }
    }

    private var controlsRow: some View {
        HStack(spacing: 6) {
            SegmentedPills(
                options: intervalOptions.map { ($0, $0.label) },
                selection: $model.detailInterval
            )
            zoomButton(systemName: "minus.magnifyingglass", help: model.t("Zoom out")) {
                zoom(by: 1.4)
            }
            zoomButton(systemName: "plus.magnifyingglass", help: model.t("Zoom in")) {
                zoom(by: 1 / 1.4)
            }
            zoomButton(systemName: "arrow.counterclockwise", help: model.t("Reset zoom")) {
                if model.detailFocusDate != nil {
                    model.detailFocusDate = nil   // 거래 포커스 해제 → 최근 구간 재조회 후 최신으로 복귀
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { resetWindow() }
                }
            }
        }
    }

    private func zoomButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.text2)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.iconBg))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(candles.isEmpty)
    }

    // MARK: - 팬/줌

    private func resetWindow() {
        endPanAnimation()
        guard let last = candles.last?.date else { return }
        let span = max(dataSpanSeconds, minWindowSeconds)
        visibleSeconds = min(defaultWindowSeconds, span)
        if let focus = model.detailFocusDate {
            // 거래로 점프 — 새 캔들이 도착하면 살짝 어긋난 지점에서 시작해 그 날짜 중앙으로
            // 스르륵 슬라이드(하드컷 대신 자연스러운 착지). 데이터는 이미 받아둔 상태.
            let center = clampScroll(focus.addingTimeInterval(-visibleSeconds / 2))
            scrollX = clampScroll(focus.addingTimeInterval(-visibleSeconds * 0.12))
            Task { @MainActor in slideWindow(to: center) }
        } else {
            // 최신을 오른쪽 끝에.
            scrollX = last.addingTimeInterval(interval.seconds - visibleSeconds)
        }
    }

    /// 창 오른쪽 끝은 마지막 캔들을 넘지 않는다 — 미래 빈 구간 금지.
    /// 창이 데이터 전체보다 크면 우측 정렬(최신이 항상 오른쪽 끝).
    private func clampScroll(_ proposed: Date) -> Date {
        guard let first = candles.first?.date, let last = candles.last?.date else { return proposed }
        let window = effectiveVisibleSeconds
        // windowEnd ≤ 마지막 캔들 + 캔들 1개 폭.
        let maxX = last.addingTimeInterval(interval.seconds - window)
        let minX = first.addingTimeInterval(-window * 0.1)
        guard minX <= maxX else { return maxX }
        return min(max(proposed, minX), maxX)
    }

    /// factor > 1 = 줌아웃, < 1 = 줌인. anchor(커서 날짜)를 창 안 같은 비율 지점에 유지.
    private func zoom(by factor: Double, anchor: Date? = nil) {
        endPanAnimation()
        let current = effectiveVisibleSeconds
        let maxWindow = max(dataSpanSeconds, minWindowSeconds)
        let proposed = min(max(current * factor, minWindowSeconds), maxWindow)
        guard proposed != current else { return }

        let anchorDate = anchor ?? scrollX.addingTimeInterval(current / 2)
        let fraction = min(max(anchorDate.timeIntervalSince(scrollX) / current, 0), 1)
        visibleSeconds = proposed
        scrollX = clampScroll(anchorDate.addingTimeInterval(-proposed * fraction))
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if magnifyStartSeconds == nil {
                    magnifyStartSeconds = effectiveVisibleSeconds
                }
                guard let base = magnifyStartSeconds, value.magnification > 0 else { return }
                let center = scrollX.addingTimeInterval(effectiveVisibleSeconds / 2)
                let maxWindow = max(dataSpanSeconds, minWindowSeconds)
                let proposed = min(max(base / value.magnification, minWindowSeconds), maxWindow)
                visibleSeconds = proposed
                scrollX = clampScroll(center.addingTimeInterval(-proposed / 2))
            }
            .onEnded { _ in magnifyStartSeconds = nil }
    }

    /// 차트 위 스크롤 — 세로 = 줌, 가로 = 팬.
    private func installScrollZoomMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard isHoveringChart, !candles.isEmpty else { return event }
            endPanAnimation()
            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY
            if abs(deltaY) > abs(deltaX), deltaY != 0 {
                let raw = event.hasPreciseScrollingDeltas ? deltaY : deltaY * 8
                // 위로 스크롤 → 줌인. 이벤트당 변화량은 ±30%로 제한.
                let factor = min(max(1 - raw * 0.006, 0.7), 1.3)
                zoom(by: factor, anchor: hoveredDate)
                return nil
            }
            if deltaX != 0 {
                let raw = event.hasPreciseScrollingDeltas ? deltaX : deltaX * 8
                let secondsPerPixel = effectiveVisibleSeconds / max(plotFrame.width, 1)
                scrollX = clampScroll(scrollX.addingTimeInterval(-raw * secondsPerPixel))
                return nil
            }
            return event
        }
    }

    private func removeScrollZoomMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    // MARK: - 좌표 변환 (플롯 프레임 기준 수동 계산)

    private func xPosition(for date: Date) -> CGFloat {
        let span = max(effectiveVisibleSeconds, 1)
        let fraction = date.timeIntervalSince(scrollX) / span
        return plotFrame.minX + fraction * plotFrame.width
    }

    private func yPosition(for value: Double) -> CGFloat {
        let lower = yDomain.lowerBound
        let span = max(yDomain.upperBound - lower, .ulpOfOne)
        let fraction = (value - lower) / span
        return plotFrame.minY + (1 - fraction) * plotFrame.height
    }

    private func date(atPlotX x: CGFloat) -> Date {
        let fraction = x / max(plotFrame.width, 1)
        return scrollX.addingTimeInterval(fraction * effectiveVisibleSeconds)
    }

    // MARK: - 상호작용 오버레이 (hover·팬·더블클릭·마커·크로스헤어)

    private var interactionLayer: some View {
        ZStack(alignment: .topLeading) {
            // 이벤트 캐치 레이어.
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: plotFrame.width, height: plotFrame.height)
                .offset(x: plotFrame.minX, y: plotFrame.minY)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hoveredDate = date(atPlotX: point.x)
                    case .ended:
                        hoveredDate = nil
                    }
                }
                .gesture(dragPan)
                .gesture(doubleClickPrefill)

            crosshair
            tradeMarkers
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dragPan: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStartScrollX == nil {
                    endPanAnimation()
                    dragStartScrollX = scrollX
                }
                guard let start = dragStartScrollX else { return }
                let secondsPerPixel = effectiveVisibleSeconds / max(plotFrame.width, 1)
                scrollX = clampScroll(
                    start.addingTimeInterval(-value.translation.width * secondsPerPixel)
                )
            }
            .onEnded { _ in dragStartScrollX = nil }
    }

    private var doubleClickPrefill: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard
                    let candle = nearestCandle(to: date(atPlotX: value.location.x))
                else {
                    return
                }
                model.push(.tradeForm(
                    assetID: asset.id,
                    editing: nil,
                    prefill: TradePrefill(date: candle.date, price: candle.close)
                ))
            }
    }

    @ViewBuilder
    private var crosshair: some View {
        if dragStartScrollX == nil,
           hoveredTradeID == nil,
           focusedTradeID == nil,
           let hoveredDate,
           let candle = nearestCandle(to: hoveredDate),
           candle.date >= scrollX, candle.date <= windowEnd {
            let x = xPosition(for: candle.date)
            let y = yPosition(for: candle.close.doubleValue)

            // zIndex: 가격 툴팁이 B/S 마커 뒤로 숨지 않게 마커보다 위.
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(theme.guide)
                    .frame(width: 1, height: plotFrame.height)
                    .offset(x: x, y: plotFrame.minY)

                DashedHLine()
                    .stroke(theme.guide.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .frame(width: plotFrame.width, height: 1)
                    .offset(x: plotFrame.minX, y: y)

                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .offset(x: x - 3.5, y: y - 3.5)

                TooltipBubble(
                    text: MoneyFormatter.price(candle.close, currency: asset.currency),
                    secondary: crosshairDateText(candle.date),
                    blurText: model.settings.privacyMode
                )
                .position(
                    x: min(max(x, plotFrame.minX + 52), plotFrame.maxX - 52),
                    y: plotFrame.minY + 18
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .zIndex(20)
        }
    }

    @ViewBuilder
    private var tradeMarkers: some View {
        // 마커 원은 전부 렌더하고 플롯에 클립한다 — 화면 밖 마커도 뷰 트리에 남아
        // scrollX가 애니메이션될 때 위치가 함께 보간돼 좌/우로 자연스럽게 들고 난다.
        ZStack(alignment: .topLeading) {
            ForEach(visibleTrades) { trade in
                markerDot(trade: trade)
                    .position(
                        x: xPosition(for: trade.date),
                        y: yPosition(for: markerLineValue(trade))
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(PlotRectClip(rect: plotFrame))

        // 강조 마커의 툴팁은 클립 밖(플롯 위)에서 그려 잘리지 않게 한다.
        emphasizedTooltip
    }

    /// 강조(hover/포커스)된 마커 위 툴팁 — 마커 원 레이어와 분리해 플롯 클립에 잘리지 않게.
    @ViewBuilder
    private var emphasizedTooltip: some View {
        if let id = focusedTradeID ?? hoveredTradeID,
           let trade = visibleTrades.first(where: { $0.id == id }) {
            let x = xPosition(for: trade.date)
            let y = yPosition(for: markerLineValue(trade))
            if x >= plotFrame.minX - 9, x <= plotFrame.maxX + 9 {
                TooltipBubble(text: markerTitle(trade), secondary: markerSub(trade))
                    .position(x: x + tooltipShift(atX: x), y: y - 32)
                    .allowsHitTesting(false)
                    .zIndex(30)
            }
        }
    }

    /// 마커 y값 — 체결가가 아니라 거래 시점 캔들 종가(가격선)에 얹는다. 체결가는 툴팁에.
    private func markerLineValue(_ trade: Trade) -> Double {
        nearestCandle(to: trade.date)?.close.doubleValue ?? trade.price.doubleValue
    }

    /// 마커 툴팁이 플롯 밖으로 잘리지 않게 좌우로 밀어줄 오프셋.
    private func tooltipShift(atX x: CGFloat) -> CGFloat {
        let halfWidth: CGFloat = 105
        let rightOverhang = (x + halfWidth) - plotFrame.maxX
        if rightOverhang > 0 { return -rightOverhang }
        let leftOverhang = plotFrame.minX - (x - halfWidth)
        if leftOverhang > 0 { return leftOverhang }
        return 0
    }

    private func crosshairDateText(_ date: Date) -> String {
        if interval.isIntraday {
            return date.formatted(
                .dateTime.month(.defaultDigits).day().hour().minute().locale(model.locale)
            )
        }
        return date.formatted(.dateTime.year().month().day().locale(model.locale))
    }

    private var avgLabel: String {
        let price = MoneyFormatter.price(position.averageCost.rounded(scale: 2), currency: asset.currency)
        return model.t("Avg \(price)")
    }

    private func markerDot(trade: Trade) -> some View {
        let isBuy = trade.side == .buy
        let markerColor = isBuy ? theme.green : theme.red
        let isEmphasized = hoveredTradeID == trade.id || focusedTradeID == trade.id
        return ZStack {
            Circle()
                .fill(theme.pointBg)
                .overlay(Circle().strokeBorder(markerColor, lineWidth: 1.5))
                .frame(width: 18, height: 18)
            Text(isBuy ? "B" : "S")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(markerColor)
        }
        .scaleEffect(isEmphasized ? 1.18 : 1)
        .shadow(
            color: isEmphasized ? markerColor.opacity(0.5) : .black.opacity(0.25),
            radius: isEmphasized ? 5 : 3, y: 1
        )
        .animation(.easeOut(duration: 0.15), value: isEmphasized)
        .zIndex(isEmphasized ? 25 : 0)
        .onHover { hovering in
            hoveredTradeID = hovering ? trade.id : nil
        }
        .onTapGesture {
            onSelectTrade(trade.id)
        }
    }

    private func markerTitle(_ trade: Trade) -> String {
        let action = trade.side == .buy ? model.t("Buy") : model.t("Sell")
        let qty = MoneyFormatter.quantity(trade.quantity)
        let price = model.settings.privacyMode
            ? MoneyFormatter.masked
            : MoneyFormatter.price(trade.price, currency: asset.currency)
        return "\(action) \(qty) @ \(price)"
    }

    private func markerSub(_ trade: Trade) -> String {
        let date = trade.date.formatted(.dateTime.month(.defaultDigits).day().locale(model.locale))
        switch trade.side {
        case .buy:
            guard let quote = model.quotes[asset.id], trade.price > 0 else { return date }
            let percent = ((quote.price - trade.price) / trade.price * 100).rounded(scale: 2)
            return "\(date) · " + model.t("vs now \(MoneyFormatter.percent(percent))")
        case .sell:
            guard let pnl = model.realizedPnL(of: trade), !model.settings.privacyMode else { return date }
            return "\(date) · " + model.t("Realized \(MoneyFormatter.signedPrice(pnl.rounded(scale: 2), currency: asset.currency))")
        }
    }

    private func nearestCandle(to date: Date) -> Candle? {
        candles.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }
}

// MARK: - 차트 본체 (Equatable — hover/툴팁 상태 변화에 재렌더되지 않음)

private struct PlotFramePreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct PriceChartBody: View, Equatable {
    let candles: [Candle]
    let xDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    let avgCost: Double?
    let avgText: String
    let color: Color
    let currency: String
    let interval: CandleInterval
    let windowSeconds: Double
    let locale: Locale
    let gridColor: Color
    let refLineColor: Color
    let labelColor: Color
    let annotationColor: Color

    var body: some View {
        Chart {
            ForEach(candles, id: \.date) { candle in
                // yStart를 도메인 하단에 고정 — 기본값(0)이면 필이 플롯 밖까지 뻗는다.
                AreaMark(
                    x: .value("Date", candle.date),
                    yStart: .value("Base", yDomain.lowerBound),
                    yEnd: .value("Price", candle.close.doubleValue)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.2), color.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Date", candle.date),
                    y: .value("Price", candle.close.doubleValue)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.2))
            }

            if let avgCost {
                RuleMark(y: .value("Avg", avgCost))
                    .foregroundStyle(refLineColor)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(avgText)
                            .font(.system(size: 8))
                            .foregroundStyle(annotationColor)
                            .padding(.leading, 2)
                    }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartPlotStyle { $0.clipped() }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(gridColor)
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(
                            MoneyFormatter.compactPrice(
                                Decimal.fromDouble(doubleValue), currency: currency
                            )
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(labelColor)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel(anchor: .top) {
                    if let date = value.as(Date.self) {
                        Text(Self.tickLabel(for: date, interval: interval, windowSeconds: windowSeconds, locale: locale))
                            .font(.system(size: 9))
                            .foregroundStyle(labelColor)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Color.clear.preference(
                    key: PlotFramePreferenceKey.self,
                    value: proxy.plotFrame.map { geo[$0] } ?? .zero
                )
            }
        }
    }

    /// 바이낸스식 눈금 — 인트라데이는 자정에 날짜, 그 외 시각(HH:mm). 일봉 이상은 창 길이에 맞춰.
    static func tickLabel(
        for date: Date,
        interval: CandleInterval,
        windowSeconds: Double,
        locale: Locale
    ) -> String {
        let calendar = Calendar.current
        if interval.isIntraday {
            let hour = calendar.component(.hour, from: date)
            let minute = calendar.component(.minute, from: date)
            if hour == 0 && minute == 0 {
                return date.formatted(.dateTime.month(.defaultDigits).day().locale(locale))
            }
            return String(format: "%02d:%02d", hour, minute)
        }
        if interval == .day {
            return windowSeconds > 400 * 86_400
                ? date.formatted(.dateTime.year(.twoDigits).month(.defaultDigits).locale(locale))
                : date.formatted(.dateTime.month(.defaultDigits).day().locale(locale))
        }
        return windowSeconds > 3 * 365 * 86_400
            ? date.formatted(.dateTime.year().locale(locale))
            : date.formatted(.dateTime.year(.twoDigits).month(.defaultDigits).locale(locale))
    }
}

/// 가로 점선 (크로스헤어 수평선용).
private struct DashedHLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

/// 플롯 사각형으로 클립 — 마커가 축 라벨 영역으로 넘치지 않게(뷰 좌표계 절대 rect).
private struct PlotRectClip: Shape {
    let rect: CGRect
    func path(in _: CGRect) -> Path { Path(rect) }
}
