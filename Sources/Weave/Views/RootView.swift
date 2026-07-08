import AppKit
import SwiftUI
import WeaveCore

/// 팝오버가 열릴 때 앱을 활성화하고 창을 key로 만든다.
/// MenuBarExtra 창은 기본적으로 키 포커스를 안 가져 키보드 단축키(⌘R 등)가 안 먹는데,
/// 이렇게 하면 키 이벤트가 앱으로 들어와 로컬 모니터/단축키가 동작한다.
private struct PopoverKeyActivator: NSViewRepresentable {
    final class KeyView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !window.isKeyWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
        }
    }
    func makeNSView(context: Context) -> NSView { KeyView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window, !window.isKeyWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
    }
}

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

            PopoverKeyActivator().frame(width: 0, height: 0)

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
        case nil:
            if model.document.assets.isEmpty {
                OnboardingView()
            } else {
                HomeView()
            }
        }
    }
}
