import Foundation

/// Sparkle 래퍼 자리 — 번들로 실행될 때만 실제 업데이터가 붙는다(M5).
/// `swift run` 개발 실행에서는 조용히 비활성.
@MainActor
final class UpdaterHandle: ObservableObject {
    @Published var availableVersion: String?
    @Published var automaticallyChecksForUpdates = true

    var isAvailable: Bool { false }

    func checkForUpdates() {}

    func setAutomaticChecks(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
    }
}
