import SwiftUI
import WeaveCore

/// 연결 추가 — 무엇이 필요한지를 태그로 보여 주고 고르게 한다.
struct AddSourceView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Add a link"), onBack: { model.pop() })

            ScrollView {
                VStack(spacing: 0) {
                    CapsLabel(text: model.t("Brokers"))
                    LinkCard {
                        VStack(spacing: 0) {
                            option(.toss, title: model.t("Toss Securities"), tags: [
                                (model.t("KR & US stocks"), .neutral),
                                (model.t("API key"), .neutral),
                                (model.t("Allowed IP required"), .orange)
                            ]) { model.push(.addToss) }
                            HairDivider(inset: 57)
                            comingSoon(model.t("Korea Investment"))
                        }
                    }

                    CapsLabel(text: model.t("Crypto wallets"))
                    LinkCard {
                        VStack(spacing: 0) {
                            option(.evmWallet, title: model.t("EVM wallet"), tags: [
                                (model.t("Address only"), .green),
                                (model.t("Ethereum + 4 chains"), .neutral),
                                (model.t("Aave deposits"), .neutral)
                            ]) { model.push(.addWallet(.evm)) }
                            HairDivider(inset: 57)
                            option(.bitcoinWallet, title: model.t("Bitcoin wallet"), tags: [
                                (model.t("Address only"), .green),
                                (model.t("Multiple addresses"), .neutral)
                            ]) { model.push(.addWallet(.bitcoin)) }
                        }
                    }

                    Text(model.t("Upbit isn't supported: its API keys need a fixed IP. Enter exchange coins by hand, or move them to a wallet and link the wallet."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }
                .padding(.bottom, 12)
            }
        }
    }

    private func option(
        _ kind: LinkedSourceKind,
        title: String,
        tags: [(String, LinkTag.Style)],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                SourceLogo(kind: kind, size: 34)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(theme.text)
                    FlowLayout(spacing: 4, rowSpacing: 4, alignment: .leading) {
                        ForEach(tags, id: \.0) { tag in
                            LinkTag(text: tag.0, style: tag.1)
                        }
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.text2)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func comingSoon(_ title: String) -> some View {
        HStack(spacing: 11) {
            SourceLogo(kind: .koreaInvestment, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(model.t("Coming soon"))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text2)
            }
            Spacer()
        }
        .padding(12)
        .opacity(0.5)
    }
}
