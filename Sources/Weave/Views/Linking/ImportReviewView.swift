import SwiftUI
import WeaveCore

/// 첫 가져오기 검토 — 무엇이 들어가고, 무엇이 합쳐지고, 무엇을 사람이 봐야 하는지.
/// 적용한 뒤에는 자동으로 채우지 못한 차이만 보여 준다.
struct ImportReviewView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let sourceID: UUID

    private var source: LinkedSource? { model.document.source(id: sourceID) }
    private var plan: ImportPlan? { model.pendingImports[sourceID]?.plan }
    private var mismatches: [HoldingMismatch] { plan?.unresolved ?? model.linkMismatches[sourceID] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Review import"), onBack: { model.pop() })

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let source {
                        Text([source.name, source.label].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.text2)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 8)
                    }

                    if let plan {
                        tiles(plan)
                        let overLimit = model.assetsOverLimit(plan)
                        if overLimit > 0 {
                            LinkNotice(
                                systemName: "exclamationmark.triangle.fill",
                                text: model.t("Weave holds up to \(AppModel.assetSoftLimit) assets, so \(overLimit) stock(s) won't be added. Free up assets and the next sync brings them in."),
                                tint: theme.orange
                            )
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                        }
                        newAssets(plan)
                        openingBalances(plan)
                        adjustments(plan)
                        duplicates(plan)
                    }
                    if !mismatches.isEmpty {
                        sectionLabel(model.t("Needs review"))
                        card {
                            rows(mismatches) { mismatch in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mismatch.instrument.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(theme.text)
                                    Text(model.mismatchText(mismatch))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(theme.text2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    } else if plan == nil {
                        Text(model.t("Nothing to review."))
                            .font(.system(size: 12))
                            .foregroundStyle(theme.text2)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                    }
                    if let plan, !plan.closedPositions.isEmpty {
                        Text(model.t("\(plan.closedPositions.count) sold-out stock(s) not in Weave were left out."))
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.text2)
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                    }
                }
                .padding(.bottom, 12)
            }

            footer
        }
    }

    // MARK: - 요약

    private func tiles(_ plan: ImportPlan) -> some View {
        HStack(spacing: 6) {
            tile(plan.newTradeCount, model.t("New trades"))
            tile(plan.duplicates.count, model.t("Duplicates"))
            tile(plan.unresolved.count, model.t("Needs review"), highlight: !plan.unresolved.isEmpty)
        }
        .padding(.horizontal, 14)
    }

    private func tile(_ count: Int, _ label: String, highlight: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text("\(count)")
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(highlight ? theme.orange : theme.text)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(highlight ? theme.orange : theme.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(highlight ? theme.orange.opacity(0.14) : theme.panel)
        )
    }

    // MARK: - 항목

    @ViewBuilder
    private func newAssets(_ plan: ImportPlan) -> some View {
        if !plan.missingAssets.isEmpty {
            sectionLabel(model.t("New assets"))
            card {
                rows(plan.missingAssets) { instrument in
                    HStack {
                        Text(instrument.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Spacer()
                        Text(instrument.symbol)
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.text2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func openingBalances(_ plan: ImportPlan) -> some View {
        if !plan.openingBalances.isEmpty {
            sectionLabel(model.t("Opening balance"))
            card {
                rows(plan.openingBalances) { trade in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(trade.instrument.name) \(MoneyFormatter.quantity(trade.quantity))")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.text)
                        Text(model.t("Holdings older than the order history start at \(MoneyFormatter.price(trade.price, currency: trade.instrument.currency)), matched to the account's average cost."))
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func adjustments(_ plan: ImportPlan) -> some View {
        let adjusted = plan.mismatches.filter(\.adjusted)
        if !adjusted.isEmpty {
            sectionLabel(model.t("Balance adjustment"))
            card {
                rows(adjusted) { mismatch in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(mismatch.instrument.name) \(mismatch.difference > 0 ? "+" : "")\(MoneyFormatter.quantity(mismatch.difference))")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.text)
                        Text(model.mismatchText(mismatch))
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func duplicates(_ plan: ImportPlan) -> some View {
        let manual = plan.duplicates.compactMap { duplicate in
            model.document.trades.first { $0.id == duplicate.manualTradeID }
        }
        if !manual.isEmpty {
            sectionLabel(model.t("Duplicates"))
            card {
                rows(manual) { trade in
                    let asset = model.asset(id: trade.assetID)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(asset?.name ?? "") · \(MoneyFormatter.quantity(trade.quantity)) @ \(MoneyFormatter.price(trade.price, currency: asset?.currency ?? "KRW"))")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.text)
                        Text(model.t("Entered manually on \(trade.date.formatted(.dateTime.month().day().locale(model.locale))). The imported record replaces it."))
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.text2)
                    }
                }
            }
        }
    }

    // MARK: - 하단

    private var footer: some View {
        HStack(spacing: 8) {
            if let plan {
                Button { model.pop() } label: {
                    Text(model.t("Later"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .frame(width: 88)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.seg))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                LinkPrimaryButton(title: applyTitle(plan)) {
                    model.applyPendingImport(sourceID: sourceID)
                    model.pop()
                }
            } else {
                LinkPrimaryButton(title: model.t("Done")) { model.pop() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hair).frame(height: 1)
        }
    }

    private func applyTitle(_ plan: ImportPlan) -> String {
        let added = model.t("Add \(plan.trades.count) trade(s)")
        guard !plan.duplicates.isEmpty else { return added }
        return added + " · " + model.t("merge \(plan.duplicates.count)")
    }

    // MARK: - 레이아웃

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .textCase(.uppercase)
            .foregroundStyle(theme.caps)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        PanelCard(padding: EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12)) {
            content()
        }
        .padding(.horizontal, 14)
    }

    private func rows<Item>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> some View
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle().fill(theme.hair).frame(height: 1)
                }
                row(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
    }
}
