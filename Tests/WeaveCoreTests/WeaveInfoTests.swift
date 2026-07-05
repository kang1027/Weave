import Testing
@testable import WeaveCore

@Suite struct WeaveInfoTests {
    @Test func versionIsSemver() {
        let parts = WeaveInfo.version.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { Int($0) != nil })
    }
}
