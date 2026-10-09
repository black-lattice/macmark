import AppKit
import Carbon

struct CaptureShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: NSEvent.ModifierFlags
    let keyEquivalent: String
    static let storageKey = "captureShortcut"
    static let modifierMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    static let defaultValue = CaptureShortcut(keyCode: UInt32(kVK_ANSI_X), modifiers: [.command, .shift], keyEquivalent: "x")
    private static let functionCodes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
    private static let specialKeys: [Int: (String, String)] = [
        kVK_Space: (" ", "空格"), kVK_Tab: ("\t", "⇥"), kVK_Return: ("\r", "↩"),
        kVK_Delete: ("\u{7f}", "⌫"), kVK_ForwardDelete: (String(UnicodeScalar(NSDeleteFunctionKey)!), "⌦"),
        kVK_LeftArrow: (String(UnicodeScalar(NSLeftArrowFunctionKey)!), "←"),
        kVK_RightArrow: (String(UnicodeScalar(NSRightArrowFunctionKey)!), "→"),
        kVK_UpArrow: (String(UnicodeScalar(NSUpArrowFunctionKey)!), "↑"),
        kVK_DownArrow: (String(UnicodeScalar(NSDownArrowFunctionKey)!), "↓")
    ]
    var isValid: Bool {
        guard keyCode <= 127, keyCode != UInt32(kVK_Escape), keyEquivalent.count == 1,
              modifiers.subtracting(Self.modifierMask).isEmpty else { return false }
        return !modifiers.intersection([.command, .control, .option]).isEmpty || Self.functionCodes.contains(Int(keyCode))
    }
    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, keyEquivalent: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyEquivalent = keyEquivalent
    }
    init?(event: NSEvent) {
        let code = Int(event.keyCode)
        let key: String
        if let index = Self.functionCodes.firstIndex(of: code) {
            key = String(UnicodeScalar(NSF1FunctionKey + index)!)
        } else if let special = Self.specialKeys[code] {
            key = special.0
        } else if let characters = event.characters(byApplyingModifiers: []), characters.count == 1,
                  !characters.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            key = characters.lowercased()
        } else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags.intersection(Self.modifierMask), keyEquivalent: key)
        guard isValid else { return nil }
    }
    var display: String {
        let key: String
        if let index = Self.functionCodes.firstIndex(of: Int(keyCode)) { key = "F\(index + 1)" }
        else { key = Self.specialKeys[Int(keyCode)]?.1 ?? keyEquivalent.uppercased() }
        return Self.modifierSymbols(modifiers) + key
    }
    static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { flags.contains($0.0) }.map { $0.1 }.joined()
    }
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        return value
    }
    static func load(from defaults: UserDefaults = .standard) -> CaptureShortcut {
        guard let stored = defaults.dictionary(forKey: storageKey), let code = stored["keyCode"] as? Int,
              (0...127).contains(code), let flags = stored["modifiers"] as? UInt,
              let key = stored["keyEquivalent"] as? String else { return .defaultValue }
        let shortcut = CaptureShortcut(keyCode: UInt32(code), modifiers: NSEvent.ModifierFlags(rawValue: flags), keyEquivalent: key)
        return shortcut.isValid ? shortcut : .defaultValue
    }
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(["keyCode": Int(keyCode), "modifiers": modifiers.rawValue, "keyEquivalent": keyEquivalent], forKey: Self.storageKey)
    }
    func conflictingMenuTitle(in menu: NSMenu?) -> String? {
        for item in menu?.items ?? [] {
            if item.keyEquivalent.lowercased() == keyEquivalent,
               item.keyEquivalentModifierMask.intersection(Self.modifierMask) == modifiers { return item.title }
            if let title = conflictingMenuTitle(in: item.submenu) { return title }
        }
        return nil
    }
}
