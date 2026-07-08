import Charts
import SwiftUI
import WeaveCore

/// 거래 입력 — 차트에서 지점 선택(클릭) 시 날짜/단가 매핑,
/// 수량/단가/총액 2개 입력 시 자동 계산, 과거 날짜 종가 프리필, 매도 검증.
struct TradeFormView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let assetID: UUID
    let editing: Trade?
    let prefill: TradePrefill?

    @State private var side: TradeSide = .buy
    @State private var quantityText = ""
    @State private var priceText = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var error: AppModel.TradeError?
    @State private var isPrefilling = false
    @State private var prefillTask: Task<Void, Never>?
    @State private var showDatePicker = false
    /// 폼 미니 차트용 일봉 — 상세 차트와 별개로 항상 일봉.
    @State private var chartCandles: [Candle] = []
    /// 차트 선택/프리필로 날짜를 바꿀 때 종가 프리필이 단가를 덮지 않게 하는 가드.
    @State private var suppressDatePrefill = false
    /// 프로그램이 방금 써넣은 필드 — 그 필드의 onChange는 자동 계산을 다시 돌리지 않는다.
    /// (SwiftUI onChange는 다음 업데이트 패스에 발화하므로 Bool 가드로는 못 막는다.)
    @State private var pendingProgrammatic: Set<TradeFormCalculator.Field> = []

    private var asset: Asset? { model.asset(id: assetID) }

    private var quantity: Decimal? { Decimal.clean(quantityText) }
    private var price: Decimal? { Decimal.clean(priceText) }

    private var availableQuantity: Decimal {
        PositionCalculator.availableQuantity(
            at: date,
            trades: model.document.trades(for: assetID),
            excluding: editing?.id
        )
    }

    private var sellExceedsHolding: Bool {
        guard side == .sell, let quantity else { return false }
        return quantity > availableQuantity
    }

    /// 저장 버튼 활성 여부 = 실제 저장 검증과 동일(전체 이력 oversell 포함).
    /// 이전엔 그 날짜 시점만 봐서 버튼은 켜졌는데 저장은 조용히 거부되는 경우가 있었다.
    private var validationError: AppModel.TradeError? {
        guard let quantity, let price, quantity > 0, price >= 0 else { return .invalidInput }
        return model.validateTrade(
            assetID: assetID, side: side, quantity: quantity,
            price: price, date: date, editingID: editing?.id
        )
    }

    private var canSave: Bool { validationError == nil }

    /// 수량 소수 자리 — 국장·일장 정수(0), 그 외(코인·미국주식) 8자리. 크기와 무관.
    private var quantityFractionDigits: Int {
        (asset?.market.tradesWholeShares ?? false) ? 0 : 8
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: editing == nil ? model.t("Add Trade") : model.t("Edit Trade")
            ) {
                model.pop()
            }

            ScrollView {
                VStack(spacing: 10) {
                    // 일봉 차트 — 마우스 호버 시 가격 표시, 클릭하면 날짜·단가가 폼에 채워진다.
                    if let asset, !chartCandles.isEmpty {
                        TradePickerChart(
                            asset: asset,
                            candles: chartCandles,
                            selectedDate: date,
                            selectedPrice: price
                        ) { candle in
                            applyChartSelection(candle)
                        }
                    }

                    SegmentedPills(
                        options: [(TradeSide.buy, model.t("Buy")), (TradeSide.sell, model.t("Sell"))],
                        selection: $side
                    )
                    .padding(.horizontal, 2)

                    PanelCard(padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                        VStack(spacing: 0) {
                            numberRow(label: model.t("Quantity"), text: $quantityText, field: .quantity)
                            divider
                            numberRow(
                                label: model.t("Price (\(asset?.currency ?? ""))"),
                                text: $priceText, field: .price
                            )
                            divider
                            numberRow(label: model.t("Total"), text: $amountText, field: .amount)
                            divider
                            dateRow
                            divider
                            HStack {
                                Text(model.t("Note"))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(theme.text)
                                Spacer()
                                TextField(model.t("Optional"), text: $note)
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(size: 12.5))
                            }
                            .padding(.vertical, 9)
                        }
                    }

                    if side == .sell {
                        HStack(spacing: 4) {
                            Text(model.t("Available: \(MoneyFormatter.quantity(availableQuantity, maxFractionDigits: quantityFractionDigits))"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.text2)
                            if sellExceedsHolding {
                                Text(model.t("— exceeds holding"))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(theme.redText)
                            }
                        }
                    }

                    // 저장이 거부된 이유(전체 이력 검증 실패 등) — 조용한 무동작 방지.
                    if let error {
                        Text(errorText(error))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.redText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    saveButton
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
            }
        }
        .onAppear(perform: applyInitialValues)
        .task { chartCandles = await model.dailyCandles(assetID: assetID) }
        .onDisappear { prefillTask?.cancel() }
        .onChange(of: date) { _, newDate in
            error = nil
            if suppressDatePrefill {
                suppressDatePrefill = false
                return
            }
            // 날짜에 따라 매도 가능 수량이 달라진다.
            clampSellQuantity()
            // 편집 로드로 세팅된 날짜(원래 체결일)는 프리필하지 않는다 — 체결가 보존.
            if let editing, Calendar.current.isDate(newDate, inSameDayAs: editing.date) {
                return
            }
            prefillClosingPrice()
        }
        .onChange(of: side) {
            error = nil
            clampSellQuantity()
        }
    }

    private var divider: some View {
        Divider().overlay(theme.hair)
    }

    // MARK: - 날짜 행 (커스텀 pill + 달력 팝오버)

    private var dateRow: some View {
        HStack {
            Text(model.t("Date"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.text)
            Spacer()
            if isPrefilling {
                ProgressView().controlSize(.mini)
            }
            Button {
                showDatePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.text2)
                    Text(date.formatted(.dateTime.year().month().day().locale(model.locale)))
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.text)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).fill(theme.seg))
                .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                DatePicker(
                    "", selection: $date,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(10)
                .frame(width: 240)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - 숫자 입력 행

    private func numberRow(
        label: String,
        text: Binding<String>,
        field: TradeFormCalculator.Field
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.text)
            Spacer()
            TextField("0", text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .frame(maxWidth: 140)
                .onChange(of: text.wrappedValue) { _, newValue in
                    error = nil
                    // 자동 계산이 써넣은 변경이면 여기서 끝 — 사용자 입력만 재계산 트리거.
                    if pendingProgrammatic.remove(field) != nil { return }
                    // 숫자·소수점만 허용 + 천단위 콤마 자동. 수량은 자산별 소수 자리로 캡.
                    var formatted = MoneyFormatter.groupedInputText(
                        newValue,
                        maxFractionDigits: field == .quantity ? quantityFractionDigits : nil
                    )
                    // 매도 수량이 보유 최대치를 넘으면 최대치로 자동 클램프(내림 절삭).
                    if side == .sell, field == .quantity,
                       let entered = Decimal.clean(formatted), entered > availableQuantity {
                        formatted = MoneyFormatter.groupedInputText(
                            MoneyFormatter.quantity(availableQuantity, maxFractionDigits: quantityFractionDigits),
                            maxFractionDigits: quantityFractionDigits
                        )
                    }
                    if formatted != newValue {
                        setFieldText(field, formatted)
                    }
                    autofill(edited: field)
                }
        }
        .padding(.vertical, 9)
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(editing == nil ? model.t("Save Trade") : model.t("Update Trade"))
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(side == .buy ? theme.green : theme.red)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.45)
    }

    // MARK: - 자동 계산 / 프리필

    /// 프로그램적 필드 쓰기 — 실제로 값이 바뀔 때만 쓰고, 그 onChange는 무시되게 마킹.
    private func setFieldText(_ field: TradeFormCalculator.Field, _ newText: String) {
        switch field {
        case .quantity:
            guard quantityText != newText else { return }
            pendingProgrammatic.insert(.quantity)
            quantityText = newText
        case .price:
            guard priceText != newText else { return }
            pendingProgrammatic.insert(.price)
            priceText = newText
        case .amount:
            guard amountText != newText else { return }
            pendingProgrammatic.insert(.amount)
            amountText = newText
        }
    }

    /// 필드 표시용 숫자 — 수량은 자산별(코인 8자리/국장 0), 돈은 통화별(1↑2자리·1↓8·원엔 0).
    private func plainNumber(_ value: Decimal, field: TradeFormCalculator.Field) -> String {
        MoneyFormatter.quantity(value, maxFractionDigits: fractionDigits(for: field, value: value))
    }

    private func fractionDigits(for field: TradeFormCalculator.Field, value: Decimal) -> Int {
        switch field {
        case .quantity:
            return quantityFractionDigits
        case .price, .amount:
            let currency = (asset?.currency ?? "").uppercased()
            if ["KRW", "JPY"].contains(currency) { return 0 }
            return abs(value) >= 1 ? 2 : 8
        }
    }

    /// 매도로 전환/날짜 변경 등으로 보유 가능 수량이 줄었을 때 수량을 최대치로 맞춘다.
    private func clampSellQuantity() {
        guard side == .sell, let entered = quantity, entered > availableQuantity else { return }
        // 내림 절삭(groupedInputText) — 반올림으로 보유량을 넘기지 않게.
        setFieldText(.quantity, MoneyFormatter.groupedInputText(
            MoneyFormatter.quantity(availableQuantity, maxFractionDigits: quantityFractionDigits),
            maxFractionDigits: quantityFractionDigits
        ))
        autofill(edited: .quantity)
    }

    private func autofill(edited: TradeFormCalculator.Field) {
        let values = TradeFormCalculator.autofill(
            .init(
                quantity: Decimal.clean(quantityText),
                price: Decimal.clean(priceText),
                amount: Decimal.clean(amountText)
            ),
            edited: edited
        )
        // 파생 필드만 갱신 — 사용자가 만진 필드(edited)는 절대 건드리지 않는다.
        if edited != .quantity, let quantity = values.quantity, Decimal.clean(quantityText) != quantity {
            setFieldText(.quantity, plainNumber(quantity, field: .quantity))
        }
        if edited != .price, let price = values.price, Decimal.clean(priceText) != price {
            setFieldText(.price, plainNumber(price, field: .price))
        }
        if edited != .amount, let amount = values.amount, Decimal.clean(amountText) != amount {
            setFieldText(.amount, plainNumber(amount, field: .amount))
        }
    }

    /// 편집 진입/차트 더블클릭 프리필 초기값 적용.
    private func applyInitialValues() {
        if let editing {
            side = editing.side
            setFieldText(.quantity, plainNumber(editing.quantity, field: .quantity))
            setFieldText(.price, plainNumber(editing.price, field: .price))
            setFieldText(.amount, plainNumber(editing.amount, field: .amount))
            date = editing.date
            note = editing.note
            return
        }
        if let prefill {
            suppressDatePrefill = true
            date = prefill.date
            setFieldText(.price, plainNumber(prefill.price, field: .price))
            autofill(edited: .price)
        }
    }

    /// 차트 지점 클릭 → 날짜·단가 매핑. 수량만 입력하면 되는 상태로.
    private func applyChartSelection(_ candle: Candle) {
        prefillTask?.cancel()
        isPrefilling = false
        suppressDatePrefill = true
        date = min(candle.date, Date())
        setFieldText(.price, plainNumber(candle.close, field: .price))
        autofill(edited: .price)
        error = nil
    }

    /// 과거 날짜 선택 → 그날 종가를 단가에 프리필(수정 가능).
    /// 연속 날짜 변경 시 이전 조회는 취소하고, 대기 중 사용자가 단가를 고쳤으면 덮지 않는다.
    private func prefillClosingPrice() {
        prefillTask?.cancel()
        guard !Calendar.current.isDateInToday(date) else { return }
        let requestedDate = date
        let priceSnapshot = priceText
        isPrefilling = true
        prefillTask = Task {
            let close = await model.closingPrice(assetID: assetID, on: requestedDate)
            guard !Task.isCancelled else { return }
            isPrefilling = false
            guard
                let close,
                Calendar.current.isDate(date, inSameDayAs: requestedDate),
                priceText == priceSnapshot
            else {
                return
            }
            setFieldText(.price, plainNumber(close, field: .price))
            autofill(edited: .price)
        }
    }

    /// 저장 거부 사유 문구.
    private func errorText(_ error: AppModel.TradeError) -> String {
        switch error {
        case .exceedsHolding(let available):
            let qty = asset?.formattedQuantity(available) ?? MoneyFormatter.quantity(available)
            return model.t("Can't sell more than you hold (\(qty))")
        case .invalidInput:
            return model.t("Enter a valid quantity and price")
        }
    }

    private func save() {
        guard let quantity, let price else { return }
        let result: AppModel.TradeError?
        if let editing {
            var updated = editing
            updated.side = side
            updated.quantity = quantity
            updated.price = price
            updated.date = date
            updated.note = note
            result = model.updateTrade(updated)
        } else {
            result = model.addTrade(
                assetID: assetID, side: side, quantity: quantity,
                price: price, date: date, note: note
            )
        }
        if let result {
            error = result
        } else {
            model.pop()
        }
    }
}

