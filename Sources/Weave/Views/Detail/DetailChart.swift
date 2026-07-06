import Charts
import SwiftUI
import WeaveCore

/// 상세 차트 — 종가 라인+그라디언트, 평단 점선, B/S 마커, 크로스헤어.
/// 가로 드래그/스크롤 = 팬, 핀치 = 줌, 더블클릭 = 최신 구간 리셋.
struct DetailChart: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let asset: Asset
    let trades: [Trade]
    let position: PositionSnapshot

    @State private var hoveredDate: Date?
    @State private var hoveredTradeID: UUID?
    /// 보이는 창의 왼쪽 끝(x 스크롤 위치).
    @State private var scrollX = Date.distantPast
    /// 보이는 창의 길이(초). 0이면 아직 초기화 전.
    @State private var visibleSeconds: Double = 0
    @State private var magnifyStartSeconds: Double?

    private var candles: [Candle] { model.detailCandles }
    private var color: Color { theme.paletteColor(asset.colorIndex) }
    private var interval: CandleInterval { model.detailInterval }

    // MARK: - 창(window) 계산

    /// 기본 창 = 캔들 90개.
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

    private var visibleCandles: [Candle] {
        let window = candles.filter { $0.date >= scrollX && $0.date <= windowEnd }
        return window.isEmpty ? candles : window
    }

    /// y 도메인은 보이는 구간에 맞춰 자동 피팅(바이낸스식).
    private var yDomain: ClosedRange<Double> {
        var values = visibleCandles.map { $0.close.doubleValue }
        values.append(contentsOf: visibleTrades
            .filter { $0.date >= scrollX && $0.date <= windowEnd }
            .map { $0.price.doubleValue })
        guard let min = values.min(), let max = values.max(), min < max else {
            let v = values.first ?? 1
            return (v * 0.9)...(v * 1.1)
        }
        let pad = (max - min) * 0.12
        return (min - pad)...(max + pad)
    }

    /// 차트 구간 안의 거래만 마커로.
    private var visibleTrades: [Trade] {
        guard let first = candles.first?.date else { return [] }
        return trades.filter { $0.date >= first }
    }

    var body: some View {
        Group {
            if candles.isEmpty {
                placeholder
            } else {
                chart
            }
        }
        .frame(height: 190)
        .padding(.horizontal, 8)
        .onChange(of: candles) { resetWindow() }
        .onAppear { resetWindow() }
    }

    private func resetWindow() {
        guard let last = candles.last?.date else { return }
        let span = max(dataSpanSeconds, minWindowSeconds)
        visibleSeconds = min(defaultWindowSeconds, span)
        scrollX = last.addingTimeInterval(interval.seconds - visibleSeconds)
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

    // MARK: - 차트

    private var chart: some View {
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

            // 평단 점선 + 라벨 — 보유 중일 때만.
            if position.quantity > 0, position.averageCost > 0 {
                RuleMark(y: .value("Avg", position.averageCost.doubleValue))
                    .foregroundStyle(theme.refLine)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(avgLabel)
                            .font(.system(size: 8))
                            .foregroundStyle(theme.text2)
                            .padding(.leading, 2)
                    }
            }

            // 크로스헤어.
            if let hoveredDate, let candle = nearestCandle(to: hoveredDate) {
                RuleMark(x: .value("Date", candle.date))
                    .foregroundStyle(theme.guide)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                RuleMark(y: .value("Price", candle.close.doubleValue))
                    .foregroundStyle(theme.guide.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                PointMark(
                    x: .value("Date", candle.date),
                    y: .value("Price", candle.close.doubleValue)
                )
                .symbolSize(30)
                .foregroundStyle(color)
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: effectiveVisibleSeconds)
        .chartScrollPosition(x: $scrollX)
        .chartYScale(domain: yDomain)
        .chartPlotStyle { $0.clipped() }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(theme.grid)
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(
                            MoneyFormatter.compactPrice(
                                Decimal.fromDouble(doubleValue), currency: asset.currency
                            )
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(theme.xLabel)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: xFormat, anchor: .top)
                    .font(.system(size: 9))
                    .foregroundStyle(theme.xLabel)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                crosshairAndMarkers(proxy: proxy, geo: geo)
            }
        }
        .simultaneousGesture(magnification)
        // 줌/팬 리셋 — 더블클릭은 거래 프리필에 쓰므로 버튼으로.
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { resetWindow() }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.text2)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6).fill(theme.iconBg))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(model.t("Reset zoom"))
            .padding(.top, 2)
            .padding(.trailing, 46)
        }
    }

    /// 핀치 줌 — 창 중앙을 고정한 채 창 길이를 조절.
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
                scrollX = center.addingTimeInterval(-proposed / 2)
            }
            .onEnded { _ in magnifyStartSeconds = nil }
    }

    /// 보이는 창 길이에 맞춘 x축 라벨 포맷.
    private var xFormat: Date.FormatStyle {
        let window = effectiveVisibleSeconds
        if window <= 2 * 86_400 {
            return .dateTime.hour().minute().locale(model.locale)
        }
        if window <= 120 * 86_400 {
            return .dateTime.month(.defaultDigits).day().locale(model.locale)
        }
        if window <= 730 * 86_400 {
            return .dateTime.month(.abbreviated).locale(model.locale)
        }
        return .dateTime.year().locale(model.locale)
    }

    private var avgLabel: String {
        let price = model.settings.privacyMode
            ? MoneyFormatter.masked
            : MoneyFormatter.price(position.averageCost.rounded(scale: 2), currency: asset.currency)
        return model.t("Avg \(price)")
    }

    // MARK: - 오버레이 (hover 추적 + B/S 마커 + 툴팁)

    @ViewBuilder
    private func crosshairAndMarkers(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let plotAnchor = proxy.plotFrame {
            let plot = geo[plotAnchor]
            ZStack(alignment: .topLeading) {
                // hover 캐치 레이어 + 더블클릭 → 그 지점 날짜/가격으로 거래 추가.
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(width: plot.width, height: plot.height)
                    .position(x: plot.midX, y: plot.midY)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            let inPlot = CGPoint(x: point.x - plot.origin.x, y: point.y - plot.origin.y)
                            hoveredDate = proxy.value(atX: inPlot.x, as: Date.self)
                        case .ended:
                            hoveredDate = nil
                        }
                    }
                    .gesture(
                        SpatialTapGesture(count: 2)
                            .onEnded { value in
                                let inPlotX = value.location.x - plot.origin.x
                                guard
                                    let date = proxy.value(atX: inPlotX, as: Date.self),
                                    let candle = nearestCandle(to: date)
                                else {
                                    return
                                }
                                model.push(.tradeForm(
                                    assetID: asset.id,
                                    editing: nil,
                                    prefill: TradePrefill(date: candle.date, price: candle.close)
                                ))
                            }
                    )

                // B/S 마커 — 팬/줌으로 창 밖에 있으면 숨김.
                ForEach(visibleTrades) { trade in
                    if let x = proxy.position(forX: trade.date),
                       let y = proxy.position(forY: trade.price.doubleValue),
                       x >= 0, x <= plot.width, y >= -9, y <= plot.height + 9 {
                        tradeMarker(trade: trade, plot: plot)
                            .position(
                                x: plot.origin.x + x,
                                y: plot.origin.y + min(max(y, 9), plot.height - 9)
                            )
                    }
                }

                // 크로스헤어 툴팁.
                if hoveredTradeID == nil,
                   let hoveredDate,
                   let candle = nearestCandle(to: hoveredDate),
                   let x = proxy.position(forX: candle.date) {
                    TooltipBubble(
                        text: model.settings.privacyMode
                            ? MoneyFormatter.masked
                            : MoneyFormatter.price(candle.close, currency: asset.currency),
                        secondary: crosshairDateText(candle.date)
                    )
                    .position(
                        x: plot.origin.x + min(max(x, 52), plot.width - 52),
                        y: plot.origin.y + 18
                    )
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private func crosshairDateText(_ date: Date) -> String {
        if interval.isIntraday {
            return date.formatted(
                .dateTime.month(.defaultDigits).day().hour().minute().locale(model.locale)
            )
        }
        return date.formatted(.dateTime.year().month().day().locale(model.locale))
    }

    private func tradeMarker(trade: Trade, plot: CGRect) -> some View {
        let isBuy = trade.side == .buy
        let markerColor = isBuy ? theme.green : theme.red
        let isHovered = hoveredTradeID == trade.id
        return ZStack {
            Circle()
                .fill(theme.pointBg)
                .overlay(Circle().strokeBorder(markerColor, lineWidth: 1.5))
                .frame(width: 18, height: 18)
            Text(isBuy ? "B" : "S")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(markerColor)
            if isHovered {
                TooltipBubble(text: markerTitle(trade), secondary: markerSub(trade))
                    .offset(y: -32)
                    .allowsHitTesting(false)
                    .zIndex(30)
            }
        }
        .scaleEffect(isHovered ? 1.18 : 1)
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            hoveredTradeID = hovering ? trade.id : nil
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
