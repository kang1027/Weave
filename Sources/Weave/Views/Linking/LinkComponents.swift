import AppKit
import SwiftUI
import WeaveCore

// 연결 화면들이 같이 쓰는 부품 — 로고, 버튼, 섹션 라벨, 태그, 상태 점, 로고 묶음, IP 상자.

/// 연결 종류 로고 — 토스는 흰 원 위 로고, 비트코인은 주황 원, EVM은 지갑 아이콘에 ETH 배지.
struct SourceLogo: View {
    @Environment(\.theme) private var theme
    let kind: LinkedSourceKind?
    let size: CGFloat

    private static let tossImage: NSImage? = L10n.resourceBundle
        .url(forResource: "toss-securities", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        if kind == .toss, let image = Self.tossImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size * 0.62, height: size * 0.62)
                .frame(width: size, height: size)
                .background(Circle().fill(.white))
        } else if kind == .bitcoinWallet {
            CoinIcon(symbol: "btc", size: size)
        } else if kind == .evmWallet {
            symbolCircle("wallet.pass")
                .overlay(alignment: .bottomTrailing) {
                    CoinIcon(symbol: "eth", size: size * 0.44)
                        .background(Circle().fill(theme.panel).padding(-1.5))
                        .offset(x: 2, y: 2)
                }
        } else {
            symbolCircle(kind == nil ? "pencil" : "building.columns")
        }
    }

    private func symbolCircle(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(theme.text2)
            .frame(width: size, height: size)
            .background(Circle().fill(theme.iconBg))
    }
}

/// 코인 아이콘(원격 아이콘셋) — 아직 없으면 회색 원.
struct CoinIcon: View {
    @Environment(\.theme) private var theme
    let symbol: String
    let size: CGFloat
    @State private var loaded = false

    private var source: AssetLogoSource? { AssetLogoSource(market: .crypto, symbol: symbol) }

    var body: some View {
        let _ = loaded
        Group {
            if let source, let image = RemoteLogoCache.shared.cachedImage(for: source) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Circle().fill(theme.iconBg)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: symbol) {
            guard let source, RemoteLogoCache.shared.cachedImage(for: source) == nil else { return }
            if await RemoteLogoCache.shared.image(for: source) != nil { loaded = true }
        }
    }
}

/// 연결에 든 자산 로고 몇 개를 겹쳐 보인다.
struct AssetLogoStack: View {
    @Environment(\.theme) private var theme
    let assets: [Asset]
    var limit = 3
    var size: CGFloat = 16

    var body: some View {
        HStack(spacing: -size * 0.25) {
            ForEach(assets.prefix(limit), id: \.id) { asset in
                AssetLogoView(asset: asset, size: size)
                    .background(Circle().fill(theme.panel).padding(-1.5))
            }
        }
    }
}

/// 대문자 섹션 라벨.
struct CapsLabel: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .textCase(.uppercase)
            .foregroundStyle(theme.caps)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 짧은 속성 태그 — "API key", "Address only".
struct LinkTag: View {
    @Environment(\.theme) private var theme
    enum Style { case neutral, green, orange, blue }
    let text: String
    var style: Style = .neutral

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(background))
    }

    private var foreground: Color {
        switch style {
        case .neutral: return theme.badgeGrayText
        case .green: return theme.greenText
        case .orange: return theme.orange
        case .blue: return theme.link
        }
    }

    private var background: Color {
        switch style {
        case .neutral: return theme.badgeGray
        case .green: return theme.green.opacity(0.14)
        case .orange: return theme.orange.opacity(0.16)
        case .blue: return theme.link.opacity(0.18)
        }
    }
}

struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 6, height: 6)
    }
}

/// 카드 — 패널 배경, 둥근 모서리. 행 사이 구분선은 안에서 긋는다.
struct LinkCard<Content: View>: View {
    @Environment(\.theme) private var theme
    var padding = EdgeInsets()
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.panelStroke, lineWidth: 1))
            .padding(.horizontal, 14)
    }
}

struct HairDivider: View {
    @Environment(\.theme) private var theme
    var inset: CGFloat = 0
    var body: some View {
        Rectangle().fill(theme.hair).frame(height: 1).padding(.leading, inset)
    }
}

struct LinkPrimaryButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var disabled = false
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(title)
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(theme.link))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(disabled || isLoading)
        .opacity(disabled ? 0.45 : 1)
    }
}

struct LinkSecondaryButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var disabled = false
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isDestructive ? theme.redText : theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isDestructive ? theme.red.opacity(0.12) : theme.seg)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

/// 바닥 한 줄 안내 — 자물쇠 + 문구.
struct LinkFootnote: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(theme.greenText)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 키체인 허용 창을 기다릴 때 그 자리에 붙이는 안내 — 화면을 덮지 않는다.
struct KeychainHint: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "key.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.orange)
                .padding(.top, 1)
            Text(model.t("Click Always Allow in the macOS keychain prompt. It may be on another display."))
                .font(.system(size: 10.5))
                .foregroundStyle(theme.badgeGrayText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 공인 IP와 복사 버튼 — 토스 허용 IP 등록용.
struct PublicIPBox: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let ip: String?
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(model.t("This IP"))
                .font(.system(size: 10.5))
                .foregroundStyle(theme.text2)
            Group {
                if let ip {
                    Text(ip).textSelection(.enabled)
                } else {
                    Text(isLoading ? model.t("Checking…") : model.t("Unavailable"))
                        .foregroundStyle(theme.text2)
                }
            }
            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            LinkSecondaryButton(title: model.t("Copy"), disabled: ip == nil) {
                guard let ip else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ip, forType: .string)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.bg))
    }
}

/// "1 coin" / "5 coins" — 앱이 영어 전용이라 복수형을 직접 붙인다.
func counted(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
    "\(count) " + (count == 1 ? singular : plural ?? singular + "s")
}

/// 상대 시각 — 1분 안이면 "Just now".
@MainActor
func relativeSyncText(_ date: Date, now: Date, model: AppModel) -> String {
    guard now.timeIntervalSince(date) >= 60 else { return model.t("Just now") }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = model.locale
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: now)
}
