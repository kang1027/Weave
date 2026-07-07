import SwiftUI
import WeaveCore

/// 설정 — 그룹 카드 + select 드롭다운 (OpenUsage 스타일).
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.t("Settings")) {
                model.pop()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel(model.t("General"))
                    SettingsCard {
                        SettingsRow(title: model.t("Launch at login")) {
                            MiniToggle(isOn: Binding(
                                get: { model.settings.launchAtLogin },
                                set: { model.setLaunchAtLogin($0) }
                            ))
                        }
                        SettingsRow(
                            title: model.t("Global shortcut"),
                            subtitle: model.t("Open the popover")
                        ) {
                            HotkeyRecorderButton()
                        }
                        SettingsRow(title: model.t("Menu bar rotation")) {
                            SelectPill(
                                options: [
                                    (5, model.t("5s")), (10, model.t("10s")),
                                    (30, model.t("30s")), (0, model.t("Off"))
                                ],
                                selection: Binding(
                                    get: { model.settings.rotationSeconds },
                                    set: { model.setRotationSeconds($0) }
                                )
                            )
                        }
                        SettingsRow(title: model.t("Menu bar format")) {
                            SelectPill(
                                options: [
                                    (MenuBarFormat.full, model.t("Full")),
                                    (MenuBarFormat.compact, model.t("Compact")),
                                    (MenuBarFormat.priceOnly, model.t("Price only"))
                                ],
                                selection: Binding(
                                    get: { model.settings.menuBarFormat },
                                    set: {
                                        model.settings.menuBarFormat = $0
                                        model.updateMenuBarTitle()
                                    }
                                )
                            )
                        }
                    }

                    sectionLabel(model.t("Appearance"))
                    SettingsCard {
                        SettingsRow(title: model.t("Theme")) {
                            SelectPill(
                                options: [
                                    (ThemePreference.system, model.t("System")),
                                    (ThemePreference.slate, "Slate"),
                                    (ThemePreference.light, "Light")
                                ],
                                selection: Binding(
                                    get: { model.settings.theme },
                                    set: { model.settings.theme = $0 }
                                )
                            )
                        }
                        SettingsRow(title: model.t("Language")) {
                            SelectPill(
                                options: [
                                    (LanguagePreference.system, model.t("System")),
                                    (LanguagePreference.korean, "한국어"),
                                    (LanguagePreference.english, "English")
                                ],
                                selection: Binding(
                                    get: { model.settings.language },
                                    set: { model.settings.language = $0 }
                                )
                            )
                        }
                    }

                    sectionLabel(model.t("Data"))
                    SettingsCard {
                        SettingsRow(title: model.t("Quote refresh")) {
                            SelectPill(
                                options: [
                                    (60, model.t("1 min")), (300, model.t("5 min")),
                                    (600, model.t("10 min")), (900, model.t("15 min"))
                                ],
                                selection: Binding(
                                    get: { model.settings.quoteRefreshSeconds },
                                    set: { model.setQuoteRefreshSeconds($0) }
                                )
                            )
                        }
                        SettingsRow(
                            title: model.t("Base currency"),
                            subtitle: model.t("Used for totals & combined chart")
                        ) {
                            SelectPill(
                                options: [("KRW", "KRW"), ("USD", "USD"), ("JPY", "JPY")],
                                selection: Binding(
                                    get: { model.settings.baseCurrency },
                                    set: { model.setBaseCurrency($0) }
                                )
                            )
                        }
                        SettingsRow(
                            title: model.t("Asset currency"),
                            subtitle: model.t("Source: BTC in $, 삼성전자 in ₩")
                        ) {
                            SelectPill(
                                options: [
                                    (DisplayCurrencyMode.source, model.t("Source")),
                                    (DisplayCurrencyMode.base, model.t("Base"))
                                ],
                                selection: Binding(
                                    get: { model.settings.displayCurrencyMode },
                                    set: { model.settings.displayCurrencyMode = $0 }
                                )
                            )
                        }
                        SettingsButton(title: model.t("Export data…")) {
                            model.exportBackup()
                        }
                        SettingsButton(title: model.t("Import data…")) {
                            model.importBackup()
                        }
                        SettingsButton(title: model.t("Clear candle cache")) {
                            model.clearCandleCache()
                        }
                    }

                    sectionLabel(model.t("Updates"))
                    SettingsCard {
                        SettingsRow(
                            title: model.t("Automatic updates"),
                            subtitle: model.updater.isAvailable
                                ? model.t("Sparkle · checks daily")
                                : model.t("Available in packaged app only")
                        ) {
                            MiniToggle(isOn: Binding(
                                get: { model.settings.autoUpdateCheck },
                                set: {
                                    model.settings.autoUpdateCheck = $0
                                    model.updater.setAutomaticChecks($0)
                                }
                            ))
                        }
                        SettingsButton(
                            title: model.t("Check for updates now…"),
                            disabled: !model.updater.isAvailable
                        ) {
                            model.updater.checkForUpdates()
                        }
                    }

                }
                .padding(.bottom, 12)
            }

            settingsFooter
        }
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

    private var settingsFooter: some View {
        HStack {
            Text(verbatim: "Weave \(WeaveInfo.version)")
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let next = model.nextRefreshAt {
                    let remaining = max(0, Int(next.timeIntervalSince(context.date)))
                    Text(
                        remaining >= 60
                            ? model.t("Next refresh in \(remaining / 60)m")
                            : model.t("Next refresh in \(remaining)s")
                    )
                    .monospacedDigit()
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(theme.caps)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hair).frame(height: 1)
        }
    }
}

// MARK: - 설정 공용 컴포넌트

struct SettingsCard<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.panel)
                .shadow(color: .black.opacity(theme.panelShadowOpacity), radius: 1.5, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.panelStroke, lineWidth: 1)
        )
        .padding(.horizontal, 14)
    }
}

struct SettingsRow<Control: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.text2)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.hair).frame(height: 1).padding(.leading, 14)
        }
    }
}

struct SettingsButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.seg))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// 팝업버튼 룩 — 값 + ⌄⌃ 셰브론(테마 토큰), 드롭다운은 체크마크 있는 네이티브 메뉴.
/// (네이티브 Picker(.menu)는 앱 강제 테마 라이트에서 안 그려져 커스텀 라벨로 처리.)
struct SelectPill<T: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Text(currentLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.text2)
            }
            .padding(.leading, 10)
            .padding(.trailing, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.seg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(theme.hair, lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }
}

/// 글로벌 단축키 레코더 — 클릭 후 키 입력을 캡처한다.
struct HotkeyRecorderButton: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 10, weight: .medium))
                Text(labelText)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isRecording ? theme.link : theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isRecording ? theme.link.opacity(0.18) : theme.seg)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if model.settings.hotkey != nil {
                Button(model.t("Remove shortcut")) {
                    model.setHotkey(nil)
                }
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var labelText: String {
        if isRecording { return model.t("Press keys…") }
        if let hotkey = model.settings.hotkey {
            return HotkeyTranslator.display(hotkey)
        }
        return model.t("Record shortcut")
    }

    private func startRecording() {
        isRecording = true
        // accessory 앱의 팝오버는 비활성 상태라 ⌘조합 키가 프론트 앱으로 새어나간다.
        // 앱을 활성화해 로컬 모니터가 조합 키를 받을 수 있게 한다.
        NSApp.activate(ignoringOtherApps: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { stopRecording() }
            if event.keyCode == 53 { // ESC → 취소
                return nil
            }
            let modifiers = HotkeyTranslator.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else { return nil }
            model.setHotkey(Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers))
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
