import SwiftUI

extension Color {
    /// `0xRRGGBB` 정수와 불투명도로 색을 만든다. 목업 CSS 변수 이식용.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
