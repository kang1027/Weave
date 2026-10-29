import Foundation

/// `Application Support/Weave/portfolio.json`에 저장되는 루트 문서.
public struct PortfolioDocument: Codable, Equatable, Sendable {
    /// 이 앱이 읽을 수 있는 최신 버전. v3 = 연결한 계좌·지갑(`sources`)과 가져온 거래 필드.
    public static let currentVersion = 3

    public var version: Int
    public var assets: [Asset]
    public var trades: [Trade]
    public var settings: AppSettings
    /// 연결한 계좌·지갑. 옛 저장파일엔 없다.
    public var sources: [LinkedSource]

    public init(
        version: Int = PortfolioDocument.currentVersion,
        assets: [Asset] = [],
        trades: [Trade] = [],
        settings: AppSettings = AppSettings(),
        sources: [LinkedSource] = []
    ) {
        self.version = version
        self.assets = assets
        self.trades = trades
        self.settings = settings
        self.sources = sources
    }

    private enum CodingKeys: String, CodingKey {
        case version, assets, trades, settings, sources
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        assets = try c.decode([Asset].self, forKey: .assets)
        trades = try c.decode([Trade].self, forKey: .trades)
        settings = try c.decode(AppSettings.self, forKey: .settings)
        sources = try c.decodeIfPresent([LinkedSource].self, forKey: .sources) ?? []
    }

    /// 저장할 때 쓰는 버전 — 연결 데이터가 없으면 v2로 써서 v0.1.x 앱도 그대로 읽게 하고,
    /// 있으면 v3로 써서 옛 앱이 모르는 필드를 지운 채 덮어쓰지 않고 거부하게 한다.
    /// `LinkedSourceKind`에 종류를 더할 때도 버전을 올려야 한다(옛 앱은 모르는 값에서 디코딩이 실패한다).
    public var storageVersion: Int {
        sources.isEmpty && !trades.contains(where: \.isImported) ? 2 : PortfolioDocument.currentVersion
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(storageVersion, forKey: .version)
        try c.encode(assets, forKey: .assets)
        try c.encode(trades, forKey: .trades)
        try c.encode(settings, forKey: .settings)
        if !sources.isEmpty { try c.encode(sources, forKey: .sources) }
    }

    public func source(id: UUID) -> LinkedSource? {
        sources.first { $0.id == id }
    }

    public static let empty = PortfolioDocument()

    public func trades(for assetID: UUID) -> [Trade] {
        trades.filter { $0.assetID == assetID }
    }
}
