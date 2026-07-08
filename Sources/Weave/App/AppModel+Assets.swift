import AppKit
import Foundation
import UniformTypeIdentifiers
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

        let asset = Asset(
            name: result.name,
            symbol: result.symbol,
            provider: result.provider,
            providerSymbol: result.providerSymbol,
            market: result.market,
            currency: result.currency ?? "USD",
            colorIndex: nextColorIndex()
        )

        // 다른 추가가 먼저 끝났을 수 있다 — 한도·중복 재확인.
        guard !isAtAssetLimit else { return nil }
        if let existing = document.assets.first(where: {
            $0.provider == result.provider && $0.providerSymbol == result.providerSymbol
        }) {
            route = [.detail(existing.id)]
            return existing
        }

        document.assets.append(asset)
        persist()
        invalidateHomeChart()
        updateMenuBarTitle()
        searchQuery = ""
        searchResults = []
        route = [.detail(asset.id)]
        Task { [weak self] in
            await self?.refreshAddedAsset(assetID: asset.id)
        }
        return asset
    }

    /// 새 자산은 먼저 화면에 반영하고, 느릴 수 있는 시세/환율은 뒤에서 채운다.
    private func refreshAddedAsset(assetID: UUID) async {
        await refreshFXRates()
        updateMenuBarTitle()

        guard let asset = asset(id: assetID), !asset.isManual else { return }
        guard let quote = try? await quoteService.quote(for: asset) else {
            staleAssetIDs.insert(assetID)
            updateMenuBarTitle()
            return
        }

        guard let index = document.assets.firstIndex(where: { $0.id == assetID }) else { return }
        quotes[assetID] = quote
        staleAssetIDs.remove(assetID)
        if quote.currency.uppercased() != document.assets[index].currency.uppercased() {
            document.assets[index].currency = quote.currency.uppercased()
            persist()
        }
        await refreshFXRates()
        invalidateHomeChart()
        updateMenuBarTitle()
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
        guard value >= 0,
              let index = document.assets.firstIndex(where: { $0.id == assetID })
        else { return }
        document.assets[index].manualValue = value
        persist()
        invalidateHomeChart()
    }

    // MARK: - 자산 관리

    /// 거래 내역까지 통째 삭제 — 확인 다이얼로그는 뷰 책임.
    func deleteAsset(id: UUID) {
        LogoStore.delete(fileName: asset(id: id)?.customLogoFileName)
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

    /// 홈 리스트 맨 위 고정 토글.
    func togglePinTop(assetID: UUID) {
        let pinned = asset(id: assetID)?.isPinnedToTop ?? false
        mutateAsset(id: assetID) { $0.pinnedToTop = pinned ? nil : true }
    }

    /// 홈 리스트 표시 순서 — 맨 위 고정 먼저, 각 그룹은 배열 순서(숨김 제외).
    private func displayedAssetOrder() -> [UUID] {
        let visible = document.assets.filter { !$0.isHidden }
        return (visible.filter { $0.isPinnedToTop } + visible.filter { !$0.isPinnedToTop }).map(\.id)
    }

    /// 같은 고정 그룹 안에서 위/아래로 이동 가능 여부(핀 경계는 못 넘음).
    func canMoveAsset(id: UUID, up: Bool) -> Bool {
        let order = displayedAssetOrder()
        guard let pos = order.firstIndex(of: id) else { return false }
        let neighbor = up ? pos - 1 : pos + 1
        guard order.indices.contains(neighbor) else { return false }
        return (asset(id: id)?.isPinnedToTop ?? false) == (asset(id: order[neighbor])?.isPinnedToTop ?? false)
    }

    /// 우클릭 메뉴 — 표시 순서에서 한 칸 위/아래로 이동.
    func moveAsset(id: UUID, up: Bool) {
        guard canMoveAsset(id: id, up: up) else { return }
        let order = displayedAssetOrder()
        guard let pos = order.firstIndex(of: id) else { return }
        let neighborID = order[up ? pos - 1 : pos + 1]
        guard let from = document.assets.firstIndex(where: { $0.id == id }) else { return }
        let moved = document.assets.remove(at: from)
        guard let target = document.assets.firstIndex(where: { $0.id == neighborID }) else {
            document.assets.insert(moved, at: min(from, document.assets.count))
            return
        }
        document.assets.insert(moved, at: up ? target : target + 1)
        persist()
    }

    // MARK: - 커스텀 로고

    /// 파일 선택 → 리사이즈 PNG 저장 → 자산에 연결. 기존 커스텀 로고는 교체 삭제.
    func pickCustomLogo(assetID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .gif, .image]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let fileName = try? LogoStore.saveLogo(from: url, assetID: assetID) else { return }
        let previous = asset(id: assetID)?.customLogoFileName
        mutateAsset(id: assetID) { $0.customLogoFileName = fileName }
        LogoStore.delete(fileName: previous)
    }

    func clearCustomLogo(assetID: UUID) {
        let previous = asset(id: assetID)?.customLogoFileName
        mutateAsset(id: assetID) { $0.customLogoFileName = nil }
        LogoStore.delete(fileName: previous)
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
