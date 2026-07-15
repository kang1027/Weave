import Foundation

/// Naver 증권 비공식 API — 국내주식(코스피/코스닥) 전담.
public struct NaverProvider: MarketDataProvider {
    public let kind: ProviderKind = .naver

    private let http: any HTTPClient
    private static let headers = ["User-Agent": "Mozilla/5.0"]

    public init(http: any HTTPClient) {
        self.http = http
    }

    // MARK: - Search (자동완성)

    public func search(query: String) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard
            !trimmed.isEmpty,
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "https://ac.stock.naver.com/ac?q=\(encoded)&target=stock")
        else {
            return []
        }
        let data = try await http.get(url, headers: Self.headers)
        return try Self.parseSearch(data)
    }

    static func parseSearch(_ data: Data) throws -> [SearchResult] {
        struct Response: Decodable {
            struct Item: Decodable {
                var code: String
                var name: String
                var typeCode: String?
                var nationCode: String?
            }
            var items: [Item]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.items
            .filter { item in
                // 국장 전담 — 6자리 종목코드 + (nation 정보가 있으면) KOR만.
                let isDomestic = item.nationCode == nil || item.nationCode == "KOR"
                return isDomestic && item.code.count == 6
            }
            .prefix(10)
            .map { item in
                SearchResult(
                    provider: .naver,
                    providerSymbol: item.code,
                    symbol: item.code,
                    name: item.name,
                    market: .koreaStock,
                    currency: "KRW"
                )
            }
    }

    // MARK: - Quote

    public func quote(providerSymbol: String) async throws -> Quote {
        guard
            let encoded = providerSymbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "https://polling.finance.naver.com/api/realtime/domestic/stock/\(encoded)")
        else {
            throw ProviderError.unsupportedSymbol(providerSymbol)
        }
        let data = try await http.get(url, headers: Self.headers)
        return try Self.parseQuote(data)
    }

    static func parseQuote(_ data: Data) throws -> Quote {
        struct Response: Decodable {
            struct Item: Decodable {
                struct Direction: Decodable { var name: String }
                var closePrice: String
                var fluctuationsRatio: String
                var compareToPreviousPrice: Direction
            }
            var datas: [Item]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard
            let item = response.datas.first,
            let price = Decimal.clean(item.closePrice),
            let rawPercent = Decimal.clean(item.fluctuationsRatio)
        else {
            throw ProviderError.invalidResponse
        }
        // fluctuationsRatio는 부호를 포함하지만, 방어적으로 방향 필드와 대조한다.
        // 하락 계열은 FALLING뿐 아니라 LOWER_LIMIT(하한가)도 있다.
        let isDown = ["FALLING", "LOWER_LIMIT"].contains(item.compareToPreviousPrice.name)
        let magnitude = abs(rawPercent)
        return Quote(
            price: price,
            changePercent: isDown ? -magnitude : magnitude,
            currency: "KRW",
            updatedAt: Date()
        )
    }

    // MARK: - Candles (fchart)

    public func candles(providerSymbol: String, interval: CandleInterval) async throws -> [Candle] {
        let timeframe: String
        switch interval {
        case .second, .m15, .h1, .h4:
            // fchart는 인트라데이 미제공 — 앱 레이어가 야후(.KS/.KQ)로 브릿지한다.
            throw ProviderError.unsupportedSymbol(providerSymbol)
        case .day: timeframe = "day"
        case .week: timeframe = "week"
        case .month: timeframe = "month"
        }
        let count = CandleFetchLimit.limit(for: interval)
        guard
            let encoded = providerSymbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(
                string: "https://fchart.stock.naver.com/sise.nhn?symbol=\(encoded)&timeframe=\(timeframe)&count=\(count)&requestType=0"
            )
        else {
            throw ProviderError.unsupportedSymbol(providerSymbol)
        }
        let data = try await http.get(url, headers: Self.headers)
        return try Self.parseFchart(data)
    }

    /// fchart 응답은 XML 유사 텍스트: `<item data="20240102|76500|77500|76000|77000|1234567" />`
    /// 필드: 날짜|시가|고가|저가|종가|거래량
    static func parseFchart(_ data: Data) throws -> [Candle] {
        // 응답이 EUC-KR — 숫자 필드는 전부 ASCII라 lossy UTF-8 디코딩으로 안전하게 읽는다.
        let text = String(decoding: data, as: UTF8.self)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyyMMdd"

        var candles: [Candle] = []
        var rest = Substring(text)
        while let start = rest.range(of: "data=\"") {
            rest = rest[start.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { break }
            let fields = rest[..<end].split(separator: "|")
            rest = rest[rest.index(after: end)...]
            guard
                fields.count >= 5,
                let date = formatter.date(from: String(fields[0])),
                let open = Decimal.clean(String(fields[1])),
                let high = Decimal.clean(String(fields[2])),
                let low = Decimal.clean(String(fields[3])),
                let close = Decimal.clean(String(fields[4]))
            else {
                continue
            }
            candles.append(Candle(date: date, open: open, high: high, low: low, close: close))
        }
        guard !candles.isEmpty else { throw ProviderError.invalidResponse }
        return candles
    }
}
