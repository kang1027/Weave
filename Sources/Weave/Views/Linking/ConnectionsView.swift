import SwiftUI
import WeaveCore

/// 설정 › 연결한 계좌 — 연결 목록, 동기화 상태, 해제.
struct ConnectionsView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    @State private var disconnectTarget: LinkedSource?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Linked accounts"), onBack: { model.pop() }) {
                IconButton(systemName: "plus") { model.push(.addToss) }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    LinkNotice(
                        systemName: "lock.fill",
                        text: model.t("Keys stay in this Mac's keychain. Weave only reads holdings and order history, never places orders.")
                    )

                    if model.document.sources.isEmpty {
                        emptyState
                    } else {
                        PanelCard(padding: EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12)) {
                            VStack(spacing: 0) {
                                ForEach(Array(model.document.sources.enumerated()), id: \.element.id) { index, source in
                                    if index > 0 {
                                        Rectangle().fill(theme.hair).frame(height: 1)
                                    }
                                    SourceRow(source: source) { disconnectTarget = source }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
        }
        .confirmDialog(
            $disconnectTarget,
            title: { _ in model.t("Disconnect account?") },
            message: { model.disconnectMessage($0) },
            confirmTitle: model.t("Disconnect"),
            isDestructive: true,
            cancelTitle: model.t("Cancel"),
            onConfirm: { model.disconnectSource(id: $0.id) }
        )
    }

    private var emptyState: some View {
        PanelCard {
            VStack(spacing: 10) {
                Text(model.t("Link a broker account to bring in holdings and trades automatically."))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                LinkPrimaryButton(title: model.t("Link Toss Securities")) {
                    model.push(.addToss)
                }
            }
        }
    }
}

private struct SourceRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let source: LinkedSource
    let onDisconnect: () -> Void
    @State private var publicIP: String?
    @State private var isCheckingIP = false

    private var status: LinkStatus? { model.linkStatus[source.id] }
    private var isSyncing: Bool { status == .syncing }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SourceLogo(kind: source.kind, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text(summary)
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(theme.text2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    statusLabel
                    if let synced = source.lastSyncedAt {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(relative(synced, now: context.date))
                                .font(.system(size: 10))
                                .foregroundStyle(theme.text2)
                        }
                    }
                }
            }

            if case .failed(let failure) = status {
                failureView(failure)
            }

            if let skipped = model.linkSkippedTrades[source.id] {
                Text(model.t("\(skipped) trade(s) weren't imported because Weave is at its asset limit."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.pendingImports[source.id] != nil {
                LinkPrimaryButton(title: model.t("Review import")) {
                    model.push(.importReview(source.id))
                }
            } else if let mismatches = model.linkMismatches[source.id], !mismatches.isEmpty {
                Button {
                    model.push(.importReview(source.id))
                } label: {
                    Text(model.t("\(mismatches.count) to review"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.orange)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                LinkSecondaryButton(title: model.t("Sync now"), disabled: isSyncing) {
                    Task { await model.syncSource(id: source.id) }
                }
                LinkSecondaryButton(title: model.t("Disconnect…"), isDestructive: true, action: onDisconnect)
            }
        }
        .padding(.vertical, 10)
    }

    private var summary: String {
        [
            source.label,
            model.t("\(model.heldAssetCount(sourceID: source.id)) holding(s)"),
            model.t("\(model.importedTradeCount(sourceID: source.id)) trade(s)")
        ].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .syncing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(model.t("Syncing…"))
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(theme.text2)
        case .failed:
            Text(model.t("● Failed"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.redText)
        case .synced, nil:
            if model.pendingImports[source.id] != nil {
                Text(model.t("● Waiting for review"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.orange)
            } else if source.lastSyncedAt != nil {
                Text(model.t("● Linked"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.greenText)
            }
        }
    }

    private func failureView(_ failure: LinkFailure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.linkFailureText(failure))
                .font(.system(size: 10.5))
                .foregroundStyle(theme.redText)
                .fixedSize(horizontal: false, vertical: true)
            if failure == .ipNotAllowed {
                PublicIPButton(publicIP: $publicIP, isChecking: $isCheckingIP)
            }
        }
    }

    private func relative(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return model.t("Just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = model.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - 연결 화면 공용

/// 연결 종류 로고 — 증권사 로고가 있으면 흰 원 위에, 없으면 SF Symbol.
struct SourceLogo: View {
    @Environment(\.theme) private var theme
    let kind: LinkedSourceKind?
    let size: CGFloat

    private static let tossImage: NSImage? = L10n.resourceBundle
        .url(forResource: "toss-securities", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        if kind == .toss, let image = Self.tossImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size * 0.62, height: size * 0.62)
                .frame(width: size, height: size)
                .background(Circle().fill(.white))
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(theme.text2)
                .frame(width: size, height: size)
                .background(Circle().fill(theme.iconBg))
        }
    }

    private var symbol: String {
        switch kind {
        case .koreaInvestment, .toss: return "building.columns"
        case .bitcoinWallet, .evmWallet: return "wallet.pass"
        case nil: return "pencil"
        }
    }
}

struct LinkNotice: View {
    @Environment(\.theme) private var theme
    let systemName: String
    let text: String
    var tint: Color?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint ?? theme.greenText)
                .frame(width: 14)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill((tint ?? theme.green).opacity(0.10)))
    }
}

struct LinkPrimaryButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var disabled = false
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(title)
            }
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.link))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled || isLoading)
        .opacity(disabled ? 0.45 : 1)
    }
}

struct LinkSecondaryButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var disabled = false
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isDestructive ? theme.redText : theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isDestructive ? theme.red.opacity(0.12) : theme.seg)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

/// 허용 IP에 넣을 공인 IP를 보여 준다 — 누를 때만 조회한다.
struct PublicIPButton: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    @Binding var publicIP: String?
    @Binding var isChecking: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let publicIP {
                Text(model.t("This network's IP: \(publicIP)"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                    .textSelection(.enabled)
                LinkSecondaryButton(title: model.t("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(publicIP, forType: .string)
                }
            } else {
                LinkSecondaryButton(title: model.t("Check this network's IP"), disabled: isChecking) {
                    isChecking = true
                    Task {
                        publicIP = await model.currentPublicIP()
                        isChecking = false
                    }
                }
            }
        }
    }
}
