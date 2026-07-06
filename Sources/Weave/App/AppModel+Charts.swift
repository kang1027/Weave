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
        let fxSeries = await fetchFXSeries(assets: assets)
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
    }

    // MARK: - 상세 차트

    /// 상세 화면 캔들 — 선택 인터벌(15m~월봉) 그대로 조회, 탐색은 차트 팬/줌 담당.
    func loadDetailChart(assetID: UUID) async {
        guard let asset = asset(id: assetID), !asset.isManual else {
            detailCandles = []
            detailChartAssetID = nil
            return
        }
        // 다른 자산으로 전환 시 이전 자산 캔들이 잠깐 보이지 않게 즉시 비운다.
        if detailChartAssetID != assetID {
            detailCandles = []
            detailChartAssetID = assetID
        }
        detailLoadToken += 1
        let token = detailLoadToken
        isDetailChartLoading = true
        defer { isDetailChartLoading = false }

        let interval = detailInterval
        let candles = await fetchDetailCandles(asset: asset, interval: interval)

        // 더 최신 요청(자산 전환/인터벌 변경)이 시작됐다면 이 결과는 버린다.
        guard token == detailLoadToken else { return }
        detailCandles = candles.sorted { $0.date < $1.date }
    }

    /// 네이버(국장)는 인트라데이가 없어 야후 `.KS`/`.KQ`로 브릿지한다.
    private func fetchDetailCandles(asset: Asset, interval: CandleInterval) async -> [Candle] {
        if asset.provider == .naver, interval.isIntraday {
            for suffix in [".KS", ".KQ"] {
                if let candles = try? await candleService.candles(
                    provider: .yahoo,
                    providerSymbol: asset.providerSymbol + suffix,
                    interval: interval
                ), !candles.isEmpty {
                    return candles
                }
            }
            return []
        }
        return (try? await candleService.candles(
            provider: asset.provider,
            providerSymbol: asset.providerSymbol,
            interval: interval
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
