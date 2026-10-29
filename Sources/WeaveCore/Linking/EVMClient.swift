import Foundation

/// EVM 잔고 조회 — 체인 공개 RPC에 Multicall3 한 번으로 가스 코인과 토큰 잔고를 함께 읽는다.
public struct EVMClient: Sendable {
    /// 모든 지원 체인에 같은 주소로 배포된 Multicall3.
    static let multicall = "0xca11bde05977b3631167028862be2a173976ca11"
    /// 한 번에 묶는 호출 수 — 공개 RPC의 eth_call 한도 안에서.
    static let batchSize = 150

    private let http: any HTTPSending

    public init(http: any HTTPSending) {
        self.http = http
    }

    /// 심볼별 잔고. 같은 심볼(USDC·USDC.e 등)은 합친다.
    public func balances(owner: String, chain: EVMChain, tokens: [EVMToken]) async throws -> [String: Decimal] {
        guard WalletConfig.isEVMAddress(owner) else { throw WalletError.invalidResponse }
        // 가스 코인은 Multicall3의 getEthBalance로 함께 읽는다.
        let calls = [(target: Self.multicall, data: Self.getEthBalance(owner), symbol: chain.nativeSymbol, decimals: 18)]
            + tokens.map { (target: $0.contract, data: Self.balanceOf(owner), symbol: $0.symbol, decimals: $0.decimals) }

        var amounts: [String: Decimal] = [:]
        // 금고 토큰 지분 — 원금으로 바꾼 뒤 더한다. 지분 워드를 그대로 다음 convertToAssets 인자로 넘긴다.
        var shares: [(token: EVMToken, word: Data)] = []
        let vaults = Dictionary(tokens.map { ($0.contract, $0) }, uniquingKeysWith: { first, _ in first })
        for start in stride(from: 0, to: calls.count, by: Self.batchSize) {
            let batch = Array(calls[start..<min(start + Self.batchSize, calls.count)])
            let results = try await aggregate(batch.map { ($0.target, $0.data) }, chain: chain)
            guard results.count == batch.count else { throw WalletError.invalidResponse }
            for (call, result) in zip(batch, results) {
                guard result.success, let raw = Self.uint(result.data) else {
                    throw WalletError.partialFailure(chain: chain.name)
                }
                guard raw > 0 else { continue }
                if let vault = vaults[call.target], !vault.vaultPath.isEmpty {
                    shares.append((vault, result.data))
                    continue
                }
                amounts[call.symbol, default: 0] += raw / Self.power(of: call.decimals)
            }
        }
        for (token, word) in shares {
            var current = word
            for vault in token.vaultPath {
                let results = try await aggregate([(vault, Self.convertToAssets(current))], chain: chain)
                guard let result = results.first, result.success, result.data.count == 32 else {
                    throw WalletError.partialFailure(chain: chain.name)
                }
                current = result.data
            }
            guard let raw = Self.uint(current) else { throw WalletError.invalidResponse }
            amounts[token.symbol, default: 0] += raw / Self.power(of: token.decimals)
        }
        return amounts
    }

    private func aggregate(_ calls: [(target: String, data: Data)], chain: EVMChain) async throws -> [(success: Bool, data: Data)] {
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "eth_call",
            "params": [["to": Self.multicall, "data": "0x" + Self.aggregate3(calls).hex], "latest"]
        ]
        var request = URLRequest(url: chain.rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, status) = try await http.send(request)
        guard 200..<300 ~= status else { throw HTTPError.badStatus(status) }

