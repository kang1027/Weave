import Foundation
import WeaveCore

extension AppModel {
    // MARK: - 홈 Value History

    func invalidateHomeChart() {
        homeSeries = []
        homeAssetSeries = []
        homeBuyMarkers = []
        chartGeneration += 1
    }

    /// 통합/자산별 시계열 + 매수 마커 재계산. 캔들은 일봉 캐시 사용.
    /// 홈 진입마다 다시 불려도 같은 날은 캐시 히트라 비용이 거의 없다.
    func loadHomeChart() async {
        chartLoadToken += 1
        let token = chartLoadToken
        let assets = visibleAssets
        let period = homeChartPeriod
        guard !assets.isEmpty else {
            homeSeries = []
            homeAssetSeries = []
            homeBuyMarkers = []
            return
        }
        isHomeChartLoading = true
        defer { isHomeChartLoading = false }

        let candlesByAsset = await fetchCandles(assets: assets, interval: .day)
        var fxSeries = await fetchFXSeries(assets: assets)
        // FX 시계열 조회 실패 통화는 현물 환율로라도 환산 — 자산이 0원으로 증발하는 것 방지.
        let base = settings.baseCurrency.uppercased()
        let neededCurrencies = Set(assets.map { $0.currency.uppercased() }).subtracting([base])
        if !neededCurrencies.allSatisfy({ fxRates[$0] != nil }) {
            await refreshFXRates()
        }
        for currency in Set(assets.map { $0.currency.uppercased() })
        where currency != base && fxSeries[currency] == nil {
            if let spot = fxRates[currency] {
                fxSeries[currency] = [
                    Candle(date: Date(), open: spot, high: spot, low: spot, close: spot)
                ]
            }
        }
        let now = Date()
        let from = period.startDate(now: now)

        let series = ValueSeriesBuilder.portfolioSeries(
            assets: assets,
            trades: document.trades,
            candlesByAsset: candlesByAsset,
            fxSeriesByCurrency: fxSeries,
            baseCurrency: settings.baseCurrency,
            from: from,
            to: now
        )

        // 자산별 정규화 라인 — 구간 시작 = 통합 시계열과 동일.
        let windowStart = series.first?.date ?? from ?? now
        let assetLines: [AssetLineSeries] = assets.compactMap { asset in
            guard !asset.isManual, let candles = candlesByAsset[asset.id] else { return nil }
            let points = ValueSeriesBuilder.normalizedSeries(
                candles: candles, from: windowStart, to: now
            )
            guard !points.isEmpty else { return nil }
            return AssetLineSeries(asset: asset, points: points)
        }

        // 매수 마커 — 표시 구간 안의 매수 체결. y = 그 날짜의 포트폴리오 가치.
        let lookup = Dictionary(uniqueKeysWithValues: series.map {
            (Calendar.current.startOfDay(for: $0.date), $0.value)
        })
        let markers: [BuyMarker] = document.trades
            .filter { $0.side == .buy && $0.date >= windowStart }
            .compactMap { trade in
                guard
                    let asset = assets.first(where: { $0.id == trade.assetID }),
                    let value = lookup[Calendar.current.startOfDay(for: trade.date)]
                else {
                    return nil
                }
                var vsCurrent: Decimal?
                if let quote = quotes[trade.assetID], trade.price > 0 {
                    vsCurrent = ((quote.price - trade.price) / trade.price * 100).rounded(scale: 2)
                }
                return BuyMarker(
                    trade: trade, asset: asset,
                    seriesValue: value, vsCurrentPercent: vsCurrent
                )
            }
            .sorted { $0.trade.date < $1.trade.date }

        // 더 최신 로드가 시작됐다면 이 결과는 버린다.
        guard token == chartLoadToken else { return }
        homeSeries = series
        homeAssetSeries = assetLines
        homeBuyMarkers = markers
        homeAssetCandles = candlesByAsset
    }

