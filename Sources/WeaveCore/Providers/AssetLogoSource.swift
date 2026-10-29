import Foundation

/// 자산 로고를 받아올 원격 주소 — 크립토는 spothq 아이콘셋, 주식은 네이버 증권 로고.
/// 네이버 로고 코드는 로이터 코드 규칙을 따른다: 국장 "005930", 나스닥 "NVDA.O",
/// 뉴욕 "KO"(서픽스 없음), 도쿄 "7203.T". 미장은 거래소를 모르므로 후보를 순서대로 시도한다.
public struct AssetLogoSource: Equatable, Sendable {
    /// 캐시 파일 이름으로도 쓰는 마켓·심볼 키.
    public let key: String
    public let candidates: [URL]

    public init?(asset: Asset) {
        // 이자·스테이킹 토큰은 원금 코인 아이콘을 쓴다.
        if asset.provider == .onchain, let underlying = EVMToken.yieldBearing(providerSymbol: asset.providerSymbol)?.underlying {
            self.init(market: .crypto, symbol: underlying)
            return
        }
        self.init(market: asset.market, symbol: asset.symbol)
    }

    public init?(market: Market, symbol: String) {
        let code: String
        let urls: [URL]
        switch market {
        case .crypto:
            code = symbol.lowercased()
            guard Self.isLogoCode(code) else { return nil }
            urls = [Self.cryptoIconURL(symbol: code)].compactMap { $0 }
        case .koreaStock:
            code = symbol.uppercased()
            guard code.count == 6, Self.isLogoCode(code) else { return nil }
            urls = [Self.naverLogoURL(code: code)].compactMap { $0 }
        case .usStock:
            // 야후 클래스 주식 "BRK-B" → 네이버 "BRK.B".
            code = symbol.uppercased().replacingOccurrences(of: "-", with: ".")
            guard Self.isLogoCode(code) else { return nil }
            urls = [Self.naverLogoURL(code: "\(code).O"), Self.naverLogoURL(code: code)].compactMap { $0 }
        case .japanStock:
            code = symbol.uppercased()
            guard Self.isLogoCode(code) else { return nil }
            urls = [Self.naverLogoURL(code: "\(code).T")].compactMap { $0 }
        case .other:
            return nil
        }
        guard !code.isEmpty, !urls.isEmpty else { return nil }
        self.key = "\(market.rawValue)-\(code)"
        self.candidates = urls
    }

    public static func cryptoIconURL(symbol: String) -> URL? {
        URL(string: "https://cdn.jsdelivr.net/gh/spothq/cryptocurrency-icons@master/128/color/\(symbol.lowercased()).png")
    }

    private static func naverLogoURL(code: String) -> URL? {
        URL(string: "https://ssl.pstatic.net/imgstock/fn/real/logo/stock/Stock\(code).svg")
    }

    /// 경로·파일명에 그대로 넣어도 안전한 영숫자·점만 허용.
    private static func isLogoCode(_ code: String) -> Bool {
        !code.isEmpty && code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }
    }
}
