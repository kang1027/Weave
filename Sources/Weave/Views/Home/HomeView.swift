import SwiftUI
import WeaveCore

/// 홈 — 헤더 · 링 3개 · 총액 · Value History · Assets 리스트 · footer.
struct HomeView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    @State private var deletionTarget: Asset?
    @State private var isHoveringTotal = false

    var body: some View {
        let (perAsset, portfolio) = model.computed

        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    // zIndex: 링/총액 hover 툴팁이 아래 형제 뷰 위에 그려지도록.
                    RingsRow(portfolio: portfolio)
                        .zIndex(10)
                    totalSection(portfolio)
                        .zIndex(9)
                    CapsHeader(text: model.t("Value History"))
                    ValueHistoryChart()
                    CapsHeader(text: model.t("Assets"))
                    // % 배지 기간 필터 — 1D(전날 대비)/1W/1M/1Y.
                    HStack {
                        Spacer()
                        SegmentedPills(
                            options: AssetReturnPeriod.allCases.map { ($0, $0.rawValue) },
                            selection: $model.assetReturnPeriod,
                            fillsWidth: false
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 2)
                    VStack(spacing: 0) {
                        ForEach(perAsset) { metric in
                            AssetListRow(metric: metric) {
                                deletionTarget = metric.asset
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            HomeFooter()
        }
        // 홈 진입·자산/거래 변이·기간 변경마다 재계산 — 같은 날은 캔들 캐시 히트라 저렴.
        .task(id: "\(model.chartGeneration)|\(model.homeChartPeriod.rawValue)") {
            await model.loadHomeChart()
        }
        .confirmDialog(
            $deletionTarget,
            title: { _ in model.t("Delete asset?") },
            message: { model.t("\($0.name) and \(model.tradeCount(assetID: $0.id)) trade(s) will be deleted.") },
            confirmTitle: model.t("Delete"),
            isDestructive: true,
            cancelTitle: model.t("Cancel"),
            onConfirm: { model.deleteAsset(id: $0.id) }
        )
    }

    private var header: some View {
        // 타이틀은 전체 폭 중앙에 절대 배치, 버튼은 양끝에(좌 1 · 우 2개라도 정확히 중앙).
        ZStack {
            // ZStack 기본 center 정렬 → "Weave"는 전체 폭 정중앙(좌우 버튼 수와 무관).
            Text(verbatim: "Weave")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.text)
            HStack {
                IconButton(systemName: "arrow.clockwise") {
                    model.manualRefresh()
                }
                .help(model.t("Refresh now"))
                Spacer()
                HStack(spacing: 6) {
                    IconButton(
                        systemName: model.settings.privacyMode ? "eye.slash" : "eye",
                        isActive: model.settings.privacyMode
                    ) {
                        model.settings.privacyMode.toggle()
                        model.updateMenuBarTitle()
                    }
                    .help(model.t("Privacy mode"))
                    IconButton(systemName: "gearshape") {
                        model.push(.settings)
                    }
                    .help(model.t("Settings"))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    /// 총 평가금 + 손익 라인. 원금은 hover 툴팁으로. (일간 등락은 Day 링이 담당)
    private func totalSection(_ portfolio: PortfolioMetrics) -> some View {
        let base = model.settings.baseCurrency
        let pnl = portfolio.unrealizedPnLBase
        return VStack(spacing: 6) {
            Text(
                MoneyFormatter.price(
                    portfolio.totalValueBase,
                    currency: base
                )
            )
            .font(.system(size: 26, weight: .bold))
            .monospacedDigit()
            .kerning(-0.3)
            .foregroundStyle(theme.text)
            .privacyBlur(model.settings.privacyMode)

            HStack(spacing: 4) {
                Text(MoneyFormatter.signedPrice(pnl, currency: base))
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .privacyBlur(model.settings.privacyMode)
                Text("(\(MoneyFormatter.percent(portfolio.totalReturnPercent)))")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(theme.upDown(pnl >= 0))
        }
        .padding(.top, 12)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .onHover { isHoveringTotal = $0 }
        // hover 시 원금 툴팁 — 아래 형제 뷰 위로 그려지게 zIndex는 호출부에서.
        .overlay(alignment: .bottom) {
            if isHoveringTotal {
                TooltipBubble(
                    text: model.t("Invested")
                        + " "
                        + MoneyFormatter.price(portfolio.costBasisBase, currency: base),
                    blurText: model.settings.privacyMode
                )
                .offset(y: 30)
                .allowsHitTesting(false)
            }
        }
    }
}

struct AssetListRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let metric: AssetMetrics
    let onDelete: () -> Void
    @State private var isHoveringPrice = false

    var body: some View {
        // 선택 기간 수익률 — 가격 색·행 배경·배지에 공통 사용.
        let percent = model.assetReturnPercent(metric)
        Button {
            model.push(.detail(metric.asset.id))
        } label: {
            HStack(spacing: 10) {
                AssetLogoView(asset: metric.asset)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        // Value History(자산별) 라인과 같은 색 점 — 범례 역할.
                        Circle()
                            .fill(theme.paletteColor(metric.asset.colorIndex))
                            .frame(width: 7, height: 7)
                        Text(metric.asset.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        if metric.asset.isPinnedToTop {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme.link)
                                .help(model.t("Pinned to top"))
                        }
                        if metric.asset.isPinned {
                            Image(systemName: "menubar.rectangle")
                                .font(.system(size: 8))
                                .foregroundStyle(theme.text2)
                        }
                        // 메뉴바에서 제외된 자산 표시(수동 자산은 애초에 메뉴바에 없어 제외).
                        if !metric.asset.isManual, !metric.asset.showInMenuBar {
                            Image(systemName: "rectangle.slash")
                                .font(.system(size: 8))
                                .foregroundStyle(theme.text2)
                                .help(model.t("Hidden from menu bar"))
                        }
                        if model.staleAssetIDs.contains(metric.asset.id) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 8))
                                .foregroundStyle(theme.orange)
                                .help(model.t("Quote unavailable — showing last value"))
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.text2)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(priceText)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(percent.map { theme.upDown($0 >= 0) } ?? theme.text)
                        .privacyBlur(model.settings.privacyMode)
                        .onHover { hovering in
                            if entryPriceText != nil { isHoveringPrice = hovering }
                        }
                        // 가격 hover 시 평단(진입가) 툴팁 — 가격 오른끝 기준 위로.
                        .overlay(alignment: .topTrailing) {
                            if isHoveringPrice, let entry = entryPriceText {
                                TooltipBubble(
                                    text: model.t("Avg \(entry)"),
                                    blurText: model.settings.privacyMode
                                )
                                .fixedSize()
                                .offset(y: -30)
                                .allowsHitTesting(false)
                            }
                        }
                    changeBadge(percent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .zIndex(isHoveringPrice ? 1 : 0)
        .hoverHighlight()
        .contextMenu {
            Button(metric.asset.isPinnedToTop ? model.t("Unpin from top") : model.t("Pin to top")) {
                model.togglePinTop(assetID: metric.asset.id)
            }
            Button(model.t("Move up")) {
                model.moveAsset(id: metric.asset.id, up: true)
            }
            .disabled(!model.canMoveAsset(id: metric.asset.id, up: true))
            Button(model.t("Move down")) {
                model.moveAsset(id: metric.asset.id, up: false)
            }
            .disabled(!model.canMoveAsset(id: metric.asset.id, up: false))
            if !metric.asset.isManual {
                Button(metric.asset.showInMenuBar ? model.t("Hide from menu bar") : model.t("Show in menu bar")) {
                    model.toggleMenuBar(assetID: metric.asset.id)
                }
                Button(metric.asset.isPinned ? model.t("Unpin from menu bar") : model.t("Pin to menu bar")) {
                    model.togglePin(assetID: metric.asset.id)
                }
            }
            Divider()
            Button(model.t("Hide")) {
                model.toggleHidden(assetID: metric.asset.id)
            }
            Button(model.t("Delete"), role: .destructive, action: onDelete)
        }
    }

    private var subtitle: String {
        if metric.asset.isManual {
            return model.t("Manual")
        }
        let qty = metric.asset.formattedQuantity(metric.position.quantity)
        let buys = model.t("\(metric.position.buyCount) buys")
        let holding = metric.asset.hasNumericSymbol
            ? model.t("\(qty) shares")
            : "\(qty) \(metric.asset.symbol)"
        return "\(holding) · \(buys)"
    }

    private var priceText: String {
        if metric.asset.isManual {
            return MoneyFormatter.price(metric.value, currency: metric.asset.currency)
        }
        guard let quote = metric.quote else { return "—" }
        // 자산 표시 통화 설정: 소스 통화 그대로(기본) / 기준 통화 환산.
        // 환율이 아직 없으면 잘못된 통화로 표기하지 말고 소스 통화 유지.
        if model.settings.displayCurrencyMode == .base,
           let rate = model.fxRates[metric.asset.currency.uppercased()] {
            return MoneyFormatter.price(quote.price * rate, currency: model.settings.baseCurrency)
        }
        return MoneyFormatter.price(quote.price, currency: quote.currency)
    }

    /// 평단(진입가) — 가격과 같은 통화 규칙으로 표기. 수동자산/미보유는 nil(툴팁 없음).
    private var entryPriceText: String? {
        guard !metric.asset.isManual,
              metric.position.quantity > 0,
              metric.position.averageCost > 0 else {
            return nil
        }
        let avg = metric.position.averageCost
        if model.settings.displayCurrencyMode == .base,
           let rate = model.fxRates[metric.asset.currency.uppercased()] {
            return MoneyFormatter.price(avg * rate, currency: model.settings.baseCurrency)
        }
        let currency = metric.quote?.currency ?? metric.asset.currency
        return MoneyFormatter.price(avg, currency: currency)
    }

    @ViewBuilder
    private func changeBadge(_ percent: Decimal?) -> some View {
        if let percent {
            ChangeBadge(
                text: MoneyFormatter.percent(percent),
                style: percent >= 0 ? .up : .down
            )
        } else {
            ChangeBadge(text: "—", style: .gray)
        }
    }
}

struct HomeFooter: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                // 버전·다음 갱신 — 항상 표시(업데이트 상태로 덮어쓰지 않음).
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(footerText(now: context.date))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.caps)
                        .monospacedDigit()
                }
                // 업데이트 진행 상태 — 활성일 때만 아래 줄에 살짝(OpenUsage 스타일).
                updateLine
            }
            Spacer()
            Button {
                model.push(.manage)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.link)
            }
            .buttonStyle(.plain)
            .help(model.t("Manage assets"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hair).frame(height: 1)
        }
    }

    @ViewBuilder private var updateLine: some View {
        switch model.updater.phase {
        case .available(let version):
            updateButton(model.t("Update & restart to \(version)"), systemImage: "arrow.down.circle.fill") {
                model.updater.startDownload()
            }
        case .readyToInstall:
            updateButton(model.t("Restart to update"), systemImage: "arrow.clockwise.circle.fill") {
                model.updater.installAndRelaunch()
            }
        case .failed:
            updateButton(model.t("Update failed · Retry"), systemImage: "exclamationmark.circle.fill", tint: theme.red) {
                model.updater.checkForUpdates()
            }
        case .checking:
            updateProgress(model.t("Checking for updates…"))
        case .downloading(let p):
            updateProgress(model.t("Downloading… \(percentText(p))"))
        case .extracting(let p):
            updateProgress(model.t("Preparing… \(percentText(p))"))
        case .installing:
            updateProgress(model.t("Installing…"))
        case .idle:
            EmptyView()
        }
    }

    private func updateButton(_ title: String, systemImage: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(tint ?? theme.greenText)
        }
        .buttonStyle(.plain)
    }

    private func updateProgress(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(theme.caps)
                .monospacedDigit()
            ProgressView()
                .controlSize(.mini)
        }
    }

    private func percentText(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private func footerText(now: Date) -> String {
        let version = "Weave \(WeaveInfo.version)"
        guard let next = model.nextRefreshAt else { return version }
        let remaining = max(0, Int(next.timeIntervalSince(now)))
        let text: String
        if remaining >= 60 {
            text = model.t("Next refresh in \(remaining / 60)m")
        } else {
            text = model.t("Next refresh in \(remaining)s")
        }
        return "\(version) · \(text)"
    }
}
