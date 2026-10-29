import SwiftUI
import WeaveCore

/// 상세 "보관 위치" — 같은 자산이 연결한 계좌·지갑과 직접 입력에 얼마씩, 몇 %씩 있는지.
struct HoldingLocationsCard: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let asset: Asset
    let trades: [Trade]

    var body: some View {
        let locations = HoldingLocations.breakdown(trades: trades)
        let total = locations.reduce(Decimal(0)) { $0 + $1.quantity }
        return PanelCard(padding: EdgeInsets(top: 10, leading: 12, bottom: 4, trailing: 12)) {
            VStack(spacing: 0) {
                if locations.count > 1, total > 0 {
                    proportionBar(locations, total: total)
                        .padding(.bottom, 4)
                }
                ForEach(Array(locations.enumerated()), id: \.offset) { index, location in
                    if index > 0 {
                        Rectangle().fill(theme.hair).frame(height: 1)
                    }
                    row(location, share: total > 0 ? location.quantity / total : 0)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private func row(_ location: HoldingLocation, share: Decimal) -> some View {
        let source = location.sourceID.flatMap(model.document.source(id:))
        return HStack(spacing: 10) {
            SourceLogo(kind: source?.kind, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(source?.name ?? model.t(location.sourceID == nil ? "Entered manually" : "Linked account"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text("\(quantityText(location.quantity)) · \(shareText(share))")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(theme.text2)
                    .lineLimit(1)
                    .privacyBlur(model.settings.privacyMode)
            }
            Spacer(minLength: 8)
            Text(valueText(location.quantity))
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .privacyBlur(model.settings.privacyMode)
        }
        .padding(.vertical, 8)
    }

    /// 많이 가진 곳부터 자산색을 점점 옅게.
    private func proportionBar(_ locations: [HoldingLocation], total: Decimal) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(Array(locations.enumerated()), id: \.offset) { index, location in
                    let share = CGFloat((location.quantity / total).doubleValue)
                    Rectangle()
                        .fill(theme.paletteColor(asset.colorIndex).opacity(max(0.3, 1 - Double(index) * 0.3)))
                        .frame(width: max(2, (proxy.size.width - CGFloat(locations.count - 1) * 2) * share))
                }
            }
        }
        .frame(height: 6)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func quantityText(_ quantity: Decimal) -> String {
        let qty = asset.shortQuantity(quantity)
        return asset.hasNumericSymbol ? model.t("\(qty) shares") : "\(qty) \(asset.symbol)"
    }

    private func shareText(_ share: Decimal) -> String {
        guard share > 0 else { return "0%" }
        return share < 0.01 ? "<1%" : "\(Int(share.doubleValue * 100 + 0.5))%"
    }

    private func valueText(_ quantity: Decimal) -> String {
        guard let quote = model.quotes[asset.id] else { return "—" }
        return MoneyFormatter.price(quote.price * quantity, currency: quote.currency)
    }
}
