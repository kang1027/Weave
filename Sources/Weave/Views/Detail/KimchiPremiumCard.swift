import SwiftUI
import WeaveCore

/// 김프 카드 갱신 트리거 — 자산이 바뀌거나 시세 폴링이 한 바퀴 돌면 다시 받는다.
private struct KimchiLoadKey: Equatable {
    let assetID: UUID
    let refresh: Date?
}

/// 크립토 상세 김프 카드 — 업비트 원화가 vs 바이낸스 달러가 × 환율, 30일 추이.
/// 값이 오기 전엔 같은 크기의 자리표시 카드로 자리를 잡아 차트가 밀려 내려가지 않게 한다.
/// 업비트 원화 마켓에 없는 코인이면 아무것도 그리지 않는다.
struct KimchiPremiumCard: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let asset: Asset
    @State private var premium: KimchiPremium?
    @State private var reservesSpace: Bool

    init(asset: Asset, initial: KimchiPremium?, reservesSpace: Bool) {
        self.asset = asset
        _premium = State(initialValue: initial)
        _reservesSpace = State(initialValue: reservesSpace)
    }

    /// 자리표시용 — 텍스트는 가려지고 크기만 실제 값과 비슷하게 잡힌다.
    private static let placeholder = KimchiPremium(
        upbitPrice: 100_000_000, binancePrice: 70_000, usdKRW: 1_400,
        history: [KimchiPremiumPoint(date: .distantPast, percent: 0), KimchiPremiumPoint(date: .distantPast, percent: 0)]
    )

    var body: some View {
        // Group이면 비어 있을 때 .task가 붙을 뷰가 없다 — 빈 VStack은 크기 0으로 남아 로드를 시작한다.
        VStack(spacing: 0) {
            if let premium {
                card(premium)
            } else if reservesSpace {
                card(Self.placeholder, isPlaceholder: true)
            }
        }
        // LIVE의 1초 갱신과 묶지 않는다 — 업비트 요청이 초마다 나가지 않게.
        .task(id: KimchiLoadKey(assetID: asset.id, refresh: model.nextRefreshAt)) {
            do {
                premium = try await model.kimchiPremium(for: asset)
                reservesSpace = premium != nil
            } catch {
                // 일시적 오류면 마지막 값(또는 자리표시)을 그대로 둔다.
            }
        }
    }

    private func card(_ premium: KimchiPremium, isPlaceholder: Bool = false) -> some View {
        let tint = isPlaceholder ? theme.track : premium.percent >= 0 ? theme.orange : theme.blue
        return PanelCard(padding: EdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12)) {
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.t("Kimchi premium"))
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(0.8)
                            .foregroundStyle(theme.text2)
                            .unredacted()
                        Text(MoneyFormatter.percent(premium.percent))
                            .font(.system(size: 20, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                    }
                    Spacer(minLength: 8)
                    if premium.history.count >= 2 {
                        VStack(alignment: .trailing, spacing: 1) {
                            KimchiSparkline(values: premium.history.map(\.percent.doubleValue), tint: tint)
                                .frame(width: 120, height: 28)
                            Text(rangeText(premium.history))
                                .font(.system(size: 9.5))
                                .monospacedDigit()
                                .foregroundStyle(theme.text2)
                        }
                    }
                }
                HStack(spacing: 8) {
                    priceTile(
                        title: model.t("Upbit"),
                        price: premium.upbitPrice,
                        caption: UpbitProvider.market(symbol: asset.symbol)
                    )
                    priceTile(
                        title: model.t("Binance"),
                        price: premium.binancePriceKRW,
                        caption: MoneyFormatter.price(premium.binancePrice, currency: "USD")
                            + " × " + premium.usdKRW.formatted(
                                .number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US"))
                            )
                    )
                }
            }
            .redacted(reason: isPlaceholder ? .placeholder : [])
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }

    private func priceTile(title: String, price: Decimal, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.text2)
            Text(Self.krwText(price))
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .privacyBlur(model.settings.privacyMode)
                .padding(.top, 4)
            Text(caption)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(theme.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.bg))
    }

    /// 원화 가격 — 1원 미만 코인(업비트 SHIB 등)이 ₩0으로 보이지 않게 작은 값은 유효숫자로.
    static func krwText(_ value: Decimal) -> String {
        guard value < 100 else { return MoneyFormatter.price(value.rounded(scale: 0), currency: "KRW") }
        return "₩" + value.formatted(
            .number.precision(.significantDigits(1...4)).locale(Locale(identifier: "en_US"))
        )
    }

    private func rangeText(_ history: [KimchiPremiumPoint]) -> String {
        let percents = history.map(\.percent)
        let low = MoneyFormatter.percent(percents.min() ?? 0, fractionDigits: 1)
        let high = MoneyFormatter.percent(percents.max() ?? 0, fractionDigits: 1)
        return model.t("30D \(low) ~ \(high)")
    }
}

/// 김프 추이 미니 라인 — 축 없이 최소~최대로 꽉 채우고 끝점에 점을 찍는다.
private struct KimchiSparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let points = points(in: proxy.size)
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                if let last = points.last {
                    Circle()
                        .fill(tint)
                        .frame(width: 5, height: 5)
                        .position(last)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2, let low = values.min(), let high = values.max() else { return [] }
        let inset: CGFloat = 2.5
        let span = high - low
        let step = (size.width - inset * 2) / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let ratio = span > 0 ? (value - low) / span : 0.5
            return CGPoint(
                x: inset + CGFloat(index) * step,
                y: inset + (size.height - inset * 2) * CGFloat(1 - ratio)
            )
        }
    }
}
