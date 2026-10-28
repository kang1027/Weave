import Foundation

/// 원격 로고 파일 캐시 — `cache/logos/` 아래 키별 파일로 한 번만 받는다.
/// 후보 주소가 전부 404면 "없음"으로 기록해 한동안 다시 묻지 않는다(이니셜 배지 유지).
/// 네트워크 오류나 이미지가 아닌 응답은 기록하지 않아 다음 요청 때 다시 시도한다.
public actor LogoService {
    private let http: any HTTPClient
    private let directory: URL
    private let missRetryInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var misses: [String: Date] = [:]
    private var loadedMisses = false
    private var inflight: [String: Task<Data?, Never>] = [:]

    public init(
        http: any HTTPClient,
        cacheDirectory: URL,
        missRetryInterval: TimeInterval = 7 * 24 * 3600,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.http = http
        self.directory = cacheDirectory.appendingPathComponent("logos", isDirectory: true)
        self.missRetryInterval = missRetryInterval
        self.now = now
    }

    public func logoData(for source: AssetLogoSource) async -> Data? {
        if let data = try? Data(contentsOf: fileURL(key: source.key)) {
            return data
        }
        loadMissesIfNeeded()
        if let missedAt = misses[source.key], now().timeIntervalSince(missedAt) < missRetryInterval {
            return nil
        }
        if let running = inflight[source.key] {
            return await running.value
        }

        let task = Task { await self.fetch(source) }
        inflight[source.key] = task
        let data = await task.value
        inflight[source.key] = nil
        return data
    }

    public func clearCache() {
        misses = [:]
        loadedMisses = false
        try? FileManager.default.removeItem(at: directory)
    }

    /// 받아 둔 파일을 앱이 이미지로 못 읽었을 때 지운다 — 다음 요청에서 다시 받는다.
    public func discard(_ source: AssetLogoSource) {
        try? FileManager.default.removeItem(at: fileURL(key: source.key))
    }

    private func fetch(_ source: AssetLogoSource) async -> Data? {
        var allMissing = true
        for url in source.candidates {
            do {
                let data = try await http.get(url)
                guard Self.isImage(data) else {
                    allMissing = false
                    continue
                }
                save(data, key: source.key)
                if misses.removeValue(forKey: source.key) != nil { saveMisses() }
                return data
            } catch HTTPError.badStatus(404) {
                continue
            } catch {
                allMissing = false
            }
        }
        if allMissing {
            misses[source.key] = now()
            saveMisses()
        }
        return nil
    }

    /// 캡티브 포털 HTML 같은 응답을 로고로 캐시하지 않도록 PNG·JPEG·SVG만 받는다.
    static func isImage(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(4))
        if bytes == [0x89, 0x50, 0x4E, 0x47] { return true }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true }
        // 512바이트 컷이 멀티바이트 문자 중간에 걸려도 판별되게 손실 허용 디코딩.
        return String(decoding: data.prefix(512), as: UTF8.self).contains("<svg")
    }

    // MARK: - 디스크 캐시

    private func fileURL(key: String) -> URL {
        directory.appendingPathComponent("\(key).img")
    }

    private var missesURL: URL {
        directory.appendingPathComponent("misses.json")
    }

    private func save(_ data: Data, key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(key: key), options: .atomic)
    }

    private func loadMissesIfNeeded() {
        guard !loadedMisses else { return }
        loadedMisses = true
        guard let data = try? Data(contentsOf: missesURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let disk = try? decoder.decode([String: Date].self, from: data) {
            misses.merge(disk) { memory, _ in memory }
        }
    }

    private func saveMisses() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(misses) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: missesURL, options: .atomic)
    }
}
