import Foundation

/// 지갑 연결이 보는 EVM 체인. 잔고는 체인마다 공개 RPC로 직접 읽는다.
public enum EVMChain: String, Codable, Sendable, CaseIterable {
    case ethereum
    case arbitrum
    case base
    case optimism
    case polygon

    public var name: String {
        switch self {
        case .ethereum: return "Ethereum"
        case .arbitrum: return "Arbitrum"
        case .base: return "Base"
        case .optimism: return "Optimism"
        case .polygon: return "Polygon"
        }
    }

    /// 가스 코인의 바이낸스 심볼.
    public var nativeSymbol: String { self == .polygon ? "POL" : "ETH" }

    /// 키 없이 쓸 수 있는 공개 RPC.
    var rpcURL: URL {
        switch self {
        case .ethereum: return URL(string: "https://ethereum-rpc.publicnode.com")!
        case .arbitrum: return URL(string: "https://arb1.arbitrum.io/rpc")!
        case .base: return URL(string: "https://mainnet.base.org")!
        case .optimism: return URL(string: "https://mainnet.optimism.io")!
        case .polygon: return URL(string: "https://polygon-bor-rpc.publicnode.com")!
        }
    }
}

/// 잔고를 읽을 ERC-20 토큰. 목록은 `EVMTokenList.swift`에서 생성한다.
public struct EVMToken: Equatable, Sendable {
    public var chain: EVMChain
    public var contract: String
    /// 바이낸스 심볼 — WETH는 ETH로 맞춰 둔다.
    public var symbol: String
    public var decimals: Int
}

/// 지갑 연결 설정. 주소는 키처럼 키체인에 두고 문서엔 줄인 주소만 남긴다.
public struct WalletConfig: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case bitcoin
        case evm
    }

    public var kind: Kind
    /// 비트코인은 여러 주소를 한 지갑으로 묶는다. EVM은 주소 하나.
    public var addresses: [String]
    /// EVM만 — 잔고를 읽을 체인.
    public var chains: [EVMChain]

    public init(kind: Kind, addresses: [String], chains: [EVMChain] = []) {
        self.kind = kind
        self.addresses = addresses
        self.chains = chains
    }

    /// 표시용 요약 — "bc1q…x8f0 +1", "0x7a3f…91c2". 연결 목록 한 줄에 종목·거래 수와 같이 들어가서 짧게 둔다.
    public var label: String {
        guard let first = addresses.first else { return "" }
        let short = Self.shortAddress(first)
        return addresses.count > 1 ? "\(short) +\(addresses.count - 1)" : short
    }

    public static func shortAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }

    // MARK: - 주소 확인

    /// 0x + ASCII 16진수 40자리(전각 숫자 등은 받지 않는다).
    public static func isEVMAddress(_ address: String) -> Bool {
        address.count == 42 && address.hasPrefix("0x")
            && address.dropFirst(2).allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    /// 메인넷 주소 형식만 본다(체크섬은 조회 서비스가 거른다). 테스트넷 주소는 받지 않는다.
    public static func isBitcoinAddress(_ address: String) -> Bool {
        let lower = address.lowercased()
        if lower.hasPrefix("bc1") {
            let bech32 = Set("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
            return (14...90).contains(address.count)
                && (address == lower || address == address.uppercased())
                && lower.dropFirst(3).allSatisfy { bech32.contains($0) }
        }
        let base58 = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        return (address.hasPrefix("1") || address.hasPrefix("3"))
            && (25...35).contains(address.count)
            && address.allSatisfy { base58.contains($0) }
    }
}

public enum WalletError: Error, Equatable, Sendable {
    case invalidResponse
    /// 토큰 잔고 조회 일부가 실패했다 — 0으로 보면 지갑에서 빠져나간 걸로 기록되니 동기화를 멈춘다.
    case partialFailure(chain: String)
}

/// 코인 시세 출처 — 바이낸스 USDT 마켓.
public protocol CryptoPriceSource: Sendable {
    /// 심볼별 현재가(USD). USDT 마켓이 없거나 거래가 멈춘 코인은 빠진다.
    func prices(baseAssets: [String]) async throws -> [String: Decimal]
}
