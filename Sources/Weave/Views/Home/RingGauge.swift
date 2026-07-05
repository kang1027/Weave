import SwiftUI

/// 세그먼트 링 게이지 (`.gauge`). 12시 시작, 시계방향, 갭 없는 butt cap.
/// hover 시 해당 세그먼트가 굵어지고 툴팁 표시.
struct RingGauge: View {
    struct Segment: Identifiable, Equatable {
        let id: String
        /// 원 전체 대비 비율 0...1 — 스케일 적용 후 값.
        let fraction: Double
        let color: Color
        let tooltip: String
    }

    @Environment(\.theme) private var theme
    let segments: [Segment]
    let size: CGFloat
    let centerText: String
    let centerColor: Color?
    let caption: String

    @State private var hoveredID: String?

    /// 목업 기준: viewBox 100에서 r=42, stroke 8(hover 11).
    private var radius: CGFloat { size * 0.42 }
    private var lineWidth: CGFloat { size * 0.08 }
    private var hoverLineWidth: CGFloat { size * 0.11 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.track, lineWidth: lineWidth)
                .frame(width: radius * 2, height: radius * 2)

            ForEach(positioned) { item in
                Circle()
                    .trim(from: item.start, to: item.end)
                    .stroke(
                        item.segment.color,
                        style: StrokeStyle(
                            lineWidth: hoveredID == item.id ? hoverLineWidth : lineWidth,
                            lineCap: .butt
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: radius * 2, height: radius * 2)
                    .animation(.easeOut(duration: 0.15), value: hoveredID)
            }

            VStack(spacing: 1) {
                Text(centerText)
                    .font(.system(size: size >= 90 ? 17 : 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(centerColor ?? theme.text)
                Text(caption.uppercased())
                    .font(.system(size: 8, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(theme.caps)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hoveredID = segmentID(at: point)
            case .ended:
                hoveredID = nil
            }
        }
        // 링 행이 스크롤 콘텐츠 최상단이라 위로 띄우면 잘린다 — 아래로 표시.
        .overlay(alignment: .bottom) {
            if let hoveredID,
               let segment = segments.first(where: { $0.id == hoveredID }) {
                TooltipBubble(text: segment.tooltip)
                    .offset(y: 32)
                    .allowsHitTesting(false)
                    .zIndex(10)
            }
        }
    }

    private struct Positioned: Identifiable {
        let segment: Segment
        let start: Double
        let end: Double
        var id: String { segment.id }
    }

    private var positioned: [Positioned] {
        var cursor = 0.0
        return segments.map { segment in
            let item = Positioned(segment: segment, start: cursor, end: min(cursor + segment.fraction, 1))
            cursor += segment.fraction
            return item
        }
    }

    /// hover 지점 → 링 밴드 위 각도 → 세그먼트.
    private func segmentID(at point: CGPoint) -> String? {
        let center = CGPoint(x: size / 2, y: size / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        // 히트 밴드 = 실제 스트로크 반폭 + 약간의 여유.
        guard abs(distance - radius) <= hoverLineWidth / 2 + 2 else { return nil }
        // 12시 기준 시계방향 각도 비율.
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        let fraction = angle / (2 * .pi)
        var cursor = 0.0
        for segment in segments {
            if fraction >= cursor && fraction < cursor + segment.fraction {
                return segment.id
            }
            cursor += segment.fraction
        }
        return nil
    }
}

/// 목업 `.tt` — 툴팁 말풍선.
struct TooltipBubble: View {
    @Environment(\.theme) private var theme
    let text: String
    var secondary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.text)
            if let secondary {
                Text(secondary)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.text2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.tooltipBg)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.tooltipBorder, lineWidth: 1)
        )
        .fixedSize()
    }
}
