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

        let env = ProcessInfo.processInfo.environment
        // 개발용: 스크린샷 자동화를 위해 실행 직후 팝오버를 연다.
        if env["WEAVE_OPEN_POPOVER"] == "1" || env["WEAVE_SHOT"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                HotkeyManager.toggleMenuBarWindow()
            }
        }
        // 개발용: 팝오버가 열린 뒤 그 창을 자체 렌더해 PNG로 저장하고 종료한다.
        // 자기 뷰를 비트맵으로 캐시하는 방식이라 화면 녹화 권한이 필요 없다.
        if let shotPath = env["WEAVE_SHOT"] {
            let delay = Double(env["WEAVE_SHOT_DELAY"] ?? "") ?? 10
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + delay) {
                Self.capturePopover(to: shotPath)
            }
        }
    }

    /// 현재 열려 있는 팝오버 창의 contentView를 PNG로 캡처한 뒤 앱을 종료한다.
    @MainActor
    static func capturePopover(to path: String) {
        defer { NSApp.terminate(nil) }
        guard
            let window = NSApp.windows.first(where: {
                $0.isVisible && $0.contentView != nil && !$0.className.contains("NSStatusBar")
            }),
            let view = window.contentView,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
