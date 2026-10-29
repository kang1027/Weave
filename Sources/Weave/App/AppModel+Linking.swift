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
    /// 다른 Mac에서 가져온 백업처럼 문서엔 연결이 있는데 이 Mac 키체인에 키가 없다.
    case missingCredentials
    case keychain
    case network
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
        case is CredentialStoreError: self = .keychain
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
        // 같은 키를 두 번 연결하면 같은 체결이 두 번 들어간다.
        let linked = document.sources.filter { $0.kind == .toss }.compactMap {
            credentialStore.tossCredentials(for: $0.id)?.clientID
        }
        guard !linked.contains(credentials.clientID) else { return .failure(.alreadyLinked) }

        let client = TossClient(credentials: credentials, http: linkHTTP)
        do {
            guard let account = try await client.accounts().first else { return .failure(.noAccount) }
            let source = LinkedSource(
                kind: .toss,
                name: t("Toss Securities"),
                label: TossConnector.maskedAccount(account.accountNo)
            )
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

    /// 연결 해제 — 키, 가져온 거래, 이 연결에서만 거래가 있던 자산을 지운다.
    func disconnectSource(id: UUID) {
        let removedAssets = assetsOnlyIn(sourceID: id)
        credentialStore.delete(for: id)
        tossClients[id] = nil
        linkStatus[id] = nil
        pendingImports[id] = nil
        linkMismatches[id] = nil
        lastLinkSyncAttempt[id] = nil
        document.trades.removeAll { $0.sourceID == id }
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

    /// 거래가 전부 이 연결에서 온 자산.
    func assetsOnlyIn(sourceID: UUID) -> Set<UUID> {
        let bySource = Set(document.trades.filter { $0.sourceID == sourceID }.map(\.assetID))
        return bySource.filter { assetID in
            document.trades.allSatisfy { $0.assetID != assetID || $0.sourceID == sourceID }
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
        return t("The keys, \(trades) imported trade(s), and \(assets) asset(s) held only in this account will be deleted.")
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
        lastLinkSyncAttempt = [:]
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
        lastLinkSyncAttempt[id] = Date()
        linkStatus[id] = .syncing
        do {
            let snapshot = try await fetchSnapshot(source)
            // 받는 사이에 연결을 해제했으면 버린다.
            guard let current = document.source(id: id) else { return }
            let plan = ImportPlanner.plan(snapshot: snapshot, document: document)
            linkMismatches[id] = plan.mismatches
            if current.lastSyncedAt == nil, !plan.trades.isEmpty || !plan.duplicates.isEmpty {
                pendingImports[id] = PendingImport(snapshot: snapshot, plan: plan)
            } else {
                applyImport(plan)
            }
            linkStatus[id] = .synced(Date())
        } catch {
            guard document.source(id: id) != nil else { return }
            linkStatus[id] = .failed(LinkFailure(error))
        }
    }

    private func fetchSnapshot(_ source: LinkedSource) async throws -> SourceSnapshot {
        switch source.kind {
        case .toss:
            guard let credentials = credentialStore.tossCredentials(for: source.id),
                  let accountSeq = credentials.accountSeq
            else { throw LinkFailure.missingCredentials }
            let client = tossClients[source.id] ?? TossClient(credentials: credentials, http: linkHTTP)
            tossClients[source.id] = client
            return try await TossConnector.fetch(
                client: client, sourceID: source.id,
                accountSeq: accountSeq, since: source.lastSyncedAt
            )
        case .koreaInvestment, .bitcoinWallet, .evmWallet:
            throw LinkFailure.server("unsupported")
        }
    }

    // MARK: - 적용

    /// 계획대로 넣는다. 없는 종목은 자산을 먼저 만든다(자산 한도까지).
    @discardableResult
    func applyImport(_ plan: ImportPlan) -> ImportResult {
        var assetIDs: [ImportInstrument: UUID] = [:]
        for instrument in plan.missingAssets {
            guard !isAtAssetLimit else { break }
            let asset = makeAsset(for: instrument)
            document.assets.append(asset)
            assetIDs[instrument] = asset.id
        }
        let result = ImportApplier.apply(plan, to: &document, assetIDs: assetIDs)
        pendingImports[plan.sourceID] = nil
        persist()
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
        linkMismatches[sourceID] = plan.mismatches
        applyImport(plan)
    }

    private func makeAsset(for instrument: ImportInstrument) -> Asset {
        let provider: ProviderKind = instrument.market == .koreaStock ? .naver : .yahoo
        return Asset(
            name: instrument.name,
            symbol: instrument.symbol,
            provider: provider,
            providerSymbol: instrument.symbol,
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
            return t("The keys aren't on this Mac. Disconnect and link again.")
        case .keychain:
            return t("Couldn't save the keys to the keychain.")
        case .network:
            return t("Couldn't reach Toss Securities. Check your connection.")
        case .server(let code):
            return t("Toss Securities returned an error (\(code)).")
        }
    }

    func mismatchText(_ mismatch: HoldingMismatch) -> String {
        switch mismatch.reason {
        case .historyExceedsHolding:
            return t("The account holds less than its history shows, likely a transfer out.")
        case .missingAverageCost:
            return t("The account didn't give an average cost, so no opening balance was added.")
        case .holdingExceedsHistory:
            return t("The account holds more than its history shows, likely a transfer in.")
        case .manualTradesMayOverlap:
            return t("You entered trades for this manually, so no opening balance was added to avoid counting it twice.")
        }
    }
}
