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
        if env["WEAVE_OPEN_POPOVER"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                HotkeyManager.toggleMenuBarWindow()
            }
        }
        // 개발용: 시드 상태를 자체 렌더해 PNG로 저장하고 종료(화면 녹화 권한 불필요).
        // menubar 상태는 상태바 아이템 창을, 그 외는 팝오버 창을 캡처한다.
        if let shotPath = env["WEAVE_SHOT"] {
            // 라벨 이름색(labelColor)이 어두운 배경에서도 보이도록 다크 외관 고정.
            NSApp.appearance = NSAppearance(named: .darkAqua)
            let state = env["WEAVE_SHOT_STATE"] ?? "home-combined"
            let delay = Double(env["WEAVE_SHOT_DELAY"] ?? "") ?? 12
            // 팝오버를 열어야 RootView가 떠서 시세·메뉴바 라벨 생성(백그라운드 작업)이 시작된다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSApp.activate(ignoringOtherApps: true)
                HotkeyManager.toggleMenuBarWindow()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + delay) {
                if state == "menubar" {
                    Self.writeMenuBarMockup(to: shotPath)
                } else {
                    Self.capturePopover(to: shotPath, attempt: 0)
                }
            }
        }
    }

    /// 팝오버 창을 캡처. 아직 안 열렸으면 다시 열고 재시도(최대 5회) — 첫 클릭이 씹히는 것 방어.
    @MainActor
    static func capturePopover(to path: String, attempt: Int) {
        if writeWindow(matching: "MenuBarExtra", to: path) {
            NSApp.terminate(nil)
            return
        }
        guard attempt < 5 else { NSApp.terminate(nil); return }
        NSApp.activate(ignoringOtherApps: true)
        HotkeyManager.toggleMenuBarWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            capturePopover(to: path, attempt: attempt + 1)
        }
    }

    /// 메뉴바 라벨(model.menuBarImage)을 어두운 메뉴바 스트립(+시계) 위에 얹어 PNG로 저장.
    @MainActor
    static func writeMenuBarMockup(to path: String) {
        defer { NSApp.terminate(nil) }
        guard let label = AppModel.shared?.menuBarImage else { return }
        let scale: CGFloat = 2
        let barH: CGFloat = 30
        let padX: CGFloat = 18
        let gap: CGFloat = 22
        let clock = NSAttributedString(
            string: "9:41",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )
        let clockSize = clock.size()
        let labelSize = label.size
        let width = padX + ceil(labelSize.width) + gap + ceil(clockSize.width) + padX
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * scale), pixelsHigh: Int(barH * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = NSSize(width: width, height: barH)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: barH), xRadius: 9, yRadius: 9).fill()
        label.draw(
            at: NSPoint(x: padX, y: (barH - labelSize.height) / 2),
            from: .zero, operation: .sourceOver, fraction: 1
        )
        clock.draw(at: NSPoint(x: width - padX - ceil(clockSize.width), y: (barH - clockSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// className에 cls가 들어가는 첫 가시 창의 contentView를 PNG로 저장. 성공 시 true.
    @MainActor
    @discardableResult
    static func writeWindow(matching cls: String, to path: String) -> Bool {
        guard
            let window = NSApp.windows.first(where: {
                $0.isVisible && $0.contentView != nil && $0.className.contains(cls)
            }),
            let view = window.contentView,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            return false
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }
}
