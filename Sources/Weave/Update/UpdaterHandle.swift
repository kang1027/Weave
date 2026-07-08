import Foundation
import Sparkle

/// 업데이트 진행 상태 — footer가 이 상태로 인라인 UI를 그린다(Sparkle 표준 팝업 대체).
enum UpdatePhase: Equatable {
    case idle
    case checking
    case available(String)      // 새 버전 발견(버전 문자열)
    case downloading(Double)    // 0...1
    case extracting(Double)     // 0...1
    case readyToInstall(String) // 다운로드 완료 → 재시작하면 설치
    case installing
    case upToDate               // 수동 확인 결과 최신(잠깐 표시)
    case failed                 // 오류(잠깐 표시)
}

/// Sparkle 2 커스텀 user driver — 모든 업데이트 UI를 앱 내부(footer)에서 처리한다.
/// 표준 팝업/창을 띄우지 않고, 발견 → 다운로드% → 재시작 설치를 인라인 버튼으로 노출.
/// `.app` 번들 + `SUFeedURL`이 있을 때만 활성(개발 `swift run`에서는 비활성).
@MainActor
final class UpdaterHandle: NSObject, ObservableObject {
    @Published private(set) var phase: UpdatePhase = .idle

    private var updater: SPUUpdater?
    private var updateFoundReply: ((SPUUserUpdateChoice) -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var pendingVersion = ""
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0
    private var transientToken = 0

    override init() {
        super.init()
        guard
            Bundle.main.bundlePath.hasSuffix(".app"),
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        else {
            return
        }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
        do {
            try updater.start()
            self.updater = updater
        } catch {
            self.updater = nil
        }
    }

    var isAvailable: Bool { updater != nil }

    var automaticallyChecksForUpdates: Bool {
        updater?.automaticallyChecksForUpdates ?? false
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
    }

    // MARK: - footer 버튼 액션

    /// "업데이트" 클릭 → 다운로드 시작(발견 단계의 reply 소비).
    func startDownload() {
        guard let reply = updateFoundReply else { return }
        updateFoundReply = nil
        reply(.install)
    }

    /// "재시작해서 업데이트" 클릭 → 설치 후 재실행.
    func installAndRelaunch() {
        guard let reply = installReply else { return }
        installReply = nil
        reply(.install)
    }

    private func flash(_ phase: UpdatePhase) {
        transientToken += 1
        let token = transientToken
        self.phase = phase
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.transientToken == token { self.phase = .idle }
        }
    }
}

// MARK: - SPUUserDriver (모든 UI를 인라인 상태로 변환)

extension UpdaterHandle: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // 자동 확인 권한은 설정 토글이 관리하므로 기본 허용으로 응답(별도 팝업 없이).
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        phase = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        pendingVersion = appcastItem.displayVersionString
        if state.userInitiated {
            // 사용자가 직접 확인을 눌렀으면 바로 다운로드로 진행.
            reply(.install)
        } else {
            // 자동(스케줄) 발견 → 버튼만 노출하고 사용자 클릭을 기다린다.
            updateFoundReply = reply
            phase = .available(pendingVersion)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error) async {
        flash(.upToDate)
    }

    func showUpdaterError(_ error: Error) async {
        updateFoundReply = nil
        installReply = nil
        flash(.failed)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedLength = 0
        receivedLength = 0
        phase = .downloading(0)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
        receivedLength = 0
        phase = .downloading(0)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        let pct = expectedLength > 0 ? min(1, Double(receivedLength) / Double(expectedLength)) : 0
        phase = .downloading(pct)
    }

    func showDownloadDidStartExtractingUpdate() {
        phase = .extracting(0)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        phase = .extracting(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installReply = reply
        phase = .readyToInstall(pendingVersion)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        phase = .installing
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        phase = .installing
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        updateFoundReply = nil
        installReply = nil
        switch phase {
        case .upToDate, .failed: break  // 잠깐 표시 중인 상태는 유지
        default: phase = .idle
        }
    }
}
