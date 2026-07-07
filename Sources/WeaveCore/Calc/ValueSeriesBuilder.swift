import Foundation

public struct ValuePoint: Equatable, Sendable {
    public var date: Date
    /// 기준통화 환산 가치.
    public var value: Decimal

    public init(date: Date, value: Decimal) {
        self.date = date
        self.value = value
    }
}

/// 통합 차트용 일별 포트폴리오 가치 시계열.
/// 하루 가치 = Σ(그날 보유수량 × 그날 종가 × 그날 환율). 보유수량은 거래 날짜 기준 스텝 함수.
public enum ValueSeriesBuilder {
    public static func portfolioSeries(
        assets: [Asset],
        trades: [Trade],
        candlesByAsset: [UUID: [Candle]],
        fxSeriesByCurrency: [String: [Candle]],
        baseCurrency: String,
        from: Date?,
        to: Date,
        calendar: Calendar = .current
    ) -> [ValuePoint] {
        let visible = assets.filter { !$0.isHidden }
        let visibleIDs = Set(visible.map(\.id))
        let tradesByAsset = Dictionary(grouping: trades, by: \.assetID)

        // 시작일 = max(요청 시작, 첫 매수일). 첫 매수 이전 구간은 그리지 않는다.
        // 숨김 자산의 거래는 표시 구간 결정에서도 제외한다.
        let firstBuy = trades
            .filter { $0.side == .buy && visibleIDs.contains($0.assetID) }
            .map(\.date)
            .min()
        guard let firstBuy else { return [] }
        let startDate = [from, firstBuy].compactMap { $0 }.max() ?? firstBuy

        var day = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: to)
        guard day <= endDay else { return [] }

        // 자산별 날짜→종가 룩업(정렬된 배열에서 이진 탐색으로 forward-fill).
        let closeLookups: [UUID: SeriesLookup] = candlesByAsset.mapValues(SeriesLookup.init)
        let fxLookups: [String: SeriesLookup] = fxSeriesByCurrency.mapValues(SeriesLookup.init)
        let base = baseCurrency.uppercased()

        var points: [ValuePoint] = []
        while day <= endDay {
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            var total: Decimal = 0
            for asset in visible {
                if asset.isManual {
                    if asset.includeInChart, let manualValue = asset.manualValue {
                        let fx = fxRate(currency: asset.currency, base: base, on: day, lookups: fxLookups)
                        total += manualValue * (fx ?? 0)
                    }
                    continue
                }
                let assetTrades = tradesByAsset[asset.id] ?? []
                // 그날 자정 이전(당일 포함) 체결분까지 반영.
                let quantity = PositionCalculator.quantity(
                    onOrBefore: endOfDay.addingTimeInterval(-1),
                    trades: assetTrades
                )
                guard quantity > 0 else { continue }
                guard let close = closeLookups[asset.id]?.value(onOrBefore: day) else { continue }
                let fx = fxRate(currency: asset.currency, base: base, on: day, lookups: fxLookups)
                total += quantity * close * (fx ?? 0)
            }
            points.append(ValuePoint(date: day, value: total))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? endDay.addingTimeInterval(1)
        }
        return points
    }

    /// 인트라데이(1D) 통합 시계열 — 캔들 타임스탬프를 샘플 격자로 쓴다.
    /// 하루짜리 창이라 보유수량·환율은 사실상 상수 → 환율은 현물(spot) 하나로 환산한다.
    /// 시장 휴장 종목은 forward-fill로 마지막 종가를 유지(값이 평평).
    public static func intradayPortfolioSeries(
        assets: [Asset],
        trades: [Trade],
        candlesByAsset: [UUID: [Candle]],
        fxSpotByCurrency: [String: Decimal],
        baseCurrency: String,
        from: Date,
        to: Date
    ) -> [ValuePoint] {
        let visible = assets.filter { !$0.isHidden }
        let tradesByAsset = Dictionary(grouping: trades, by: \.assetID)
        let base = baseCurrency.uppercased()

        func fx(_ currency: String) -> Decimal {
            let code = currency.uppercased()
            return code == base ? 1 : (fxSpotByCurrency[code] ?? 0)
        }

        // 정렬된 캔들 + 표시 구간 내 타임스탬프 = 샘플 격자.
        let sorted: [UUID: [Candle]] = candlesByAsset.mapValues { $0.sorted { $0.date < $1.date } }
        var sampleSet = Set<Date>()
        for asset in visible where !asset.isManual {
            for candle in sorted[asset.id] ?? [] where candle.date >= from && candle.date <= to {
                sampleSet.insert(candle.date)
            }
        }
        sampleSet.insert(to)
        let samples = sampleSet.sorted()
        guard !samples.isEmpty else { return [] }

        // 그날의 끝 보정 없이 정확히 "그 시각 이전 마지막 종가"를 찾는 forward-fill.
        func close(_ candles: [Candle], at time: Date) -> Decimal? {
            guard !candles.isEmpty else { return nil }
            var low = 0
            var high = candles.count - 1
            var found = -1
            while low <= high {
                let mid = (low + high) / 2
                if candles[mid].date <= time {
                    found = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return found >= 0 ? candles[found].close : candles.first?.close
        }

        return samples.map { time in
            var total: Decimal = 0
            for asset in visible {
                if asset.isManual {
                    if asset.includeInChart, let manualValue = asset.manualValue {
                        total += manualValue * fx(asset.currency)
                    }
                    continue
                }
                let quantity = PositionCalculator.quantity(onOrBefore: time, trades: tradesByAsset[asset.id] ?? [])
                guard quantity > 0, let price = close(sorted[asset.id] ?? [], at: time) else { continue }
                total += quantity * price * fx(asset.currency)
            }
            return ValuePoint(date: time, value: total)
        }
    }

    /// 자산별 모드 — 종가를 구간 시작점 0% 기준으로 정규화한 % 시계열.
    public static func normalizedSeries(
        candles: [Candle],
        from: Date,
        to: Date
    ) -> [(date: Date, percent: Double)] {
        let window = candles
            .filter { $0.date >= from && $0.date <= to }
            .sorted { $0.date < $1.date }
        guard let first = window.first, first.close > 0 else { return [] }
        return window.map { candle in
            (candle.date, ((candle.close - first.close) / first.close * 100).doubleValue)
        }
    }

    private static func fxRate(
        currency: String,
        base: String,
        on day: Date,
        lookups: [String: SeriesLookup]
    ) -> Decimal? {
        let code = currency.uppercased()
        if code == base { return 1 }
        return lookups[code]?.value(onOrBefore: day)
    }
}

/// 날짜 오름차순 캔들에서 "그날 또는 그 이전 마지막 종가"를 찾는 forward-fill 룩업.
/// 첫 캔들 이전 날짜는 첫 캔들 종가로 backward-fill.
struct SeriesLookup {
    private let dates: [Date]
    private let closes: [Decimal]

    init(candles: [Candle]) {
        let sorted = candles.sorted { $0.date < $1.date }
        dates = sorted.map(\.date)
        closes = sorted.map(\.close)
    }

    func value(onOrBefore day: Date) -> Decimal? {
        guard !dates.isEmpty else { return nil }
        // 그날의 끝까지 포함 — 캔들 date가 그날 자정+α(타임존 차이)여도 매칭되게.
        let cutoff = day.addingTimeInterval(86_400 - 1)
        var low = 0
        var high = dates.count - 1
        var found = -1
        while low <= high {
            let mid = (low + high) / 2
            if dates[mid] <= cutoff {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found >= 0 ? closes[found] : closes.first
    }
}
