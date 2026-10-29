import SwiftUI
import WeaveCore

/// 첫 가져오기 검토 — 자산마다 한 줄로, 그 자산에 무엇이 일어나는지(이동·새로 시작·체결·합침·확인)를 짧게.
/// 적용한 뒤에는 자동으로 채우지 못한 차이만 보여 준다.
struct ImportReviewView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let sourceID: UUID
    @State private var showsSkipped = false

    private var source: LinkedSource? { model.document.source(id: sourceID) }
    private var isWallet: Bool { source?.kind.isWallet ?? false }
    private var pending: PendingImport? { model.pendingImports[sourceID] }
    private var mismatches: [HoldingMismatch] { pending?.plan.unresolved ?? model.linkMismatches[sourceID] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Review import"), onBack: { model.pop() })

            ScrollView {
                VStack(spacing: 0) {
                    if let pending {
                        let groups = groups(pending)
                        hero(groups)
                        overLimitNotice(pending.plan)
                        if !groups.isEmpty {
                            LinkCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                                        if index > 0 { HairDivider(inset: 50) }
                                        GroupRow(group: group)
                                    }
                                }
                            }
                            .padding(.top, 12)
                        }
                        skippedSection(pending)
                        if !pending.plan.closedPositions.isEmpty {
                            footnote(model.t("\(pending.plan.closedPositions.count) sold-out stock(s) not in Weave were left out."))
                        }
                    } else if !mismatches.isEmpty {
                        CapsLabel(text: model.t("Needs review"))
                        LinkCard {
                            VStack(spacing: 0) {
                                ForEach(Array(mismatches.enumerated()), id: \.offset) { index, mismatch in
                                    if index > 0 { HairDivider() }
                                    mismatchRow(mismatch)
                                }
                            }
                        }
                    } else {
                        Text(model.t("Nothing to review."))
                            .font(.system(size: 12))
                            .foregroundStyle(theme.text2)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 12)
            }

            footer
        }
    }

    // MARK: - 요약

    private func hero(_ groups: [ImportGroup]) -> some View {
        // 시세를 모르는 종목이 있으면 합계를 지어내지 않고 뺀다.
        let total: Decimal? = groups.allSatisfy { $0.value != nil }
            ? groups.reduce(Decimal(0)) { $0 + model.amountInBase($1.value ?? 0, currency: $1.asset.currency) }
            : nil
        let unresolved = groups.reduce(0) { $0 + $1.lines.filter(\.isWarning).count }
        return VStack(spacing: 4) {
            if let source {
                Text([source.name, source.label].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text2)
                    .lineLimit(1)
            }
            if let total {
                Text(MoneyFormatter.price(total, currency: model.settings.baseCurrency))
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .privacyBlur(model.settings.privacyMode)
            }
            HStack(spacing: 0) {
                Text(counted(groups.count, isWallet ? "coin" : "holding") + " to import")
                    .foregroundStyle(theme.text2)
                Text(" · ").foregroundStyle(theme.text2)
                Text(unresolved == 0 ? model.t("nothing to check") : model.t("\(unresolved) to check"))
                    .foregroundStyle(unresolved == 0 ? theme.greenText : theme.orange)
                    .fontWeight(unresolved == 0 ? .regular : .semibold)
            }
            .font(.system(size: 11.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func overLimitNotice(_ plan: ImportPlan) -> some View {
        let overLimit = model.assetsOverLimit(plan)
        if overLimit > 0 {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.top, 1)
                Text(model.t("Weave holds up to \(AppModel.assetSoftLimit) assets, so \(overLimit) stock(s) won't be added. Free up assets and the next sync brings them in."))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(theme.orange)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.orange.opacity(0.12)))
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
    }

    // MARK: - 자산별 묶음

    /// 계획을 자산별로 묶는다 — 큰 것부터.
    private func groups(_ pending: PendingImport) -> [ImportGroup] {
        let plan = pending.plan
        var order: [ImportInstrument] = []
        func note(_ instrument: ImportInstrument) {
            if !order.contains(instrument) { order.append(instrument) }
        }
        plan.trades.filter { !$0.isManualSide }.forEach { note($0.instrument) }
        plan.unresolved.forEach { note($0.instrument) }

        let missing = Set(plan.missingAssets)
        let duplicateIDs = Set(plan.duplicates.map(\.externalID))
        return order.map { instrument in
            let asset = model.previewAsset(for: instrument)
            let holding = pending.snapshot.holdings.first { $0.instrument == instrument }
            // 받은 현재가(지갑·토스), 없으면 이미 있는 자산의 시세로.
            let price = holding?.marketPrice ?? model.quotes[asset.id]?.price
            let value = holding.flatMap { holding in price.map { $0 * holding.quantity } }
            let trades = plan.trades.filter { $0.instrument == instrument && !$0.isManualSide }
            let merged = trades.filter { $0.externalID.map(duplicateIDs.contains) ?? false }.count
            var lines = trades.compactMap { line(for: $0, asset: asset) }
            let orders = trades.filter { !$0.isOpeningBalance && !$0.isAdjustment && !$0.isTransfer }
            if !orders.isEmpty {
                lines.append(GroupLine(label: model.t("Orders"), detail: model.t("\(orders.count) from history")))
            }
            if merged > 0 {
                lines.append(GroupLine(label: model.t("Merged"), detail: model.t("\(merged) trade(s) you entered by hand")))
            }
            lines += plan.unresolved.filter { $0.instrument == instrument }.map {
                GroupLine(label: model.t("Check"), detail: model.mismatchShortText($0), isWarning: true)
            }
            return ImportGroup(
                instrument: instrument, asset: asset, isNew: missing.contains(instrument),
                quantity: holding?.quantity, value: value, lines: lines
            )
        }
        .sorted { model.amountInBase($0.value ?? 0, currency: $0.asset.currency) > model.amountInBase($1.value ?? 0, currency: $1.asset.currency) }
    }

    /// 거래 하나가 그 자산에 하는 일 — 체결은 묶어서 따로 센다.
    private func line(for trade: PlannedTrade, asset: Asset) -> GroupLine? {
        let quantity = "\(asset.shortQuantity(trade.quantity)) \(asset.symbol)"
        let price = MoneyFormatter.price(trade.price, currency: trade.instrument.currency)
        if trade.isTransfer {
            return trade.side == .buy
                ? GroupLine(label: model.t("Moved"), detail: model.t("\(quantity) from manual · avg \(price)"))
                : GroupLine(label: model.t("Back to manual"), detail: model.t("\(quantity) · avg \(price)"))
        }
        if trade.isAdjustment {
            let sign = trade.side == .buy ? "+" : "−"
            return GroupLine(label: model.t("Adjusted"), detail: "\(sign)\(quantity) · \(price)")
        }
        if trade.isOpeningBalance {
            return isWallet
                ? GroupLine(label: model.t("New"), detail: model.t("\(quantity) · today's price \(price)"))
                : GroupLine(label: model.t("Opening"), detail: model.t("\(quantity) · avg \(price)"))
        }
        return nil
    }

    private func mismatchRow(_ mismatch: HoldingMismatch) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AssetLogoView(asset: model.previewAsset(for: mismatch.instrument), size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(mismatch.instrument.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(model.mismatchText(mismatch))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    // MARK: - 가져오지 않은 잔고

    @ViewBuilder
    private func skippedSection(_ pending: PendingImport) -> some View {
        let snapshot = pending.snapshot
        let skipped = snapshot.holdings
            .filter { snapshot.dust.contains($0.instrument) || snapshot.unsettled.contains($0.instrument) }
            .sorted { $0.quantity * ($0.marketPrice ?? 0) > $1.quantity * ($1.marketPrice ?? 0) }
        if isWallet, !skipped.isEmpty {
            let total = skipped.reduce(Decimal(0)) { $0 + $1.quantity * ($1.marketPrice ?? 0) }
            LinkCard {
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { showsSkipped.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 0) {
                                    Text(counted(skipped.count, "balance") + " skipped")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(theme.text)
                                    Text(" · " + model.t("\(MoneyFormatter.price(total, currency: "USD")) total"))
                                        .font(.system(size: 12))
                                        .foregroundStyle(theme.text2)
                                        .privacyBlur(model.settings.privacyMode)
                                }
                                Text(model.t("Under $10 or no Binance price"))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(theme.text2)
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.text2)
                                .rotationEffect(.degrees(showsSkipped ? 180 : 0))
                        }
                        .padding(12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showsSkipped {
                        ForEach(Array(skipped.prefix(10).enumerated()), id: \.offset) { _, holding in
                            HairDivider()
                            HStack {
                                Text(holding.instrument.displaySymbol)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(theme.text)
                                Text(MoneyFormatter.quantity(holding.quantity))
                                    .font(.system(size: 10.5))
                                    .monospacedDigit()
                                    .foregroundStyle(theme.text2)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(snapshot.unsettled.contains(holding.instrument)
                                    ? model.t("No price")
                                    : MoneyFormatter.price(holding.quantity * (holding.marketPrice ?? 0), currency: "USD"))
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(theme.text2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        }
                        if skipped.count > 10 {
                            HairDivider()
                            Text(model.t("and \(skipped.count - 10) more"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.text2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                        }
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(theme.text2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 10)
    }

    // MARK: - 하단

    private var footer: some View {
        HStack(spacing: 8) {
            if let pending {
                Button { model.pop() } label: {
                    Text(model.t("Later"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .frame(width: 88)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 9).fill(theme.seg))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                LinkPrimaryButton(title: applyTitle(pending)) {
                    model.applyPendingImport(sourceID: sourceID)
                    model.pop()
                }
            } else {
                LinkPrimaryButton(title: model.t("Done")) { model.pop() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { HairDivider() }
    }

    private func applyTitle(_ pending: PendingImport) -> String {
        let plan = pending.plan
        if isWallet {
            let coins = Set(plan.trades.filter { !$0.isManualSide }.map(\.instrument)).count
            return "Import " + counted(coins, "coin")
        }
        let added = model.t("Add \(plan.trades.count) trade(s)")
        guard !plan.duplicates.isEmpty else { return added }
        return added + " · " + model.t("merge \(plan.duplicates.count)")
    }
}

// MARK: - 행

private struct GroupLine {
    let label: String
    let detail: String
    var isWarning = false
}

private struct ImportGroup: Identifiable {
    let instrument: ImportInstrument
    let asset: Asset
    let isNew: Bool
    /// 계좌·지갑의 실제 보유. 다 판 종목이면 nil.
    let quantity: Decimal?
    /// 원래 통화 기준 평가액.
    let value: Decimal?
    let lines: [GroupLine]

    var id: ImportInstrument { instrument }
}

private struct GroupRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let group: ImportGroup

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AssetLogoView(asset: group.asset, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(group.asset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    if group.isNew {
                        LinkTag(text: model.t("New asset"), style: .blue)
                    }
                }
                ForEach(Array(group.lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(line.label)
                            .fontWeight(.semibold)
                            .foregroundStyle(line.isWarning ? theme.orange : theme.text)
                        Text(line.detail)
                            .foregroundStyle(theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(group.value.map { MoneyFormatter.price($0, currency: group.asset.currency) } ?? "—")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                if let quantity = group.quantity {
                    Text("\(group.asset.shortQuantity(quantity)) \(group.asset.symbol)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.text2)
                        .lineLimit(1)
                }
            }
            .monospacedDigit()
            .privacyBlur(model.settings.privacyMode)
        }
        .padding(12)
    }
}
