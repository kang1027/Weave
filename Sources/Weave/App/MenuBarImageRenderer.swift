import AppKit
import WeaveCore

/// 메뉴바 라벨을 NSImage로 렌더 — MenuBarExtra의 Text 라벨은 색을 무시(단색 강제)하고
/// 2줄 표현도 안 되기 때문. 비-template 이미지라 색이 그대로 유지된다.
/// (앞부분은 labelColor로 시스템 외관을 따르고, 등락%만 초록/빨강.)
enum MenuBarImageRenderer {
    private static let up = NSColor(srgbRed: 0x32 / 255, green: 0xD7 / 255, blue: 0x4B / 255, alpha: 1)
    private static let down = NSColor(srgbRed: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)

    static func image(_ parts: MenuBarTitleBuilder.MenuBarParts) -> NSImage {
        let change = parts.isUp ? up : down
        let attributed = parts.stacked
            ? stacked(parts.leading, percent: parts.percent, change: change)
            : single(parts.leading, percent: parts.percent, change: change)
        return render(attributed)
    }

    private static func single(_ leading: String, percent: String?, change: NSColor) -> NSAttributedString {
        let base = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let result = NSMutableAttributedString(
            string: leading,
            attributes: [.font: base, .foregroundColor: NSColor.labelColor]
        )
        if let percent {
            result.append(NSAttributedString(string: " ", attributes: [.font: base]))
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

    private static func stacked(_ line1: String, percent: String?, change: NSColor) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.maximumLineHeight = 10
        para.minimumLineHeight = 10
        let result = NSMutableAttributedString(
            string: line1,
            attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para
            ]
        )
        if let percent {
            result.append(NSAttributedString(
                string: "\n" + percent,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: change,
                    .paragraphStyle: para
                ]
            ))
        }
        return result
    }

    private static func render(_ attributed: NSAttributedString) -> NSImage {
        let bounds = attributed.boundingRect(
            with: NSSize(width: 500, height: 100),
            options: [.usesLineFragmentOrigin]
        )
        let size = NSSize(width: ceil(bounds.width) + 2, height: ceil(bounds.height))
        let image = NSImage(size: size)
        image.lockFocus()
        attributed.draw(
            with: NSRect(origin: .zero, size: size),
            options: [.usesLineFragmentOrigin]
        )
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
