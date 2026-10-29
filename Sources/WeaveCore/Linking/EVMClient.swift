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
        // 가스 코인은 Multicall3의 getEthBalance로 함께 읽는다.
        let calls = [(target: Self.multicall, data: Self.getEthBalance(owner), symbol: chain.nativeSymbol, decimals: 18)]
            + tokens.map { (target: $0.contract, data: Self.balanceOf(owner), symbol: $0.symbol, decimals: $0.decimals) }

        var amounts: [String: Decimal] = [:]
        for start in stride(from: 0, to: calls.count, by: Self.batchSize) {
            let batch = Array(calls[start..<min(start + Self.batchSize, calls.count)])
            let results = try await aggregate(batch.map { ($0.target, $0.data) }, chain: chain)
            guard results.count == batch.count else { throw WalletError.invalidResponse }
            for (call, result) in zip(batch, results) {
                guard result.success, let raw = Self.uint(result.data) else {
                    throw WalletError.partialFailure(chain: chain.name)
                }
                guard raw > 0 else { continue }
                amounts[call.symbol, default: 0] += raw / Self.power(of: call.decimals)
            }
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
    static func decodeAggregate3(_ data: Data) -> [(success: Bool, data: Data)]? {
        let bytes = [UInt8](data)
        func readWord(_ offset: Int) -> Int? {
            guard offset >= 0, offset + 32 <= bytes.count else { return nil }
            // 오프셋·길이는 작다 — 앞 24바이트가 0이 아니면 깨진 응답.
            guard bytes[offset..<(offset + 24)].allSatisfy({ $0 == 0 }) else { return nil }
            return bytes[(offset + 24)..<(offset + 32)].reduce(0) { $0 << 8 | Int($1) }
        }
        guard let arrayOffset = readWord(0), let count = readWord(arrayOffset) else { return nil }
        let headStart = arrayOffset + 32
        var results: [(Bool, Data)] = []
        for index in 0..<count {
            guard
                let elementOffset = readWord(headStart + index * 32),
                let success = readWord(headStart + elementOffset),
                let bytesOffset = readWord(headStart + elementOffset + 32),
                let length = readWord(headStart + elementOffset + bytesOffset)
            else { return nil }
            let start = headStart + elementOffset + bytesOffset + 32
            guard start + length <= bytes.count else { return nil }
            results.append((success == 1, Data(bytes[start..<(start + length)])))
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

    private static func word(address: String) -> Data {
        let hex = address.lowercased().hasPrefix("0x") ? String(address.dropFirst(2)) : address
        return Data(repeating: 0, count: 12) + (Data(hex: hex) ?? Data(repeating: 0, count: 20))
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
