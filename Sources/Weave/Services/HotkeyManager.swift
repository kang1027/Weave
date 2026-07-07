import AppKit
import Carbon.HIToolbox
import WeaveCore

/// 글로벌 단축키 — Carbon RegisterEventHotKey 기반(접근성 권한 불필요).
/// id별로 여러 단축키를 등록하고, 트리거되면 해당 액션을 호출한다.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// 단축키 id — 등록/디스패치 식별용.
    enum Action: UInt32 {
        case togglePopover = 1
        case switchAsset = 2
    }

    private struct Registration {
        var ref: EventHotKeyRef?
        var action: () -> Void
    }

    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: Registration] = [:]

    private init() { installHandler() }

    /// 주어진 id의 단축키를 (재)등록. hotkey가 nil이면 해제만 한다.
    func register(_ id: Action, hotkey: Hotkey?, action: @escaping () -> Void) {
        if let existing = registrations[id.rawValue]?.ref {
            UnregisterEventHotKey(existing)
        }
        registrations[id.rawValue] = nil
        guard let hotkey else { return }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5756_4B59), id: id.rawValue) // "WVKY"
        RegisterEventHotKey(
            hotkey.keyCode, hotkey.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        registrations[id.rawValue] = Registration(ref: ref, action: action)
    }

    private func trigger(id: UInt32) {
        registrations[id]?.action()
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                Task { @MainActor in manager.trigger(id: id) }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
    }

    /// 메뉴바 팝오버 토글 — MenuBarExtra는 공개 API가 없어 상태바 버튼 클릭으로 대체.
    /// 비공개 KVC 의존이라 OS 업데이트로 키가 사라져도 크래시하지 않게 방어한다.
    static func toggleMenuBarWindow() {
        for window in NSApp.windows {
            guard
                window.className.contains("NSStatusBarWindow"),
                window.responds(to: NSSelectorFromString("statusItem")),
                let statusItem = window.value(forKey: "statusItem") as? NSStatusItem,
                let button = statusItem.button
            else {
                continue
            }
            button.performClick(nil)
            return
        }
    }
}

/// NSEvent 수식키 → Carbon 수식키.
enum HotkeyTranslator {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    static func display(_ hotkey: Hotkey) -> String {
        var parts = ""
        if hotkey.modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if hotkey.modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if hotkey.modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if hotkey.modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + keyName(hotkey.keyCode)
    }

    static func keyName(_ keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
            26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
            34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }
}
