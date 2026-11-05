import XCTest
@testable import Mtile

final class ProcessLauncherTests: XCTestCase {
    private func onPath(_ names: String...) -> (String) -> String? {
        { name in names.contains(name) ? "/usr/local/bin/\(name)" : nil }
    }

    func testLauncherInvocation_OpensTarget() {
        XCTAssertEqual(ProcessLauncher.launcherInvocation("/Applications/Safari.app"),
                       .init(executable: "/usr/bin/open", arguments: ["/Applications/Safari.app"]))
    }

    func testEmptyArgs_ReturnsNil() {
        XCTAssertNil(ProcessLauncher.resolve([], findOnPath: onPath()))
        XCTAssertNil(ProcessLauncher.resolve(["  "], findOnPath: onPath()))
    }

    func testCommandOnPath_RunsDirectly_WithExeSuffixDropped() {
        XCTAssertEqual(ProcessLauncher.resolve(["wezterm.exe", "start"], findOnPath: onPath("wezterm")),
                       .init(executable: "/usr/local/bin/wezterm", arguments: ["start"]))
    }

    func testAppName_OpensViaLaunchServices() {
        XCTAssertEqual(ProcessLauncher.resolve(["firefox.exe"], findOnPath: onPath()),
                       .init(executable: "/usr/bin/open", arguments: ["-a", "firefox"]))
        XCTAssertEqual(ProcessLauncher.resolve(["Firefox", "--private-window"], findOnPath: onPath()),
                       .init(executable: "/usr/bin/open", arguments: ["-a", "Firefox", "--args", "--private-window"]))
    }

    func testDotAppName_AlwaysOpensViaLaunchServices() {
        XCTAssertEqual(ProcessLauncher.resolve(["Safari.app"], findOnPath: onPath("Safari.app")),
                       .init(executable: "/usr/bin/open", arguments: ["-a", "Safari.app"]))
    }

    func testPath_RunsDirectly() {
        XCTAssertEqual(ProcessLauncher.resolve(["/opt/homebrew/bin/alacritty", "-e", "htop"], findOnPath: onPath()),
                       .init(executable: "/opt/homebrew/bin/alacritty", arguments: ["-e", "htop"]))
    }

    func testTildePath_IsExpanded() {
        let resolved = ProcessLauncher.resolve(["~/bin/tool"], findOnPath: onPath())
        XCTAssertEqual(resolved?.executable, NSString(string: "~/bin/tool").expandingTildeInPath)
        XCTAssertFalse(resolved?.executable.hasPrefix("~") ?? true)
    }

    func testSampleTerminalOverride_RunsOpenDirectly() {
        // The shared sample's macOS override for Win+Shift+T: `open` is on PATH.
        XCTAssertEqual(ProcessLauncher.resolve(["open", "-a", "Terminal", "."], findOnPath: { $0 == "open" ? "/usr/bin/open" : nil }),
                       .init(executable: "/usr/bin/open", arguments: ["-a", "Terminal", "."]))
    }
}
