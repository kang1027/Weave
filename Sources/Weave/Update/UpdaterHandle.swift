import Foundation
import Sparkle

/// Sparkle 2 래퍼 — `.app` 번들 + `SUFeedURL`이 있을 때만 실제 업데이터 활성.
/// `swift run` 개발 실행에서는 조용히 비활성.
@MainActor
final class UpdaterHandle: NSObject, ObservableObject {
    @Published var availableVersion: String?

    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        guard
            Bundle.main.bundlePath.hasSuffix(".app"),
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        else {
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    var isAvailable: Bool { controller != nil }

    var automaticallyChecksForUpdates: Bool {
        controller?.updater.automaticallyChecksForUpdates ?? false
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}

extension UpdaterHandle: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.availableVersion = version
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.availableVersion = nil
        }
    }
}
