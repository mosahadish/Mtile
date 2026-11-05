/// Modifier flags, named after Wtile's so one config reads the same on both platforms. Which Mac
/// key "Win" and "Alt" stand for is decided when matching key events (see MacWinKey).
public struct HotkeyModifiers: OptionSet, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let alt = HotkeyModifiers(rawValue: 1 << 0)
    public static let control = HotkeyModifiers(rawValue: 1 << 1)
    public static let shift = HotkeyModifiers(rawValue: 1 << 2)
    public static let win = HotkeyModifiers(rawValue: 1 << 3)
}

/// A parsed hotkey: modifiers plus a macOS virtual key code (kVK_*).
public struct KeyCombo: Hashable {
    public var modifiers: HotkeyModifiers
    public var keyCode: UInt16

    public init(modifiers: HotkeyModifiers, keyCode: UInt16) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }
}

/// `general.macosWinKey`: which physical Mac modifier the config's "Win" means; "Alt" is the other.
/// Option is the default because it sits where the Windows key is on a PC keyboard and binding it
/// leaves every Cmd app shortcut (Cmd+S, Cmd+Q, Cmd+W, ...) alone.
public enum MacWinKey: String {
    case option
    case command

    public static func from(_ setting: String) -> MacWinKey { MacWinKey(rawValue: setting.lowercased()) ?? .option }

    /// Translates the Mac modifier keys held during a key event into config modifiers.
    public func modifiers(command: Bool, option: Bool, control: Bool, shift: Bool) -> HotkeyModifiers {
        var m: HotkeyModifiers = []
        if self == .option ? option : command { m.insert(.win) }
        if self == .option ? command : option { m.insert(.alt) }
        if control { m.insert(.control) }
        if shift { m.insert(.shift) }
        return m
    }
}
