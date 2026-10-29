import SwiftUI
import WeaveCore

/// 연결 하나 — 무엇을 어디서 읽는지, 가져온 보유, 가져오지 않은 잔고.
struct SourceDetailView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let sourceID: UUID
    @State private var disconnectTarget: LinkedSource?

    private var source: LinkedSource? { model.document.source(id: sourceID) }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: source?.name ?? "", onBack: { model.pop() })

            if let source {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        infoCard(source)
                        holdingsSection(source)
                        skippedSection(source)
                    }
                    .padding(.bottom, 12)
                }
                footer(source)
            } else {
                Spacer()
            }
        }
        .confirmDialog(
            $disconnectTarget,
            title: { _ in model.t("Disconnect account?") },
            message: { model.disconnectMessage($0) },
            confirmTitle: model.t("Disconnect"),
            isDestructive: true,
            cancelTitle: model.t("Cancel"),
            onConfirm: {
                model.disconnectSource(id: $0.id)
                model.pop()
            }
        )
    }

    // MARK: - 정보

    private func infoCard(_ source: LinkedSource) -> some View {
        let config = model.walletConfigs[source.id]
        return PanelCard(padding: EdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 14)) {
            VStack(spacing: 0) {
                infoRow(model.t("Type"), model.sourceKindName(source.kind))
                if let config {
                    divider
                    infoRow(model.t(config.addresses.count > 1 ? "Addresses" : "Address"),
                            config.addresses.map(WalletConfig.shortAddress).joined(separator: "\n"),
                            monospaced: true)
                    if config.kind == .evm {
                        divider
                        infoRow(model.t("Chains"), config.chains.map(\.name).joined(separator: ", "))
                    }
                } else if !source.label.isEmpty {
                    divider
                    infoRow(model.t(source.kind.isWallet ? "Address" : "Account"), source.label, monospaced: true)
                }
                divider
                infoRow(model.t("Last sync"), lastSyncText(source))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private func infoRow(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.text)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .system(size: 11.5, design: .monospaced) : .system(size: 12))
                .foregroundStyle(theme.text2)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 8)
    }

    private var divider: some View {
        Rectangle().fill(theme.hair).frame(height: 1)
    }

    // MARK: - 보유

    @ViewBuilder
    private func holdingsSection(_ source: LinkedSource) -> some View {
        let holdings = model.holdings(sourceID: source.id)
        sectionLabel(model.t("Holdings"))
        PanelCard(padding: EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12)) {
            if holdings.isEmpty {
                Text(emptyText(source))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(holdings.enumerated()), id: \.element.asset.id) { index, item in
                        if index > 0 { divider }
                        Button {
                            model.push(.detail(item.asset.id))
                        } label: {
                            HStack(spacing: 10) {
                                AssetLogoView(asset: item.asset, size: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.asset.name)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(theme.text)
                                        .lineLimit(1)
                                    Text("\(item.asset.formattedQuantity(item.quantity)) \(item.asset.symbol)")
                                        .font(.system(size: 10.5))
                                        .monospacedDigit()
                                        .foregroundStyle(theme.text2)
                                        .privacyBlur(model.settings.privacyMode)
                                }
                                Spacer(minLength: 8)
                                Text(valueText(item.asset, item.quantity))
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(theme.text)
                                    .privacyBlur(model.settings.privacyMode)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private func emptyText(_ source: LinkedSource) -> String {
        guard source.kind.isWallet else { return model.t("No holdings in this account.") }
        return model.t("No coins worth $10 or more with a Binance price were found on these chains.")
    }

    private func valueText(_ asset: Asset, _ quantity: Decimal) -> String {
        guard let quote = model.quotes[asset.id] else { return "—" }
        return MoneyFormatter.price(quote.price * quantity, currency: quote.currency)
    }

    // MARK: - 가져오지 않은 잔고

    @ViewBuilder
    private func skippedSection(_ source: LinkedSource) -> some View {
        let all = model.skippedBalances(sourceID: source.id)
        // 소액 토큰이 수십 개일 수 있다 — 큰 것 10개만 보이고 나머지는 개수만.
        let skipped = Array(all.prefix(10))
        if source.kind.isWallet, !skipped.isEmpty {
            sectionLabel(model.t("Not imported"))
            PanelCard(padding: EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12)) {
                VStack(spacing: 0) {
                    ForEach(Array(skipped.enumerated()), id: \.offset) { index, item in
                        if index > 0 { divider }
                        HStack {
                            Text(item.holding.instrument.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.text)
                            Text(MoneyFormatter.quantity(item.holding.quantity))
                                .font(.system(size: 10.5))
                                .monospacedDigit()
                                .foregroundStyle(theme.text2)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(item.unpriced
                                ? model.t("No price")
                                : MoneyFormatter.price(item.holding.quantity * (item.holding.marketPrice ?? 0), currency: "USD"))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(theme.text2)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
            .padding(.horizontal, 14)
            if all.count > skipped.count {
                Text(model.t("and \(all.count - skipped.count) more"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.text2)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
            }
            Text(model.t("Coins under $10 or without a Binance price aren't added. Tokens outside Weave's list aren't read."))
                .font(.system(size: 10.5))
                .foregroundStyle(theme.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 6)
        }
    }

    // MARK: - 하단

    private func footer(_ source: LinkedSource) -> some View {
        HStack(spacing: 8) {
            LinkSecondaryButton(title: model.t("Sync now"), disabled: model.linkStatus[source.id] == .syncing) {
                Task { await model.syncSource(id: source.id) }
            }
            Spacer()
            LinkSecondaryButton(title: model.t("Disconnect…"), isDestructive: true) {
                disconnectTarget = source
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hair).frame(height: 1)
        }
    }

    private func lastSyncText(_ source: LinkedSource) -> String {
        if model.linkStatus[source.id] == .syncing { return model.t("Syncing…") }
        guard let date = source.lastSyncedAt else { return "—" }
        return date.formatted(.dateTime.month().day().hour().minute().locale(model.locale))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .textCase(.uppercase)
            .foregroundStyle(theme.caps)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}
