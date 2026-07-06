import SwiftUI
import WeaveCore

/// 자산 상세 — 현재가/배지 · 실캔들 차트 · Trades 리스트.
struct AssetDetailView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let assetID: UUID

    @State private var deletionTarget: Trade?
    @State private var isHoveringLogo = false

    private var trades: [Trade] {
        model.document.trades(for: assetID)
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        if let asset = model.asset(id: assetID) {
            content(asset: asset)
        } else {
            // 삭제 직후 잔상 방지.
            Color.clear.onAppear { model.popToHome() }
        }
    }

    private func content(asset: Asset) -> some View {
        let metric = model.metrics(id: assetID)
        let position = metric?.position ?? PositionSnapshot()

        return VStack(spacing: 0) {
            detailHeader(asset: asset)

            ScrollView {
                VStack(spacing: 0) {
                    priceSection(asset: asset, metric: metric, position: position)

                    if asset.isManual {
                        manualSection(asset: asset)
                    } else {
                        DetailChart(asset: asset, trades: model.document.trades(for: assetID), position: position)
                            .padding(.top, 10)

                        CapsHeader(text: model.t("Trades"))
                        realizedSummary(position: position, currency: asset.currency)
                        tradesList(asset: asset)
                    }
                }
                .padding(.bottom, 8)
            }

            footer(asset: asset, position: position)
        }
        .task(id: model.detailInterval) {
            await model.loadDetailChart(assetID: assetID)
        }
        .confirmationDialog(
            model.t("Delete trade?"),
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(model.t("Delete"), role: .destructive) {
                if let target = deletionTarget {
                    model.deleteTrade(id: target.id)
                }
                deletionTarget = nil
            }
            Button(model.t("Cancel"), role: .cancel) { deletionTarget = nil }
        }
    }

    // MARK: - 헤더 (로고 + 이름, 로고 클릭 = 아이콘 변경)

    private func detailHeader(asset: Asset) -> some View {
        HStack {
            IconButton(systemName: "chevron.left") {
                model.pop()
            }
            Spacer()
            HStack(spacing: 7) {
                AssetLogoView(asset: asset, size: 22)
                    // hover 시 "바꿀 수 있음" 어포던스 — 연필 오버레이 + 확대 + 손 커서.
                    .overlay {
                        if isHoveringLogo {
                            RoundedRectangle(cornerRadius: 22 * 0.29)
                                .fill(.black.opacity(0.45))
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .scaleEffect(isHoveringLogo ? 1.15 : 1)
                    .animation(.easeOut(duration: 0.15), value: isHoveringLogo)
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                    .onHover { hovering in
                        isHoveringLogo = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .onTapGesture {
                        model.pickCustomLogo(assetID: asset.id)
                    }
                    .contextMenu {
                        Button(model.t("Change icon…")) {
                            model.pickCustomLogo(assetID: asset.id)
                        }
                        if asset.customLogoFileName != nil {
                            Button(model.t("Reset to default icon")) {
                                model.clearCustomLogo(assetID: asset.id)
                            }
                        }
                    }
                    .help(model.t("Click to change icon"))
                Text(asset.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }
            Spacer()
            Group {
                if !asset.isManual {
                    IconButton(systemName: "plus") {
                        model.push(.tradeForm(assetID: assetID, editing: nil, prefill: nil))
                    }
                    .help(model.t("Add Trade"))
                } else {
                    Color.clear.frame(width: 26, height: 26)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - 현재가 + 배지

    private func priceSection(asset: Asset, metric: AssetMetrics?, position: PositionSnapshot) -> some View {
        VStack(spacing: 7) {
            Text(priceText(asset: asset, metric: metric))
                .font(.system(size: 24, weight: .bold))
                .monospacedDigit()
                .kerning(-0.3)
                .foregroundStyle(theme.text)
                .privacyBlur(model.settings.privacyMode)

            HStack(spacing: 5) {
                if let percent = metric?.dayChangePercent {
                    ChangeBadge(
                        text: MoneyFormatter.percent(percent),
                        style: percent >= 0 ? .up : .down
                    )
                }
                if !asset.isManual, position.averageCost > 0,
                   let price = metric?.quote?.price, position.quantity > 0 {
                    let vsAvg = ((price - position.averageCost) / position.averageCost * 100)
                        .rounded(scale: 2)
                    ChangeBadge(
                        text: model.t("vs avg \(MoneyFormatter.percent(vsAvg))"),
                        style: .gray,
                        minWidth: 0
                    )
                }
            }
        }
        .padding(.top, 6)
    }

    private func priceText(asset: Asset, metric: AssetMetrics?) -> String {
        if asset.isManual {
            return MoneyFormatter.price(asset.manualValue ?? 0, currency: asset.currency)
        }
        guard let quote = metric?.quote else { return "—" }
        return MoneyFormatter.price(quote.price, currency: quote.currency)
    }

    // MARK: - Trades

    private func realizedSummary(position: PositionSnapshot, currency: String) -> some View {
        HStack {
            Text(model.t("Realized P&L"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.text2)
            Spacer()
            Text(MoneyFormatter.signedPrice(position.realizedPnL, currency: currency))
                .font(.system(size: 11.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(position.realizedPnL >= 0 ? theme.greenText : theme.redText)
                .privacyBlur(model.settings.privacyMode)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func tradesList(asset: Asset) -> some View {
        if trades.isEmpty {
            Text(model.t("No trades yet — tap + to record your first buy."))
                .font(.system(size: 11.5))
                .foregroundStyle(theme.text2)
                .padding(.top, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(trades) { trade in
                    TradeRow(trade: trade, asset: asset) {
                        deletionTarget = trade
                    }
                }
            }
        }
    }

    private func footer(asset: Asset, position: PositionSnapshot) -> some View {
        HStack {
            Text(countText(position: position))
                .font(.system(size: 11))
                .foregroundStyle(theme.caps)
            Spacer()
            if !asset.isManual {
                Button {
                    model.push(.tradeForm(assetID: assetID, editing: nil, prefill: nil))
                } label: {
                    Text(model.t("+ Add Trade"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.greenText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hair).frame(height: 1)
        }
    }

    private func countText(position: PositionSnapshot) -> String {
        var parts: [String] = [model.t("\(position.buyCount) buys")]
        if position.sellCount > 0 {
            parts.append(model.t("\(position.sellCount) sells"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Manual

    private func manualSection(asset: Asset) -> some View {
        VStack(spacing: 10) {
            Text(model.t("Manual assets have no price updates."))
                .font(.system(size: 11.5))
                .foregroundStyle(theme.text2)
            Button {
                model.push(.manage)
            } label: {
                Text(model.t("Edit in asset manager"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.link)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 28)
    }
}

/// Trades 리스트 행 — 매수/매도 칩 · 수량@단가 · 우측 성과.
private struct TradeRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let trade: Trade
    let asset: Asset
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            chip
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text("\(MoneyFormatter.quantity(trade.quantity)) \(asset.symbol) @")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(MoneyFormatter.price(trade.price, currency: asset.currency))
                        .font(.system(size: 12.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .privacyBlur(model.settings.privacyMode)
                }
                Text(subText)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(rightValue)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(rightIsUp ? theme.greenText : theme.redText)
                    .privacyBlur(model.settings.privacyMode && trade.side == .sell)
                Text(rightLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.text2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .hoverHighlight()
        .contextMenu {
            Button(model.t("Edit")) {
                model.push(.tradeForm(assetID: asset.id, editing: trade, prefill: nil))
            }
            Button(model.t("Delete"), role: .destructive, action: onDelete)
        }
    }

    private var chip: some View {
        let isBuy = trade.side == .buy
        return Text(isBuy ? model.t("BUY") : model.t("SELL"))
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(isBuy ? theme.greenText : theme.redText)
            .padding(.horizontal, 8)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill((isBuy ? theme.green : theme.red).opacity(0.15))
            )
    }

    private var subText: String {
        let date = trade.date.formatted(
            .dateTime.year(.twoDigits).month(.defaultDigits).day().locale(model.locale)
        )
        return trade.note.isEmpty ? date : "\(date) · \(trade.note)"
    }

    private var rightIsUp: Bool {
        switch trade.side {
        case .buy:
            guard let quote = model.quotes[asset.id] else { return true }
            return quote.price >= trade.price
        case .sell:
            return (model.realizedPnL(of: trade) ?? 0) >= 0
        }
    }

    private var rightValue: String {
        switch trade.side {
        case .buy:
            guard let quote = model.quotes[asset.id], trade.price > 0 else { return "—" }
            let percent = ((quote.price - trade.price) / trade.price * 100).rounded(scale: 2)
            return MoneyFormatter.percent(percent)
        case .sell:
            guard let pnl = model.realizedPnL(of: trade) else { return "—" }
            return MoneyFormatter.signedPrice(pnl.rounded(scale: 2), currency: asset.currency)
        }
    }

    private var rightLabel: String {
        switch trade.side {
        case .buy: return model.t("vs now")
        case .sell: return model.t("Realized")
        }
    }
}
