import Foundation
import WeaveCore

extension AppModel {
    // MARK: - 홈 Value History

    func invalidateHomeChart() {
        homeSeries = []
        homeAssetSeries = []
        homeBuyMarkers = []
        homeAssetCandles = [:]
        chartGeneration += 1
    }

    func isHomeChartAssetHidden(_ assetID: UUID) -> Bool {
        settings.hiddenHomeChartAssetIDs.contains(assetID)
    }

    func toggleHomeChartAssetVisibility(assetID: UUID) {
        guard document.assets.contains(where: { $0.id == assetID }) else { return }

        var hiddenIDs = Set(settings.hiddenHomeChartAssetIDs)
        if hiddenIDs.contains(assetID) {
            hiddenIDs.remove(assetID)
        } else {
            hiddenIDs.insert(assetID)
        }

        var next = settings
        next.hiddenHomeChartAssetIDs = document.assets.map(\.id).filter { hiddenIDs.contains($0) }
        settings = next
    }

    /// 통합/자산별 시계열 + 매수 마커 재계산.
    /// 1D는 시간봉으로 최근 24h 인트라데이 곡선, 그 외는 일봉. x 도메인은 기간 전체로 고정.
    func loadHomeChart() async {
        chartLoadToken += 1
        let token = chartLoadToken
        let assets = visibleAssets
        let period = homeChartPeriod
        let now = Date()
        // 축은 데이터와 무관하게 늘 선택 기간 전체를 덮는다.
        // 일봉 기간은 시작을 자정에 맞춰 x축 눈금 간격이 고르게(첫 칸이 넓어 보이던 것 방지).
        let domain: ClosedRange<Date>
        if period.isIntraday {
            domain = period.startDate(now: now)...now
        } else {
            domain = Calendar.current.startOfDay(for: period.startDate(now: now))...now
        }
        guard !assets.isEmpty else {
            homeChartDomain = domain
            homeSeries = []
            homeAssetSeries = []
            homeBuyMarkers = []
            return
        }
        isHomeChartLoading = true
        defer { isHomeChartLoading = false }

        let candlesByAsset = await fetchCandles(assets: assets, interval: period.candleInterval)
        // ASSETS %배지는 항상 일봉 기준(별개의 assetReturnPeriod로 1W/1M/1Y 계산)이라,
        // 차트가 1D(시간봉)일 때도 배지가 정확하도록 일봉을 따로 확보한다(일봉 캐시라 저렴).
        let dailyCandles = period.isIntraday
            ? await fetchCandles(assets: assets, interval: .day)
            : candlesByAsset
        // 기준통화가 아닌 자산 통화의 현물 환율 확보(없으면 갱신).
        let base = settings.baseCurrency.uppercased()
        let neededCurrencies = Set(assets.map { $0.currency.uppercased() }).subtracting([base])
        if !neededCurrencies.allSatisfy({ fxRates[$0] != nil }) {
            await refreshFXRates()
        }
        let from = period.startDate(now: now)

        let series: [ValuePoint]
        if period.isIntraday {
            // 하루짜리 창 — 환율은 현물 상수로 환산(인트라데이 FX는 자산 변동 대비 미미).
            series = ValueSeriesBuilder.intradayPortfolioSeries(
                assets: assets,
                trades: document.trades,
                candlesByAsset: candlesByAsset,
                fxSpotByCurrency: fxRates,
                baseCurrency: settings.baseCurrency,
                from: from,
                to: now
            )
        } else {
            var fxSeries = await fetchFXSeries(assets: assets)
            // FX 시계열 조회 실패 통화는 현물 환율로라도 환산 — 자산이 0원으로 증발하는 것 방지.
            for currency in neededCurrencies where fxSeries[currency] == nil {
                if let spot = fxRates[currency] {
                    fxSeries[currency] = [
                        Candle(date: now, open: spot, high: spot, low: spot, close: spot)
                    ]
                }
            }
            series = ValueSeriesBuilder.portfolioSeries(
                assets: assets,
                trades: document.trades,
                candlesByAsset: candlesByAsset,
                fxSeriesByCurrency: fxSeries,
                baseCurrency: settings.baseCurrency,
                from: from,
                to: now
            )
        }

        // 자산별 정규화 라인 — Combined와 같은 기준: 각 종목의 매수일부터 0%.
        // (창 시작보다 늦게 산 종목은 그 매수일부터 그려 날짜 기준을 통일.)
        let windowStart = series.first?.date ?? from
        let firstBuyByAsset: [UUID: Date] = Dictionary(
            document.trades.filter { $0.side == .buy }.map { ($0.assetID, $0.date) },
            uniquingKeysWith: min
        )
        let assetLines: [AssetLineSeries] = assets.compactMap { asset in
            guard !asset.isManual, let candles = candlesByAsset[asset.id] else { return nil }
            // 일봉 캔들은 자정에 찍히므로 매수일 자정 기준으로 잘라야 당일 캔들이 포함된다.
            // (인트라데이는 매수 시각 그대로.)
            let rawStart = firstBuyByAsset[asset.id] ?? windowStart
            let buyStart = period.isIntraday ? rawStart : Calendar.current.startOfDay(for: rawStart)
            let assetStart = max(windowStart, buyStart)
            // 일/시간 격자로 forward-fill — 주말·휴장 구멍 없이 Combined와 같은 규격.
            let points = ValueSeriesBuilder.normalizedSeries(
                candles: candles, from: assetStart, to: now,
                step: period.isIntraday ? .hour : .day
            )
            guard !points.isEmpty else { return nil }
            return AssetLineSeries(asset: asset, points: points)
        }

        // 매수 마커 — 표시 구간 안의 매수 체결. y = 그 시점과 가장 가까운 시계열 값.
        // (일봉/시간봉 공통 — 날짜 키 사전은 인트라데이에서 중복 키로 깨지므로 최근접 탐색.)
        let markers: [BuyMarker] = document.trades
            .filter { $0.side == .buy && $0.date >= windowStart }
            .compactMap { trade -> BuyMarker? in
                guard
                    let asset = assets.first(where: { $0.id == trade.assetID }),
                    let nearest = series.min(by: {
                        abs($0.date.timeIntervalSince(trade.date)) < abs($1.date.timeIntervalSince(trade.date))
                    })
                else {
                    return nil
                }
                var vsCurrent: Decimal?
                if let quote = quotes[trade.assetID], trade.price > 0 {
                    vsCurrent = ((quote.price - trade.price) / trade.price * 100).rounded(scale: 2)
                }
                return BuyMarker(
                    trade: trade, asset: asset,
                    seriesValue: nearest.value, vsCurrentPercent: vsCurrent
                )
            }
            .sorted { $0.trade.date < $1.trade.date }

        // 더 최신 로드가 시작됐다면 이 결과는 버린다.
        guard token == chartLoadToken else { return }
        homeChartDomain = domain
        homeSeries = series
        homeAssetSeries = assetLines
        homeBuyMarkers = markers
        homeAssetCandles = dailyCandles
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
                let id = asset.id
                let provider = asset.provider
                let symbol = asset.providerSymbol
                group.addTask { [candleService] in
                    // 네이버(국장)는 인트라데이가 없어 야후 .KS/.KQ로 브릿지.
                    if provider == .naver, interval.isIntraday {
                        for suffix in [".KS", ".KQ"] {
                            if let candles = try? await candleService.candles(
                                provider: .yahoo, providerSymbol: symbol + suffix, interval: interval
                            ), !candles.isEmpty {
                                return (id, candles)
                            }
                        }
                        return (id, nil)
                    }
                    let candles = try? await candleService.candles(
                        provider: provider, providerSymbol: symbol, interval: interval
                    )
                    return (id, candles)
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
