import Foundation
import WeaveCore

extension AppModel {
    /// API rate limit 보호용 soft limit.
    static let assetSoftLimit = 30

    var isAtAssetLimit: Bool { document.assets.count >= Self.assetSoftLimit }

    // MARK: - 자산 추가

    /// 검색 결과 선택 → 자산 생성. 중복이면 기존 자산 상세로 이동.
    @discardableResult
    func addAsset(from result: SearchResult) async -> Asset? {
        if let existing = document.assets.first(where: {
            $0.provider == result.provider && $0.providerSymbol == result.providerSymbol
        }) {
            route = [.detail(existing.id)]
            return existing
        }
        guard !isAtAssetLimit else { return nil }

        var asset = Asset(
            name: result.name,
            symbol: result.symbol,
            provider: result.provider,
            providerSymbol: result.providerSymbol,
            market: result.market,
            currency: result.currency ?? "USD",
            colorIndex: nextColorIndex()
        )

        // 통화 확정 — 야후는 추정치라 첫 시세의 실제 통화로 교정.
        if let quote = try? await quoteService.quote(for: asset) {
            asset.currency = quote.currency.uppercased()
            quotes[asset.id] = quote
        }

        document.assets.append(asset)
        persist()
        await refreshFXRates()
        updateMenuBarTitle()
        searchQuery = ""
        searchResults = []
        route = [.detail(asset.id)]
        return asset
    }

    /// Manual Asset — 검색 불가 자산. 시세 갱신 없음.
    @discardableResult
    func addManualAsset(name: String, currency: String, value: Decimal, includeInChart: Bool) -> Asset? {
        guard !isAtAssetLimit else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, value >= 0 else { return nil }

        let asset = Asset(
            name: trimmed,
            symbol: trimmed,
            provider: .manual,
            providerSymbol: "manual-\(UUID().uuidString)",
            market: .other,
            currency: currency.uppercased(),
            colorIndex: nextColorIndex(),
            showInMenuBar: false,
            manualValue: value,
            includeInChart: includeInChart
        )
        document.assets.append(asset)
        persist()
        invalidateHomeChart()
        Task { await refreshFXRates() }
        route = [.manage]
        return asset
    }

    func updateManualValue(assetID: UUID, value: Decimal) {
        guard let index = document.assets.firstIndex(where: { $0.id == assetID }) else { return }
        document.assets[index].manualValue = value
        persist()
    }

    // MARK: - 자산 관리

    /// 거래 내역까지 통째 삭제 — 확인 다이얼로그는 뷰 책임.
    func deleteAsset(id: UUID) {
        document.assets.removeAll { $0.id == id }
        document.trades.removeAll { $0.assetID == id }
        quotes[id] = nil
        staleAssetIDs.remove(id)
        persist()
        invalidateHomeChart()
        updateMenuBarTitle()
        // 삭제된 자산 화면이 스택에 있으면 홈으로.
        if route.contains(where: { if case .detail(id) = $0 { return true } else { return false } }) {
            route = document.assets.isEmpty ? [] : [.manage]
        }
    }

    func tradeCount(assetID: UUID) -> Int {
        document.trades(for: assetID).count
    }

    func toggleMenuBar(assetID: UUID) {
        mutateAsset(id: assetID) { $0.showInMenuBar.toggle() }
        updateMenuBarTitle()
    }

    /// 핀은 하나만 — 새로 핀하면 기존 핀 해제.
    func togglePin(assetID: UUID) {
        let wasPinned = asset(id: assetID)?.isPinned ?? false
        for index in document.assets.indices {
            document.assets[index].isPinned = false
        }
        if !wasPinned {
            mutateAsset(id: assetID, save: false) { $0.isPinned = true }
        }
        persist()
        updateMenuBarTitle()
    }

    func toggleHidden(assetID: UUID) {
        mutateAsset(id: assetID) { $0.isHidden.toggle() }
        invalidateHomeChart()
        updateMenuBarTitle()
    }

    func setColor(assetID: UUID, colorIndex: Int) {
        mutateAsset(id: assetID) { $0.colorIndex = colorIndex }
    }

    private func mutateAsset(id: UUID, save: Bool = true, _ transform: (inout Asset) -> Void) {
        guard let index = document.assets.firstIndex(where: { $0.id == id }) else { return }
        transform(&document.assets[index])
        if save { persist() }
    }

    /// 팔레트 8색 중 사용 빈도가 가장 낮은 인덱스(동률이면 낮은 번호).
    func nextColorIndex() -> Int {
        var usage = [Int](repeating: 0, count: 8)
        for asset in document.assets {
            usage[((asset.colorIndex % 8) + 8) % 8] += 1
        }
        return usage.enumerated().min { lhs, rhs in
            lhs.element == rhs.element ? lhs.offset < rhs.offset : lhs.element < rhs.element
        }?.offset ?? 0
    }
}
