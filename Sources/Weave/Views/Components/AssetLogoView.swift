import SwiftUI
import WeaveCore

/// 자산 로고 — 크립토는 아이콘 CDN, 주식은 네이버 증권 로고, 그 외/실패 시 자산색 이니셜 배지 폴백.
/// 두 로고 소스가 모두 원형이라 커스텀 로고·이니셜 배지도 원형으로 맞춘다.
struct AssetLogoView: View {
    @Environment(\.theme) private var theme
    let asset: Asset
    var size: CGFloat = 28
    @State private var remoteLogo: NSImage?

    var body: some View {
        Group {
            if let fileName = asset.customLogoFileName,
               let custom = LogoStore.image(named: fileName) {
                // 사용자 업로드 로고 우선.
                Image(nsImage: custom)
                    .resizable()
                    .scaledToFill()
            } else if let remote = remoteLogo ?? RemoteLogoCache.shared.cachedImage(for: asset) {
                Image(nsImage: remote)
                    .resizable()
                    .scaledToFit()
            } else {
                initialBadge
            }
        }
        .frame(width: size, height: size)
        .background(color.opacity(0.15))
        .clipShape(Circle())
        .task(id: logoTaskID) {
            remoteLogo = nil
            guard asset.customLogoFileName == nil else { return }
            remoteLogo = await RemoteLogoCache.shared.image(for: asset)
        }
    }

    /// 자산이 바뀌거나 커스텀 로고가 지워지면 원격 로고를 다시 찾는다.
    private var logoTaskID: String {
        "\(AssetLogoSource(asset: asset)?.key ?? "")|\(asset.customLogoFileName ?? "")"
    }

    private var color: Color {
        theme.paletteColor(asset.colorIndex)
    }

    private var initialBadge: some View {
        Text(String(asset.name.prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
    }
}

/// 검색 결과 마켓 뱃지 — 크립토/국장/미장/일장/기타.
struct MarketBadgeChip: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let market: Market

    var body: some View {
        Text(label)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.15)))
    }

    private var label: String {
        switch market {
        case .crypto: return model.t("Crypto")
        case .koreaStock: return model.t("KR")
        case .usStock: return model.t("US")
        case .japanStock: return model.t("JP")
        case .other: return model.t("Other")
        }
    }

    private var color: Color {
        switch market {
        case .crypto: return theme.orange
        case .koreaStock: return theme.blue
        case .usStock: return theme.indigo
        case .japanStock: return theme.red
        case .other: return theme.assetGray
        }
    }
}
