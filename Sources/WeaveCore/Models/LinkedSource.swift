import Foundation

/// 연결한 계좌·지갑 종류. 업비트는 키 발급에 고정 IP가 필요해서 넣지 않았다.
public enum LinkedSourceKind: String, Codable, Sendable, CaseIterable {
    case koreaInvestment
    case toss
    case bitcoinWallet
    case evmWallet
}

/// 거래를 가져오는 연결 하나. 키·전체 주소는 키체인에 두고 문서엔 표시용 요약만 남긴다.
public struct LinkedSource: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var kind: LinkedSourceKind
    /// 표시 이름 — "한국투자증권", "콜드 월렛"
    public var name: String
    /// 표시용 계좌·주소 요약 — "6412****-01", "bc1q…x8f0"
    public var label: String
    public var lastSyncedAt: Date?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: LinkedSourceKind,
        name: String,
        label: String,
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.label = label
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
    }
}
