import AppKit
import Foundation
import OSLog
import SwiftUI
import WeaveCore

/// 차트에서 지점을 골라 거래 폼으로 넘길 때의 초기값.
struct TradePrefill: Hashable {
    var date: Date
    var price: Decimal
}

/// 팝오버 내 화면 스택 — 마지막 요소가 현재 화면, 비어 있으면 홈.
enum Route: Hashable {
    case manage
    case detail(UUID)
    case settings
    case tradeForm(assetID: UUID, editing: Trade?, prefill: TradePrefill?)
    case manualAssetForm
}

@MainActor
final class AppModel: ObservableObject {
    /// 스크린샷 도구가 메뉴바 라벨 이미지에 접근하기 위한 약참조(dev 전용).
    static weak var shared: AppModel?

    @Published var document: PortfolioDocument
    @Published var quotes: [UUID: Quote] = [:]
    @Published var fxRates: [String: Decimal] = [:]
    /// 최근 갱신 라운드에서 시세를 못 받은 자산 — stale 표시용.
    @Published var staleAssetIDs: Set<UUID> = []
    @Published var route: [Route] = []
    @Published var menuBarTitle: String = MenuBarTitleBuilder.placeholder
    /// 메뉴바 라벨 이미지 — 색상·2줄(compact) 표현을 위해 텍스트 대신 렌더.
    @Published var menuBarImage: NSImage?
    @Published var nextRefreshAt: Date?

    // 검색 (자산 관리 화면)
    @Published var searchQuery = "" {
        didSet { scheduleSearch() }
    }
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false

    // 홈 차트 상태
    @Published var homeChartMode: HomeChartMode = .combined {
        didSet {
            guard oldValue != homeChartMode else { return }
            // 모드별로 기간을 따로 기억한다 — Combined/By Asset이 각자 1D/1W/1M/1Y를 유지.
            let remembered = periodByMode[homeChartMode] ?? .oneWeek
            if remembered != homeChartPeriod { homeChartPeriod = remembered }
        }
    }
    @Published var homeChartPeriod: ChartPeriod = .oneWeek {
        didSet { periodByMode[homeChartMode] = homeChartPeriod }
    }
    /// 차트 모드별 마지막 선택 기간 — 모드 전환 시 복원(두 모드를 따로 본다).
    private var periodByMode: [HomeChartMode: ChartPeriod] = [
        .combined: .oneWeek,
        .perAsset: .oneWeek
    ]
    @Published var homeSeries: [ValuePoint] = []
    @Published var homeAssetSeries: [AssetLineSeries] = []
    @Published var homeBuyMarkers: [BuyMarker] = []
    /// 홈 차트 x 도메인 — 선택 기간 전체 창(startDate~now)으로 고정. 데이터가 짧아도 축은 기간만큼.
    @Published var homeChartDomain: ClosedRange<Date>?
    @Published var isHomeChartLoading = false
    /// Assets 리스트 % 배지 기간(1D/1W/1M/1Y).
    @Published var assetReturnPeriod: AssetReturnPeriod = .day
    /// 자산별 일봉 — 기간 수익률 계산용(홈 차트 로드 시 채워짐).
    var homeAssetCandles: [UUID: [Candle]] = [:]
    /// 자산/거래 변이마다 증가 — 홈 `.task(id:)`가 이를 보고 재로드한다.
    @Published var chartGeneration = 0
    /// 늦게 끝난 이전 로드가 최신 결과를 덮어쓰지 않게 하는 토큰.
    var chartLoadToken = 0

    // 상세 차트 상태
    @Published var detailInterval: CandleInterval = .day
    @Published var detailCandles: [Candle] = []
    @Published var isDetailChartLoading = false
    /// 상세 차트가 중심으로 볼 시점 — nil이면 최근. 데이터 범위 밖 거래로 점프할 때 그 거래일로 설정.
    @Published var detailFocusDate: Date?
    var detailChartAssetID: UUID?
    var detailLoadToken = 0