    /// Assets 리스트 % 배지 — 선택 기간(1D/1W/1M/1Y) 기준 수익률(소스 통화, FX 무관).
    /// 1D는 시세의 24h 변동을 그대로, 그 이상은 일봉 종가 대비로 계산한다.
    func assetReturnPercent(_ metric: AssetMetrics) -> Decimal? {
        if assetReturnPeriod == .day {
            return metric.dayChangePercent
        }
        guard
            !metric.asset.isManual,
            let candles = homeAssetCandles[metric.asset.id], !candles.isEmpty,
            let current = metric.quote?.price ?? candles.last?.close, current > 0
        else {
            return nil
        }
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -assetReturnPeriod.days, to: Date()
        ) ?? Date()
        // 기준 시점 이전 마지막 종가. 이력이 기간보다 짧으면 최초 종가로 폴백.
        let past = candles.last(where: { $0.date <= cutoff })?.close ?? candles.first?.close
        guard let past, past > 0 else { return nil }
        return ((current - past) / past * 100).rounded(scale: 2)
    }

    // MARK: - 상세 차트

    /// 상세 화면 캔들 — 선택 인터벌(15m~월봉) 그대로 조회, 탐색은 차트 팬/줌 담당.
    func loadDetailChart(assetID: UUID) async {
        guard let asset = asset(id: assetID), !asset.isManual else {
            detailCandles = []
            detailChartAssetID = nil
            return
        }
        // 다른 자산으로 전환 시 이전 자산 캔들이 잠깐 보이지 않게 즉시 비우고, 포커스도 최근으로 리셋.
        if detailChartAssetID != assetID {
            detailCandles = []
            detailChartAssetID = assetID
            detailFocusDate = nil
        }
        detailLoadToken += 1
        let token = detailLoadToken
        isDetailChartLoading = true
        defer { isDetailChartLoading = false }

        let interval = detailInterval
        // 포커스 시점이 있으면 그 날짜를 대략 중앙에 두도록 그 이후로 끝나는 과거 구간을 받는다.
        let endingAt = detailFocusDate.map { focus -> Date in
            let halfSpan = Double(CandleFetchLimit.limit(for: interval)) * interval.seconds / 2
            return min(Date(), focus.addingTimeInterval(halfSpan))
        }
        let candles = await fetchDetailCandles(asset: asset, interval: interval, endingAt: endingAt)

        // 더 최신 요청(자산 전환/인터벌 변경/포커스 변경)이 시작됐다면 이 결과는 버린다.
        guard token == detailLoadToken else { return }
        detailCandles = candles.sorted { $0.date < $1.date }
    }

    /// 거래 폼 미니 차트용 일봉(캐시 활용) — detailCandles/인터벌과 무관하게 항상 일봉.
    func dailyCandles(assetID: UUID) async -> [Candle] {
        guard let asset = asset(id: assetID), !asset.isManual else { return [] }
        return await fetchDetailCandles(asset: asset, interval: .day).sorted { $0.date < $1.date }
    }

    /// 네이버(국장)는 인트라데이가 없어 야후 `.KS`/`.KQ`로 브릿지한다.
    /// endingAt이 있으면 그 시점으로 끝나는 과거 구간을 조회(거래로 점프).
    private func fetchDetailCandles(
        asset: Asset,
        interval: CandleInterval,
        endingAt: Date? = nil
    ) async -> [Candle] {
        if asset.provider == .naver, interval.isIntraday {
            for suffix in [".KS", ".KQ"] {
                if let candles = try? await candleService.candles(
                    provider: .yahoo,
                    providerSymbol: asset.providerSymbol + suffix,
                    interval: interval,
                    endingAt: endingAt
                ), !candles.isEmpty {
                    return candles
                }
            }
            return []
        }
        return (try? await candleService.candles(
            provider: asset.provider,
            providerSymbol: asset.providerSymbol,
            interval: interval,
            endingAt: endingAt
        )) ?? []
    }

    // MARK: - 캔들/환율 일괄 조회

    private func fetchCandles(assets: [Asset], interval: CandleInterval) async -> [UUID: [Candle]] {
        await withTaskGroup(of: (UUID, [Candle]?).self) { group in
            for asset in assets where !asset.isManual {
                group.addTask { [candleService] in
                    let candles = try? await candleService.candles(
                        provider: asset.provider,
                        providerSymbol: asset.providerSymbol,
                        interval: interval
                    )
                    return (asset.id, candles)
                }
            }
            var result: [UUID: [Candle]] = [:]
            for await (id, candles) in group {
                if let candles { result[id] = candles }
            }
            return result
        }
    }

    /// 기준통화가 아닌 자산 통화의 일별 환율 시계열(야후 FX 캔들, 캐시 공유).
    private func fetchFXSeries(assets: [Asset]) async -> [String: [Candle]] {
        let base = settings.baseCurrency.uppercased()
        let currencies = Set(assets.map { $0.currency.uppercased() }).subtracting([base])
        var result: [String: [Candle]] = [:]
        for currency in currencies {
            let pair = FXService.pairSymbol(from: currency, to: base)
            if let candles = try? await candleService.candles(
                provider: .yahoo, providerSymbol: pair, interval: .day
            ) {
                result[currency] = candles
            }
        }
        return result
    }
}
