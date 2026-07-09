import Foundation

/// `Application Support/Weave/portfolio.json`에 저장되는 루트 문서.
public struct PortfolioDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var assets: [Asset]
    public var trades: [Trade]
    public var settings: AppSettings

    public init(
        version: Int = PortfolioDocument.currentVersion,
        assets: [Asset] = [],
        trades: [Trade] = [],
        settings: AppSettings = AppSettings()
    ) {
        self.version = version
        self.assets = assets
        self.trades = trades
        self.settings = settings
    }

    public static let empty = PortfolioDocument()

    public func trades(for assetID: UUID) -> [Trade] {
        trades.filter { $0.assetID == assetID }
    }
}
