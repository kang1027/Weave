import SwiftUI
import WeaveCore

/// Manual Asset 입력 — 부동산·비상장 등 검색 불가 자산.
struct ManualAssetForm: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    @State private var name = ""
    @State private var currency = "KRW"
    @State private var valueText = ""
    @State private var includeInChart = true

    private var value: Decimal? {
        Decimal.clean(valueText)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (value ?? -1) >= 0
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Manual Asset")) {
                model.pop()
            }

            VStack(spacing: 10) {
                PanelCard(padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                    VStack(spacing: 0) {
                        formRow(label: model.t("Name")) {
                            TextField(model.t("e.g. Apartment"), text: $name)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 12.5))
                        }
                        Divider().overlay(theme.hair)
                        formRow(label: model.t("Currency")) {
                            Picker("", selection: $currency) {
                                ForEach(["KRW", "USD", "JPY"], id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 90)
                        }
                        Divider().overlay(theme.hair)
                        formRow(label: model.t("Value")) {
                            TextField("0", text: $valueText)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 12.5))
                                .monospacedDigit()
                        }
                        Divider().overlay(theme.hair)
                        formRow(label: model.t("Include in chart")) {
                            MiniToggle(isOn: $includeInChart)
                        }
                    }
                }

                Text(model.t("Manual assets have no price updates."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.text2)

                Button {
                    guard let value else { return }
                    model.addManualAsset(
                        name: name, currency: currency,
                        value: value, includeInChart: includeInChart
                    )
                } label: {
                    Text(model.t("Add Asset"))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.link))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
    }

    private func formRow(label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.text)
            Spacer()
            control()
        }
        .padding(.vertical, 9)
    }
}
