import AppKit
import Foundation
import UniformTypeIdentifiers
import WeaveCore

extension AppModel {
    // MARK: - 설정 변경 부수효과

    func setRotationSeconds(_ seconds: Int) {
        settings.rotationSeconds = seconds
        rotationIndex = 0
        restartRotationLoop()
    }

    func setQuoteRefreshSeconds(_ seconds: Int) {
        settings.quoteRefreshSeconds = seconds
        restartRefreshLoop()
    }

    func setBaseCurrency(_ currency: String) {
        settings.baseCurrency = currency
        invalidateHomeChart()
        Task {
            await refreshFXRates()
            updateMenuBarTitle()
            await loadHomeChart()
        }
    }

    func setHotkey(_ hotkey: Hotkey?) {
        settings.hotkey = hotkey
        applyHotkey()
    }

    func setSwitchAssetHotkey(_ hotkey: Hotkey?) {
        settings.switchAssetHotkey = hotkey
        applyHotkey()
    }

    func applyHotkey() {
        HotkeyManager.shared.register(.togglePopover, hotkey: settings.hotkey) {
            HotkeyManager.toggleMenuBarWindow()
        }
        HotkeyManager.shared.register(.switchAsset, hotkey: settings.switchAssetHotkey) { [weak self] in
            self?.advanceMenuBarAsset()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if LaunchAtLogin.set(enabled: enabled) {
            settings.launchAtLogin = enabled
        } else {
            // 등록 실패(개발 실행 등) — 저장값 원복.
            settings.launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    // MARK: - 데이터 백업 / 복원

    func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "weave-backup.json"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try data.write(to: url, options: .atomic)
        } catch {
            presentAlert(
                title: t("Backup failed"),
                message: error.localizedDescription
            )
        }
    }

    func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let migrated = try PortfolioMigrator.migrate(data)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let restored = try decoder.decode(PortfolioDocument.self, from: migrated)
            // 되돌릴 수 없는 전체 교체 — 확인받는다.
            let confirm = NSAlert()
            confirm.messageText = t("Replace all data?")
            confirm.informativeText = t("This replaces your current data with the imported file. This can't be undone.")
            confirm.alertStyle = .warning
            confirm.addButton(withTitle: t("Replace"))
            confirm.addButton(withTitle: t("Cancel"))
            NSApp.activate(ignoringOtherApps: true)
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
            document = restored
            persist()
            invalidateHomeChart()
            quotes = [:]
            // 복원된 설정(주기·로테이션·단축키)을 즉시 반영.
            applyHotkey()
            restartRefreshLoop()
            restartRotationLoop()
            Task {
                await loadHomeChart()
            }
        } catch {
            presentAlert(
                title: t("Restore failed"),
                message: t("The file is not a valid Weave backup.")
            )
        }
    }

    func clearCandleCache() {
        Task {
            await candleService.clearCache()
            invalidateHomeChart()
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - 종료

    func quit() {
        NSApp.terminate(nil)
    }
}
