import AppKit
import SwiftUI
import WeaveCore

/// 지갑 연결 — 주소부터 받고 바로 형식을 확인한다. EVM은 볼 체인을 칩으로, 이름은 선택.
struct AddWalletView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    @State private var kind: WalletConfig.Kind
    @State private var name = ""
    @State private var addressText = ""
    @State private var chains = Set(EVMChain.allCases)
    @State private var isConnecting = false
    @State private var failure: LinkFailure?

    init(kind: WalletConfig.Kind) {
        _kind = State(initialValue: kind)
    }

    private var addresses: [String] {
        addressText
            .components(separatedBy: CharacterSet(charactersIn: ",\n "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var addressesValid: Bool {
        !addresses.isEmpty && addresses.allSatisfy(kind == .bitcoin ? WalletConfig.isBitcoinAddress : WalletConfig.isEVMAddress)
    }

    private var canConnect: Bool {
        addressesValid && (kind == .bitcoin || !chains.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Link a wallet"), onBack: { model.pop() })

            SegmentedPills(
                options: [(WalletConfig.Kind.evm, "EVM"), (WalletConfig.Kind.bitcoin, model.t("Bitcoin"))],
                selection: $kind,
                fillsWidth: true
            )
            .padding(.horizontal, 14)
            .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    addressSection
                    if kind == .evm { chainSection }
                    nameSection
                    infoCard
                    if let failure {
                        Text(model.linkFailureText(failure))
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.redText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }

            VStack(spacing: 8) {
                LinkPrimaryButton(title: model.t("Import balances"), disabled: !canConnect, isLoading: isConnecting, action: connect)
                if isConnecting, model.isAwaitingKeychain { KeychainHint() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { HairDivider() }
        }
        .onChange(of: kind) { _, _ in
            addressText = ""
            failure = nil
        }
    }

    // MARK: - 주소

    private var addressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            label(model.t(kind == .bitcoin ? "Addresses (one per line)" : "Address"))
            HStack(alignment: kind == .bitcoin ? .top : .center, spacing: 6) {
                if kind == .bitcoin {
                    ZStack(alignment: .topLeading) {
                        if addressText.isEmpty {
                            Text("bc1q…")
                                .foregroundStyle(theme.text2)
                                .padding(.leading, 5)
                                .padding(.top, 1)
                        }
                        TextEditor(text: $addressText)
                            .scrollContentBackground(.hidden)
                            .frame(height: 58)
                    }
                } else {
                    TextField("0x…", text: $addressText)
                        .textFieldStyle(.plain)
                }
                Button(model.t("Paste")) {
                    if let pasted = NSPasteboard.general.string(forType: .string) {
                        addressText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.seg))
            }
            .font(.system(size: 11.5, design: .monospaced))
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 9).fill(theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(addressBorder, lineWidth: 1))

            if !addresses.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: addressesValid ? "checkmark" : "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5, weight: .bold))
                    Text(addressesValid
                        ? model.t(kind == .bitcoin ? "Valid Bitcoin address" : "Valid EVM address")
                        : model.t(kind == .bitcoin ? "That doesn't look like a Bitcoin address" : "That doesn't look like an EVM address"))
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(addressesValid ? theme.greenText : theme.orange)
            }
        }
    }

    private var addressBorder: Color {
        guard !addresses.isEmpty else { return theme.hair }
        return addressesValid ? theme.green.opacity(0.55) : theme.orange.opacity(0.6)
    }

    // MARK: - 체인

    private var chainSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                label(model.t("Chains"))
                Spacer()
                Text(model.t("\(chains.count) selected"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.badgeGrayText)
            }
            FlowLayout(spacing: 6, rowSpacing: 6, alignment: .leading) {
                ForEach(EVMChain.allCases, id: \.self) { chain in
                    chainChip(chain)
                }
            }
        }
    }

    private func chainChip(_ chain: EVMChain) -> some View {
        let isOn = chains.contains(chain)
        return Button {
            if isOn { chains.remove(chain) } else { chains.insert(chain) }
        } label: {
            HStack(spacing: 5) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.link)
                }
                Text(chain.name)
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(isOn ? theme.text : theme.text2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(isOn ? theme.link.opacity(0.22) : theme.seg))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - 이름 · 안내

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                label(model.t("Name"))
                Text(model.t("(optional)"))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.caps)
            }
            TextField(model.t(kind == .bitcoin ? "Bitcoin wallet" : "EVM wallet"), text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.hair, lineWidth: 1))
        }
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow("eye", tint: theme.greenText, text: model.t("Reads balances only. An address can't move coins."))
            HairDivider()
            infoRow("arrow.left.arrow.right", tint: theme.link, text: model.t("Coins you entered by hand move to the wallet at their average cost."))
            HairDivider()
            infoRow("clock", tint: theme.text2, text: model.t("Balances under $10 and coins without a Binance price are skipped."))
        }
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.panel))
    }

    private func infoRow(_ symbol: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(theme.badgeGrayText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.text2)
    }

    private func connect() {
        isConnecting = true
        failure = nil
        let walletKind = kind
        Task {
            let result = await model.connectWallet(
                kind: walletKind, name: name, addresses: addresses,
                chains: EVMChain.allCases.filter(chains.contains)
            )
            isConnecting = false
            switch result {
            case .success(let sourceID):
                // 추가 화면 둘(고르기·입력)을 닫고 검토 화면으로. 연결 중에 화면을 떠났으면 건드리지 않는다.
                guard case .addWallet = model.currentRoute else { return }
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
