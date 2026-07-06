import SwiftUI
import WeaveCore

/// 홈 — 헤더 · 링 3개 · 총액 · Value History · Assets 리스트 · footer.
struct HomeView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    @State private var deletionTarget: Asset?

    var body: some View {
        let (perAsset, portfolio) = model.computed

        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    // zIndex: 링 hover 툴팁이 아래 총액 위에 그려지도록.
                    RingsRow(portfolio: portfolio)
                        .zIndex(10)
                    totalSection(portfolio)
                    CapsHeader(text: model.t("Value History"))
                    ValueHistoryChart()
                    CapsHeader(text: model.t("Assets"))
                    VStack(spacing: 0) {
                        ForEach(perAsset) { metric in
                            AssetListRow(metric: metric) {
                                deletionTarget = metric.asset
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            HomeFooter()
        }
        // 홈 진입·자산/거래 변이·기간 변경마다 재계산 — 같은 날은 캔들 캐시 히트라 저렴.
        .task(id: "\(model.chartGeneration)|\(model.homeChartPeriod.rawValue)") {
            await model.loadHomeChart()
        }
        .confirmationDialog(
            model.t("Delete asset?"),
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(model.t("Delete"), role: .destructive) {
                if let target = deletionTarget {
                    model.deleteAsset(id: target.id)
                }
                deletionTarget = nil
            }
            Button(model.t("Cancel"), role: .cancel) { deletionTarget = nil }
        } message: {
            if let target = deletionTarget {
                Text(model.t("\(target.name) and \(model.tradeCount(assetID: target.id)) trade(s) will be deleted."))
            }
        }
    }

    private var header: some View {
        HStack {
            IconButton(systemName: "arrow.clockwise") {
                model.manualRefresh()
            }
            .help(model.t("Refresh now"))
            Spacer()
            Text(verbatim: "Weave")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.text)
            Spacer()
            HStack(spacing: 6) {
                IconButton(
                    systemName: model.settings.privacyMode ? "eye.slash" : "eye",
                    isActive: model.settings.privacyMode
                ) {
                    model.settings.privacyMode.toggle()
                    model.updateMenuBarTitle()
                }
                .help(model.t("Privacy mode"))
                IconButton(systemName: "gearshape") {
                    model.push(.settings)
                }
                .help(model.t("Settings"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func totalSection(_ portfolio: PortfolioMetrics) -> some View {
        VStack(spacing: 8) {
            Text(
                MoneyFormatter.price(
                    portfolio.totalValueBase.rounded(scale: 0),
                    currency: model.settings.baseCurrency
                )
            )
            .font(.system(size: 26, weight: .bold))
            .monospacedDigit()
            .kerning(-0.3)
            .foregroundStyle(theme.text)
            .privacyBlur(model.settings.privacyMode)

            ChangeBadge(
                text: badgeText(portfolio.dayChangePercent),
                style: portfolio.dayChangePercent >= 0 ? .up : .down
            )
        }
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    private func badgeText(_ percent: Decimal) -> String {
        let arrow = percent >= 0 ? "▲ " : "▼ "
        return arrow + MoneyFormatter.percent(abs(percent)).dropFirst()
    }
}

struct AssetListRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let metric: AssetMetrics
    let onDelete: () -> Void

    var body: some View {
        Button {
            model.push(.detail(metric.asset.id))
        } label: {
            HStack(spacing: 10) {
                AssetLogoView(asset: metric.asset)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(metric.asset.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        if metric.asset.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(theme.text2)
                        }
                        if model.staleAssetIDs.contains(metric.asset.id) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 8))
                                .foregroundStyle(theme.orange)
                                .help(model.t("Quote unavailable — showing last value"))
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.text2)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(priceText)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.text)
                        .privacyBlur(model.settings.privacyMode)
                    changeBadge
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .contextMenu {
            if !metric.asset.isManual {
                Button(metric.asset.isPinned ? model.t("Unpin from menu bar") : model.t("Pin to menu bar")) {
                    model.togglePin(assetID: metric.asset.id)
                }
            }
            Button(model.t("Hide")) {
                model.toggleHidden(assetID: metric.asset.id)
            }
            Button(model.t("Delete"), role: .destructive, action: onDelete)
        }
    }

    private var subtitle: String {
        if metric.asset.isManual {
            return model.t("Manual")
        }
        let qty = MoneyFormatter.quantity(metric.position.quantity)
        let buys = model.t("\(metric.position.buyCount) buys")
        return "\(qty) \(metric.asset.symbol) · \(buys)"
    }

    private var priceText: String {
        if metric.asset.isManual {
            return MoneyFormatter.price(metric.value, currency: metric.asset.currency)
        }
        guard let quote = metric.quote else { return "—" }
        // 자산 표시 통화 설정: 소스 통화 그대로(기본) / 기준 통화 환산.
        // 환율이 아직 없으면 잘못된 통화로 표기하지 말고 소스 통화 유지.
        if model.settings.displayCurrencyMode == .base,
           let rate = model.fxRates[metric.asset.currency.uppercased()] {
            return MoneyFormatter.price(quote.price * rate, currency: model.settings.baseCurrency)
        }
        return MoneyFormatter.price(quote.price, currency: quote.currency)
    }

    @ViewBuilder
    private var changeBadge: some View {
        if let percent = metric.dayChangePercent {
            ChangeBadge(
                text: MoneyFormatter.percent(percent),
                style: percent >= 0 ? .up : .down
            )
        } else {
            ChangeBadge(text: "—", style: .gray)
        }
    }
}

struct HomeFooter: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack {
            if let newVersion = model.updater.availableVersion {
                Button {
                    model.updater.checkForUpdates()
                } label: {
                    Text(model.t("Weave \(WeaveInfo.version) → \(newVersion) available"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.greenText)
                }
                .buttonStyle(.plain)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(footerText(now: context.date))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.caps)
                        .monospacedDigit()
                }
            }
            Spacer()
            Button {
                model.push(.manage)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.link)
            }
            .buttonStyle(.plain)
            .help(model.t("Manage assets"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hair).frame(height: 1)
        }
    }

    private func footerText(now: Date) -> String {
        let version = "Weave \(WeaveInfo.version)"
        guard let next = model.nextRefreshAt else { return version }
        let remaining = max(0, Int(next.timeIntervalSince(now)))
        let text: String
        if remaining >= 60 {
            text = model.t("Next refresh in \(remaining / 60)m")
        } else {
            text = model.t("Next refresh in \(remaining)s")
        }
        return "\(version) · \(text)"
    }
}
