import XCTest
@testable import Mtile

final class HotkeyTableTests: XCTestCase {
    private let known: Set<String> = ["focus-next", "view-tag", "spawn"]

    private func build(_ bindings: [HotkeyBinding]) -> (table: [KeyCombo: HotkeyBinding], notes: [String]) {
        HotkeyTable.build(bindings) { self.known.contains($0) }
    }

    func testRegisteredCommands_AreBoundByParsedCombo() throws {
        let result = build([HotkeyBinding(keys: "Win+J", command: "focus-next"),
                            HotkeyBinding(keys: "Win+1", command: "view-tag", args: ["1"])])
        XCTAssertEqual(result.table.count, 2)
        XCTAssertTrue(result.notes.isEmpty)
        let combo = try XCTUnwrap(KeyComboParser.tryParse("Win+1"))
        XCTAssertEqual(result.table[combo]?.args, ["1"])
    }

    func testCommandLookup_IsCaseInsensitive() {
        let result = build([HotkeyBinding(keys: "Win+J", command: "Focus-Next")])
        XCTAssertEqual(result.table.count, 1)
    }

    func testToggleTaskbar_IsBoundOnMacOS() throws {
        let result = HotkeyTable.build([HotkeyBinding(keys: "Win+Space", command: "toggle-taskbar")]) { $0 == "toggle-taskbar" }
        XCTAssertTrue(result.notes.isEmpty)
        let combo = try XCTUnwrap(KeyComboParser.tryParse("Win+Space"))
        XCTAssertEqual(result.table[combo]?.command, "toggle-taskbar")
    }

    func testUnknownCommand_IsSkippedWithNote() {
        let result = build([HotkeyBinding(keys: "Win+J", command: "focus-nxt")])
        XCTAssertTrue(result.table.isEmpty)
        XCTAssertEqual(result.notes.count, 1)
        XCTAssertTrue(result.notes[0].contains("focus-nxt"))
    }

    func testUnparseableCombo_IsSkippedWithNote() {
        let result = build([HotkeyBinding(keys: "Win+Nope", command: "focus-next")])
        XCTAssertTrue(result.table.isEmpty)
        XCTAssertEqual(result.notes.count, 1)
    }

    func testDuplicateCombo_KeepsFirstBinding() throws {
        let result = build([HotkeyBinding(keys: "Win+J", command: "focus-next"),
                            HotkeyBinding(keys: "win+j", command: "spawn", args: ["x"])])
        let combo = try XCTUnwrap(KeyComboParser.tryParse("Win+J"))
        XCTAssertEqual(result.table.count, 1)
        XCTAssertEqual(result.table[combo]?.command, "focus-next")
        XCTAssertEqual(result.notes.count, 1)
    }
}
