import SwiftUI
import WeaveCore

@main
struct WeaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.live()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environmentObject(model)
                .frame(width: 360, height: 720)
        } label: {
            if let image = model.menuBarImage {
                Image(nsImage: image)
                    .accessibilityLabel(Text(model.menuBarTitle))
            } else {
                Text(model.menuBarTitle)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 메뉴바 전용 앱 — Dock 아이콘을 숨긴다. (dev 실행에서도 동일하게 동작)
        NSApp.setActivationPolicy(.accessory)

        // 개발용: 스크린샷 자동화를 위해 실행 직후 팝오버를 연다.
        if ProcessInfo.processInfo.environment["WEAVE_OPEN_POPOVER"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                HotkeyManager.toggleMenuBarWindow()
            }
        }
    }
}
