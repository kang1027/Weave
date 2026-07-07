import Foundation

public enum PortfolioCalculator {
    /// 자산·거래·시세·환율 → 자산별/포트폴리오 지표.
    /// - Parameter fxRates: [통화코드: 기준통화 환산율]. 빠진 통화의 자산은 합산에서 제외.
    public static func compute(
        assets: [Asset],
        trades: [Trade],
        quotes: [UUID: Quote],
        fxRates: [String: Decimal],
        baseCurrency: String
    ) -> (perAsset: [AssetMetrics], portfolio: PortfolioMetrics) {
        let visible = assets.filter { !$0.isHidden }
        var metrics: [AssetMetrics] = []

        for asset in visible {
            let position = PositionCalculator.snapshot(trades: trades.filter { $0.assetID == asset.id })
            let quote = quotes[asset.id]
            let fx = fxRates[asset.currency.uppercased()] ?? (asset.currency.uppercased() == baseCurrency.uppercased() ? 1 : 0)

            let value: Decimal
            let unrealized: Decimal
            var returnPercent: Decimal?
            var dayPercent: Decimal?
            var dayAmount: Decimal = 0

            if asset.isManual {
                value = asset.manualValue ?? 0
                unrealized = 0
            } else if let quote {
                value = position.quantity * quote.price
                unrealized = value - position.costBasis
                if position.costBasis > 0 {
                    returnPercent = (unrealized / position.costBasis * 100).rounded(scale: 4)
                }
                dayPercent = quote.changePercent
                // 전일(또는 24h 전) 가치 = value / (1 + pct/100) → 변동액 = value − 전일 가치.
                let divisor = 1 + quote.changePercent / 100
                if divisor > 0 {
                    dayAmount = value - value / divisor
                }
            } else {
                // 시세 없음(최초 로드 실패 등) — 원가로만 계상.
                value = position.costBasis
                unrealized = 0
            }

            metrics.append(
                AssetMetrics(
                    asset: asset,
                    position: position,
                    quote: quote,
                    value: value,
                    valueBase: value * fx,
                    unrealizedPnL: unrealized,
                    unrealizedPnLBase: unrealized * fx,
                    returnPercent: returnPercent,
                    dayChangePercent: dayPercent,
                    dayChangeAmountBase: dayAmount * fx,
                    weight: 0
                )
            )
        }

        // 비중 계산 후 재기입.
        let totalValueBase = metrics.reduce(Decimal(0)) { $0 + $1.valueBase }
        metrics = metrics.map { metric in
            var updated = metric
            updated.weight = totalValueBase > 0
                ? (metric.valueBase / totalValueBase).doubleValue
                : 0
            return updated
        }

        let portfolio = portfolioMetrics(metrics: metrics, totalValueBase: totalValueBase)
        let ordered = metrics.sorted { $0.valueBase > $1.valueBase }
        return (ordered, portfolio)
    }

    private static func portfolioMetrics(
        metrics: [AssetMetrics],
        totalValueBase: Decimal
    ) -> PortfolioMetrics {
        // 일간 변동 % = Σ변동액 / Σ전일가치.
        let dayAmountTotal = metrics.reduce(Decimal(0)) { $0 + $1.dayChangeAmountBase }
        let previousTotal = totalValueBase - dayAmountTotal
        let dayPercent: Decimal = previousTotal > 0
            ? (dayAmountTotal / previousTotal * 100).rounded(scale: 4)
            : 0

        // 총 수익률 — manual 제외(미실현/원가 기준).
        let invested = metrics.filter { !$0.asset.isManual }
        let unrealizedTotal = invested.reduce(Decimal(0)) { $0 + $1.unrealizedPnLBase }
        let costTotal = invested.reduce(Decimal(0)) { $0 + ($1.valueBase - $1.unrealizedPnLBase) }
        let returnPercent: Decimal = costTotal > 0
            ? (unrealizedTotal / costTotal * 100).rounded(scale: 4)
            : 0

        return PortfolioMetrics(
            totalValueBase: totalValueBase,
            dayChangePercent: dayPercent,
            totalReturnPercent: returnPercent,
            unrealizedPnLBase: unrealizedTotal,
            costBasisBase: costTotal,
            daySegments: contributionSegments(metrics: metrics, total: dayAmountTotal) {
                $0.dayChangeAmountBase
            },
            returnSegments: contributionSegments(metrics: metrics, total: unrealizedTotal) {
                $0.unrealizedPnLBase
            },
            assetSegments: donutSegments(metrics: metrics, totalValueBase: totalValueBase),
            assetCount: metrics.count
        )
    }

    /// Day/Return 링 — 포트폴리오 손익과 같은 부호인 종목만, 기여액 비율로 분할.
    static func contributionSegments(
        metrics: [AssetMetrics],
        total: Decimal,
        amount: (AssetMetrics) -> Decimal
    ) -> [RingSegment] {
        guard total != 0 else { return [] }
        let sameSign = metrics.filter { metric in
            let value = amount(metric)
            return value != 0 && (value > 0) == (total > 0)
        }
        let sum = sameSign.reduce(Decimal(0)) { $0 + amount($1) }
        guard sum != 0 else { return [] }
        return sameSign
            .sorted { abs(amount($0)) > abs(amount($1)) }
            .map { metric in
                RingSegment(
                    assetID: metric.asset.id,
                    label: metric.asset.name,
                    fraction: (amount(metric) / sum).doubleValue,
                    amountBase: amount(metric),
                    colorIndex: metric.asset.colorIndex
                )
            }
    }

    /// Assets 도넛 — 비중 상위 4개 + 나머지 "기타"(회색).
    static func donutSegments(metrics: [AssetMetrics], totalValueBase: Decimal) -> [RingSegment] {
        guard totalValueBase > 0 else { return [] }
        let ordered = metrics
            .filter { $0.valueBase > 0 }
            .sorted { $0.valueBase > $1.valueBase }

        let top = ordered.prefix(4).map { metric in
            RingSegment(
                assetID: metric.asset.id,
                label: metric.asset.name,
                fraction: (metric.valueBase / totalValueBase).doubleValue,
                amountBase: metric.valueBase,
                colorIndex: metric.asset.colorIndex
            )
        }
        let rest = ordered.dropFirst(4)
        guard !rest.isEmpty else { return top }
        let restValue = rest.reduce(Decimal(0)) { $0 + $1.valueBase }
        return top + [
            RingSegment(
                assetID: nil,
                label: "",
                fraction: (restValue / totalValueBase).doubleValue,
                amountBase: restValue,
                colorIndex: nil
            )
        ]
    }
}
