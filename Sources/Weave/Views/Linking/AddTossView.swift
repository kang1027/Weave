import SwiftUI
import WeaveCore

/// 토스증권 연결 — Open API 키를 받아 계좌를 확인하고 첫 동기화까지 한다.
struct AddTossView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var isConnecting = false
    @State private var failure: LinkFailure?
    @State private var publicIP: String?
    @State private var isCheckingIP = false

    private var canConnect: Bool {
        !clientID.trimmingCharacters(in: .whitespaces).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Toss Securities"), onBack: { model.pop() })

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    PanelCard(padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                        VStack(spacing: 0) {
                            fieldRow(label: model.t("Client ID")) {
                                TextField("tsck_live_…", text: $clientID)
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(size: 12.5))
                            }
                            Divider().overlay(theme.hair)
                            fieldRow(label: model.t("Client secret")) {
                                SecureField("", text: $clientSecret)
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(size: 12.5))
                            }
                        }
                    }

                    LinkNotice(
                        systemName: "lock.fill",
                        text: model.t("Keys are saved in this Mac's keychain and sent only to Toss Securities. Weave only reads holdings and order history.")
                    )
                    LinkNotice(
                        systemName: "network",
                        text: model.t("Toss Securities only answers allowed IPs. Add this network's IP in WTS › Settings › Open API › Allowed IPs. On other networks Weave keeps the last synced values."),
                        tint: theme.orange
                    )

                    LinkPrimaryButton(
                        title: model.t("Connect and import"),
                        disabled: !canConnect,
                        isLoading: isConnecting,
                        action: connect
                    )

                    if let failure {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.linkFailureText(failure))
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.redText)
                                .fixedSize(horizontal: false, vertical: true)
                            if failure == .ipNotAllowed {
                                PublicIPButton(publicIP: $publicIP, isChecking: $isCheckingIP)
                            }
                        }
                    }

                    Button(model.t("How to get keys")) { model.openTossDocs() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.link)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
        }
    }

    private func connect() {
        isConnecting = true
        failure = nil
        Task {
            let result = await model.connectToss(clientID: clientID, clientSecret: clientSecret)
            isConnecting = false
            switch result {
            case .success(let sourceID):
                // 이 화면 대신 검토 화면으로 — 뒤로 가면 연결 목록이 나온다. 연결 중에 화면을 떠났으면 건드리지 않는다.
                guard model.currentRoute == .addToss else { return }
                model.pop()
                if model.currentRoute == .addSource { model.pop() }
                if model.pendingImports[sourceID] != nil {
                    model.push(.importReview(sourceID))
                }
            case .failure(let error):
                failure = error
            }
        }
    }

    private func fieldRow(label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.text)
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 9)
    }
}
