import Foundation
import Testing
@testable import Weave

@Suite struct KimchiPremiumCardTests {
    @Test func smallKRWPricesKeepTheirDecimals() {
        #expect(KimchiPremiumCard.krwText(109_371_000.4) == "₩109,371,000")
        #expect(KimchiPremiumCard.krwText(0.01853) == "₩0.01853")
        #expect(KimchiPremiumCard.krwText(12.3456) == "₩12.35")
    }
}