        struct Response: Decodable {
            struct RPCError: Decodable { var message: String }
            var result: String?
            var error: RPCError?
        }
        guard
            let response = try? JSONDecoder().decode(Response.self, from: data),
            let hex = response.result,
            let encoded = Data(hex: hex),
            let results = Self.decodeAggregate3(encoded)
        else { throw WalletError.invalidResponse }
        return results
    }

    // MARK: - ABI

    /// balanceOf(address)
    static func balanceOf(_ owner: String) -> Data {
        Data(hex: "70a08231")! + word(address: owner)
    }

    /// ERC-4626 convertToAssets(uint256) — 인자는 받은 32바이트 워드 그대로.
    static func convertToAssets(_ shares: Data) -> Data {
        Data(hex: "07a2d13a")! + shares
    }

    /// Multicall3.getEthBalance(address)
    static func getEthBalance(_ owner: String) -> Data {
        Data(hex: "4d2301cc")! + word(address: owner)
    }

    /// aggregate3((address target, bool allowFailure, bytes callData)[])
    static func aggregate3(_ calls: [(target: String, data: Data)]) -> Data {
        var heads = Data()
        var tails = Data()
        let headSize = calls.count * 32
        for call in calls {
            heads += word(UInt64(headSize + tails.count))
            tails += word(address: call.target)
            tails += word(1) // 실패해도 나머지를 돌려받고 여기서 판단한다.
            tails += word(0x60)
            tails += word(UInt64(call.data.count))
            tails += padded(call.data)
        }
        return Data(hex: "82ad56cb")! + word(0x20) + word(UInt64(calls.count)) + heads + tails
    }

    /// (bool success, bytes returnData)[]
    /// 응답은 RPC가 주는 대로라 모든 오프셋·길이를 응답 크기 안으로 묶어 읽는다 — 깨진 응답이 크래시가 되지 않게.
    static func decodeAggregate3(_ data: Data) -> [(success: Bool, data: Data)]? {
        let bytes = [UInt8](data)
        /// 응답 길이를 넘지 않는 작은 값만 받는다. 넘으면 깨진 응답.
        func readWord(_ offset: Int) -> Int? {
            guard offset >= 0, offset <= bytes.count - 32 else { return nil }
            guard bytes[offset..<(offset + 24)].allSatisfy({ $0 == 0 }) else { return nil }
            let value = bytes[(offset + 24)..<(offset + 32)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            return value <= UInt64(bytes.count) ? Int(value) : nil
        }
        func add(_ lhs: Int, _ rhs: Int) -> Int? {
            lhs <= bytes.count - rhs ? lhs + rhs : nil
        }
        guard
            bytes.count >= 64,
            let arrayOffset = readWord(0),
            let count = readWord(arrayOffset),
            let headStart = add(arrayOffset, 32),
            count <= (bytes.count - headStart) / 32
        else { return nil }
        var results: [(Bool, Data)] = []
        for index in 0..<count {
            guard
                let elementOffset = readWord(headStart + index * 32),
                let element = add(headStart, elementOffset),
                let success = readWord(element),
                let successWord = add(element, 32),
                let bytesOffset = readWord(successWord),
                let lengthAt = add(element, bytesOffset),
                let length = readWord(lengthAt),
                let start = add(lengthAt, 32),
                let end = add(start, length)
            else { return nil }
            results.append((success == 1, Data(bytes[start..<end])))
        }
        return results
    }

    /// uint256 → Decimal. 실제 잔고는 38자리 안에 들어온다.
    static func uint(_ data: Data) -> Decimal? {
        guard data.count == 32 else { return nil }
        return data.reduce(Decimal(0)) { $0 * 256 + Decimal($1) }
    }

    static func power(of decimals: Int) -> Decimal {
        var value = Decimal(1)
        for _ in 0..<decimals { value *= 10 }
        return value
    }

    private static func word(_ value: UInt64) -> Data {
        Data(repeating: 0, count: 24) + withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    /// 주소는 `WalletConfig.isEVMAddress`로 확인된 것만 들어온다.
    private static func word(address: String) -> Data {
        let hex = address.lowercased().hasPrefix("0x") ? String(address.dropFirst(2)) : address
        guard let raw = Data(hex: hex), raw.count == 20 else {
            preconditionFailure("unchecked EVM address")
        }
        return Data(repeating: 0, count: 12) + raw
    }

    private static func padded(_ data: Data) -> Data {
        let remainder = data.count % 32
        return remainder == 0 ? data : data + Data(repeating: 0, count: 32 - remainder)
    }
}

extension Data {
    /// "0x"를 떼고 16진수 문자열을 바이트로. 홀수 길이나 16진수가 아니면 nil.
    init?(hex: String) {
        let digits = hex.hasPrefix("0x") ? Array(hex.dropFirst(2)) : Array(hex)
        guard digits.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        var index = 0
        while index < digits.count {
            guard let byte = UInt8(String(digits[index...index + 1]), radix: 16) else { return nil }
            bytes.append(byte)
            index += 2
        }
        self.init(bytes)
    }

    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
