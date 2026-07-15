import SwiftUI

/// 헤더용 26×26 아이콘 버튼 (`.ib`).
struct IconButton: View {
    @Environment(\.theme) private var theme
    let systemName: String
    var isActive = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? theme.link : theme.text2)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isActive ? theme.link.opacity(0.18) : theme.iconBg)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

/// 등락 솔리드 배지 (`.bdg`).
struct ChangeBadge: View {
    @Environment(\.theme) private var theme

    enum Style {
        case up, down, gray
    }

    let text: String
    let style: Style
    var minWidth: CGFloat = 70

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(style == .gray ? theme.badgeGrayText : .white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .frame(minWidth: minWidth)
            .background(RoundedRectangle(cornerRadius: 6).fill(background))
    }

    private var background: Color {
        switch style {
        case .up: return theme.green
        case .down: return theme.red
        case .gray: return theme.badgeGray
        }
    }
}

/// 섹션 캡션 — 양옆 헤어라인 (`.cap`).
struct CapsHeader: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(theme.hair).frame(height: 1)
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.3)
                .foregroundStyle(theme.caps)
                .fixedSize()
            Rectangle().fill(theme.hair).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

/// 세그먼트 컨트롤 (`.tseg`). `fillsWidth`면 균등 분할, 아니면 mini 스타일.
struct SegmentedPills<T: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var fillsWidth = true
    var isDisabled = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Text(option.label)
                    .font(.system(size: fillsWidth ? 11 : 10, weight: .semibold))
                    .foregroundStyle(isOn ? theme.text : theme.text2)
                    .padding(.vertical, fillsWidth ? 4.5 : 3)
                    .padding(.horizontal, fillsWidth ? 0 : 12)
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isOn ? theme.segOn : .clear)
                            .shadow(
                                color: .black.opacity(isOn ? theme.segOnShadow : 0),
                                radius: 1, y: 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture {
                        guard !isDisabled else { return }
                        selection = option.value
                    }
            }
        }
        .opacity(isDisabled ? 0.55 : 1)
    }
}

/// 목업 `.sw` — 34×20 미니 스위치.
struct MiniToggle: View {
    @Environment(\.theme) private var theme
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? theme.green : theme.seg)
            Circle()
                .fill(.white)
                .frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                .padding(2)
        }
        .frame(width: 34, height: 20)
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        }
    }
}

/// 프라이버시 모드 금액 가리기 — 목업(blur 5px)처럼 강한 블러.
/// 문자열 조립이 필요한 곳(메뉴바 등)은 `MoneyFormatter.masked`를 계속 쓴다.
extension View {
    func privacyBlur(_ enabled: Bool) -> some View {
        blur(radius: enabled ? 6.5 : 0)
            .allowsHitTesting(!enabled)
    }
}

/// hover 시 배경 하이라이트 (`.click`).
struct HoverHighlight: ViewModifier {
    @Environment(\.theme) private var theme
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(hovering ? theme.hover : .clear)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}

/// 패널 카드 (`.panel` / `.scard`).
struct PanelCard<Content: View>: View {
    @Environment(\.theme) private var theme
    var padding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12)
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.panel)
                    .shadow(color: .black.opacity(theme.panelShadowOpacity), radius: 1.5, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(theme.panelStroke, lineWidth: 1)
            )
    }
}
