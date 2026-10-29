import SwiftUI
import WeaveCore

/// 지갑 연결 — 주소만 받아 잔고를 읽는다. 키는 받지 않는다.
struct AddWalletView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let kind: WalletConfig.Kind

    @State private var name = ""
    @State private var addressText = ""
    @State private var chains = Set(EVMChain.allCases)
    @State private var isConnecting = false
    @State private var failure: LinkFailure?

    private var addresses: [String] {
        addressText
            .components(separatedBy: CharacterSet(charactersIn: ",\n "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var canConnect: Bool {
        !addresses.isEmpty && (kind == .bitcoin || !chains.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: model.t(kind == .bitcoin ? "Bitcoin wallet" : "EVM wallet"),
                onBack: { model.pop() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    PanelCard(padding: EdgeInsets(top: 4, leading: 14, bottom: 8, trailing: 14)) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text(model.t("Name"))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(theme.text)
                                Spacer(minLength: 12)
                                TextField(model.t(kind == .bitcoin ? "Bitcoin wallet" : "EVM wallet"), text: $name)
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(size: 12.5))
                            }
                            .padding(.vertical, 9)
                            Divider().overlay(theme.hair)
                            Text(model.t(kind == .bitcoin ? "Addresses (one per line)" : "Address"))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(theme.text)
                                .padding(.top, 9)
                                .padding(.bottom, 5)
                            addressField
                        }
                    }

                    if kind == .evm {
                        chainPicker
                    }

                    LinkNotice(
                        systemName: "eye",
                        text: model.t(kind == .bitcoin
                            ? "Weave only reads balances: the addresses go to mempool.space. An address can't move coins."
                            : "Weave only reads balances: the address goes to each chain's public RPC. An address can't move coins.")
                    )
                    LinkNotice(
                        systemName: "arrow.left.arrow.right",
                        text: model.t("If you entered the same coin manually, the wallet's share moves over at your average cost. The rest starts at today's price."),
                        tint: theme.blue
                    )

                    LinkPrimaryButton(
                        title: model.t("Connect and import balances"),
                        disabled: !canConnect,
                        isLoading: isConnecting,
                        action: connect
                    )

                    if let failure {
                        Text(model.linkFailureText(failure))
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.redText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var addressField: some View {
        let placeholder = kind == .bitcoin ? "bc1q…" : "0x…"
        if kind == .bitcoin {
            ZStack(alignment: .topLeading) {
                if addressText.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.text2)
                        .padding(.top, 1)
                        .padding(.leading, 5)
                }
                TextEditor(text: $addressText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(height: 64)
            }
        } else {
            TextField(placeholder, text: $addressText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.bottom, 2)
        }
    }

    private var chainPicker: some View {
        PanelCard(padding: EdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 14)) {
            VStack(spacing: 0) {
                ForEach(Array(EVMChain.allCases.enumerated()), id: \.element) { index, chain in
                    if index > 0 {
                        Rectangle().fill(theme.hair).frame(height: 1)
                    }
                    HStack {
                        Text(chain.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Spacer()
                        MiniToggle(isOn: Binding(
                            get: { chains.contains(chain) },
                            set: { isOn in
                                if isOn { chains.insert(chain) } else { chains.remove(chain) }
                            }
                        ))
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }

    private func connect() {
        isConnecting = true
        failure = nil
        Task {
            let result = await model.connectWallet(
                kind: kind, name: name, addresses: addresses,
                chains: EVMChain.allCases.filter(chains.contains)
            )
            isConnecting = false
            switch result {
            case .success(let sourceID):
                // 추가 화면 둘(고르기·입력)을 닫고 검토 화면으로. 연결 중에 화면을 떠났으면 건드리지 않는다.
                guard model.currentRoute == .addWallet(kind) else { return }
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
