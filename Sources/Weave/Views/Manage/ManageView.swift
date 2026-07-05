import SwiftUI
import WeaveCore

/// 자산 관리 & 검색 (홈 footer ✎로 진입).
struct ManageView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    @State private var deletionTarget: Asset?

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
                                ManagedAssetRow(asset: asset) {
                                    deletionTarget = asset
                                }
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .confirmationDialog(
            model.t("Delete asset?"),
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(model.t("Delete"), role: .destructive) {
                if let target = deletionTarget {
                    model.deleteAsset(id: target.id)
                }
                deletionTarget = nil
            }
            Button(model.t("Cancel"), role: .cancel) { deletionTarget = nil }
        } message: {
            if let target = deletionTarget {
                Text(model.t("\(target.name) and \(model.tradeCount(assetID: target.id)) trade(s) will be deleted."))
            }
        }
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
        HStack {
            IconButton(systemName: "chevron.left", action: onBack)
            Spacer()
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Spacer()
            trailing
                .frame(minWidth: 26, alignment: .trailing)
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
            }
            Spacer(minLength: 6)

            if !asset.isManual {
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
