import SwiftUI
import WeaveCore

/// 자산 로고 — 크립토는 아이콘 CDN, 그 외/실패 시 자산색 이니셜 배지 폴백.
struct AssetLogoView: View {
    @Environment(\.theme) private var theme
    let asset: Asset
    var size: CGFloat = 28
    var isCircle = false

    var body: some View {
        Group {
            if let url = Self.logoURL(for: asset) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                            .padding(size * 0.08)
                    } else {
                        initialBadge
                    }
                }
            } else {
                initialBadge
            }
        }
        .frame(width: size, height: size)
        .background(color.opacity(0.15))
        .clipShape(shape)
    }

    private var shape: AnyShape {
        isCircle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: size * 0.29))
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

    static func logoURL(for asset: Asset) -> URL? {
        guard asset.market == .crypto else { return nil }
        let symbol = asset.symbol.lowercased()
        return URL(
            string: "https://cdn.jsdelivr.net/gh/spothq/cryptocurrency-icons@master/128/color/\(symbol).png"
        )
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
