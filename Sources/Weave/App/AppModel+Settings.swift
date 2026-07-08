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

    /// `.weave` 번들(zip) = `portfolio.json` + `logos/`(참조된 커스텀 로고).
    private var backupType: UTType {
        UTType("app.weave.backup") ?? UTType(filenameExtension: "weave") ?? .data
    }

    func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [backupType]
        panel.nameFieldStringValue = "weave-backup.weave"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("weave-export-\(UUID().uuidString)", isDirectory: true)
        let tmpZip = fm.temporaryDirectory.appendingPathComponent("weave-export-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: stage); try? fm.removeItem(at: tmpZip) }
        do {
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: stage.appendingPathComponent("portfolio.json"), options: .atomic)

            // 자산이 참조하는 커스텀 로고 PNG만 번들에 담는다.
            let logoNames = document.assets.compactMap(\.customLogoFileName)
            if !logoNames.isEmpty {
                let logosDir = stage.appendingPathComponent("logos", isDirectory: true)
                try fm.createDirectory(at: logosDir, withIntermediateDirectories: true)
                for name in logoNames {
                    let src = LogoStore.url(for: name)
                    guard fm.fileExists(atPath: src.path) else { continue }
                    try? fm.copyItem(at: src, to: logosDir.appendingPathComponent(name))
                }
            }

            try BackupArchive.zip(contentsOf: stage, to: tmpZip)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            try fm.moveItem(at: tmpZip, to: url)
        } catch {
            presentAlert(title: t("Backup failed"), message: error.localizedDescription)
        }
    }

    func importBackup() {
        let panel = NSOpenPanel()
        // 신규 `.weave` 번들 + 구버전 순수 `.json` 백업 모두 허용.
        panel.allowedContentTypes = [backupType, .json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let fm = FileManager.default
        let extractDir = fm.temporaryDirectory.appendingPathComponent("weave-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: extractDir) }
        do {
            let documentData: Data
            var extractedLogosDir: URL?
            if url.pathExtension.lowercased() == "json" {
                // 구버전: 순수 JSON(로고 없음).
                documentData = try Data(contentsOf: url)
            } else {
                // `.weave` 번들: 추출 → portfolio.json (+ logos/).
                try BackupArchive.unzip(url, to: extractDir)
                documentData = try Data(contentsOf: extractDir.appendingPathComponent("portfolio.json"))
                let logos = extractDir.appendingPathComponent("logos", isDirectory: true)
                if fm.fileExists(atPath: logos.path) { extractedLogosDir = logos }
            }

            let migrated = try PortfolioMigrator.migrate(documentData)
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

            // 번들이면 커스텀 로고를 LogoStore 디렉토리에 병합(같은 이름 덮어쓰기).
            if let extractedLogosDir {
                try fm.createDirectory(at: LogoStore.directory, withIntermediateDirectories: true)
                let files = (try? fm.contentsOfDirectory(at: extractedLogosDir, includingPropertiesForKeys: nil)) ?? []
                for file in files where file.pathExtension.lowercased() == "png" {
                    let dest = LogoStore.url(for: file.lastPathComponent)
                    try? fm.removeItem(at: dest)
                    try? fm.copyItem(at: file, to: dest)
                }
            }

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
