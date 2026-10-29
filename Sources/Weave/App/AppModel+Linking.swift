import AppKit
import Foundation
import WeaveCore

/// 연결 하나의 최근 동기화 상태.
enum LinkStatus: Equatable {
    case syncing
    case synced(Date)
    case failed(LinkFailure)
}

/// 검토를 기다리는 첫 가져오기 — 적용할 때 그때의 문서로 다시 계획한다.
struct PendingImport {
    var snapshot: SourceSnapshot
    var plan: ImportPlan
}

/// 사용자가 고칠 수 있는 단위로 나눈 연결 실패.
enum LinkFailure: Error, Equatable {
    case invalidCredentials
    /// 지금 네트워크 IP가 토스증권 허용 IP 목록에 없다.
    case ipNotAllowed
    case rateLimited
    case noAccount
    case alreadyLinked
    /// 다른 Mac에서 가져온 백업처럼 문서엔 연결이 있는데 이 Mac 키체인에 키·주소가 없다.
    case missingCredentials
    case keychain
    case network
    case invalidAddress
    /// 체인 RPC가 일부 잔고를 못 줬다 — 0으로 보지 않고 이번 동기화를 건너뛴다.
    case walletUnavailable(String)
    case server(String)

    init(_ error: Error) {
        switch error {
        case let failure as LinkFailure: self = failure
        case TossError.invalidCredentials: self = .invalidCredentials
        case TossError.ipNotAllowed: self = .ipNotAllowed
        case TossError.rateLimited: self = .rateLimited
        case TossError.noAccount: self = .noAccount
        case TossError.server(let status, let code): self = .server(code.isEmpty ? "HTTP \(status)" : code)
        case TossError.invalidResponse: self = .server("invalid-response")
        case WalletError.partialFailure(let chain): self = .walletUnavailable(chain)
        case WalletError.invalidResponse: self = .server("invalid-response")
        case HTTPError.badStatus(let status): self = .server("HTTP \(status)")
        case is CredentialStoreError, is DecodingError: self = .keychain
        case is URLError: self = .network
        default: self = .server(String(describing: error))
        }
    }
}

extension AppModel {
    /// 자동 동기화 최소 간격 — 시세 갱신 주기가 1분이어도 증권사는 5분마다만 부른다.
    static let linkSyncInterval: TimeInterval = 290

    var tossDocsURL: URL { URL(string: "https://developers.tossinvest.com/docs")! }

    // MARK: - 연결

