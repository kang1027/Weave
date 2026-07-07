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
    /// 세그먼트가 아닌 링 내부(중앙/트랙) 호버 시 보여줄 툴팁(예: 총 손익).
    var centerTooltip: String? = nil
    /// 지정하면 내장 툴팁 대신 부모가 툴팁을 그린다(가장자리 클리핑 회피용).
    /// 세그먼트 위면 그 세그먼트 툴팁, 그 외 링 내부면 centerTooltip을 전달한다.
    var onHoverTooltip: ((String?) -> Void)? = nil

    @State private var hoveredID: String?
    @State private var reportedTooltip: String?

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
                            lineWidth: hoveredID == item.segment.id ? hoverLineWidth : lineWidth,
                            lineCap: .butt
                        )
                    )
                    // 오버플로우 바퀴(lap>0)는 점점 밝게 — "계속 차오르는" 느낌.
                    .brightness(min(Double(item.lap) * 0.22, 0.66))
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
            let newID: String?
            let tooltip: String?
            switch phase {
            case .active(let point):
                newID = segmentID(at: point)
                // 세그먼트 위면 그 툴팁, 아니면(중앙/트랙) centerTooltip.
                tooltip = newID.flatMap { id in segments.first { $0.id == id }?.tooltip }
                    ?? centerTooltip
            case .ended:
                newID = nil
                tooltip = nil
            }
            if newID != hoveredID { hoveredID = newID }
            if tooltip != reportedTooltip {
                reportedTooltip = tooltip
                onHoverTooltip?(tooltip)
            }
        }
        // 링 행이 스크롤 콘텐츠 최상단이라 위로 띄우면 잘린다 — 아래로 표시.
        // (부모가 툴팁을 그리는 경우엔 생략)
        .overlay(alignment: .bottom) {
            if onHoverTooltip == nil,
               let hoveredID,
               let segment = segments.first(where: { $0.id == hoveredID }) {
                TooltipBubble(text: segment.tooltip)
                    .offset(y: 32)
                    .allowsHitTesting(false)
                    .zIndex(10)
            }
        }
        // 툴팁이 이웃 링/아래 형제 뷰에 가려지지 않게 hover 중엔 위로.
        .zIndex(hoveredID != nil ? 50 : 0)
    }

    private struct Positioned: Identifiable {
        let segment: Segment
        let start: Double   // 바퀴 안에서의 0...1 위치
        let end: Double
        let lap: Int
        let index: Int
        var id: String { "\(segment.id)-\(index)" }
    }

    /// 세그먼트들을 누적하며 바퀴(lap) 경계에서 쪼갠다. 채움 합이 1을 넘으면
    /// 넘친 만큼 다음 바퀴 arc로 이어 그린다(뒤 항목=상위 바퀴가 위에 그려짐).
    private var positioned: [Positioned] {
        var result: [Positioned] = []
        var cursor = 0.0
        var index = 0
        for segment in segments where segment.fraction > 0 {
            var remaining = segment.fraction
            while remaining > 1e-9 {
                let lap = Int(cursor + 1e-9)
                let withinStart = cursor - Double(lap)
                let take = min(remaining, 1.0 - withinStart)
                result.append(Positioned(
                    segment: segment,
                    start: withinStart,
                    end: withinStart + take,
                    lap: lap,
                    index: index
                ))
                index += 1
                cursor += take
                remaining -= take
            }
        }
        return result
    }

    /// hover 지점 → 링 밴드 위 각도 → 세그먼트(그 각도에서 가장 위 바퀴).
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
        // 여러 바퀴가 겹치면 마지막(상위 바퀴) arc가 이긴다.
        var found: String?
        for item in positioned where fraction >= item.start && fraction < item.end {
            found = item.segment.id
        }
        return found
    }
}

/// 목업 `.tt` — 툴팁 말풍선.
struct TooltipBubble: View {
    @Environment(\.theme) private var theme
    let text: String
    var secondary: String?
    /// 프라이버시 모드에서 본문(금액)만 블러.
    var blurText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.text)
                .privacyBlur(blurText)
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
