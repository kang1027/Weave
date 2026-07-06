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
        case nil:
            if model.document.assets.isEmpty {
                OnboardingView()
            } else {
                HomeView()
            }
        }
    }
}
