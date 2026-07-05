import SwiftUI

/// `design/mockups-v5.html`의 CSS 변수를 그대로 이식한 시맨틱 토큰.
/// 색은 반드시 이 토큰을 통해서만 사용한다.
struct Theme: Equatable {
    let bg: Color
    let panel: Color
    let panelStroke: Color
    let panelShadowOpacity: Double
    let text: Color
    let text2: Color
    let caps: Color
    let hair: Color
    let iconBg: Color
    let track: Color
    let grid: Color
    let refLine: Color
    let xLabel: Color
    let seg: Color
    let segOn: Color
    let segOnShadow: Double
    let tooltipBg: Color
    let tooltipBorder: Color
    let pointBg: Color
    let hover: Color
    let guide: Color
    let green: Color
    let greenText: Color
    let red: Color
    let redText: Color
    let orange: Color
    let blue: Color
    let indigo: Color
    let assetGray: Color
    let badgeGray: Color
    let badgeGrayText: Color
    let link: Color
    /// 자산색 8색 팔레트 — 추가 순서대로 자동 할당.
    let palette: [Color]
    let colorScheme: ColorScheme

    static let slate = Theme(
        bg: Color(hex: 0x2B2D35),
        panel: Color(hex: 0x383A43),
        panelStroke: Color(hex: 0xFFFFFF, opacity: 0.04),
        panelShadowOpacity: 0,
        text: Color(hex: 0xFFFFFF),
        text2: Color(hex: 0x9A9DA8),
        caps: Color(hex: 0x8A8D98),
        hair: Color(hex: 0xFFFFFF, opacity: 0.09),
        iconBg: Color(hex: 0xFFFFFF, opacity: 0.08),
        track: Color(hex: 0xFFFFFF, opacity: 0.12),
        grid: Color(hex: 0xFFFFFF, opacity: 0.07),
        refLine: Color(hex: 0xFFFFFF, opacity: 0.32),
        xLabel: Color(hex: 0x7C7F8A),
        seg: Color(hex: 0xFFFFFF, opacity: 0.08),
        segOn: Color(hex: 0x4A4D57),
        segOnShadow: 0,
        tooltipBg: Color(hex: 0x3A3C46),
        tooltipBorder: Color(hex: 0xFFFFFF, opacity: 0.14),
        pointBg: Color(hex: 0x33353E),
        hover: Color(hex: 0xFFFFFF, opacity: 0.05),
        guide: Color(hex: 0xFFFFFF, opacity: 0.25),
        green: Color(hex: 0x32D74B),
        greenText: Color(hex: 0x32D74B),
        red: Color(hex: 0xFF453A),
        redText: Color(hex: 0xFF453A),
        orange: Color(hex: 0xFF9F0A),
        blue: Color(hex: 0x0A84FF),
        indigo: Color(hex: 0x8583FF),
        assetGray: Color(hex: 0x9094A0),
        badgeGray: Color(hex: 0xFFFFFF, opacity: 0.10),
        badgeGrayText: Color(hex: 0xC7CCD6),
        link: Color(hex: 0x0A84FF),
        palette: [
            Color(hex: 0xFF9F0A), // orange
            Color(hex: 0x0A84FF), // blue
            Color(hex: 0x8583FF), // indigo
            Color(hex: 0xFF375F), // pink
            Color(hex: 0x64D2FF), // teal
            Color(hex: 0xBF5AF2), // purple
            Color(hex: 0xFFD60A), // yellow
            Color(hex: 0x66D4CF)  // mint
        ],
        colorScheme: .dark
    )

    static let light = Theme(
        bg: Color(hex: 0xF4F4F6),
        panel: Color(hex: 0xFFFFFF),
        panelStroke: .clear,
        panelShadowOpacity: 0.07,
        text: Color(hex: 0x1D1D1F),
        text2: Color(hex: 0x6E6E73),
        caps: Color(hex: 0x86868B),
        hair: Color(hex: 0x000000, opacity: 0.08),
        iconBg: Color(hex: 0x000000, opacity: 0.05),
        track: Color(hex: 0x000000, opacity: 0.08),
        grid: Color(hex: 0x000000, opacity: 0.07),
        refLine: Color(hex: 0x000000, opacity: 0.32),
        xLabel: Color(hex: 0x9A9AA0),
        seg: Color(hex: 0x000000, opacity: 0.06),
        segOn: Color(hex: 0xFFFFFF),
        segOnShadow: 0.12,
        tooltipBg: Color(hex: 0xFFFFFF),
        tooltipBorder: Color(hex: 0x000000, opacity: 0.10),
        pointBg: Color(hex: 0xFFFFFF),
        hover: Color(hex: 0x000000, opacity: 0.045),
        guide: Color(hex: 0x000000, opacity: 0.28),
        green: Color(hex: 0x34C759),
        greenText: Color(hex: 0x1E9E46),
        red: Color(hex: 0xFF3B30),
        redText: Color(hex: 0xD70015),
        orange: Color(hex: 0xFF9500),
        blue: Color(hex: 0x007AFF),
        indigo: Color(hex: 0x5856D6),
        assetGray: Color(hex: 0xB0B0B6),
        badgeGray: Color(hex: 0x000000, opacity: 0.07),
        badgeGrayText: Color(hex: 0x515154),
        link: Color(hex: 0x007AFF),
        palette: [
            Color(hex: 0xFF9500), // orange
            Color(hex: 0x007AFF), // blue
            Color(hex: 0x5856D6), // indigo
            Color(hex: 0xFF2D55), // pink
            Color(hex: 0x32ADE6), // teal
            Color(hex: 0xAF52DE), // purple
            Color(hex: 0xF5B800), // yellow
            Color(hex: 0x00C7BE)  // mint
        ],
        colorScheme: .light
    )

    func paletteColor(_ index: Int) -> Color {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    func upDown(_ isUp: Bool) -> Color { isUp ? greenText : redText }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.slate
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
