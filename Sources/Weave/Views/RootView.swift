import SwiftUI
import WeaveCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var systemScheme

    private var theme: Theme {
        model.theme(systemScheme: systemScheme)
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            content
                .overlay(alignment: .top) {
                    if model.isAwaitingKeychain {
                        KeychainNotice()
                            .padding(.top, 52)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: model.isAwaitingKeychain)

            // 전역 ⌘Q — 설정에 버튼을 두지 않아도 어디서든 종료되게 숨겨둔다.
            Button(action: model.quit) { EmptyView() }
                .keyboardShortcut("q", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .environment(\.theme, theme)
        .environment(\.locale, model.locale)
        .preferredColorScheme(model.settings.theme == .system ? nil : theme.colorScheme)
        .task {
            model.startBackgroundWork()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.currentRoute {
        case .manage:
            ManageView()
        case .detail(let assetID):
            AssetDetailView(assetID: assetID)
        case .settings:
            SettingsView()
        case .tradeForm(let assetID, let editing, let prefill):
            TradeFormView(assetID: assetID, editing: editing, prefill: prefill)
        case .manualAssetForm:
            ManualAssetForm()
        case .connections:
            ConnectionsView()
        case .addToss:
            AddTossView()
        case .importReview(let sourceID):
            ImportReviewView(sourceID: sourceID)
        case .addSource:
            AddSourceView()
        case .addWallet(let kind):
            AddWalletView(kind: kind)
        case .sourceDetail(let sourceID):
            SourceDetailView(sourceID: sourceID)
        case nil:
            if model.document.assets.isEmpty {
                OnboardingView()
            } else {
                HomeView()
            }
        }
    }
}

/// 키체인 허용 창을 기다리는 동안 — 창이 다른 창 뒤에 숨어도 무엇을 기다리는지 보이게.
private struct KeychainNotice: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.orange)
                .padding(.top, 1)
            Text(model.t("Waiting for keychain access. Click Always Allow in the keychain prompt."))
                .font(.system(size: 11))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.tooltipBg))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.orange.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, 14)
    }
}
