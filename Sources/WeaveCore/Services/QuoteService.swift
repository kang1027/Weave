import Foundation

/// 자산 전체 시세를 병렬로 갱신. 실패한 자산은 결과에서 빠진다(마지막 값 유지는 앱 상태 몫).
public struct QuoteService: Sendable {
    private let providers: [ProviderKind: any MarketDataProvider]

    public init(providers: [any MarketDataProvider]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.kind, $0) })
    }

    public func quote(for asset: Asset) async throws -> Quote {
        guard !asset.isManual, let provider = providers[asset.provider] else {
            throw ProviderError.unsupportedSymbol(asset.providerSymbol)
        }
        return try await provider.quote(providerSymbol: asset.providerSymbol)
    }

    public func quotes(for assets: [Asset]) async -> [UUID: Quote] {
        await withTaskGroup(of: (UUID, Quote?).self) { group in
            for asset in assets where !asset.isManual {
                group.addTask {
                    (asset.id, try? await self.quote(for: asset))
                }
            }
            var result: [UUID: Quote] = [:]
            for await (id, quote) in group {
                if let quote {
                    result[id] = quote
                }
            }
            return result
        }
    }
}
