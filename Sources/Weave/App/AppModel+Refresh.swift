import Foundation
import WeaveCore

extension AppModel {
    /// 시세 + 환율 한 라운드 갱신. 실패한 자산은 마지막 값 유지 + stale 마킹.
    func refreshQuotes() async {
        let targets = document.assets.filter { !$0.isManual }
        guard !targets.isEmpty else {
            staleAssetIDs = []
            await refreshFXRates()
            updateMenuBarTitle()
            return
        }

        let fresh = await quoteService.quotes(for: targets)
        // 성공분만 덮어쓰기 — 실패 자산은 이전 시세 유지.
        quotes.merge(fresh) { _, new in new }
        staleAssetIDs = Set(targets.map(\.id)).subtracting(fresh.keys)

        // 야후 추정 통화 보정 — 실제 시세 통화가 다르면 자산에 반영.
        for asset in targets {
            if let quote = fresh[asset.id],
               quote.currency.uppercased() != asset.currency.uppercased(),
               let index = document.assets.firstIndex(where: { $0.id == asset.id }) {
                document.assets[index].currency = quote.currency.uppercased()
            }
        }

        await refreshFXRates()
        updateMenuBarTitle()
    }

    func refreshFXRates() async {
        let currencies = Set(document.assets.map { $0.currency.uppercased() })
        fxRates = await fxService.rates(currencies: currencies, base: settings.baseCurrency)
    }

    /// 수동 새로고침(헤더 ↻) — 갱신 카운트다운도 리셋.
    func manualRefresh() {
        restartRefreshLoop()
    }

    // MARK: - 메뉴바 타이틀

    /// 로테이션 대상: 핀 자산이 있으면 그것만(메뉴바 토글보다 우선), 없으면 메뉴바 표시가 켜진 자산 순환.
    func updateMenuBarTitle() {
        let candidates = visibleAssets.filter { $0.showInMenuBar && !$0.isManual }
        let privacy = settings.privacyMode

        let target: Asset?
        if let pinned = visibleAssets.first(where: { $0.isPinned && !$0.isManual }) {
            target = pinned
        } else if candidates.isEmpty {
            target = nil
        } else {
            target = candidates[rotationIndex % candidates.count]
        }

        if let target {
            let quote = quotes[target.id]
            menuBarTitle = MenuBarTitleBuilder.title(
                asset: target, quote: quote,
                format: settings.menuBarFormat, privacy: privacy
            )
            let parts = MenuBarTitleBuilder.parts(
                asset: target, quote: quote,
                format: settings.menuBarFormat, privacy: privacy
            )
            // 배지 로고 해석 — 커스텀 업로드 or 크립토 CDN(비동기 도착 시 재렌더).
            let logo = parts.badge == nil
                ? nil
                : MenuBarLogoProvider.shared.image(for: target) { [weak self] in
                    self?.updateMenuBarTitle()
                }
            menuBarImage = MenuBarImageRenderer.image(parts, logo: logo)
            return
        }

        // 표시할 자산이 없으면 포트폴리오 총액.
        let portfolio = computed.portfolio
        if portfolio.totalValueBase > 0 {
            menuBarTitle = MenuBarTitleBuilder.totalTitle(
                totalBase: portfolio.totalValueBase,
                baseCurrency: settings.baseCurrency,
                dayChangePercent: portfolio.dayChangePercent,
                privacy: privacy
            )
            menuBarImage = MenuBarImageRenderer.image(
                MenuBarTitleBuilder.totalParts(
                    totalBase: portfolio.totalValueBase,
                    baseCurrency: settings.baseCurrency,
                    dayChangePercent: portfolio.dayChangePercent,
                    privacy: privacy
                ),
                logo: nil
            )
        } else {
            menuBarTitle = MenuBarTitleBuilder.placeholder
            menuBarImage = nil
        }
    }
}