// MARK: - 지점 선택 차트

/// 거래 폼 상단 미니 차트 — 클릭한 지점의 캔들(날짜·종가)을 폼으로 넘긴다.
private struct TradePickerChart: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let asset: Asset
    let candles: [Candle]
    let selectedDate: Date
    let selectedPrice: Decimal?
    let onPick: (Candle) -> Void

    @State private var hoveredDate: Date?

    private var color: Color { theme.paletteColor(asset.colorIndex) }

    private var yDomain: ClosedRange<Double> {
        let values = candles.map { $0.close.doubleValue }
        guard let min = values.min(), let max = values.max(), min < max else {
            let v = values.first ?? 1
            return (v * 0.9)...(v * 1.1)
        }
        let pad = (max - min) * 0.12
        return (min - pad)...(max + pad)
    }

    /// 선택된 날짜에 대응하는 캔들(마커 표시용).
    private var selectedCandle: Candle? {
        nearestCandle(to: selectedDate)
    }

    /// 데이터 범위에 맞춘 x축 라벨 — 수년치 월봉에서 "1/1"만 반복되는 것 방지.
    private var xTickFormat: Date.FormatStyle {
        guard let first = candles.first?.date, let last = candles.last?.date else {
            return .dateTime.month(.defaultDigits).day().locale(model.locale)
        }
        let span = last.timeIntervalSince(first)
        if span > 3 * 365 * 86_400 {
            return .dateTime.year().locale(model.locale)
        }
        if span > 400 * 86_400 {
            return .dateTime.year(.twoDigits).month(.defaultDigits).locale(model.locale)
        }
        return .dateTime.month(.defaultDigits).day().locale(model.locale)
    }

    var body: some View {
        VStack(spacing: 4) {
            Chart {
                ForEach(candles, id: \.date) { candle in
                    LineMark(
                        x: .value("Date", candle.date),
                        y: .value("Price", candle.close.doubleValue)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                }

                if let hoveredDate, let candle = nearestCandle(to: hoveredDate) {
                    RuleMark(x: .value("Date", candle.date))
                        .foregroundStyle(theme.guide)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }

                if let selected = selectedCandle {
                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(color.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("Price", selected.close.doubleValue)
                    )
                    .symbolSize(46)
                    .foregroundStyle(color)
                }
            }
            .chartYScale(domain: yDomain)
            .chartPlotStyle { $0.clipped() }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(theme.grid)
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(
                                MoneyFormatter.compactPrice(
                                    Decimal.fromDouble(doubleValue), currency: asset.currency
                                )
                            )
                            .font(.system(size: 8.5))
                            .foregroundStyle(theme.xLabel)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: xTickFormat, anchor: .top)
                        .font(.system(size: 8.5))
                        .foregroundStyle(theme.xLabel)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let plotAnchor = proxy.plotFrame {
                        let plot = geo[plotAnchor]
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .frame(width: plot.width, height: plot.height)
                                .position(x: plot.midX, y: plot.midY)
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let point):
                                        let x = point.x - plot.origin.x
                                        hoveredDate = proxy.value(atX: x, as: Date.self)
                                    case .ended:
                                        hoveredDate = nil
                                    }
                                }
                                .onTapGesture { location in
                                    let x = location.x - plot.origin.x
                                    guard
                                        let tapped = proxy.value(atX: x, as: Date.self),
                                        let candle = nearestCandle(to: tapped)
                                    else {
                                        return
                                    }
                                    onPick(candle)
                                }

                            // 호버 지점의 가격·날짜 툴팁.
                            if let hoveredDate,
                               let candle = nearestCandle(to: hoveredDate),
                               let x = proxy.position(forX: candle.date) {
                                TooltipBubble(
                                    text: MoneyFormatter.price(candle.close, currency: asset.currency),
                                    secondary: candle.date.formatted(
                                        .dateTime.year().month().day().locale(model.locale)
                                    ),
                                    blurText: model.settings.privacyMode
                                )
                                .fixedSize()
                                .position(
                                    x: min(max(plot.origin.x + x, plot.origin.x + 52), plot.maxX - 52),
                                    y: plot.origin.y + 18
                                )
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }
            }
            .frame(height: 120)

            Text(model.t("Tap the chart to fill date & price"))
                .font(.system(size: 9.5))
                .foregroundStyle(theme.caps)
        }
        .padding(.horizontal, 2)
    }

    private func nearestCandle(to date: Date) -> Candle? {
        candles.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }
}
