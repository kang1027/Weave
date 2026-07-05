import Foundation

public struct Asset: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    /// 표시 이름 — "Bitcoin", "삼성전자"
    public var name: String
    /// 표시 심볼 — "BTC", "005930", "AAPL"
    public var symbol: String
    public var provider: ProviderKind
    /// provider API에 넘기는 심볼 — "BTCUSDT", "005930", "AAPL"
    public var providerSymbol: String
    public var market: Market
    /// 상장 시장이 결정하는 소스 통화 — "USD", "KRW", "JPY" 등
    public var currency: String
    /// 팔레트 8색 인덱스. 추가 순서대로 자동 할당, 관리 화면에서 수동 변경.
    public var colorIndex: Int
    public var showInMenuBar: Bool
    /// 메뉴바 핀 고정 — 켜지면 로테이션 없이 이 자산만 표시.
    public var isPinned: Bool
    public var isHidden: Bool
    /// Manual Asset 평가액(자산 통화 기준). 시세 갱신 없음.
    public var manualValue: Decimal?
    /// Manual Asset을 통합 차트에 포함할지.
    public var includeInChart: Bool
    public var createdAt: Date

    public var isManual: Bool { provider == .manual }

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        provider: ProviderKind,
        providerSymbol: String,
        market: Market,
        currency: String,
        colorIndex: Int = 0,
        showInMenuBar: Bool = true,
        isPinned: Bool = false,
        isHidden: Bool = false,
        manualValue: Decimal? = nil,
        includeInChart: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.provider = provider
        self.providerSymbol = providerSymbol
        self.market = market
        self.currency = currency
        self.colorIndex = colorIndex
        self.showInMenuBar = showInMenuBar
        self.isPinned = isPinned
        self.isHidden = isHidden
        self.manualValue = manualValue
        self.includeInChart = includeInChart
        self.createdAt = createdAt
    }
}
