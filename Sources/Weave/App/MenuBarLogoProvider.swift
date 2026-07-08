import AppKit
import WeaveCore

/// 메뉴바 배지용 자산 로고 해석 — 커스텀 업로드 로고(동기) 또는 크립토 CDN 로고(비동기 캐시).
/// CDN 로고는 처음엔 nil을 주고 백그라운드로 받아 캐시한 뒤 onLoad로 재렌더를 요청한다.
@MainActor
final class MenuBarLogoProvider {
    static let shared = MenuBarLogoProvider()

    private var cache: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    /// 실패 시각 — 영구 블랙리스트 대신 쿨다운 후 재시도(일시적 네트워크 오류 복구).
    private var failedAt: [String: Date] = [:]
    private let retryAfter: TimeInterval = 300

    /// 지금 그릴 수 있는 로고. 없으면 nil(배지는 이니셜 폴백), CDN이면 백그라운드 로드 후 onLoad.
    func image(for asset: Asset, onLoad: @escaping () -> Void) -> NSImage? {
        // 1) 사용자 업로드 커스텀 로고 우선.
        if let fileName = asset.customLogoFileName, let custom = LogoStore.image(named: fileName) {
            return custom
        }
        // 2) 크립토 CDN 로고(처음부터 딸려오는 로고).
        guard let url = AssetLogoView.logoURL(for: asset) else { return nil }
        let key = url.absoluteString
        if let cached = cache[key] { return cached }
        guard !inFlight.contains(key) else { return nil }
        // 최근 실패는 쿨다운 동안만 건너뛴다(영구 차단 X).
        if let failed = failedAt[key], Date().timeIntervalSince(failed) < retryAfter { return nil }

        inFlight.insert(key)
        Task { [weak self] in
            let image = await Self.download(url)
            self?.finish(key: key, image: image, onLoad: onLoad)
        }
        return nil
    }

    private func finish(key: String, image: NSImage?, onLoad: () -> Void) {
        inFlight.remove(key)
        if let image {
            cache[key] = image
            failedAt[key] = nil
            onLoad()
        } else {
            failedAt[key] = Date()
        }
    }

    private static func download(_ url: URL) async -> NSImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }
}
