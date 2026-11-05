import Foundation

/// Parses config strings like "Win+Shift+Return" into a `KeyCombo`. Accepts exactly the names
/// Wtile's KeyComboParser accepts, mapped to macOS virtual key codes (Carbon's kVK_* values,
/// hardcoded so this stays testable on non-Apple toolchains). There are deliberately no
/// cmd/option spellings: which Mac key "Win" and "Alt" mean is `general.macosWinKey`'s job.
public enum KeyComboParser {
    private static let modifierNames: [String: HotkeyModifiers] = [
        "alt": .alt,
        "ctrl": .control, "control": .control,
        "shift": .shift,
        "win": .win, "windows": .win, "super": .win,
    ]

    private static let namedKeys: [String: UInt16] = [
        "backspace": 0x33,
        "tab": 0x30,
        "enter": 0x24, "return": 0x24,
        "escape": 0x35, "esc": 0x35,
        "space": 0x31,
        "pageup": 0x74,
        "pagedown": 0x79,
        "end": 0x77,
        "home": 0x73,
        "left": 0x7B,
        "up": 0x7E,
        "right": 0x7C,
        "down": 0x7D,
        "insert": 0x72, // the Help key's code, where a PC keyboard's Insert lands on macOS
        "delete": 0x75, "del": 0x75, // forward delete, like VK_DELETE
        "`": 0x32, "grave": 0x32,
        "-": 0x1B, "minus": 0x1B,
        "=": 0x18, "equal": 0x18, "plus": 0x18,
        ",": 0x2B, "comma": 0x2B,
        ".": 0x2F, "period": 0x2F,
    ]

    private static let letters: [Character: UInt16] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05, "Z": 0x06, "X": 0x07,
        "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10,
        "T": 0x11, "O": 0x1F, "U": 0x20, "I": 0x22, "P": 0x23, "L": 0x25, "J": 0x26, "K": 0x28,
        "N": 0x2D, "M": 0x2E,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C,
        "9": 0x19, "0": 0x1D,
    ]

    // macOS has no F21-F24 key codes (Wtile accepts up to F24).
    private static let functionKeys: [UInt16] = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
        0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
    ]

    public static func tryParse(_ text: String) -> KeyCombo? {
        let parts = text.split(separator: "+", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        var modifiers: HotkeyModifiers = []
        var keyCode: UInt16?

        for part in parts {
            if let modifier = modifierNames[part.lowercased()] {
                modifiers.insert(modifier)
                continue
            }
            if keyCode != nil { return nil } // more than one non-modifier token, e.g. "Alt+J+K"
            guard let code = parseKey(part) else { return nil }
            keyCode = code
        }

        guard let keyCode else { return nil }
        return KeyCombo(modifiers: modifiers, keyCode: keyCode)
    }

    private static func parseKey(_ token: String) -> UInt16? {
        if let code = namedKeys[token.lowercased()] { return code }

        if token.count == 1, let c = token.uppercased().first, let code = letters[c] {
            return code
        }

        if (token.count == 2 || token.count == 3), token.first == "F" || token.first == "f",
           let n = Int(token.dropFirst()), n >= 1, n <= functionKeys.count {
            return functionKeys[n - 1]
        }
        return nil
    }
}

