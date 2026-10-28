import AppKit
import WeaveCore

/// 원격 자산 로고(크립토 아이콘·주식 로고) 메모리 캐시 — 디스크 캐시와 다운로드는 LogoService가 맡는다.
/// 홈 리스트·상세·차트 마커·메뉴바 배지가 같은 이미지를 공유한다.
@MainActor
final class RemoteLogoCache {
    static let shared = RemoteLogoCache()

    private let service: LogoService
    private var images: [String: NSImage] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    /// 실패 시각 — 화면이 다시 그려질 때마다 재요청하지 않도록 잠깐 쉬었다가 다시 시도.
    private var failedAt: [String: Date] = [:]
    private let retryAfter: TimeInterval = 300

    init(service: LogoService? = nil) {
        let cacheDir = (try? CandleService.liveCacheDirectory())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("WeaveCache")
        self.service = service ?? LogoService(http: URLSessionHTTPClient(), cacheDirectory: cacheDir)
    }

    /// 이미 받아 둔 로고 — 첫 프레임부터 이니셜 배지 깜빡임 없이 그리기 위한 동기 조회.
    func cachedImage(for asset: Asset) -> NSImage? {
        guard let source = AssetLogoSource(asset: asset) else { return nil }
        return images[source.key]
    }

    func image(for asset: Asset) async -> NSImage? {
        guard let source = AssetLogoSource(asset: asset) else { return nil }
        let key = source.key
        if let cached = images[key] { return cached }
        if let failed = failedAt[key], Date().timeIntervalSince(failed) < retryAfter { return nil }

        let task: Task<Data?, Never>
        if let running = inFlight[key] {
            task = running
        } else {
            let service = self.service
            task = Task { await service.logoData(for: source) }
            inFlight[key] = task
        }
        let data = await task.value
        inFlight[key] = nil

        if let cached = images[key] { return cached }
        // SVG(네이버 주식 로고)는 NSImage가 벡터 그대로 읽는다. 못 읽으면 이니셜 배지로 남는다.
        guard let data, let image = NSImage(data: data) else {
            failedAt[key] = Date()
            return nil
        }
        images[key] = image
        failedAt[key] = nil
        return image
    }
}
