import Foundation

public struct SearchResult: Identifiable, Equatable, Hashable, Sendable {
    public var provider: ProviderKind
    public var providerSymbol: String
    /// 표시 심볼 — "BTC", "005930", "AAPL"
    public var symbol: String
    public var name: String
    public var market: Market
    /// 검색 단계에서 확정 가능한 통화. Yahoo는 추가 시 quote로 확정한다.
    public var currency: String?

    public var id: String { "\(provider.rawValue):\(providerSymbol)" }

    public init(
        provider: ProviderKind,
        providerSymbol: String,
        symbol: String,
        name: String,
        market: Market,
        currency: String? = nil
    ) {
        self.provider = provider
        self.providerSymbol = providerSymbol
        self.symbol = symbol
        self.name = name
        self.market = market
        self.currency = currency
    }
}
