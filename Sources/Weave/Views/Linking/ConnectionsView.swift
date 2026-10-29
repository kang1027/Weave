import SwiftUI
import WeaveCore

/// 설정 › 계좌·지갑 — 합계와 동기화, 종류별 연결 목록, 행마다 그 연결의 상태와 할 일.
struct ConnectionsView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    private var brokers: [LinkedSource] { model.document.sources.filter { !$0.kind.isWallet } }
    private var wallets: [LinkedSource] { model.document.sources.filter(\.kind.isWallet) }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Accounts & wallets"), onBack: { model.pop() }) {
                IconButton(systemName: "plus") { model.push(.addSource) }
            }

            ScrollView {
                VStack(spacing: 0) {
                    if model.document.sources.isEmpty {
                        emptyState
                    } else {
                        summary
                        if !brokers.isEmpty {
                            CapsLabel(text: model.t("Brokers"))
                            sourceList(brokers)
                        }
                        if !wallets.isEmpty {
                            CapsLabel(text: model.t("Crypto wallets"))
                            sourceList(wallets)
                        }
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 12)
            }

            LinkFootnote(text: model.t("Keys and addresses stay in this Mac's keychain. Read-only: no orders, no transfers."))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .overlay(alignment: .top) { HairDivider() }
        }
    }

    private var summary: some View {
        LinkCard(padding: EdgeInsets(top: 13, leading: 14, bottom: 12, trailing: 14)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.t("Linked holdings"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.text2)
                HStack(alignment: .firstTextBaseline) {
                    Text(MoneyFormatter.price(model.linkedTotal, currency: model.settings.baseCurrency))
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .privacyBlur(model.settings.privacyMode)
                    Spacer()
                    Button(model.t("Sync all")) {
                        Task { await model.syncAllSources() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.link)
                }
                HStack(spacing: 6) {
                    StatusDot(color: summaryColor)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(summaryLine(now: context.date))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.text2)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func summaryLine(now: Date) -> String {
        let count = counted(model.document.sources.count, "link")
        guard let latest = model.latestLinkSync else { return count }
        let synced = model.t("synced \(relativeSyncText(latest, now: now, model: model).lowercased())")
        return [count, synced, model.t("every \(model.linkSyncMinutes) min")].joined(separator: " · ")
    }

    /// 하나라도 멈췄으면 빨강, 검토할 게 있으면 주황.
    private var summaryColor: Color {
        let ids = model.document.sources.map(\.id)
        if ids.contains(where: { if case .failed = model.linkStatus[$0] { return true } else { return false } }) {
            return theme.red
        }
        if ids.contains(where: { model.pendingImports[$0] != nil || !(model.linkMismatches[$0] ?? []).isEmpty }) {
            return theme.orange
        }
        return theme.green
    }

    private func sourceList(_ sources: [LinkedSource]) -> some View {
        LinkCard {
            VStack(spacing: 0) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    if index > 0 { HairDivider(inset: 57) }
                    SourceRow(source: source)
                }
            }
        }
    }

    private var emptyState: some View {
        LinkCard(padding: EdgeInsets(top: 16, leading: 14, bottom: 14, trailing: 14)) {
            VStack(spacing: 12) {
                Text(model.t("Link a broker account or a crypto wallet to bring in holdings automatically."))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                LinkPrimaryButton(title: model.t("Add a link")) {
                    model.push(.addSource)
                }
            }
        }
    }
}

