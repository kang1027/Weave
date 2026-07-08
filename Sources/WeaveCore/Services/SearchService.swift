import Foundation

/// 3소스 병렬 라이브서치 + 중복 병합. 디바운스는 뷰 레이어 담당.
public struct SearchService: Sendable {
    private let providers: [any MarketDataProvider]

    public init(providers: [any MarketDataProvider]) {
        self.providers = providers
    }

    public func search(query: String) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }

        let results = await withTaskGroup(of: (ProviderKind, [SearchResult]).self) { group in
            for provider in providers {
                group.addTask {
                    (provider.kind, (try? await provider.search(query: trimmed)) ?? [])
                }
            }
            var collected: [ProviderKind: [SearchResult]] = [:]
            for await (kind, items) in group {
                collected[kind] = items
            }
            return collected
        }

        return SearchMerger.merge(
            query: trimmed,
            binance: results[.binance] ?? [],
            naver: results[.naver] ?? [],
            yahoo: results[.yahoo] ?? []
        )
    }
}

/// 소스 우선순위 병합 — 국장=네이버, 크립토=Binance 우선. 야후는 미장/일장/기타 전담.
public enum SearchMerger {
    public static func merge(
        query: String,
        binance: [SearchResult],
        naver: [SearchResult],
        yahoo: [SearchResult]
    ) -> [SearchResult] {
        let binanceBases = Set(binance.map { $0.symbol.uppercased() })
        let yahooWithAliases = dedupePreservingFirst(SearchAliases.yahooResults(for: query) + yahoo)

        let dedupedYahoo = yahooWithAliases.filter { result in
            switch result.market {
            case .koreaStock:
                // 국장은 네이버 전담 — 네이버가 응답했으면 야후 국장 결과는 버린다.
                return naver.isEmpty
            case .crypto:
                return !binanceBases.contains(result.symbol.uppercased())
            case .usStock, .japanStock, .other:
                return true
            }
        }

        let combined = naver + binance + dedupedYahoo
        let q = query.uppercased()

        func score(_ r: SearchResult) -> Int {
            let symbol = r.symbol.uppercased()
            let name = r.name.uppercased()
            if symbol == q || name == q { return 0 }
            if symbol.hasPrefix(q) || name.hasPrefix(q) { return 1 }
            if name.contains(q) || symbol.contains(q) { return 2 }
            return 3
        }

        return combined
            .enumerated()
            .sorted { lhs, rhs in
                let ls = score(lhs.element)
                let rs = score(rhs.element)
                return ls == rs ? lhs.offset < rhs.offset : ls < rs
            }
            .map(\.element)
            .prefix(20)
            .map { $0 }
    }

    private static func dedupePreservingFirst(_ results: [SearchResult]) -> [SearchResult] {
        var seen: Set<String> = []
        return results.filter { seen.insert($0.id).inserted }
    }
}

private enum SearchAliases {
    static func yahooResults(for query: String) -> [SearchResult] {
        guard isSandP500Query(query) else { return [] }
        return [
            SearchResult(
                provider: .yahoo,
                providerSymbol: "^GSPC",
                symbol: "^GSPC",
                name: "S&P 500",
                market: .usStock,
                currency: "USD"
            )
        ]
    }

    private static func isSandP500Query(_ query: String) -> Bool {
        let lowercased = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalized = lowercased.filter(\.isLetterOrNumber)
        return normalized == "sp" && lowercased.contains("&")
            || ["sp500", "sandp", "sandp500", "snp500", "gspc"].contains(normalized)
    }
}

private extension Character {
    var isLetterOrNumber: Bool {
        unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
}
