import SwiftUI
import WeaveCore

/// 토스증권 연결 — 키 발급, 허용 IP 등록, 키 붙여넣기 세 단계. 지금 IP를 미리 보여 줘서 막히기 전에 등록하게 한다.
struct AddTossView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var showsSecret = false
    @State private var isConnecting = false
    @State private var failure: LinkFailure?
    @State private var publicIP: String?
    @State private var isCheckingIP = true

    private var canConnect: Bool {
        !clientID.trimmingCharacters(in: .whitespaces).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Link Toss Securities"), onBack: { model.pop() })

            ScrollView {
                VStack(spacing: 10) {
                    step(1, title: model.t("Get a key in WTS")) {
                        Text(model.t("Toss Securities WTS › Settings › Open API"))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.text2)
                        Button(model.t("How to get a key ↗")) { model.openTossDocs() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.link)
                    }
                    step(2, title: model.t("Allow this network's IP")) {
                        PublicIPBox(ip: publicIP, isLoading: isCheckingIP)
                        Text(model.t("WTS › Settings › Open API › Allowed IPs. On other networks syncing pauses and the last values stay."))
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    step(3, title: model.t("Paste the key")) {
                        field(model.t("Client ID")) {
                            TextField("tsck_live_…", text: $clientID)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        field(model.t("Client Secret")) {
                            HStack(spacing: 6) {
                                Group {
                                    if showsSecret {
                                        TextField("", text: $clientSecret)
                                    } else {
                                        SecureField("", text: $clientSecret)
                                    }
                                }
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                Button {
                                    showsSecret.toggle()
                                } label: {
                                    Image(systemName: showsSecret ? "eye.slash" : "eye")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(theme.text2)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(model.t(showsSecret ? "Hide secret" : "Show secret"))
                            }
                        }
                    }

                    if let failure {
                        Text(model.linkFailureText(failure))
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.redText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 12)
            }

            VStack(spacing: 8) {
                LinkPrimaryButton(title: model.t("Connect"), disabled: !canConnect, isLoading: isConnecting, action: connect)
                if isConnecting, model.isAwaitingKeychain {
                    KeychainHint()
                } else {
                    LinkFootnote(text: model.t("Keys stay in this Mac's keychain · reads holdings and orders only"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { HairDivider() }
        }
        .task {
            publicIP = await model.currentPublicIP()
            isCheckingIP = false
        }
    }

    private func step(_ number: Int, title: String, @ViewBuilder content: () -> some View) -> some View {
        LinkCard(padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
            HStack(alignment: .top, spacing: 11) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(theme.link))
                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                    content()
                }
            }
        }
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.text2)
            content()
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.hair, lineWidth: 1))
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
                // 추가 화면 둘(고르기·입력)을 닫고 검토 화면으로. 연결 중에 화면을 떠났으면 건드리지 않는다.
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
}
