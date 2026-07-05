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
    /// 자동 계산이 서로를 다시 트리거하지 않게 하는 가드.
    @State private var isAutofilling = false

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
                            if case .exceedsHolding = error {
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
        .onChange(of: date) {
            error = nil
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

    private func autofill(edited: TradeFormCalculator.Field) {
        guard !isAutofilling else { return }
        isAutofilling = true
        defer { isAutofilling = false }

        let values = TradeFormCalculator.autofill(
            .init(
                quantity: Decimal.clean(quantityText),
                price: Decimal.clean(priceText),
                amount: Decimal.clean(amountText)
            ),
            edited: edited
        )
        // 파생 필드만 갱신 — 사용자가 만진 필드는 그대로.
        if edited != .quantity, let quantity = values.quantity, Decimal.clean(quantityText) != quantity {
            quantityText = MoneyFormatter.quantity(quantity).replacingOccurrences(of: ",", with: "")
        }
        if edited != .price, let price = values.price, Decimal.clean(priceText) != price {
            priceText = MoneyFormatter.quantity(price).replacingOccurrences(of: ",", with: "")
        }
        if edited != .amount, let amount = values.amount, Decimal.clean(amountText) != amount {
            amountText = MoneyFormatter.quantity(amount).replacingOccurrences(of: ",", with: "")
        }
    }

    private func prefillFromEditing() {
        guard let editing else { return }
        side = editing.side
        quantityText = MoneyFormatter.quantity(editing.quantity).replacingOccurrences(of: ",", with: "")
        priceText = MoneyFormatter.quantity(editing.price).replacingOccurrences(of: ",", with: "")
        amountText = MoneyFormatter.quantity(editing.amount).replacingOccurrences(of: ",", with: "")
        date = editing.date
        note = editing.note
    }

    /// 과거 날짜 선택 → 그날 종가를 단가에 프리필(수정 가능).
    private func prefillClosingPrice() {
        guard !Calendar.current.isDateInToday(date) else { return }
        isPrefilling = true
        Task {
            let close = await model.closingPrice(assetID: assetID, on: date)
            isPrefilling = false
            guard let close else { return }
            isAutofilling = true
            priceText = MoneyFormatter.quantity(close).replacingOccurrences(of: ",", with: "")
            isAutofilling = false
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
