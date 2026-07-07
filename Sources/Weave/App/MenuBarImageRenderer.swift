import AppKit
import WeaveCore

/// 메뉴바 라벨을 NSImage로 렌더 — MenuBarExtra의 Text 라벨은 색을 무시(단색)하고
/// 2줄 표현도 안 되기 때문. 비-template 이미지라 색이 그대로 유지된다.
/// 앞부분은 labelColor(시스템 외관 추종), 등락%만 초록/빨강.
enum MenuBarImageRenderer {
    private static let up = hex(0x32D74B)
    private static let down = hex(0xFF453A)
    /// 자산 팔레트(슬레이트) — inline 배지 색.
    private static let palette: [NSColor] = [
        hex(0xFF9F0A), hex(0x0A84FF), hex(0x8583FF), hex(0xFF375F),
        hex(0x64D2FF), hex(0xBF5AF2), hex(0xFFD60A), hex(0x66D4CF)
    ]

    static func image(_ parts: MenuBarTitleBuilder.MenuBarParts) -> NSImage {
        let change = parts.isUp ? up : down
        if let line2 = parts.line2 {
            return render(twoLine(parts.line1, line2, change: change), badge: nil)
        }
        return render(oneLine(parts.line1, change: change), badge: parts.badge)
    }

    // MARK: - 텍스트 구성

    private static func oneLine(_ line: MenuBarTitleBuilder.Line, change: NSColor) -> NSAttributedString {
        let base = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let result = NSMutableAttributedString(
            string: line.text,
            attributes: [.font: base, .foregroundColor: NSColor.labelColor]
        )
        if let percent = line.percent {
            result.append(NSAttributedString(
                string: percent,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: change
                ]
            ))
        }
        return result
    }

    private static func twoLine(
        _ line1: MenuBarTitleBuilder.Line,
        _ line2: MenuBarTitleBuilder.Line,
        change: NSColor
    ) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.maximumLineHeight = 10
        para.minimumLineHeight = 10
        let text = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let percentFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)

        let result = NSMutableAttributedString()
        append(line1, to: result, textFont: text, percentFont: percentFont, change: change, para: para)
        result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: para]))
        append(line2, to: result, textFont: text, percentFont: percentFont, change: change, para: para)
        return result
    }

    private static func append(
        _ line: MenuBarTitleBuilder.Line,
        to result: NSMutableAttributedString,
        textFont: NSFont,
        percentFont: NSFont,
        change: NSColor,
        para: NSParagraphStyle
    ) {
        if !line.text.isEmpty {
            result.append(NSAttributedString(
                string: line.text,
                attributes: [.font: textFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
            ))
        }
        if let percent = line.percent {
            result.append(NSAttributedString(
                string: percent,
                attributes: [.font: percentFont, .foregroundColor: change, .paragraphStyle: para]
            ))
        }
    }

    // MARK: - 이미지 합성

    private static func render(_ attributed: NSAttributedString, badge: MenuBarTitleBuilder.Badge?) -> NSImage {
        let textBounds = attributed.boundingRect(
            with: NSSize(width: 500, height: 100),
            options: [.usesLineFragmentOrigin]
        )
        let textWidth = ceil(textBounds.width)
        let textHeight = ceil(textBounds.height)
        let badgeSize: CGFloat = badge != nil ? 13 : 0
        let gap: CGFloat = badge != nil ? 4 : 0
        let width = badgeSize + gap + textWidth + 2
        let height = max(textHeight, badgeSize)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        if let badge {
            let rect = NSRect(x: 0, y: (height - badgeSize) / 2, width: badgeSize, height: badgeSize)
            color(for: badge.colorIndex).setFill()
            NSBezierPath(ovalIn: rect).fill()
            let initial = NSAttributedString(
                string: badge.initial,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 7.5, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
            )
            let size = initial.size()
            initial.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }

        attributed.draw(
            with: NSRect(x: badgeSize + gap, y: (height - textHeight) / 2, width: textWidth, height: textHeight),
            options: [.usesLineFragmentOrigin]
        )

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func color(for colorIndex: Int) -> NSColor {
        palette[((colorIndex % palette.count) + palette.count) % palette.count]
    }

    private static func hex(_ value: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
