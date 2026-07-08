import SwiftUI
import WeaveCore

/// 자산 관리 & 검색 (홈 footer ✎로 진입).
struct ManageView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    @State private var deletionTarget: Asset?
    @State private var valueEditTarget: Asset?
    @State private var valueEditText = ""

    private var isShowingSearch: Bool {
        model.searchQuery.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Assets")) {
                model.pop()
            }

            SearchSection()

            if !isShowingSearch {
                manualAssetButton

                if !model.document.assets.isEmpty {
                    CapsHeader(text: model.t("Holdings"))
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.document.assets) { asset in
                                ManagedAssetRow(
                                    asset: asset,
                                    onDelete: { deletionTarget = asset },
                                    onEditValue: {
                                        valueEditText = MoneyFormatter.quantity(asset.manualValue ?? 0)
                                        valueEditTarget = asset
                                    }
                                )
                            }
                        }
                        .disableHorizontalScrollBounce()
                    }
                }
            }

            Spacer(minLength: 0)
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
        .onChange(of: valueEditText) { _, newValue in
            // 숫자만 + 천단위 콤마 (멱등이라 가드 불필요).
            let formatted = MoneyFormatter.groupedInputText(newValue)
            if formatted != newValue {
                valueEditText = formatted
            }
        }
        .inputDialog(
            $valueEditTarget,
            title: { _ in model.t("Edit value") },
            message: { "\($0.name) · \($0.currency)" },
            placeholder: model.t("Value"),
            text: $valueEditText,
            confirmTitle: model.t("Save"),
            cancelTitle: model.t("Cancel"),
            onConfirm: { target in
                if let value = Decimal.clean(valueEditText) {
                    model.updateManualValue(assetID: target.id, value: value)
                }
            }
        )
    }

    private var manualAssetButton: some View {
        Button {
            model.push(.manualAssetForm)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12, weight: .medium))
                Text(model.t("Add Manual Asset…"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(theme.link)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.seg))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(model.isAtAssetLimit)
        .opacity(model.isAtAssetLimit ? 0.45 : 1)
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }
}

/// 공통 화면 헤더 — ‹ 뒤로 · 타이틀 · (옵션) 우측 액션.
struct ScreenHeader<Trailing: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    init(title: String, onBack: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        // 타이틀은 전체 폭 중앙에 절대 배치, 버튼은 양끝에 얹어 좌우 폭과 무관하게 정확히 중앙.
        ZStack {
            // ZStack 기본 center 정렬 → 타이틀은 전체 폭 정중앙.
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .padding(.horizontal, 34)
            HStack {
                IconButton(systemName: "chevron.left", action: onBack)
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

private struct ManagedAssetRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let asset: Asset
    let onDelete: () -> Void
    let onEditValue: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AssetLogoView(asset: asset)
            VStack(alignment: .leading, spacing: 1) {
                Text(asset.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(asset.isHidden ? theme.text2 : theme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text2)
                    .lineLimit(1)
                    .privacyBlur(model.settings.privacyMode && asset.isManual)
            }
            Spacer(minLength: 6)

            if asset.isManual {
                rowIcon(
                    systemName: "pencil",
                    active: false,
                    help: model.t("Edit value"),
                    action: onEditValue
                )
            } else {
                rowIcon(
                    systemName: "menubar.rectangle",
                    active: asset.showInMenuBar,
                    help: model.t("Show in menu bar")
                ) {
                    model.toggleMenuBar(assetID: asset.id)
                }
            }

            colorPicker

            rowIcon(
                systemName: asset.isHidden ? "eye" : "eye.slash",
                active: asset.isHidden,
                help: asset.isHidden ? model.t("Unhide") : model.t("Hide")
            ) {
                model.toggleHidden(assetID: asset.id)
            }

            rowIcon(systemName: "trash", active: false, help: model.t("Delete"), action: onDelete)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .hoverHighlight()
    }

    private var subtitle: String {
        if asset.isManual {
            return model.t("Manual · \(MoneyFormatter.price(asset.manualValue ?? 0, currency: asset.currency))")
        }
        return "\(asset.symbol) · \(model.t("\(model.tradeCount(assetID: asset.id)) trade(s)"))"
    }

    private func rowIcon(
        systemName: String,
        active: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? theme.link : theme.text2)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var colorPicker: some View {
        Menu {
            ForEach(0..<8, id: \.self) { index in
                Button {
                    model.setColor(assetID: asset.id, colorIndex: index)
                } label: {
                    HStack {
                        Image(systemName: index == asset.colorIndex ? "circle.fill" : "circle")
                        Text(model.t("Color \(index + 1)"))
                    }
                }
            }
        } label: {
            Circle()
                .fill(theme.paletteColor(asset.colorIndex))
                .frame(width: 12, height: 12)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22, height: 22)
        .help(model.t("Change color"))
    }
}
