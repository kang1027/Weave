import Charts
import SwiftUI
import WeaveCore

/// 상세 실캔들 차트 — 종가 라인+그라디언트, 평단 점선, B/S 마커, hover 크로스헤어.
struct DetailChart: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let asset: Asset
    let trades: [Trade]
    let position: PositionSnapshot

    @State private var hoveredDate: Date?
    @State private var hoveredTradeID: UUID?

    private var candles: [Candle] { model.detailCandles }
    private var color: Color { theme.paletteColor(asset.colorIndex) }

    private var yDomain: ClosedRange<Double> {
        var values = candles.map { $0.close.doubleValue }
        values.append(contentsOf: visibleTrades.map { $0.price.doubleValue })
        if position.quantity > 0, position.averageCost > 0 {
            values.append(position.averageCost.doubleValue)
        }
        guard let min = values.min(), let max = values.max(), min < max else {
            let v = values.first ?? 1
            return (v * 0.9)...(v * 1.1)
        }
        let pad = (max - min) * 0.1
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

    private var chart: some View {
        Chart {
            ForEach(candles, id: \.date) { candle in
                AreaMark(
                    x: .value("Date", candle.date),
                    y: .value("Price", candle.close.doubleValue)
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
        .chartYScale(domain: yDomain)
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
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: xLabelFormat, anchor: .top)
                    .font(.system(size: 9))
                    .foregroundStyle(theme.xLabel)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                crosshairAndMarkers(proxy: proxy, geo: geo)
            }
        }
    }

    private var xLabelFormat: Date.FormatStyle {
        model.detailPeriod == .all
            ? .dateTime.year(.twoDigits).locale(model.locale)
            : .dateTime.month(.narrow).locale(model.locale)
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
                // hover 캐치 레이어.
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

                // B/S 마커.
                ForEach(visibleTrades) { trade in
                    if let x = proxy.position(forX: trade.date),
                       let y = proxy.position(forY: trade.price.doubleValue) {
                        tradeMarker(trade: trade, plot: plot)
                            .position(x: plot.origin.x + x, y: plot.origin.y + y)
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
                        secondary: candle.date.formatted(
                            .dateTime.year().month().day().locale(model.locale)
                        )
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
