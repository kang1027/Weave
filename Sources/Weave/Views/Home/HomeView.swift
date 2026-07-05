import SwiftUI
import WeaveCore

// M3에서 링/차트/리스트로 채워지는 홈 — M2 시점엔 자산 리스트 + footer만.
struct HomeView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                IconButton(systemName: "arrow.clockwise") {
                    model.manualRefresh()
                }
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
                    IconButton(systemName: "gearshape") {
                        model.push(.settings)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            CapsHeader(text: model.t("Assets"))
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.computed.perAsset) { metric in
                        AssetListRow(metric: metric)
                    }
                }
            }

            Spacer(minLength: 0)
            HomeFooter()
        }
    }
}

struct AssetListRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let metric: AssetMetrics

    var body: some View {
        Button {
            model.push(.detail(metric.asset.id))
        } label: {
            HStack(spacing: 10) {
                AssetLogoView(asset: metric.asset)
                VStack(alignment: .leading, spacing: 1) {
                    Text(metric.asset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
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
                        .privacySensitive(model.settings.privacyMode)
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
            Button(model.t("Delete"), role: .destructive) {
                model.deleteAsset(id: metric.asset.id)
            }
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
        if model.settings.privacyMode { return MoneyFormatter.masked }
        if metric.asset.isManual {
            return MoneyFormatter.price(metric.value, currency: metric.asset.currency)
        }
        guard let quote = metric.quote else { return "—" }
        // 자산 표시 통화 설정: 소스 통화 그대로(기본) / 기준 통화 환산.
        if model.settings.displayCurrencyMode == .base {
            let rate = model.fxRates[metric.asset.currency.uppercased()] ?? 1
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
