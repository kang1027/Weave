import Foundation

public protocol HTTPClient: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> Data
}

extension HTTPClient {
    public func get(_ url: URL) async throws -> Data {
        try await get(url, headers: [:])
    }
}

public enum HTTPError: Error, Equatable {
    case badStatus(Int)
    case invalidBody
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: request)
        guard
            let http = response as? HTTPURLResponse,
            200..<300 ~= http.statusCode
        else {
            throw HTTPError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }
}

/// 상태 코드와 본문을 그대로 돌려주는 요청 — 오류 본문의 코드로 원인을 가려야 하는 API용.
public protocol HTTPSending: Sendable {
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int)
}

extension URLSessionHTTPClient: HTTPSending {
    public func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        var request = request
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? -1)
    }
}
