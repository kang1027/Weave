import SwiftUI
import WeaveCore

@main
struct WeaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .frame(width: 360, height: 720)
        } label: {
            Text(WeaveInfo.appName)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 메뉴바 전용 앱 — Dock 아이콘을 숨긴다. (dev 실행에서도 동일하게 동작)
        NSApp.setActivationPolicy(.accessory)
    }
}
