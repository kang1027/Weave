import Foundation

public protocol PortfolioStore: Sendable {
    func load() throws -> PortfolioDocument
    func save(_ document: PortfolioDocument) throws
}

public struct JSONPortfolioStore: PortfolioStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/Weave/portfolio.json`
    public static func live() throws -> JSONPortfolioStore {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(WeaveInfo.appName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return JSONPortfolioStore(fileURL: dir.appendingPathComponent("portfolio.json"))
    }

    public func load() throws -> PortfolioDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let migrated = try PortfolioMigrator.migrate(data)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PortfolioDocument.self, from: migrated)
        } catch {
            // 읽지 못한 문서를 이후 persist()가 빈 문서로 덮어쓰지 않게
            // 원본을 백업으로 보존한 뒤 실패를 전파한다.
            backUpUnreadableFile()
            throw error
        }
    }

    private func backUpUnreadableFile() {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("portfolio-unreadable-\(stamp).json")
        try? FileManager.default.copyItem(at: fileURL, to: backupURL)
    }

    public func save(_ document: PortfolioDocument) throws {
        var doc = document
        doc.version = PortfolioDocument.currentVersion
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(doc)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

/// 스키마 버전 마이그레이션 체인. 버전이 오르면 단계를 추가한다.
public enum PortfolioMigrator {
    public static func migrate(_ data: Data) throws -> Data {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = object["version"] as? Int
        else {
            throw MigrationError.unreadable
        }
        guard version <= PortfolioDocument.currentVersion else {
            throw MigrationError.newerThanApp(version)
        }
        // version 1이 최초 스키마 — 아직 마이그레이션 단계 없음.
        return data
    }

    public enum MigrationError: Error, Equatable {
        case unreadable
        case newerThanApp(Int)
    }
}
