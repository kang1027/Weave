import AppKit
import Carbon.HIToolbox
import WeaveCore

/// 글로벌 단축키 — Carbon RegisterEventHotKey 기반(접근성 권한 불필요).
/// 트리거 시 메뉴바 팝오버를 여닫는다.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onTrigger: (() -> Void)?

    private init() {}

    func apply(_ hotkey: Hotkey?) {
        unregister()
        guard let hotkey else { return }
        register(hotkey)
    }

    private func register(_ hotkey: Hotkey) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.onTrigger?()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x5756_4B59), id: 1) // "WVKY"
        RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    /// 메뉴바 팝오버 토글 — MenuBarExtra는 공개 API가 없어 상태바 버튼 클릭으로 대체.
    static func toggleMenuBarWindow() {
        for window in NSApp.windows {
            guard
                window.className.contains("NSStatusBarWindow"),
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
