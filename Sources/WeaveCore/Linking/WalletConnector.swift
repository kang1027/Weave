import Foundation

/// 비트코인 잔고 — mempool.space 공개 API. 확정된 거래만 센다.
public struct BitcoinClient: Sendable {
    static let baseURL = URL(string: "https://mempool.space/api/address/")!

    private let http: any HTTPSending

    public init(http: any HTTPSending) {
        self.http = http
    }

    public func balance(addresses: [String]) async throws -> Decimal {
        struct Response: Decodable {
            struct Stats: Decodable {
                var funded_txo_sum: Int64
                var spent_txo_sum: Int64
            }
            var chain_stats: Stats
        }
        var satoshis: Int64 = 0
        for address in addresses {
            let (data, status) = try await http.send(URLRequest(url: Self.baseURL.appendingPathComponent(address)))
            guard 200..<300 ~= status else { throw HTTPError.badStatus(status) }
            guard let stats = try? JSONDecoder().decode(Response.self, from: data).chain_stats else {
                throw WalletError.invalidResponse
            }
            satoshis += stats.funded_txo_sum - stats.spent_txo_sum
        }
        return Decimal(satoshis) / 100_000_000
    }
}

/// 지갑 → 가져오기 스냅샷. 지갑엔 매수 기록이 없으니 잔고만 보내고, 평단은 플래너가
/// 직접 입력분에서 옮겨오거나 그때 시세로 잡는다.
public enum WalletConnector {
    /// 이보다 작은 잔고(USD)로는 새 코인을 들이지 않는다 — 에어드랍·잔돈 토큰이 자산 목록을 채우지 않게.
    static let dustValue: Decimal = 10

    public static func fetch(
        config: WalletConfig,
        sourceID: UUID,
        http: any HTTPSending,
        prices: any CryptoPriceSource,
        now: Date = Date()
    ) async throws -> SourceSnapshot {
        var amounts: [String: Decimal] = [:]
        switch config.kind {
        case .bitcoin:
            amounts["BTC"] = try await BitcoinClient(http: http).balance(addresses: config.addresses)
        case .evm:
            let client = EVMClient(http: http)
            for address in config.addresses {
                for chain in config.chains {
                    let tokens = EVMToken.known.filter { $0.chain == chain }
                    let balances = try await client.balances(owner: address, chain: chain, tokens: tokens)
                    amounts.merge(balances, uniquingKeysWith: +)
                }
            }
        }

        let symbols = amounts.filter { $0.value > 0 }.keys.sorted()
        let quotes = try await prices.prices(baseAssets: symbols)
        return snapshot(sourceID: sourceID, amounts: amounts, quotes: quotes, now: now)
    }

    static func snapshot(
        sourceID: UUID,
        amounts: [String: Decimal],
        quotes: [String: Decimal],
        now: Date
    ) -> SourceSnapshot {
        var holdings: [ImportedHolding] = []
        var unpriced: Set<ImportInstrument> = []
        var dust: Set<ImportInstrument> = []
        for symbol in amounts.keys.sorted() {
            guard let quantity = amounts[symbol], quantity > 0 else { continue }
            let instrument = ImportInstrument(
                market: .crypto, symbol: symbol, name: CryptoNames.name(for: symbol), currency: "USD"
            )
            // 잔고는 있는데 시세가 없다(상장 폐지·거래 중단) — 0으로 보면 지갑에서 다 빠진 걸로 기록되니 이번엔 건너뛴다.
            guard let price = quotes[symbol] else {
                unpriced.insert(instrument)
                continue
            }
            holdings.append(ImportedHolding(
                instrument: instrument, quantity: quantity, averageCost: nil, marketPrice: price
            ))
            if quantity * price < dustValue { dust.insert(instrument) }
        }
        return SourceSnapshot(
            sourceID: sourceID,
            holdings: holdings,
            executions: [],
            historyStart: now,
            unsettled: unpriced,
            takenAt: now,
            inheritsManualHoldings: true,
            dust: dust
        )
    }
}
