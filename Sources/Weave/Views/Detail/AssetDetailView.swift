import SwiftUI
import WeaveCore

/// 상세 차트 재조회 트리거 — 인터벌 또는 포커스 시점이 바뀌면 캔들을 다시 받는다.
private struct DetailLoadKey: Equatable {
    let interval: CandleInterval
    let focusDate: Date?
}

/// 자산 상세 — 현재가/배지 · 실캔들 차트 · Trades 리스트.
struct AssetDetailView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let assetID: UUID

    @State private var deletionTarget: Trade?
    @State private var isHoveringLogo = false
    @State private var isHoveringInvested = false
    @State private var highlightedTradeID: UUID?
    /// 거래 행 클릭 → 차트 마커 포커스 요청.
    @State private var chartFocusTradeID: UUID?
    @State private var isLive = false
    /// 인터벌 전환 후(로드 완료 시) 적용할 포커스 — 현재 인터벌 데이터 범위 밖 거래용.
    @State private var pendingFocusTradeID: UUID?

    /// 화면에 보이는 거래 — 지갑 이동은 지갑 쪽 한 줄만 보인다(직접 입력 쪽은 같은 이동의 짝).
    private var trades: [Trade] {
        model.document.trades(for: assetID).filter { !($0.isTransfer && !$0.isImported) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        if let asset = model.asset(id: assetID) {
            content(asset: asset)
        } else {
            // 삭제 직후 잔상 방지.
            Color.clear.onAppear { model.popToHome() }
        }
    }

    private func content(asset: Asset) -> some View {
        let metric = model.metrics(id: assetID)
        let position = metric?.position ?? PositionSnapshot()

        return VStack(spacing: 0) {
            detailHeader(asset: asset)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        priceSection(asset: asset, metric: metric, position: position)

                        if model.showsKimchiPremium(for: asset) {
                            KimchiPremiumCard(
                                asset: asset,
                                initial: model.cachedKimchiPremium(for: asset),
                                reservesSpace: model.reservesKimchiPremiumSpace(for: asset)
                            )
                        }

                        if asset.isManual {
                            manualSection(asset: asset)
                        } else {
                            DetailChart(
                                asset: asset,
                                // 차트 마커는 실제 체결만 — 지갑 이동과 잔고 맞춤은 시장에서 사고판 게 아니다.
                                trades: model.document.trades(for: assetID).filter { !$0.isTransfer && !$0.isBalanceAdjustment },
                                position: position,
                                isLive: isLive,
                                onSelectTrade: { tradeID in
                                    focusTrade(tradeID, using: scrollProxy)
                                },
                                focusRequest: $chartFocusTradeID
                            )
                            .padding(.top, 10)
                            .id("detail-chart")

                            // 지금 연결한 계좌·지갑에 남아 있는 몫이 있을 때만 — 직접 입력만이면 한 곳뿐이다.
                            if HoldingLocations.breakdown(trades: trades).contains(where: { $0.sourceID != nil }) {
                                CapsHeader(text: model.t("Where it's held"))
                                HoldingLocationsCard(asset: asset, trades: model.document.trades(for: assetID))
                            }

                            CapsHeader(text: model.t("Trades"))
                            realizedSummary(position: position, currency: asset.currency)
                            tradesList(asset: asset, scrollProxy: scrollProxy)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }

            footer(asset: asset, position: position)
        }
        .task(id: DetailLoadKey(interval: model.detailInterval, focusDate: model.detailFocusDate)) {
            await model.loadDetailChart(assetID: assetID)
        }
        .onDisappear {
            isLive = false
            model.stopDetailLive()
        }
        .onChange(of: model.detailCandles) {
            // 인터벌 전환으로 새 캔들이 도착하면, 대기 중이던 포커스를 적용한다.
            // 같은 사이클의 창 리셋(resetWindow)이 끝난 뒤 걸리도록 한 틱 미룬다.
            guard let id = pendingFocusTradeID else { return }
            pendingFocusTradeID = nil
            Task { @MainActor in chartFocusTradeID = id }
        }
        .confirmDialog(
            $deletionTarget,
            title: { _ in model.t("Delete trade?") },
            confirmTitle: model.t("Delete"),
            isDestructive: true,
            cancelTitle: model.t("Cancel"),
            onConfirm: { trade in
                if model.deleteTrade(id: trade.id) == .neededByMove {
                    model.presentAlert(
                        title: model.t("Can't delete this trade"),
                        message: model.t("Part of this buy moved to a wallet, so it can't be removed")
                    )
                }
            }
        )
    }

    // MARK: - 헤더 (로고 + 이름, 로고 클릭 = 아이콘 변경)

    private func detailHeader(asset: Asset) -> some View {
        HStack {
            IconButton(systemName: "chevron.left") {
                model.pop()
            }
            Spacer()
            HStack(spacing: 7) {
                AssetLogoView(asset: asset, size: 22)
                    // hover 시 "바꿀 수 있음" 어포던스 — 연필 오버레이 + 확대 + 손 커서.
                    .overlay {
                        if isHoveringLogo {
                            Circle()
                                .fill(.black.opacity(0.45))
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .scaleEffect(isHoveringLogo ? 1.15 : 1)
                    .animation(.easeOut(duration: 0.15), value: isHoveringLogo)
                    .contentShape(Circle())
                    .onHover { hovering in
                        isHoveringLogo = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .onTapGesture {
                        model.pickCustomLogo(assetID: asset.id)
                    }
                    .contextMenu {
                        Button(model.t("Change icon…")) {
                            model.pickCustomLogo(assetID: asset.id)
                        }
                        if asset.customLogoFileName != nil {
                            Button(model.t("Reset to default icon")) {
                                model.clearCustomLogo(assetID: asset.id)
                            }
                        }
                    }
                    .help(model.t("Click to change icon"))
                Text(asset.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }
            Spacer()
            Group {
                if !asset.isManual {
                    liveButton(asset: asset)
                    IconButton(systemName: "plus") {
                        model.push(.tradeForm(assetID: assetID, editing: nil, prefill: nil))
                    }
                    .help(model.t("Add Trade"))
                } else {
                    Color.clear.frame(width: 26, height: 26)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func liveButton(asset: Asset) -> some View {
        Button {
            isLive.toggle()
            if isLive {
                model.startDetailLive(assetID: asset.id)
            } else {
                model.stopDetailLive()
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(isLive ? theme.green : theme.text2)
                    .frame(width: 5, height: 5)
                Text(model.t("LIVE"))
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.4)
            }
            .foregroundStyle(isLive ? theme.greenText : theme.text2)
            .frame(height: 26)
            .padding(.horizontal, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isLive ? theme.green.opacity(0.16) : theme.iconBg)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(model.t("Live price updates"))
    }

    // MARK: - 현재가 + 배지

    private func priceSection(asset: Asset, metric: AssetMetrics?, position: PositionSnapshot) -> some View {
        // 미실현 평가손익 — 보유 중인 실물 자산일 때만(수량·평단 있음).
        let unrealized: (amount: Decimal, percent: Decimal, currency: String)? = {
            guard !asset.isManual, position.averageCost > 0,
                  let price = metric?.quote?.price, position.quantity > 0 else { return nil }
            let percent = ((price - position.averageCost) / position.averageCost * 100).rounded(scale: 2)
            let amount = (price - position.averageCost) * position.quantity
            return (amount, percent, metric?.quote?.currency ?? asset.currency)
        }()

        // 이 종목에 넣은 원금(보유분 취득원가) — 평단 × 보유수량.
        let invested: Decimal? = (!asset.isManual && position.averageCost > 0 && position.quantity > 0)
            ? position.averageCost * position.quantity : nil
        let currency = metric?.quote?.currency ?? asset.currency
        let day = metric?.dayChangePercent
        let dayText = day.map { MoneyFormatter.percent($0) }
        // 현재 보유 평가금액 = 현재가 × 보유수량.
        let holdingsValue: Decimal? = {
            guard !asset.isManual, let price = metric?.quote?.price, position.quantity > 0 else { return nil }
            return price * position.quantity
        }()

        return VStack(spacing: 5) {
            // 현재 단가(중앙) + 오늘 등락률(부호 색). 좌측 투명 사본으로 단가를 정중앙에.
            HStack(alignment: .center, spacing: 8) {
                if let dayText {
                    Text(dayText).font(.system(size: 14, weight: .semibold)).monospacedDigit().hidden()
                }
                Text(priceText(asset: asset, metric: metric))
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .kerning(-0.3)
                    .foregroundStyle(theme.text)
                    .privacyBlur(model.settings.privacyMode)
                if let dayText, let day {
                    Text(dayText)
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(day >= 0 ? theme.greenText : theme.redText)
                }
            }

            // 현재 보유 평가금액 + 수익률 — 투자금 대비 이익이면 초록, 손실이면 빨강.
            if let holdingsValue, let unrealized {
                HStack(spacing: 4) {
                    Text(MoneyFormatter.price(holdingsValue, currency: currency))
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .privacyBlur(model.settings.privacyMode)
                    Text("(\(MoneyFormatter.percent(unrealized.percent)))")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(theme.upDown(unrealized.amount >= 0))
            }
        }
        .padding(.top, 6)
        .contentShape(Rectangle())
        .onHover { isHoveringInvested = $0 }
        .overlay(alignment: .bottom) {
            if isHoveringInvested, let invested {
                TooltipBubble(
                    text: model.t("Invested") + " " + MoneyFormatter.price(invested, currency: currency),
                    secondary: unrealized.map {
                        model.t("Unrealized P&L") + " "
                            + MoneyFormatter.signedPrice($0.amount, currency: currency)
                    },
                    blurText: model.settings.privacyMode,
                    blurSecondary: model.settings.privacyMode
                )
                .offset(y: 26)
                .allowsHitTesting(false)
            }
        }
        .zIndex(1)
    }

    private func priceText(asset: Asset, metric: AssetMetrics?) -> String {
        if asset.isManual {
            return MoneyFormatter.price(asset.manualValue ?? 0, currency: asset.currency)
        }
        guard let quote = metric?.quote else { return "—" }
        return MoneyFormatter.price(quote.price, currency: quote.currency)
    }

    // MARK: - Trades

    private func realizedSummary(position: PositionSnapshot, currency: String) -> some View {
        HStack {
            Text(model.t("Realized P&L"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.text2)
            Spacer()
            Text(MoneyFormatter.signedPrice(position.realizedPnL, currency: currency))
                .font(.system(size: 11.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(position.realizedPnL >= 0 ? theme.greenText : theme.redText)
                .privacyBlur(model.settings.privacyMode)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func tradesList(asset: Asset, scrollProxy: ScrollViewProxy) -> some View {
        if trades.isEmpty {
            Text(model.t("No trades yet — tap + to record your first buy."))
                .font(.system(size: 11.5))
                .foregroundStyle(theme.text2)
                .padding(.top, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(trades) { trade in
                    TradeRow(
                        trade: trade,
                        asset: asset,
                        isHighlighted: highlightedTradeID == trade.id,
                        onFocusMarker: {
                            // 행 클릭 → 차트가 보이게 스크롤 + 해당 마커 포커스.
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scrollProxy.scrollTo("detail-chart", anchor: .center)
                            }
                            requestChartFocus(trade)
                        },
                        onDelete: {
                            deletionTarget = trade
                        }
                    )
                    .id(trade.id)
                }
            }
        }
    }

    /// 거래 행 클릭 → 차트 마커 포커스. 현재 인터벌 데이터에 그 시점이 있으면 바로 팬,
    /// 없으면(인트라데이의 오래된 거래) 인터벌은 유지한 채 그 거래일 구간을 재조회한 뒤 포커스.
    private func requestChartFocus(_ trade: Trade) {
        let candles = model.detailCandles
        var inRange = false
        if let first = candles.first?.date, let last = candles.last?.date {
            inRange = trade.date >= first && trade.date <= last
        }
        if inRange {
            chartFocusTradeID = trade.id
        } else if model.detailFocusDate == trade.date {
            // 이미 이 거래 시점으로 조회한 상태(소스에 그 구간이 없을 수도) → 가능한 데까지.
            chartFocusTradeID = trade.id
        } else {
            pendingFocusTradeID = trade.id
            model.detailFocusDate = trade.date   // .task(id:)가 재조회 → onChange에서 포커스
        }
    }

    /// 차트 B/S 마커 클릭 → 해당 거래 행으로 스크롤 + 잠깐 하이라이트.
    private func focusTrade(_ tradeID: UUID, using scrollProxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.25)) {
            scrollProxy.scrollTo(tradeID, anchor: .center)
            highlightedTradeID = tradeID
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if highlightedTradeID == tradeID {
                withAnimation(.easeOut(duration: 0.4)) {
                    highlightedTradeID = nil
                }
            }
        }
    }

    private func footer(asset: Asset, position: PositionSnapshot) -> some View {
        HStack {
            Text(countText(position: position))
                .font(.system(size: 11))
                .foregroundStyle(theme.caps)
            Spacer()
            if !asset.isManual {
                Button {
                    model.push(.tradeForm(assetID: assetID, editing: nil, prefill: nil))
                } label: {
                    Text(model.t("+ Add Trade"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.greenText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hair).frame(height: 1)
        }
    }

    /// 매수·매도 횟수 — 지갑 이동은 사고판 게 아니라 세지 않는다.
    private func countText(position: PositionSnapshot) -> String {
        let traded = trades.filter { !$0.isTransfer }
        let buys = traded.filter { $0.side == .buy }.count
        let sells = traded.count - buys
        let moves = trades.count - traded.count
        var parts: [String] = [model.t("\(buys) buys")]
        if sells > 0 {
            parts.append(model.t("\(sells) sells"))
        }
        if moves > 0 {
            parts.append(model.t(moves == 1 ? "1 move" : "\(moves) moves"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Manual

    private func manualSection(asset: Asset) -> some View {
        VStack(spacing: 10) {
            Text(model.t("Manual assets have no price updates."))
                .font(.system(size: 11.5))
                .foregroundStyle(theme.text2)
            Button {
                model.push(.manage)
            } label: {
                Text(model.t("Edit in asset manager"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.link)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 28)
    }
}

/// Trades 리스트 행 — 매수/매도 칩 · 수량@단가 · 우측 성과.
private struct TradeRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let trade: Trade
    let asset: Asset
    var isHighlighted = false
    var onFocusMarker: () -> Void = {}
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if trade.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundStyle(theme.text2)
                            .help(model.t("Imported trades can't be changed here"))
                    }
                    Text(subText)
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(theme.text2)
                        .lineLimit(1)
                        .privacyBlur(model.settings.privacyMode)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(rightValue)
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(trade.isTransfer ? theme.badgeGrayText : theme.text)
                    .lineLimit(1)
                    .privacyBlur(model.settings.privacyMode)
                if let change = changeText {
                    Text(change)
                        .font(.system(size: 10.5, weight: trade.isOpeningBalance ? .regular : .semibold))
                        .monospacedDigit()
                        .foregroundStyle(trade.isOpeningBalance ? theme.text2 : (changeIsUp ? theme.greenText : theme.redText))
                        .privacyBlur(model.settings.privacyMode && trade.side == .sell)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(theme.link.opacity(isHighlighted ? 0.16 : 0))
        .hoverHighlight()
        // 더블클릭 = 수정, 단일 클릭 = 차트 마커 포커스. (exclusively로 구분)
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    guard !trade.isLocked else { return }
                    model.push(.tradeForm(assetID: asset.id, editing: trade, prefill: nil))
                }
                .exclusively(
                    before: TapGesture().onEnded { onFocusMarker() }
                )
        )
        .contextMenu {
            if trade.isLocked {
                // 원본은 연결한 계좌·지갑 — 고치면 다음 동기화와 어긋난다.
                Text(trade.isImported
                    ? model.t("Imported from \(sourceName)")
                    : model.t("Moved with \(sourceName)"))
                Text(model.t("Imported trades can't be changed here"))
            } else {
                Button(model.t("Edit")) {
                    model.push(.tradeForm(assetID: asset.id, editing: trade, prefill: nil))
                }
                Button(model.t("Delete"), role: .destructive, action: onDelete)
            }
        }
    }

    private var sourceName: String {
        (trade.sourceID ?? trade.transferSourceID).flatMap(model.document.source(id:))?.name
            ?? model.t("Linked account")
    }

    /// 사고판 기록과 이동·기초 잔고가 한눈에 갈리게 — 모양과 색이 다른 동그라미.
    private var icon: some View {
        let (symbol, tint): (String, Color?) = {
            if trade.isTransfer { return ("arrow.left.arrow.right", nil) }
            if trade.isOpeningBalance { return ("flag.fill", theme.greenText) }
            if trade.isBalanceAdjustment { return ("plusminus", nil) }
            return trade.side == .buy ? ("arrow.down", theme.greenText) : ("arrow.up", theme.redText)
        }()
        return Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(tint ?? theme.badgeGrayText)
            .frame(width: 28, height: 28)
            .background(Circle().fill(tint.map { $0.opacity(0.14) } ?? theme.badgeGray))
    }

    private var quantityLabel: String {
        let qty = asset.formattedQuantity(trade.quantity)
        return asset.hasNumericSymbol
            ? model.t("\(qty) shares")
            : "\(qty) \(asset.symbol)"
    }

    /// 오른쪽 자리용 — 소수 자리를 줄인다.
    private var shortQuantityLabel: String {
        let qty = asset.shortQuantity(trade.quantity)
        return asset.hasNumericSymbol ? model.t("\(qty) shares") : "\(qty) \(asset.symbol)"
    }

    private var title: String {
        if trade.isTransfer {
            // 지갑 쪽 한 줄만 보인다 — 어디서 어디로 옮겼는지.
            let manual = model.t("Manual")
            return trade.side == .buy ? "\(manual) → \(sourceName)" : "\(sourceName) → \(manual)"
        }
        if trade.isOpeningBalance { return model.t("Opening balance · \(sourceName)") }
        if trade.isBalanceAdjustment { return model.t("Adjustment · \(sourceName)") }
        return trade.side == .buy ? model.t("Buy \(quantityLabel)") : model.t("Sell \(quantityLabel)")
    }

    private var subText: String {
        let price = MoneyFormatter.price(trade.price, currency: asset.currency)
        var parts = [dateText]
        if trade.isTransfer {
            parts.append(model.t("at avg cost \(price)"))
        } else if trade.isOpeningBalance {
            parts.append(model.t("price at link \(price)"))
        } else {
            parts.append(price)
            if trade.isImported, !trade.isBalanceAdjustment {
                parts.append(sourceName)
            } else if !trade.note.isEmpty {
                parts.append(trade.note)
            }
        }
        return parts.joined(separator: " · ")
    }

    /// 올해면 "Oct 29", 아니면 "Sep 15, 2024".
    private var dateText: String {
        let sameYear = Calendar.current.isDate(trade.date, equalTo: Date(), toGranularity: .year)
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(model.locale)
        return trade.date.formatted(sameYear ? style : style.year())
    }

    /// 오른쪽 위 — 사고판 기록은 금액, 이동·기초 잔고·잔고 맞춤은 수량.
    private var rightValue: String {
        if trade.isTransfer || trade.isOpeningBalance { return shortQuantityLabel }
        if trade.isBalanceAdjustment { return (trade.side == .buy ? "+" : "−") + shortQuantityLabel }
        return MoneyFormatter.price(trade.amount, currency: asset.currency)
    }

    /// 오른쪽 아래 — 매수·기초 잔고는 지금 대비 등락, 매도는 실현 손익. 이동은 없음.
    private var changeText: String? {
        if trade.isTransfer || trade.isBalanceAdjustment { return nil }
        switch trade.side {
        case .buy:
            guard let quote = model.quotes[asset.id], trade.price > 0 else { return nil }
            let percent = ((quote.price - trade.price) / trade.price * 100).rounded(scale: 1)
            return MoneyFormatter.percent(percent, fractionDigits: 1)
        case .sell:
            guard let pnl = model.realizedPnL(of: trade) else { return nil }
            return MoneyFormatter.signedPrice(pnl.rounded(scale: 2), currency: asset.currency)
        }
    }

    private var changeIsUp: Bool {
        switch trade.side {
        case .buy:
            guard let quote = model.quotes[asset.id] else { return true }
            return quote.price >= trade.price
        case .sell:
            return (model.realizedPnL(of: trade) ?? 0) >= 0
        }
    }
}
