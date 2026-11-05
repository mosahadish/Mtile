// Port of tests/Wtile.Tests/Commands/CommandRegistryTests.cs
import XCTest
@testable import Mtile

final class CommandRegistryTests: XCTestCase {
    private final class RecordingCommand: Command {
        let name: String
        private(set) var lastArgs: [String]?
        private(set) var callCount = 0

        init(_ name: String) {
            self.name = name
        }

        func execute(_ args: [String]) {
            lastArgs = args
            callCount += 1
        }
    }

    func testTryExecute_RegisteredCommand_InvokesWithArgs() {
        let registry = CommandRegistry()
        let command = RecordingCommand("view-tag")
        registry.register(command)

        let found = registry.tryExecute("view-tag", ["3"])

        XCTAssertTrue(found)
        XCTAssertEqual(command.callCount, 1)
        XCTAssertEqual(command.lastArgs, ["3"])
    }

    func testTryExecute_UnknownCommand_ReturnsFalse() {
        let registry = CommandRegistry()
        let found = registry.tryExecute("does-not-exist", [])
        XCTAssertFalse(found)
    }

    func testRegister_IsCaseInsensitive() {
        let registry = CommandRegistry()
        let command = RecordingCommand("focus-next")
        registry.register(command)

        XCTAssertTrue(registry.tryExecute("FOCUS-NEXT", []))
        XCTAssertNotNil(registry.get("Focus-Next"))
    }

    func testRegister_SameNameTwice_LastWriterWins() {
        let registry = CommandRegistry()
        let first = RecordingCommand("spawn")
        let second = RecordingCommand("spawn")
        registry.register(first)
        registry.register(second)

        registry.tryExecute("spawn", [])

        XCTAssertEqual(first.callCount, 0)
        XCTAssertEqual(second.callCount, 1)
    }

    func testClosureCommand_ForwardsArgsToClosure() {
        let registry = CommandRegistry()
        var received: [String]?
        registry.register(ClosureCommand("spawn") { args in received = args })

        XCTAssertTrue(registry.tryExecute("spawn", ["open", "-a", "Terminal"]))
        XCTAssertEqual(received, ["open", "-a", "Terminal"])
    }

    func testWindowsOnlyCommands_ExcludesTaskbarAndAppLauncher() {
        XCTAssertFalse(CommandRegistry.windowsOnlyCommands.contains("toggle-taskbar"))
        XCTAssertFalse(CommandRegistry.windowsOnlyCommands.contains("app-launcher"))
    }

    func testAppLauncherCommand_PassesElevatedFlag() {
        var received: [Bool] = []
        let registry = CommandRegistry()
        registry.register(AppLauncherCommand { received.append($0) })
        XCTAssertTrue(registry.tryExecute("App-Launcher", []))
        XCTAssertTrue(registry.tryExecute("app-launcher", ["elevated"]))
        XCTAssertEqual(received, [false, true])
    }
}