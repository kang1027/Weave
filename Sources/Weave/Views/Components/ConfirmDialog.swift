import SwiftUI

/// 팝오버 안에서 뜨는 확인/입력 다이얼로그.
///
/// 시스템 `confirmationDialog`/`alert`는 MenuBarExtra(.window) 팝오버에서 별도 윈도우로
/// 떠서, 버튼을 누르면 팝오버가 key를 잃고 통째로 닫혀버린다. 그래서 확인 UI를 팝오버
/// 뷰 계층 안에 직접 그려 포커스가 팝오버를 벗어나지 않게 한다.

// MARK: - 공용 조각

private struct DialogButton: View {
    let title: String
    let tint: Color
    let background: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(background))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    /// 다이얼로그 카드 배경(둥근 사각형 + 테두리 + 그림자).
    func dialogCard(_ theme: Theme) -> some View {
        frame(width: 258)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.tooltipBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(theme.tooltipBorder)
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
    }
}

/// 딤 배경 — 탭하면 취소, 뒤쪽 클릭 차단.
private struct DialogScrim: View {
    let onTap: () -> Void
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.45))
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }
}

// MARK: - 확인 다이얼로그

private struct ConfirmDialog<Item: Identifiable>: ViewModifier {
    @Environment(\.theme) private var theme
    @Binding var item: Item?
    let title: (Item) -> String
    let message: (Item) -> String?
    let confirmTitle: String
    let isDestructive: Bool
    let cancelTitle: String
    let onConfirm: (Item) -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if let item {
                    dialog(item).transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.14), value: item != nil)
    }

    private func dialog(_ target: Item) -> some View {
        ZStack {
            DialogScrim { item = nil }
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(title(target))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.center)
                    if let message = message(target) {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.text2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)

                HStack(spacing: 8) {
                    DialogButton(title: cancelTitle, tint: theme.text, background: theme.seg) { item = nil }
                    DialogButton(
                        title: confirmTitle,
                        tint: .white,
                        background: isDestructive ? theme.red : theme.link
                    ) {
                        onConfirm(target)
                        item = nil
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .dialogCard(theme)
        }
    }
}

// MARK: - 입력 다이얼로그

private struct InputDialog<Item: Identifiable>: ViewModifier {
    @Environment(\.theme) private var theme
    @Binding var item: Item?
    let title: (Item) -> String
    let message: (Item) -> String?
    let placeholder: String
    @Binding var text: String
    let confirmTitle: String
    let cancelTitle: String
    let onConfirm: (Item) -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if let item {
                    dialog(item).transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.14), value: item != nil)
    }

    private func dialog(_ target: Item) -> some View {
        ZStack {
            DialogScrim { item = nil }
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(title(target))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                    if let message = message(target) {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.text2)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.seg))
                    .focused($focused)
                    .onSubmit { confirm(target) }
                    .padding(.horizontal, 12)

                HStack(spacing: 8) {
                    DialogButton(title: cancelTitle, tint: theme.text, background: theme.seg) { item = nil }
                    DialogButton(title: confirmTitle, tint: .white, background: theme.link) { confirm(target) }
                }
                .padding(12)
            }
            .dialogCard(theme)
            .onAppear { focused = true }
        }
    }

    private func confirm(_ target: Item) {
        onConfirm(target)
        item = nil
    }
}

// MARK: - View API

extension View {
    /// 팝오버 내부 확인 다이얼로그. `item`이 nil이 아니면 표시된다.
    func confirmDialog<Item: Identifiable>(
        _ item: Binding<Item?>,
        title: @escaping (Item) -> String,
        message: @escaping (Item) -> String? = { _ in nil },
        confirmTitle: String,
        isDestructive: Bool = false,
        cancelTitle: String,
        onConfirm: @escaping (Item) -> Void
    ) -> some View {
        modifier(ConfirmDialog(
            item: item,
            title: title,
            message: message,
            confirmTitle: confirmTitle,
            isDestructive: isDestructive,
            cancelTitle: cancelTitle,
            onConfirm: onConfirm
        ))
    }

    /// 팝오버 내부 텍스트 입력 다이얼로그.
    func inputDialog<Item: Identifiable>(
        _ item: Binding<Item?>,
        title: @escaping (Item) -> String,
        message: @escaping (Item) -> String? = { _ in nil },
        placeholder: String,
        text: Binding<String>,
        confirmTitle: String,
        cancelTitle: String,
        onConfirm: @escaping (Item) -> Void
    ) -> some View {
        modifier(InputDialog(
            item: item,
            title: title,
            message: message,
            placeholder: placeholder,
            text: text,
            confirmTitle: confirmTitle,
            cancelTitle: cancelTitle,
            onConfirm: onConfirm
        ))
    }
}
