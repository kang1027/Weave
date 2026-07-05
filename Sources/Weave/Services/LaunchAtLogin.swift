import Foundation
import ServiceManagement

/// 로그인 시 자동 시작 — `SMAppService`. 앱 번들로 실행 중일 때만 동작한다.
enum LaunchAtLogin {
    /// `swift run` 개발 실행에서는 등록 불가.
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func set(enabled: Bool) -> Bool {
        guard isSupported else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
