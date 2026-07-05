import SwiftUI
import WeaveCore

/// 거래 입력 — 수량/단가/총액 2개 입력 시 자동 계산, 과거 날짜 종가 프리필, 매도 검증.
struct TradeFormView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let assetID: UUID
    let editing: Trade?

    @State private var side: TradeSide = .buy
    @State private var quantityText = ""
    @State private var priceText = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var error: AppModel.TradeError?
    @State private var isPrefilling = false
    @State private var prefillTask: Task<Void, Never>?
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

    private var canSave: Bool {
        guard let quantity, let price, quantity > 0, price >= 0 else { return false }
        if side == .sell {
            return TradeFormCalculator.validateSell(quantity: quantity, available: availableQuantity)
        }
        return true
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
                            HStack {
                                Text(model.t("Date"))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(theme.text)
                                Spacer()
                                DatePicker(
                                    "", selection: $date,
                                    in: ...Date(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                if isPrefilling {
                                    ProgressView().controlSize(.mini)
                                }
                            }
                            .padding(.vertical, 6)
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
                            Text(model.t("Available: \(MoneyFormatter.quantity(availableQuantity))"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.text2)
                            if sellExceedsHolding {
                                Text(model.t("— exceeds holding"))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(theme.redText)
                            }
                        }
                    }

                    saveButton
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
            }
        }
        .onAppear(perform: prefillFromEditing)
        .onDisappear { prefillTask?.cancel() }
        .onChange(of: date) { _, newDate in
            error = nil
            // 편집 로드로 세팅된 날짜(원래 체결일)는 프리필하지 않는다 — 체결가 보존.
            if let editing, Calendar.current.isDate(newDate, inSameDayAs: editing.date) {
                return
            }
            prefillClosingPrice()
        }
        .onChange(of: side) { error = nil }
    }

    private var divider: some View {
        Divider().overlay(theme.hair)
    }

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
                .onChange(of: text.wrappedValue) {
                    error = nil
                    // 자동 계산이 써넣은 변경이면 여기서 끝 — 사용자 입력만 재계산 트리거.
                    if pendingProgrammatic.remove(field) != nil { return }
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

    private func plainNumber(_ value: Decimal) -> String {
        MoneyFormatter.quantity(value).replacingOccurrences(of: ",", with: "")
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
            setFieldText(.quantity, plainNumber(quantity))
        }
        if edited != .price, let price = values.price, Decimal.clean(priceText) != price {
            setFieldText(.price, plainNumber(price))
        }
        if edited != .amount, let amount = values.amount, Decimal.clean(amountText) != amount {
            setFieldText(.amount, plainNumber(amount))
        }
    }

    private func prefillFromEditing() {
        guard let editing else { return }
        side = editing.side
        setFieldText(.quantity, plainNumber(editing.quantity))
        setFieldText(.price, plainNumber(editing.price))
        setFieldText(.amount, plainNumber(editing.amount))
        date = editing.date
        note = editing.note
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
            setFieldText(.price, plainNumber(close))
            autofill(edited: .price)
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
