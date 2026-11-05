// Port of tests/Wtile.Tests/Hotkeys/KeyComboParserTests.cs. Expected key codes are macOS kVK_*
// values (see KeyComboParser.swift) instead of Win32 VK_* codes.
import XCTest
@testable import Mtile

final class KeyComboParserTests: XCTestCase {
    func testTryParse_ValidCombos_ProducesExpectedResult() {
        let cases: [(text: String, modifiers: HotkeyModifiers, keyCode: UInt16)] = [
            ("Alt+J", .alt, 0x26),                                   // kVK_ANSI_J
            ("Alt+Shift+Return", [.alt, .shift], 0x24),              // kVK_Return
            ("Alt+1", .alt, 0x12),                                   // kVK_ANSI_1
            ("Ctrl+Alt+Shift+Win+Escape", [.control, .alt, .shift, .win], 0x35), // kVK_Escape
            ("alt+j", .alt, 0x26),                                   // case-insensitive
            ("Alt+F5", .alt, 0x60),                                  // kVK_F5
            ("Alt+Space", .alt, 0x31),                               // kVK_Space
            ("Win+`", .win, 0x32),                                   // kVK_ANSI_Grave
            ("Win+Grave", .win, 0x32),
            ("Win+-", .win, 0x1B),                                   // kVK_ANSI_Minus
            ("Win+=", .win, 0x18),                                   // kVK_ANSI_Equal
            ("Win+Shift+=", [.win, .shift], 0x18),                   // "+" is Shift+"="
        ]
        for c in cases {
            guard let combo = KeyComboParser.tryParse(c.text) else {
                XCTFail("'\(c.text)' failed to parse")
                continue
            }
            XCTAssertEqual(combo.modifiers, c.modifiers, c.text)
            XCTAssertEqual(combo.keyCode, c.keyCode, c.text)
        }
    }

    func testTryParse_InvalidCombos_ReturnsNil() {
        let cases = [
            "",
            "   ",
            "Alt",       // modifier only, no key
            "Alt+J+K",   // two non-modifier tokens
            "Alt+NotAKey",
            "Alt+F99",
        ]
        for text in cases {
            XCTAssertNil(KeyComboParser.tryParse(text), "'\(text)'")
        }
    }

    func testTryParse_MacModifierSpellings_AreRejected() {
        // Deliberately unsupported: general.macosWinKey decides which Mac key "Win"/"Alt" mean.
        XCTAssertNil(KeyComboParser.tryParse("Cmd+J"))
        XCTAssertNil(KeyComboParser.tryParse("Option+J"))
    }

    func testMacWinKey_Option_MapsOptionToWinAndCommandToAlt() {
        let key = MacWinKey.option
        XCTAssertEqual(key.modifiers(command: false, option: true, control: false, shift: false), .win)
        XCTAssertEqual(key.modifiers(command: true, option: false, control: false, shift: false), .alt)
        XCTAssertEqual(key.modifiers(command: true, option: true, control: true, shift: true), [.win, .alt, .control, .shift])
        XCTAssertEqual(key.modifiers(command: false, option: false, control: false, shift: false), [])
    }

    func testMacWinKey_Command_MapsCommandToWinAndOptionToAlt() {
        let key = MacWinKey.command
        XCTAssertEqual(key.modifiers(command: true, option: false, control: false, shift: false), .win)
        XCTAssertEqual(key.modifiers(command: false, option: true, control: false, shift: false), .alt)
        XCTAssertEqual(key.modifiers(command: false, option: false, control: true, shift: true), [.control, .shift])
    }

    func testMacWinKey_From_IsCaseInsensitiveAndDefaultsToOption() {
        XCTAssertEqual(MacWinKey.from("COMMAND"), .command)
        XCTAssertEqual(MacWinKey.from("option"), .option)
        XCTAssertEqual(MacWinKey.from("bogus"), .option)
    }
}