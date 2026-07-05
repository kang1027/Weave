import SwiftUI
import WeaveCore

// M5에서 그룹 카드 설정으로 채워지는 스텁.
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Settings")) {
                model.pop()
            }
            Spacer()
            Text(verbatim: "Settings — M5")
                .foregroundStyle(theme.text2)
            Spacer()
        }
    }
}