    let store: any PortfolioStore
    let quoteService: QuoteService
    let candleService: CandleService
    let fxService: FXService
    let searchService: SearchService
    let updater: UpdaterHandle

    private let logger = Logger(subsystem: "app.weave", category: "AppModel")
    private var refreshTask: Task<Void, Never>?
    var detailLiveTask: Task<Void, Never>?
    var detailLiveAssetID: UUID?
    private var rotationTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var hasStartedBackgroundWork = false
    var lastRefreshAt: Date?
    var rotationIndex = 0

    init(
        store: any PortfolioStore,
        quoteService: QuoteService,
        candleService: CandleService,
        fxService: FXService,
        searchService: SearchService,
        updater: UpdaterHandle = UpdaterHandle()
    ) {
        self.store = store
        self.quoteService = quoteService
        self.candleService = candleService
        self.fxService = fxService
        self.searchService = searchService
        self.updater = updater
        do {
            self.document = try store.load()
        } catch {
            Logger(subsystem: "app.weave", category: "AppModel")
                .error("포트폴리오 로드 실패: \(error.localizedDescription)")
            self.document = .empty
        }
        AppModel.shared = self
    }

    /// 프로덕션 조립 — 스토어/캐시 경로 실패 시 임시 디렉토리 폴백.
    static func live() -> AppModel {
        let http = URLSessionHTTPClient()
        let cacheDir = (try? CandleService.liveCacheDirectory())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("WeaveCache")
        let binance = BinanceProvider(http: http, cacheDirectory: cacheDir)
        let naver = NaverProvider(http: http)
        let yahoo = YahooProvider(http: http)
        let providers: [any MarketDataProvider] = [binance, naver, yahoo]
        // 스크린샷/데모용: WEAVE_STORE가 있으면 실제 데이터와 격리된 시드 문서를 로드한다.
        let overrideStore = ProcessInfo.processInfo.environment["WEAVE_STORE"]
            .map { JSONPortfolioStore(fileURL: URL(fileURLWithPath: $0)) }
        let store: any PortfolioStore = overrideStore
            ?? (try? JSONPortfolioStore.live())
            ?? JSONPortfolioStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("Weave/portfolio.json")
            )
        return AppModel(
            store: store,
            quoteService: QuoteService(providers: providers),
            candleService: CandleService(providers: providers, cacheDirectory: cacheDir),
            fxService: FXService(yahoo: yahoo, cacheDirectory: cacheDir),
            searchService: SearchService(providers: providers)
        )
    }

    // MARK: - 파생 상태

    var settings: AppSettings {
        get { document.settings }
        set {
            document.settings = newValue
            persist()
        }
    }

    var visibleAssets: [Asset] { document.assets.filter { !$0.isHidden } }

    var computed: (perAsset: [AssetMetrics], portfolio: PortfolioMetrics) {
        let result = PortfolioCalculator.compute(
            assets: document.assets,
            trades: document.trades,
            quotes: quotes,
            fxRates: fxRates,
            baseCurrency: settings.baseCurrency
        )
        // 표시 순서 = 맨 위 고정 먼저, 그다음 사용자 지정 순서(document.assets 배열 순).
        let order = Dictionary(
            uniqueKeysWithValues: document.assets.enumerated().map { ($1.id, $0) }
        )
        let sorted = result.perAsset.sorted { lhs, rhs in
            if lhs.asset.isPinnedToTop != rhs.asset.isPinnedToTop {
                return lhs.asset.isPinnedToTop
            }
            return (order[lhs.asset.id] ?? 0) < (order[rhs.asset.id] ?? 0)
        }
        return (sorted, result.portfolio)
    }

    func asset(id: UUID) -> Asset? {
        document.assets.first { $0.id == id }
    }

    func metrics(id: UUID) -> AssetMetrics? {
        computed.perAsset.first { $0.id == id }
    }

    // MARK: - 라우팅

    var currentRoute: Route? { route.last }

    func push(_ newRoute: Route) {
        route.append(newRoute)
    }

    func pop() {
        _ = route.popLast()
    }

    func popToHome() {
        route = []
    }

    // MARK: - 저장

    func persist() {
        do {
            try store.save(document)
        } catch {
            logger.error("포트폴리오 저장 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - 다국어

    func t(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: L10n.bundle(for: settings.language))
    }

    var locale: Locale {
        L10n.locale(for: settings.language)
    }

    // MARK: - 테마

    func theme(systemScheme: ColorScheme) -> Theme {
        switch settings.theme {
        case .system: return systemScheme == .dark ? .slate : .light
        case .slate: return .slate
        case .light: return .light
        }
    }

    // MARK: - 검색 디바운스

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            let results = await self.searchService.search(query: query)
            guard !Task.isCancelled, self.searchQuery == query else { return }
            self.searchResults = results
            self.isSearching = false
        }
    }

    // MARK: - 주기 작업 (시세 폴링 · 메뉴바 로테이션)

    func resetBackgroundWorkForDataWipe() {
        refreshTask?.cancel()
        rotationTask?.cancel()
        searchTask?.cancel()
        refreshTask = nil
        rotationTask = nil
        searchTask = nil
        hasStartedBackgroundWork = false
    }

    /// 팝오버가 열릴 때마다 불리지만 실제 시작은 최초 1회.
    /// 이후 열림에서는 60초 이상 지난 시세만 즉시 갱신.
    func startBackgroundWork() {
        guard !hasStartedBackgroundWork else {
            refreshIfStale()
            return
        }
        hasStartedBackgroundWork = true
        // 스크린샷용: 상태(홈 Combined / By Asset / 종목 세부)를 env로 지정해 캡처.
        let shotEnv = ProcessInfo.processInfo.environment
        if shotEnv["WEAVE_SHOT"] != nil {
            let state = shotEnv["WEAVE_SHOT_STATE"] ?? "home-combined"
            if state == "home-byasset" { homeChartMode = .perAsset }
            // 모드 확정 뒤 기간을 잡아야 모드별 복원값에 안 덮인다. 1M가 최근 상승 흐름을 잘 보여준다.
            homeChartPeriod = .oneMonth
            assetReturnPeriod = .month
            if state == "detail", let id = visibleAssets.first?.id {
                push(.detail(id))
            }
        }
        restartRefreshLoop()
        restartRotationLoop()
        applyHotkey()
        // 번들 밖에서 바뀌었을 수 있는 자동 시작 상태 동기화.
        if LaunchAtLogin.isSupported {
            document.settings.launchAtLogin = LaunchAtLogin.isEnabled
        }
        updater.setAutomaticChecks(settings.autoUpdateCheck)
        updater.startPeriodicChecks(everyMinutes: 5)
    }

    func refreshIfStale() {
        guard let lastRefreshAt else { return }
        if Date().timeIntervalSince(lastRefreshAt) > 60 {
            restartRefreshLoop()
        }
    }

    func restartRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refreshQuotes()
                self.lastRefreshAt = Date()
                let interval = max(60, min(900, self.settings.quoteRefreshSeconds))
                self.nextRefreshAt = Date().addingTimeInterval(TimeInterval(interval))
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func restartRotationLoop() {
        rotationTask?.cancel()
        rotationTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.updateMenuBarTitle()
                let interval = self.settings.rotationSeconds
                if interval <= 0 {
                    // 로테이션 끔 — 타이틀만 갱신 주기로 유지.
                    try? await Task.sleep(for: .seconds(30))
                } else {
                    try? await Task.sleep(for: .seconds(interval))
                    // 취소로 sleep이 조기 반환되면 증가시키지 않는다(restart 시 유령 +1 방지).
                    if Task.isCancelled { break }
                    self.rotationIndex += 1
                }
            }
        }
    }
}
