import SwiftUI

/// 아이템을 가로로 채우다 폭을 넘으면 다음 줄로 넘기는 flow 레이아웃(범례 등).
/// 각 줄은 alignment대로 정렬. 아이템은 자기 고유 크기(`.fixedSize()`)로 배치한다.
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    var rowSpacing: CGFloat = 5
    var alignment: HorizontalAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let contentWidth = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(0, rows.count - 1))
        let width = maxWidth == .greatestFiniteMagnitude ? contentWidth : maxWidth
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x: CGFloat
            if alignment == .center {
                x = bounds.minX + (bounds.width - row.width) / 2
            } else if alignment == .trailing {
                x = bounds.maxX - row.width
            } else {
                x = bounds.minX
            }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && projected > maxWidth {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
                current.indices.append(index)
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
