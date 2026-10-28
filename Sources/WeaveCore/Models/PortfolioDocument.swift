import Foundation

/// `Application Support/Weave/portfolio.json`에 저장되는 루트 문서.
public struct PortfolioDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 2

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

    public func source(id: UUID) -> LinkedSource? {
        sources.first { $0.id == id }
    }

    public static let empty = PortfolioDocument()

    public func trades(for assetID: UUID) -> [Trade] {
        trades.filter { $0.assetID == assetID }
    }
}
