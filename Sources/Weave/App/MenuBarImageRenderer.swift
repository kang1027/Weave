import AppKit
import WeaveCore

/// 메뉴바 라벨을 NSImage로 렌더 — MenuBarExtra의 Text 라벨은 색을 무시(단색)하고
/// 2줄 표현도 안 되기 때문. 비-template 이미지라 색이 그대로 유지된다.
/// 이름은 labelColor(시스템 외관 추종), 가격·등락%는 등락 색.
@MainActor
enum MenuBarImageRenderer {
    private static let up = hex(0x32D74B)
    private static let down = hex(0xFF453A)
    /// 상태바 항목 최대 폭 — 넘치면 그리기 캔버스에서 클립(비정상 긴 이름 방어).
    private static let maxWidth: CGFloat = 300
    /// 자산 팔레트(슬레이트) — 로고 없는 배지 색.
    private static let palette: [NSColor] = [
        hex(0xFF9F0A), hex(0x0A84FF), hex(0x8583FF), hex(0xFF375F),
        hex(0x64D2FF), hex(0xBF5AF2), hex(0xFFD60A), hex(0x66D4CF)
    ]

    /// - logo: 앱이 해석한 배지 로고(커스텀/크립토 CDN). nil이면 이니셜 폴백.
    static func image(_ parts: MenuBarTitleBuilder.MenuBarParts, logo: NSImage?) -> NSImage {
        let change = parts.isUp ? up : down
        if let line2 = parts.line2 {
            return renderStacked(
                top: attributed(parts.line1, change: change, size: 9),
                bottom: attributed(line2, change: change, size: 9),
                badge: parts.badge, logo: logo
            )
        }
        return renderInline(attributed(parts.line1, change: change, size: 13), badge: parts.badge, logo: logo)
    }

    // MARK: - 한 줄 텍스트 구성

    private static func attributed(
        _ line: MenuBarTitleBuilder.Line,
        change: NSColor,
        size: CGFloat
    ) -> NSAttributedString {
        let textFont = NSFont.monospacedDigitSystemFont(ofSize: size, weight: size < 11 ? .semibold : .medium)
        let percentFont = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
        let result = NSMutableAttributedString()
        if !line.text.isEmpty {
            result.append(NSAttributedString(
                string: line.text,
                attributes: [.font: textFont, .foregroundColor: line.textColored ? change : NSColor.labelColor]
            ))
        }
        if let percent = line.percent {
            result.append(NSAttributedString(
                string: percent,
                attributes: [.font: percentFont, .foregroundColor: change]
            ))
        }
        return result
    }

    // MARK: - 합성

    /// 1줄: [배지] 텍스트.
    private static func renderInline(
        _ text: NSAttributedString,
        badge: MenuBarTitleBuilder.Badge?,
        logo: NSImage?
    ) -> NSImage {
        let ts = text.size()
        let badgeSize: CGFloat = badge != nil ? 14 : 0
        let gap: CGFloat = badge != nil ? 4 : 0
        // 비정상적으로 긴 이름/총액이 상태바를 밀지 않게 상한(넘치면 그리기 캔버스에서 클립).
        let width = min(badgeSize + gap + ceil(ts.width) + 2, maxWidth)
        let height = max(ceil(ts.height), badgeSize)

        return draw(width: width, height: height) {
            if let badge {
                drawBadge(badge, logo: logo, in: NSRect(x: 0, y: (height - badgeSize) / 2, width: badgeSize, height: badgeSize))
            }
            text.draw(at: NSPoint(x: badgeSize + gap, y: (height - ceil(ts.height)) / 2))
        }
    }

    /// 2줄: 상단 [배지] 텍스트 / 하단 텍스트 (좌측 정렬). 배지는 상단 줄 이름 왼쪽에만.
    private static func renderStacked(
        top: NSAttributedString,
        bottom: NSAttributedString,
        badge: MenuBarTitleBuilder.Badge?,
        logo: NSImage?
    ) -> NSImage {
        let ts = top.size()
        let bs = bottom.size()
        let badgeSize: CGFloat = badge != nil ? 13 : 0
        let gap: CGFloat = badge != nil ? 3 : 0
        let topRowHeight = max(ceil(ts.height), badgeSize)
        let bottomRowHeight = ceil(bs.height)
        let height = topRowHeight + bottomRowHeight
        let topContentWidth = badgeSize + gap + ceil(ts.width)
        let width = min(max(topContentWidth, ceil(bs.width)) + 2, maxWidth)

        return draw(width: width, height: height) {
            // 하단(가격 등락%) — 가로 중앙.
            bottom.draw(at: NSPoint(x: (width - ceil(bs.width)) / 2, y: (bottomRowHeight - ceil(bs.height)) / 2))
            // 상단 배지 + 이름 — 한 덩어리로 가로 중앙, 배지는 이름 왼쪽.
            let topStart = (width - topContentWidth) / 2
            if let badge {
                drawBadge(
                    badge, logo: logo,
                    in: NSRect(x: topStart, y: bottomRowHeight + (topRowHeight - badgeSize) / 2, width: badgeSize, height: badgeSize)
                )
            }
            top.draw(at: NSPoint(x: topStart + badgeSize + gap, y: bottomRowHeight + (topRowHeight - ceil(ts.height)) / 2))
        }
    }

    private static func draw(width: CGFloat, height: CGFloat, _ body: () -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: max(width, 1), height: max(height, 1)))
        image.lockFocus()
        body()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawBadge(
        _ badge: MenuBarTitleBuilder.Badge,
        logo: NSImage?,
        in rect: NSRect
    ) {
        let radius = rect.width * 0.29
        let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if let logo {
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            drawAspectFill(logo, in: rect)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            color(for: badge.colorIndex).setFill()
            clip.fill()
            let initial = NSAttributedString(
                string: badge.initial,
                attributes: [
                    .font: NSFont.systemFont(ofSize: rect.width * 0.55, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
            )
            let size = initial.size()
            initial.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
    }

    /// 배지 사각형을 꽉 채우도록 종횡비 유지 스케일(넘치는 부분은 클립됨).
    private static func drawAspectFill(_ image: NSImage, in rect: NSRect) {
        let source = image.size
        guard source.width > 0, source.height > 0 else {
            image.draw(in: rect)
            return
        }
        let scale = max(rect.width / source.width, rect.height / source.height)
        let scaled = NSSize(width: source.width * scale, height: source.height * scale)
        image.draw(
            in: NSRect(
                x: rect.midX - scaled.width / 2, y: rect.midY - scaled.height / 2,
                width: scaled.width, height: scaled.height
            ),
            from: .zero, operation: .sourceOver, fraction: 1
        )
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
