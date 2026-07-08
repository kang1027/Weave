import Foundation

/// 자산이 속한 시장 — 검색 결과 뱃지와 소스 우선순위 판단에 쓰인다.
public enum Market: String, Codable, Sendable, CaseIterable {
    case crypto
    case koreaStock
    case usStock
    case japanStock
    case other

    /// 24시간 거래 시장만 인트라데이(15m/1H/4H)가 의미 있다.
    /// 주식은 장중에만 거래돼 야간·주말 슬롯이 비므로 상세 차트에서 1D부터 노출한다.
    public var supportsIntraday: Bool { self == .crypto }

    /// 국장·일장은 정수 단위로만 거래돼 수량 표시에 소수점이 불필요하다.
    public var tradesWholeShares: Bool { self == .koreaStock || self == .japanStock }
}

/// 시세 데이터 소스. Naver/Yahoo는 비공식 API라 어댑터 교체를 전제로 한다.
public enum ProviderKind: String, Codable, Sendable, CaseIterable {
    case binance
    case naver
    case yahoo
    case manual
}
