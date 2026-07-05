import SwiftUI
import WeaveCore

// M4에서 실차트+거래 리스트로 채워지는 상세 스텁.
struct AssetDetailView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let assetID: UUID

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.asset(id: assetID)?.name ?? "") {
                model.pop()
            } trailing: {
                IconButton(systemName: "plus") {
                    model.push(.tradeForm(assetID: assetID, editing: nil))
                }
            }
            Spacer()
            Text(verbatim: "Detail — M4")
                .foregroundStyle(theme.text2)
            Spacer()
        }
    }
}

struct TradeFormView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let assetID: UUID
    let editing: Trade?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Add Trade")) {
                model.pop()
            }
            Spacer()
            Text(verbatim: "Trade Form — M4")
                .foregroundStyle(theme.text2)
            Spacer()
        }
    }
}
