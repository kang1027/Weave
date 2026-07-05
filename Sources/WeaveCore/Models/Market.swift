import Foundation

/// 자산이 속한 시장 — 검색 결과 뱃지와 소스 우선순위 판단에 쓰인다.
public enum Market: String, Codable, Sendable, CaseIterable {
    case crypto
    case koreaStock
    case usStock
    case japanStock
    case other
}

/// 시세 데이터 소스. Naver/Yahoo는 비공식 API라 어댑터 교체를 전제로 한다.
public enum ProviderKind: String, Codable, Sendable, CaseIterable {
    case binance
    case naver
    case yahoo
    case manual
}
