import SwiftUI
import WeaveCore

/// 연결 추가 — 증권사와 지갑 중 고른다.
struct AddSourceView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Add a link"), onBack: { model.pop() })

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel(model.t("Brokers"))
                    PanelCard(padding: EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12)) {
                        option(.toss, title: model.t("Toss Securities"), detail: model.t("Open API key · Korean and US stocks")) {
                            model.push(.addToss)
                        }
                    }
                    .padding(.horizontal, 14)

                    sectionLabel(model.t("Wallets"))
                    PanelCard(padding: EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12)) {
                        VStack(spacing: 0) {
                            option(.bitcoinWallet, title: model.t("Bitcoin wallet"), detail: model.t("Addresses only · no keys")) {
                                model.push(.addWallet(.bitcoin))
                            }
                            Rectangle().fill(theme.hair).frame(height: 1)
                            option(.evmWallet, title: model.t("EVM wallet"), detail: "Ethereum · Arbitrum · Base · Optimism · Polygon") {
                                model.push(.addWallet(.evm))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.bottom, 12)
            }
        }
    }

    private func option(_ kind: LinkedSourceKind, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SourceLogo(kind: kind, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.text2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.text2)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

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
}
