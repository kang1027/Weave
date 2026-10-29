import AppKit
import SwiftUI
import WeaveCore

/// 연결 하나 — 위에 합계와 상태, 보유는 비중과 함께, 주소·체인은 아래 정보로, 동기화·해제는 맨 아래.
struct SourceDetailView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let sourceID: UUID
    @State private var disconnectTarget: LinkedSource?
    @State private var showsSkipped = false

    private var source: LinkedSource? { model.document.source(id: sourceID) }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "", onBack: { model.pop() })

            if let source {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(source)
                        holdingsSection(source)
                        skippedSection(source)
                        detailsSection(source)
                        actionsCard(source)
                    }
                    .padding(.bottom, 14)
                }
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

    // MARK: - 위

    private func hero(_ source: LinkedSource) -> some View {
        VStack(spacing: 4) {
            SourceLogo(kind: source.kind, size: 44)
            Text(source.name)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .padding(.top, 4)
            Text(MoneyFormatter.price(model.sourceValue(sourceID: source.id), currency: model.settings.baseCurrency))
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .privacyBlur(model.settings.privacyMode)
            HStack(spacing: 6) {
                switch model.linkStatus[source.id] {
                case .syncing:
                    ProgressView().controlSize(.mini)
                    Text(model.t("Syncing…"))
                case .failed(let failure):
                    StatusDot(color: theme.red)
                    Text(model.t("Paused"))
                        .foregroundStyle(theme.redText)
                        .help(model.linkFailureText(failure))
                default:
                    if let synced = source.lastSyncedAt {
                        StatusDot(color: theme.green)
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(model.t("Synced \(relativeSyncText(synced, now: context.date, model: model).lowercased()) · every \(model.linkSyncMinutes) min"))
                        }
                    }
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(theme.text2)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    // MARK: - 보유

    @ViewBuilder
    private func holdingsSection(_ source: LinkedSource) -> some View {
        let holdings = model.holdings(sourceID: source.id)
        let total = model.sourceValue(sourceID: source.id)
        CapsLabel(text: model.t("Holdings"))
        LinkCard {
            if holdings.isEmpty {
                Text(emptyText(source))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(holdings.enumerated()), id: \.element.asset.id) { index, item in
                        if index > 0 { HairDivider(inset: 48) }
                        let share = total > 0 ? model.valueInBase(item.asset, item.quantity) / total : 0
                        HoldingShareRow(asset: item.asset, quantity: item.quantity, share: share)
                    }
                }
            }
        }
    }

    private func emptyText(_ source: LinkedSource) -> String {
        guard source.kind.isWallet else { return model.t("No holdings in this account.") }
        return model.t("No coins worth $10 or more with a Binance price were found on these chains.")
    }

    // MARK: - 가져오지 않은 잔고

    @ViewBuilder
    private func skippedSection(_ source: LinkedSource) -> some View {
        let all = model.skippedBalances(sourceID: source.id)
        if source.kind.isWallet, !all.isEmpty {
            let total = all.reduce(Decimal(0)) { $0 + $1.holding.quantity * ($1.holding.marketPrice ?? 0) }
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showsSkipped.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        HStack(spacing: 0) {
                            Text(counted(all.count, "balance") + " skipped")
                                .fontWeight(.semibold)
                                .foregroundStyle(theme.badgeGrayText)
                            Text(" · \(MoneyFormatter.price(total, currency: "USD"))")
                                .foregroundStyle(theme.text2)
                                .privacyBlur(model.settings.privacyMode)
                        }
                        .font(.system(size: 11.5))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.text2)
                            .rotationEffect(.degrees(showsSkipped ? 90 : 0))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsSkipped {
                    // 소액 토큰이 수십 개일 수 있다 — 큰 것 10개만 보이고 나머지는 개수만.
                    ForEach(Array(all.prefix(10).enumerated()), id: \.offset) { _, item in
                        HairDivider()
                        HStack {
                            Text(item.holding.instrument.displaySymbol)
                                .font(.system(size: 11.5, weight: .semibold))
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                    HairDivider()
                    Text(all.count > 10
                        ? model.t("and \(all.count - 10) more. Coins under $10 or without a Binance price aren't added.")
                        : model.t("Coins under $10 or without a Binance price aren't added."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.seg))
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }

    // MARK: - 정보

    @ViewBuilder
    private func detailsSection(_ source: LinkedSource) -> some View {
        let config = model.walletConfigs[source.id]
        CapsLabel(text: model.t("Details"))
        LinkCard(padding: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)) {
            VStack(spacing: 0) {
                if let config {
                    ForEach(Array(config.addresses.enumerated()), id: \.offset) { index, address in
                        if index > 0 { HairDivider() }
                        infoRow(index == 0 ? model.t(config.addresses.count > 1 ? "Addresses" : "Address") : "") {
                            HStack(spacing: 8) {
                                Text(WalletConfig.shortAddress(address))
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(theme.text2)
                                    .help(address)
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(address, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(theme.link)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(model.t("Copy address"))
                            }
                        }
                    }
                    if config.kind == .evm {
                        HairDivider()
                        infoRow(model.t("Chains")) {
                            FlowLayout(spacing: 4, rowSpacing: 4, alignment: .trailing) {
                                ForEach(config.chains, id: \.self) { chain in
                                    LinkTag(text: chain.name)
                                }
                            }
                            .frame(maxWidth: 190, alignment: .trailing)
                        }
                    }
                } else {
                    infoRow(model.t("Type")) {
                        Text(model.sourceKindName(source.kind))
                            .font(.system(size: 12))
                            .foregroundStyle(theme.text2)
                    }
                    if !source.label.isEmpty {
                        HairDivider()
                        infoRow(model.t("Account")) {
                            Text(source.label)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(theme.text2)
                        }
                    }
                }
                if let synced = source.lastSyncedAt {
                    HairDivider()
                    infoRow(model.t("Last sync")) {
                        Text(synced.formatted(.dateTime.month().day().hour().minute().locale(model.locale)))
                            .font(.system(size: 12))
                            .foregroundStyle(theme.text2)
                    }
                }
            }
        }
    }

    private func infoRow(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.text)
            Spacer(minLength: 0)
            value()
        }
        .padding(.vertical, 9)
    }

    // MARK: - 아래

    private func actionsCard(_ source: LinkedSource) -> some View {
        LinkCard {
            VStack(spacing: 0) {
                actionRow(model.t("Sync now"), color: theme.link, disabled: model.linkStatus[source.id] == .syncing) {
                    Task { await model.syncSource(id: source.id) }
                }
                HairDivider().padding(.horizontal, 12)
                actionRow(model.t("Disconnect…"), color: theme.redText) {
                    disconnectTarget = source
                }
            }
        }
        .padding(.top, 14)
    }

    private func actionRow(_ title: String, color: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

/// 보유 한 줄 — 이름·평가액, 그 아래 수량과 비중 막대.
private struct HoldingShareRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let asset: Asset
    let quantity: Decimal
    let share: Decimal

    var body: some View {
        Button {
            model.push(.detail(asset.id))
        } label: {
            HStack(spacing: 10) {
                AssetLogoView(asset: asset, size: 26)
                VStack(spacing: 3) {
                    HStack {
                        Text(asset.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(valueText)
                            .font(.system(size: 12.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.text)
                            .privacyBlur(model.settings.privacyMode)
                    }
                    HStack(spacing: 8) {
                        Text("\(asset.shortQuantity(quantity)) \(asset.symbol)")
                            .lineLimit(1)
                            .privacyBlur(model.settings.privacyMode)
                        Spacer(minLength: 0)
                        Capsule()
                            .fill(theme.seg)
                            .frame(width: 56, height: 4)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(theme.link)
                                    .frame(width: max(2, 56 * fraction), height: 4)
                            }
                        Text(shareText)
                            .frame(width: 28, alignment: .trailing)
                    }
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(theme.text2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var fraction: CGFloat {
        CGFloat(min(1, max(0, share)).doubleValue)
    }

    private var shareText: String {
        guard share > 0 else { return "—" }
        return share < 0.01 ? "<1%" : "\(Int(share.doubleValue * 100 + 0.5))%"
    }

    private var valueText: String {
        guard let quote = model.quotes[asset.id] else { return "—" }
        return MoneyFormatter.price(quote.price * quantity, currency: quote.currency)
    }
}
