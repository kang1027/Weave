import AppKit
import WeaveCore

/// 메뉴바 배지용 자산 로고 해석 — 커스텀 업로드 로고(동기) 또는 원격 로고(크립토 아이콘·주식 로고, 비동기 캐시).
/// 원격 로고는 처음엔 nil을 주고 백그라운드로 받은 뒤 onLoad로 재렌더를 요청한다.
@MainActor
final class MenuBarLogoProvider {
    static let shared = MenuBarLogoProvider()

    /// 지금 그릴 수 있는 로고. 없으면 nil(배지는 이니셜 폴백), 원격 로고면 백그라운드 로드 후 onLoad.
    func image(for asset: Asset, onLoad: @escaping () -> Void) -> NSImage? {
        // 1) 사용자 업로드 커스텀 로고 우선.
        if let fileName = asset.customLogoFileName, let custom = LogoStore.image(named: fileName) {
            return custom
        }
        // 2) 원격 로고 — 중복 요청·실패 쿨다운은 RemoteLogoCache가 막는다.
        if let cached = RemoteLogoCache.shared.cachedImage(for: asset) { return cached }
        guard AssetLogoSource(asset: asset) != nil else { return nil }
        Task {
            if await RemoteLogoCache.shared.image(for: asset) != nil { onLoad() }
        }
        return nil
    }
}
