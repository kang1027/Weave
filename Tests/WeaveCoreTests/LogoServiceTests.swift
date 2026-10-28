import Foundation
import Testing
@testable import WeaveCore

/// URL별로 지정한 응답을 돌려주고 요청 순서를 기록하는 페이크 HTTP. 지정 없는 URL은 404.
private actor FakeLogoHTTPState {
    private var responses: [String: Result<Data, HTTPError>] = [:]
    private(set) var requested: [String] = []

    func set(_ url: String, _ response: Result<Data, HTTPError>) {
        responses[url] = response
    }

    func respond(to url: URL) throws -> Data {
        requested.append(url.absoluteString)
        return try (responses[url.absoluteString] ?? .failure(.badStatus(404))).get()
    }
}

private struct FakeLogoHTTP: HTTPClient {
    let state: FakeLogoHTTPState

    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        try await state.respond(to: url)
    }
}

@Suite struct LogoServiceTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("weave-logo-tests-\(UUID().uuidString)")
    }

    private func makeService(state: FakeLogoHTTPState, directory: URL, now: Date) -> LogoService {
        LogoService(http: FakeLogoHTTP(state: state), cacheDirectory: directory, now: { now })
    }

    @Test func fallsThroughMissingCandidateAndCachesOnDisk() async throws {
        let state = FakeLogoHTTPState()
        let source = try #require(AssetLogoSource(market: .usStock, symbol: "KO"))
        await state.set(source.candidates[1].absoluteString, .success(png))
        let directory = tempDirectory()

        let first = await makeService(state: state, directory: directory, now: start).logoData(for: source)
        // 새 인스턴스(앱 재실행)도 디스크 캐시로 네트워크 없이 돌려준다.
        let second = await makeService(state: state, directory: directory, now: start).logoData(for: source)

        #expect(first == png)
        #expect(second == png)
        #expect(await state.requested == source.candidates.map(\.absoluteString))
    }

    @Test func missingLogoIsRememberedUntilRetryInterval() async throws {
        let state = FakeLogoHTTPState()
        let source = try #require(AssetLogoSource(market: .koreaStock, symbol: "069500"))
        let directory = tempDirectory()

        #expect(await makeService(state: state, directory: directory, now: start).logoData(for: source) == nil)
        let nextDay = start.addingTimeInterval(24 * 3600)
        #expect(await makeService(state: state, directory: directory, now: nextDay).logoData(for: source) == nil)
        #expect(await state.requested.count == 1)

        let nextWeek = start.addingTimeInterval(8 * 24 * 3600)
        #expect(await makeService(state: state, directory: directory, now: nextWeek).logoData(for: source) == nil)
        #expect(await state.requested.count == 2)
    }

    @Test func transientErrorIsRetriedNextTime() async throws {
        let state = FakeLogoHTTPState()
        let source = try #require(AssetLogoSource(market: .koreaStock, symbol: "005930"))
        await state.set(source.candidates[0].absoluteString, .failure(.badStatus(500)))
        let service = makeService(state: state, directory: tempDirectory(), now: start)

        #expect(await service.logoData(for: source) == nil)
        #expect(await service.logoData(for: source) == nil)
        #expect(await state.requested.count == 2)
    }

    @Test func nonImageResponseIsNotCached() async throws {
        let state = FakeLogoHTTPState()
        let source = try #require(AssetLogoSource(market: .koreaStock, symbol: "005930"))
        await state.set(source.candidates[0].absoluteString, .success(Data("<html>login</html>".utf8)))
        let service = makeService(state: state, directory: tempDirectory(), now: start)

        #expect(await service.logoData(for: source) == nil)
        #expect(await service.logoData(for: source) == nil)
        #expect(await state.requested.count == 2)
    }

    @Test func recognizesSupportedImageFormats() {
        #expect(LogoService.isImage(png))
        #expect(LogoService.isImage(Data([0xFF, 0xD8, 0xFF, 0xE0])))
        #expect(LogoService.isImage(Data(#"<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"></svg>"#.utf8)))
        #expect(!LogoService.isImage(Data("<!DOCTYPE html><html></html>".utf8)))
        #expect(!LogoService.isImage(Data()))
    }
}

@Suite struct LogoServiceSniffTests {
    @Test func svgSniffSurvivesACutMultibyteCharacter() {
        // 512바이트 경계에 한글(3바이트)이 걸리게 앞을 채운다.
        let prefix = "<svg xmlns=\"http://www.w3.org/2000/svg\"><!--" + String(repeating: "a", count: 466)
        let data = Data((prefix + "로고-->").utf8)
        #expect(data.count > 512)
        #expect(LogoService.isImage(data))
    }
}
