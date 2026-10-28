import Foundation

/// 김치 프리미엄 — 업비트 원화가가 바이낸스 달러가 × 환율보다 몇 % 비싼지.
public struct KimchiPremium: Equatable, Sendable {
    public var upbitPrice: Decimal
    public var binancePrice: Decimal
    public var usdKRW: Decimal
    /// 일별 김프(오래된 순). 마지막 점은 현재 김프.
    public var history: [KimchiPremiumPoint]

    public init(upbitPrice: Decimal, binancePrice: Decimal, usdKRW: Decimal, history: [KimchiPremiumPoint] = []) {
        self.upbitPrice = upbitPrice
        self.binancePrice = binancePrice
        self.usdKRW = usdKRW
        self.history = history
    }

    public var binancePriceKRW: Decimal { binancePrice * usdKRW }

    public var percent: Decimal {
        Self.percent(upbitKRW: upbitPrice, binanceUSD: binancePrice, usdKRW: usdKRW) ?? 0
    }

    public static func percent(upbitKRW: Decimal, binanceUSD: Decimal, usdKRW: Decimal) -> Decimal? {
        let binanceKRW = binanceUSD * usdKRW
        guard upbitKRW > 0, binanceKRW > 0 else { return nil }
        return ((upbitKRW / binanceKRW - 1) * 100).rounded(scale: 4)
    }

    /// 같은 UTC 날짜의 업비트·바이낸스 일봉 종가를 맞대고, 환율은 그날 일봉(주말엔 금요일 일봉)을 쓴다.
    public static func dailyHistory(upbit: [Candle], binance: [Candle], usdKRW fx: [Candle]) -> [KimchiPremiumPoint] {
        let binanceByDay = Dictionary(binance.map { ($0.date, $0.close) }, uniquingKeysWith: { _, last in last })
        let fx = fx.sorted { $0.date < $1.date }
        return upbit.sorted { $0.date < $1.date }.compactMap { candle in
            guard
                let binanceClose = binanceByDay[candle.date],
                // 야후 환율 일봉은 런던 자정에 찍힌다(서머타임엔 전날 23:00Z) — 몇 시간 여유를 둔다.
                let rate = fx.last(where: { $0.date <= candle.date.addingTimeInterval(3 * 3_600) })?.close,
                let percent = percent(upbitKRW: candle.close, binanceUSD: binanceClose, usdKRW: rate)
            else {
                return nil
            }
            return KimchiPremiumPoint(date: candle.date, percent: percent)
        }
    }
}

public struct KimchiPremiumPoint: Equatable, Sendable {
    public var date: Date
    public var percent: Decimal

    public init(date: Date, percent: Decimal) {
        self.date = date
        self.percent = percent
    }
}

/// 김프 조회 — 현재가는 매번 새로 받고, 일별 추이는 1시간 캐시한다.
/// 업비트 원화 마켓에 없는 코인은 하루 동안 다시 묻지 않는다.
public actor KimchiPremiumService {
    public static let historyDays = 30

    private let upbit: UpbitProvider
    private let binance: any MarketDataProvider
    private let yahoo: any MarketDataProvider
    private let usdKRW: @Sendable () async throws -> Decimal
    private let now: @Sendable () -> Date
    private var histories: [String: (points: [KimchiPremiumPoint], fetchedAt: Date)] = [:]
    private var unlistedAt: [String: Date] = [:]

    public init(
        upbit: UpbitProvider,
        binance: any MarketDataProvider,
        yahoo: any MarketDataProvider,
        usdKRW: @escaping @Sendable () async throws -> Decimal,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.upbit = upbit
        self.binance = binance
        self.yahoo = yahoo
        self.usdKRW = usdKRW
        self.now = now
    }

    /// - symbol: 코인 심볼(BTC). binanceSymbol: 바이낸스 USDT 페어(BTCUSDT).
    /// - Returns: 업비트 원화 마켓에 없으면 nil.
    public func premium(symbol: String, binanceSymbol: String) async throws -> KimchiPremium? {
        let key = symbol.uppercased()
        if let unlisted = unlistedAt[key], now().timeIntervalSince(unlisted) < 86_400 { return nil }

        async let upbitPrice = upbit.price(symbol: key)
        async let binanceQuote = binance.quote(providerSymbol: binanceSymbol)
        async let rate = usdKRW()
        guard let upbitPrice = try await upbitPrice else {
            unlistedAt[key] = now()
            return nil
        }
        unlistedAt[key] = nil
        var premium = KimchiPremium(
            upbitPrice: upbitPrice,
            binancePrice: try await binanceQuote.price,
            usdKRW: try await rate
        )

        var points = await history(symbol: key, binanceSymbol: binanceSymbol)
        // 오늘 일봉은 아직 진행 중 — 마지막 점을 현재 김프로 맞춘다.
        if let last = points.last, Calendar.utc.isDate(last.date, inSameDayAs: now()) {
            points.removeLast()
        }
        points.append(KimchiPremiumPoint(date: now(), percent: premium.percent))
        premium.history = points
        return premium
    }

    public func clearCache() {
        histories = [:]
        unlistedAt = [:]
    }

    /// 추이를 못 받아도 현재 김프는 보여준다 — 실패 시 빈 배열.
    private func history(symbol: String, binanceSymbol: String) async -> [KimchiPremiumPoint] {
        if let cached = histories[symbol], now().timeIntervalSince(cached.fetchedAt) < 3_600 {
            return cached.points
        }
        do {
            async let upbitCandles = upbit.dailyCandles(symbol: symbol, count: Self.historyDays)
            async let binanceCandles = binance.candles(providerSymbol: binanceSymbol, interval: .day)
            async let fxCandles = yahoo.candles(
                providerSymbol: FXService.pairSymbol(from: "USD", to: "KRW"), interval: .day
            )
            let points = KimchiPremium.dailyHistory(
                upbit: try await upbitCandles,
                binance: try await binanceCandles,
                usdKRW: try await fxCandles
            )
            histories[symbol] = (points, now())
            return points
        } catch {
            return histories[symbol]?.points ?? []
        }
    }
}

private extension Calendar {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