    /// 토스증권 키로 계좌를 확인하고 연결한 뒤 첫 동기화를 한다. 실패하면 아무것도 저장하지 않는다.
    func connectToss(clientID: String, clientSecret: String) async -> Result<UUID, LinkFailure> {
        let credentials = TossCredentials(
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !credentials.clientID.isEmpty, !credentials.clientSecret.isEmpty else {
            return .failure(.invalidCredentials)
        }
        // 같은 계좌를 두 번 연결하면 같은 체결이 두 번 들어간다.
        guard !isTossLinked(clientID: credentials.clientID) else { return .failure(.alreadyLinked) }

        let client = TossClient(credentials: credentials, http: linkHTTP)
        do {
            guard let account = try await client.accounts().first else { return .failure(.noAccount) }
            let label = TossConnector.maskedAccount(account.accountNo)
            // 기다리는 사이 같은 키나 계좌가 먼저 연결됐을 수 있다.
            guard !isTossLinked(clientID: credentials.clientID, label: label) else { return .failure(.alreadyLinked) }
            let source = LinkedSource(kind: .toss, name: t("Toss Securities"), label: label)
            var stored = credentials
            stored.accountSeq = account.accountSeq
            try credentialStore.save(stored, for: source.id)
            document.sources.append(source)
            persist()
            // 토큰은 클라이언트당 하나 — 방금 받은 토큰을 동기화에서 그대로 쓴다.
            tossClients[source.id] = client
            await syncSource(id: source.id)
            return .success(source.id)
        } catch {
            return .failure(LinkFailure(error))
        }
    }

    private func isTossLinked(clientID: String, label: String? = nil) -> Bool {
        document.sources.contains { source in
            guard source.kind == .toss else { return false }
            if let label, source.label == label { return true }
            let stored = try? credentialStore.tossCredentials(for: source.id)
            return stored?.clientID == clientID
        }
    }

    /// 지갑 주소를 확인하고 잔고를 받아 본 뒤 연결한다. 받지 못하면 아무것도 저장하지 않는다.
    func connectWallet(
        kind: WalletConfig.Kind,
        name: String,
        addresses: [String],
        chains: [EVMChain]
    ) async -> Result<UUID, LinkFailure> {
        var seen = Set<String>()
        let cleaned = addresses
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        let valid = kind == .bitcoin ? WalletConfig.isBitcoinAddress : WalletConfig.isEVMAddress
        guard !cleaned.isEmpty, cleaned.allSatisfy(valid), kind == .bitcoin || !chains.isEmpty else {
            return .failure(.invalidAddress)
        }
        guard !isWalletLinked(cleaned) else { return .failure(.alreadyLinked) }
        guard let prices = cryptoPrices else { return .failure(.server("no-prices")) }

        let config = WalletConfig(kind: kind, addresses: cleaned, chains: kind == .evm ? chains : [])
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = LinkedSource(
            kind: kind == .bitcoin ? .bitcoinWallet : .evmWallet,
            name: trimmedName.isEmpty ? t(kind == .bitcoin ? "Bitcoin wallet" : "EVM wallet") : trimmedName,
            label: config.label
        )
        do {
            let snapshot = try await WalletConnector.fetch(config: config, sourceID: source.id, http: linkHTTP, prices: prices)
            // 받는 사이 같은 주소가 먼저 연결됐을 수 있다.
            guard !isWalletLinked(cleaned) else { return .failure(.alreadyLinked) }
            try credentialStore.save(config, for: source.id)
            document.sources.append(source)
            persist()
            lastLinkSyncAttempt[source.id] = Date()
            receive(snapshot, for: source.id, firstSync: true)
            linkStatus[source.id] = .synced(Date())
            return .success(source.id)
        } catch {
            return .failure(LinkFailure(error))
        }
    }

    private func isWalletLinked(_ addresses: [String]) -> Bool {
        let wanted = Set(addresses.map { $0.lowercased() })
        return document.sources.contains { source in
            guard source.kind == .bitcoinWallet || source.kind == .evmWallet,
                  let config = try? credentialStore.walletConfig(for: source.id)
            else { return false }
            return config.addresses.contains { wanted.contains($0.lowercased()) }
        }
    }

    /// 연결 해제 — 키·주소, 가져온 거래, 이 연결에서만 거래가 있던 자산을 지운다.
    /// 지갑으로 옮겼던 직접 입력분은 이동 기록이 지워지면서 직접 입력분으로 돌아온다.
    func disconnectSource(id: UUID) {
        let removedAssets = assetsOnlyIn(sourceID: id)
        credentialStore.delete(for: id)
        tossClients[id] = nil
        linkStatus[id] = nil
        pendingImports[id] = nil
        linkMismatches[id] = nil
        linkSkippedTrades[id] = nil
        lastLinkSyncAttempt[id] = nil
        document.trades.removeAll { $0.sourceID == id || $0.transferSourceID == id }
        for assetID in removedAssets {
            LogoStore.delete(fileName: asset(id: assetID)?.customLogoFileName)
            quotes[assetID] = nil
            staleAssetIDs.remove(assetID)
            document.settings.hiddenHomeChartAssetIDs.removeAll { $0 == assetID }
        }
        document.assets.removeAll { removedAssets.contains($0.id) }
        document.sources.removeAll { $0.id == id }
        persist()
        invalidateHomeChart()
        updateMenuBarTitle()
    }

    /// 거래가 전부 이 연결에서 온 자산(지갑 이동의 직접 입력 쪽 포함).
    func assetsOnlyIn(sourceID: UUID) -> Set<UUID> {
        let belongs: (Trade) -> Bool = { $0.sourceID == sourceID || $0.transferSourceID == sourceID }
        let bySource = Set(document.trades.filter(belongs).map(\.assetID))
        return bySource.filter { assetID in
            document.trades.allSatisfy { $0.assetID != assetID || belongs($0) }
        }
    }

    func importedTradeCount(sourceID: UUID) -> Int {
        document.trades.filter { $0.sourceID == sourceID }.count
    }

    /// 이 연결에 지금 남아 있는 종목 수.
    func heldAssetCount(sourceID: UUID) -> Int {
        Dictionary(grouping: document.trades.filter { $0.sourceID == sourceID }, by: \.assetID)
            .values
            .filter { PositionCalculator.snapshot(trades: $0).quantity > 0 }
            .count
    }

    func disconnectMessage(_ source: LinkedSource) -> String {
        let trades = importedTradeCount(sourceID: source.id)
        let assets = assetsOnlyIn(sourceID: source.id).count
        let message = t("The keys, \(trades) imported trade(s), and \(assets) asset(s) held only in this account will be deleted.")
        guard document.trades.contains(where: { $0.sourceID == nil && $0.transferSourceID == source.id }) else {
            return message
        }
        return message + "\n" + t("Coins moved from your manual holdings go back to them.")
    }

    /// 지울 데이터에 딸린 키를 키체인에서 지운다 — 전체 삭제·백업 복원 때.
    func forgetCredentials(keeping kept: Set<UUID> = []) {
        for source in document.sources where !kept.contains(source.id) {
            credentialStore.delete(for: source.id)
        }
        tossClients = [:]
        linkStatus = [:]
        pendingImports = [:]
        linkMismatches = [:]
        linkSkippedTrades = [:]
        lastLinkSyncAttempt = [:]
        // 이미 받고 있던 동기화 결과가 바뀐 문서에 들어가지 않게 한다.
        linkGeneration += 1
    }

    // MARK: - 동기화

    /// 갱신 주기마다 불린다. 검토를 기다리는 연결은 사용자가 볼 때까지 다시 부르지 않는다.
    func syncLinkedSources(now: Date = Date()) async {
        for source in document.sources where pendingImports[source.id] == nil {
            if let last = lastLinkSyncAttempt[source.id], now.timeIntervalSince(last) < Self.linkSyncInterval {
                continue
            }
            await syncSource(id: source.id)
        }
    }

    /// 한 연결을 동기화한다. 처음 가져올 때는 검토 화면에 올리고, 그 뒤로는 바로 반영한다.
    func syncSource(id: UUID) async {
        guard let source = document.source(id: id), linkStatus[id] != .syncing else { return }
        let generation = linkGeneration
        lastLinkSyncAttempt[id] = Date()
        linkStatus[id] = .syncing
        do {
            let snapshot = try await fetchSnapshot(source)
            // 받는 사이에 연결을 해제했거나 데이터를 지우고 복원했으면 버린다.
            guard generation == linkGeneration, let current = document.source(id: id) else { return }
            receive(snapshot, for: id, firstSync: current.lastSyncedAt == nil)
            linkStatus[id] = .synced(Date())
        } catch {
            guard generation == linkGeneration, document.source(id: id) != nil else { return }
            linkStatus[id] = .failed(LinkFailure(error))
        }
    }

    /// 받은 스냅샷을 계획한다. 처음 가져올 때는 검토 화면에 올리고, 그 뒤로는 바로 반영한다.
    private func receive(_ snapshot: SourceSnapshot, for id: UUID, firstSync: Bool) {
        let plan = ImportPlanner.plan(snapshot: snapshot, document: document)
        linkMismatches[id] = plan.unresolved
        if firstSync, !plan.trades.isEmpty || !plan.duplicates.isEmpty {
            pendingImports[id] = PendingImport(snapshot: snapshot, plan: plan)
        } else {
            applyImport(plan, syncedAt: snapshot.takenAt)
        }
    }

    private func fetchSnapshot(_ source: LinkedSource) async throws -> SourceSnapshot {
        switch source.kind {
        case .toss:
            guard let credentials = try credentialStore.tossCredentials(for: source.id),
                  let accountSeq = credentials.accountSeq
            else { throw LinkFailure.missingCredentials }
            let client = tossClients[source.id] ?? TossClient(credentials: credentials, http: linkHTTP)
            tossClients[source.id] = client
            return try await TossConnector.fetch(
                client: client, sourceID: source.id,
                accountSeq: accountSeq, since: source.lastSyncedAt
            )
        case .bitcoinWallet, .evmWallet:
            guard let config = try credentialStore.walletConfig(for: source.id) else {
                throw LinkFailure.missingCredentials
            }
            guard let prices = cryptoPrices else { throw LinkFailure.server("no-prices") }
            return try await WalletConnector.fetch(config: config, sourceID: source.id, http: linkHTTP, prices: prices)
        case .koreaInvestment:
            throw LinkFailure.server("unsupported")
        }
    }

    // MARK: - 적용

    /// 계획대로 넣는다. 없는 종목은 자산을 먼저 만든다(자산 한도까지).
    /// - syncedAt: 스냅샷을 받은 시각 — 다음 동기화가 이 시각 기준으로 주문을 다시 받는다.
    @discardableResult
    func applyImport(_ plan: ImportPlan, syncedAt: Date) -> ImportResult {
        let previousSync = document.source(id: plan.sourceID)?.lastSyncedAt
        var assetIDs: [ImportInstrument: UUID] = [:]
        for instrument in plan.missingAssets {
            guard !isAtAssetLimit else { break }
            let asset = makeAsset(for: instrument)
            document.assets.append(asset)
            assetIDs[instrument] = asset.id
        }
        let result = ImportApplier.apply(plan, to: &document, assetIDs: assetIDs, now: syncedAt)
        pendingImports[plan.sourceID] = nil
        linkSkippedTrades[plan.sourceID] = result.skippedWithoutAsset > 0 ? result.skippedWithoutAsset : nil
        if result.skippedWithoutAsset > 0, let index = document.sources.firstIndex(where: { $0.id == plan.sourceID }) {
            // 자산 한도로 못 넣은 거래가 있으면 동기화 시점을 앞당기지 않는다 — 자리가 나면 다시 받는다.
            document.sources[index].lastSyncedAt = previousSync
        }
        persist()
        guard result.added + result.openingBalances + result.merged > 0 || !assetIDs.isEmpty else { return result }
        invalidateHomeChart()
        updateMenuBarTitle()
        if !assetIDs.isEmpty {
            Task { await refreshQuotes() }
        }
        return result
    }

    /// 검토한 가져오기를 적용한다. 검토하는 사이 직접 입력 거래가 바뀌었을 수 있어 지금 문서로 다시 계획한다.
    func applyPendingImport(sourceID: UUID) {
        guard let pending = pendingImports[sourceID] else { return }
        let plan = ImportPlanner.plan(snapshot: pending.snapshot, document: document)
        linkMismatches[sourceID] = plan.unresolved
        applyImport(plan, syncedAt: pending.snapshot.takenAt)
        // 검토를 오래 미뤘으면 그사이 생긴 주문을 바로 받아 온다.
        if Date().timeIntervalSince(pending.snapshot.takenAt) > Self.linkSyncInterval {
            Task { await syncSource(id: sourceID) }
        }
    }

    /// 자산 한도 때문에 새로 만들 수 없는 종목 수.
    func assetsOverLimit(_ plan: ImportPlan) -> Int {
        max(0, plan.missingAssets.count - max(0, Self.assetSoftLimit - document.assets.count))
    }

    private func makeAsset(for instrument: ImportInstrument) -> Asset {
        let provider: ProviderKind
        let providerSymbol: String
        switch instrument.market {
        case .koreaStock: (provider, providerSymbol) = (.naver, instrument.symbol)
        case .crypto: (provider, providerSymbol) = (.binance, "\(instrument.symbol)USDT")
        default: (provider, providerSymbol) = (.yahoo, instrument.symbol)
        }
        return Asset(
            name: instrument.name,
            symbol: instrument.symbol,
            provider: provider,
            providerSymbol: providerSymbol,
            market: instrument.market,
            currency: instrument.currency,
            colorIndex: nextColorIndex()
        )
    }

    // MARK: - 도움

    /// 허용 IP 등록을 돕는 공인 IP 확인 — 사용자가 버튼을 누를 때만 부른다.
    func currentPublicIP() async -> String? {
        guard let data = try? await URLSessionHTTPClient().get(URL(string: "https://api.ipify.org")!) else {
            return nil
        }
        let ip = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return ip.isEmpty || ip.count > 45 ? nil : ip
    }

    func openTossDocs() {
        NSWorkspace.shared.open(tossDocsURL)
    }

    func linkFailureText(_ failure: LinkFailure) -> String {
        switch failure {
        case .invalidCredentials:
            return t("The client ID or secret is wrong. Copy them again from Toss Securities WTS.")
        case .ipNotAllowed:
            return t("This network's IP isn't on Toss Securities' allowed list. Add it in WTS › Settings › Open API › Allowed IPs.")
        case .rateLimited:
            return t("Too many requests. Try again in a moment.")
        case .noAccount:
            return t("No brokerage account was found.")
        case .alreadyLinked:
            return t("These keys are already linked.")
        case .missingCredentials:
            return t("The link details aren't on this Mac. Disconnect and link again.")
        case .keychain:
            return t("Couldn't read or save the keychain item.")
        case .network:
            return t("Couldn't connect. Check your internet connection.")
        case .invalidAddress:
            return t("Check the address. Pick at least one chain for an EVM wallet.")
        case .walletUnavailable(let chain):
            return t("\(chain) didn't return every balance, so this sync was skipped.")
        case .server(let code):
            return t("The service returned an error (\(code)).")
        }
    }

    func mismatchText(_ mismatch: HoldingMismatch) -> String {
        switch mismatch.reason {
        case .historyExceedsHolding where mismatch.adjusted:
            return t("The account holds less than its history shows, like after a transfer out or an after-hours sale. A balance adjustment at the average cost matches it.")
        case .holdingExceedsHistory where mismatch.adjusted:
            return t("The account holds more than its history shows, like after a transfer in or a split. A balance adjustment matches it.")
        case .historyExceedsHolding:
            return t("The account holds less than its history shows, likely a transfer out.")
        case .missingAverageCost:
            return t("The account didn't give an average cost, so no opening balance was added.")
        case .holdingExceedsHistory:
            return t("The account holds more than its history shows, likely a transfer in.")
        case .manualTradesMayOverlap:
            return t("You entered trades for this manually, so no opening balance was added to avoid counting it twice. Delete those trades to match the account on the next sync.")
        }
    }
}