/// 연결 한 줄 — 로고 · 이름 · 보유 로고와 수 · 평가액 · 상태. 할 일이 있으면 그 아래에 붙는다.
private struct SourceRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let source: LinkedSource
    @State private var publicIP: String?
    @State private var isCheckingIP = false

    private var status: LinkStatus? { model.linkStatus[source.id] }
    private var holdings: [(asset: Asset, quantity: Decimal)] { model.holdings(sourceID: source.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                model.push(.sourceDetail(source.id))
            } label: {
                HStack(spacing: 11) {
                    SourceLogo(kind: source.kind, size: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        // 좁으면 로고를 먼저 빼고, 그래도 안 되면 주소를 뺀다.
                        ViewThatFits(in: .horizontal) {
                            subtitleRow(showsLogos: true, text: subtitle)
                            subtitleRow(showsLogos: false, text: subtitle)
                            subtitleRow(showsLogos: true, text: countText)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(valueText)
                            .fixedSize()
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(isSyncing ? theme.text2 : theme.text)
                            .privacyBlur(model.settings.privacyMode)
                        statusLabel
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            actions
                .padding(.leading, 45)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var isSyncing: Bool { status == .syncing }

    private var countText: String {
        counted(holdings.count, source.kind.isWallet ? "coin" : "holding")
    }

    private var subtitle: String {
        [countText, source.label].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func subtitleRow(showsLogos: Bool, text: String) -> some View {
        HStack(spacing: 6) {
            if showsLogos, !holdings.isEmpty {
                AssetLogoStack(assets: holdings.map(\.asset))
            }
            Text(text)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(theme.text2)
                .lineLimit(1)
        }
    }

    private var valueText: String {
        let value = model.sourceValue(sourceID: source.id)
        return value > 0 ? MoneyFormatter.price(value, currency: model.settings.baseCurrency) : "—"
    }

    @ViewBuilder
    private var statusLabel: some View {
        HStack(spacing: 5) {
            switch status {
            case .syncing where model.isAwaitingKeychain:
                Image(systemName: "key.fill").font(.system(size: 9, weight: .semibold))
                Text(model.t("Waiting"))
            case .syncing:
                ProgressView().controlSize(.mini)
                Text(model.t("Syncing"))
            case .failed:
                StatusDot(color: theme.red)
                Text(model.t("Paused"))
            default:
                if model.pendingImports[source.id] != nil {
                    StatusDot(color: theme.orange)
                    Text(model.t("Review"))
                } else if let mismatches = model.linkMismatches[source.id], !mismatches.isEmpty {
                    StatusDot(color: theme.orange)
                    Text(model.t("\(mismatches.count) to review"))
                } else if let synced = source.lastSyncedAt {
                    StatusDot(color: theme.green)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(relativeSyncText(synced, now: context.date, model: model))
                    }
                }
            }
        }
        .font(.system(size: 10.5, weight: statusIsWarning ? .semibold : .regular))
        .foregroundStyle(statusColor)
    }

    private var statusIsWarning: Bool {
        if case .failed = status { return true }
        if status == .syncing { return model.isAwaitingKeychain }
        return model.pendingImports[source.id] != nil || !(model.linkMismatches[source.id] ?? []).isEmpty
    }

    private var statusColor: Color {
        if case .failed = status { return theme.redText }
        return statusIsWarning ? theme.orange : theme.text2
    }

    /// 그 연결에서 지금 할 일 — 검토, 키체인 허용, IP 등록, 확인 필요.
    @ViewBuilder
    private var actions: some View {
        if status == .syncing, model.isAwaitingKeychain {
            KeychainHint()
        } else if case .failed(let failure) = status {
            failureActions(failure)
        } else if let pending = model.pendingImports[source.id] {
            let count = Set(pending.plan.trades.filter { !$0.isManualSide }.map(\.instrument)).count
            actionLink("Review " + counted(count, source.kind.isWallet ? "coin" : "holding") + " to import", tint: theme.link) {
                model.push(.importReview(source.id))
            }
        } else if let mismatch = model.linkMismatches[source.id]?.first {
            actionLink("\(mismatch.instrument.name) · \(model.mismatchShortText(mismatch))", tint: theme.orange) {
                model.push(.importReview(source.id))
            }
        }
        if let skipped = model.linkSkippedTrades[source.id] {
            Text(counted(skipped, "trade") + (skipped == 1 ? " wasn't" : " weren't") + " imported because Weave is at its asset limit.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionLink(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.14)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func failureActions(_ failure: LinkFailure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.linkFailureText(failure))
                .font(.system(size: 10.5))
                .foregroundStyle(theme.badgeGrayText)
                .fixedSize(horizontal: false, vertical: true)
            if failure == .ipNotAllowed {
                PublicIPBox(ip: publicIP, isLoading: isCheckingIP)
                    .task {
                        guard publicIP == nil else { return }
                        isCheckingIP = true
                        publicIP = await model.currentPublicIP()
                        isCheckingIP = false
                    }
                Button(model.t("How to allow ↗")) { model.openTossDocs() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.link)
            }
        }
    }
}
