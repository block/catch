import AppKit
import Carbon.HIToolbox
import Foundation

public struct GlobalShortcut: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let normalized: String

    public init?(_ rawValue: String) {
        let collapsed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let parts = collapsed.split(separator: "+").map(String.init)
        let endsWithPlusKey = collapsed == "+" || collapsed.hasSuffix("++")
        let key = endsWithPlusKey ? "plus" : Self.normalizedKey(parts.last ?? "")
        let modifierParts = endsWithPlusKey ? parts : Array(parts.dropLast())

        guard !key.isEmpty, Self.modifier(for: key) == nil else { return nil }

        var modifierValues: [String: UInt32] = [:]
        for part in modifierParts {
            guard let modifier = Self.modifier(for: part) else { return nil }
            modifierValues[modifier.name] = modifier.value
        }
        guard !modifierValues.isEmpty else { return nil }
        guard let keyCode = Self.keyCode(for: key) else { return nil }

        self.keyCode = keyCode
        modifiers = modifierValues.values.reduce(0) { $0 | $1 }
        normalized = (Self.modifierOrder.filter { modifierValues[$0] != nil } + [key]).joined(separator: "+")
    }

    static let defaultStandalone = GlobalShortcut("alt+space")!

    private static let modifierOrder = ["ctrl", "meta", "alt", "shift"]

    private static func normalizedKey(_ key: String) -> String {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case " ":
            return "space"
        case "esc":
            return "escape"
        case "+":
            return "plus"
        default:
            return key
        }
    }

    private static func modifier(for part: String) -> (name: String, value: UInt32)? {
        switch part {
        case "cmd", "command", "meta":
            return ("meta", UInt32(cmdKey))
        case "control", "ctrl":
            return ("ctrl", UInt32(controlKey))
        case "alt", "option":
            return ("alt", UInt32(optionKey))
        case "shift":
            return ("shift", UInt32(shiftKey))
        default:
            return nil
        }
    }

    private static func keyCode(for key: String) -> UInt32? {
        switch key {
        case "a": return UInt32(kVK_ANSI_A)
        case "b": return UInt32(kVK_ANSI_B)
        case "c": return UInt32(kVK_ANSI_C)
        case "d": return UInt32(kVK_ANSI_D)
        case "e": return UInt32(kVK_ANSI_E)
        case "f": return UInt32(kVK_ANSI_F)
        case "g": return UInt32(kVK_ANSI_G)
        case "h": return UInt32(kVK_ANSI_H)
        case "i": return UInt32(kVK_ANSI_I)
        case "j": return UInt32(kVK_ANSI_J)
        case "k": return UInt32(kVK_ANSI_K)
        case "l": return UInt32(kVK_ANSI_L)
        case "m": return UInt32(kVK_ANSI_M)
        case "n": return UInt32(kVK_ANSI_N)
        case "o": return UInt32(kVK_ANSI_O)
        case "p": return UInt32(kVK_ANSI_P)
        case "q": return UInt32(kVK_ANSI_Q)
        case "r": return UInt32(kVK_ANSI_R)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "u": return UInt32(kVK_ANSI_U)
        case "v": return UInt32(kVK_ANSI_V)
        case "w": return UInt32(kVK_ANSI_W)
        case "x": return UInt32(kVK_ANSI_X)
        case "y": return UInt32(kVK_ANSI_Y)
        case "z": return UInt32(kVK_ANSI_Z)
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        case "space": return UInt32(kVK_Space)
        case "enter", "return": return UInt32(kVK_Return)
        case "escape": return UInt32(kVK_Escape)
        case "tab": return UInt32(kVK_Tab)
        case "backspace": return UInt32(kVK_Delete)
        case "delete": return UInt32(kVK_ForwardDelete)
        case "arrowleft": return UInt32(kVK_LeftArrow)
        case "arrowright": return UInt32(kVK_RightArrow)
        case "arrowup": return UInt32(kVK_UpArrow)
        case "arrowdown": return UInt32(kVK_DownArrow)
        case "plus": return UInt32(kVK_ANSI_Equal)
        case "=": return UInt32(kVK_ANSI_Equal)
        case "-": return UInt32(kVK_ANSI_Minus)
        case ",": return UInt32(kVK_ANSI_Comma)
        case ".": return UInt32(kVK_ANSI_Period)
        case "/": return UInt32(kVK_ANSI_Slash)
        case "\\": return UInt32(kVK_ANSI_Backslash)
        case ";": return UInt32(kVK_ANSI_Semicolon)
        case "'": return UInt32(kVK_ANSI_Quote)
        case "`": return UInt32(kVK_ANSI_Grave)
        case "[": return UInt32(kVK_ANSI_LeftBracket)
        case "]": return UInt32(kVK_ANSI_RightBracket)
        default: return nil
        }
    }
}

public final class GlobalShortcutRegistrar: @unchecked Sendable {
    private static let signature = fourCharacterCode("Ctch")

    private let shortcut: GlobalShortcut
    private let onTrigger: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    @MainActor
    public init(shortcut: GlobalShortcut, onTrigger: @escaping @MainActor () -> Void) {
        self.shortcut = shortcut
        self.onTrigger = onTrigger
    }

    public func register() {
        guard hotKeyRef == nil, eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == GlobalShortcutRegistrar.signature else {
                    return noErr
                }

                let registrar = Unmanaged<GlobalShortcutRegistrar>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    registrar.onTrigger()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else { return }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if hotKeyStatus != noErr {
            unregister()
        }
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        eventHandlerRef = nil
    }

    private static func fourCharacterCode(_ value: String) -> OSType {
        value.utf8.reduce(0) { result, byte in
            (result << 8) + OSType(byte)
        }
    }
}
