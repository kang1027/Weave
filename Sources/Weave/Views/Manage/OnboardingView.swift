import SwiftUI

/// 자산 0개 빈 상태 — 홈 대신 노출되는 온보딩.
struct OnboardingView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text(verbatim: "Weave")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
            }
            .padding(.top, 14)
            .padding(.bottom, 4)
            .overlay(alignment: .trailing) {
                IconButton(systemName: "gearshape") {
                    model.push(.settings)
                }
                .padding(.trailing, 14)
                .padding(.top, 10)
            }

            VStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(theme.link)
                    .padding(.bottom, 6)
                Text(model.t("Track your portfolio"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.text)
                Text(model.t("Search symbols like BTC, 삼성전자 or AAPL to add your first asset."))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
            .padding(.top, 40)
            .padding(.bottom, 18)

            SearchSection()

            if model.searchResults.isEmpty && !model.isSearching {
                Button {
                    model.push(.manualAssetForm)
                } label: {
                    Text(model.t("Or add a manual asset…"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.link)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }

            Spacer(minLength: 0)
        }
    }
}
