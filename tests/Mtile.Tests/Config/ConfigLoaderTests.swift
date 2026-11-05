import XCTest
@testable import Mtile

final class ConfigLoaderTests: XCTestCase {
    /// <repo>/docs/config.sample.yaml -- the one config file shared by Wtile and Mtile.
    private static let samplePath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Config
        .deletingLastPathComponent() // Mtile.Tests
        .deletingLastPathComponent() // tests
        .deletingLastPathComponent() // <repo>
        .appendingPathComponent("docs/config.sample.yaml").path

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .newlines)
    }

    func testEmptyYaml_GivesDefaults() throws {
        let result = try ConfigLoader.load("")
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.config.general.tagCount, 9)
        XCTAssertEqual(result.config.general.macosWinKey, "option")
        XCTAssertEqual(result.config.layouts.map(\.name), ["master-stack"])
    }

    func testDefaultConfigMatchesSampleFile() throws {
        let sample = try String(contentsOfFile: Self.samplePath, encoding: .utf8)
        XCTAssertEqual(Self.normalize(DefaultConfig.yaml), Self.normalize(sample),
                       "DefaultConfig.swift is out of date with docs/config.sample.yaml; regenerate it.")
    }

    func testSampleConfig_LoadsWithoutWarnings() throws {
        let result = try ConfigLoader.loadFromFile(Self.samplePath)
        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.config.general.launchOnBoot, "off")
        XCTAssertEqual(result.config.general.macosWinKey, "option")
        XCTAssertFalse(result.config.hotkeys.isEmpty)
    }

    func testSampleConfig_EveryHotkeyCommandExistsOrIsWindowsOnly() throws {
        let config = try ConfigLoader.loadFromFile(Self.samplePath).config
        let manager = WindowManager(backend: FakeBackend(), layouts: LayoutRegistry.createDefault(), defaultLayoutName: "master-stack",
                                    defaultLayoutParams: [:], tagCount: 9)
        let registry = BuiltinCommands.createDefault(manager, spawn: { _ in })
        for name in ["quit", "reload", "open-config", "toggle-bar", "app-launcher"] {
            registry.register(ClosureCommand(name) { _ in })
        }

        for binding in config.hotkeys {
            let command = binding.command.lowercased()
            XCTAssertTrue(registry.get(command) != nil || CommandRegistry.windowsOnlyCommands.contains(command),
                          "hotkey '\(binding.keys)' uses unknown command '\(binding.command)'")
        }
    }

    func testSampleConfig_SpawnTerminalUsesMacOverride() throws {
        let config = try ConfigLoader.loadFromFile(Self.samplePath).config
        let spawn = config.hotkeys.first { $0.keys == "Win+Shift+T" }
        XCTAssertEqual(spawn?.command, "spawn")
        XCTAssertEqual(spawn?.args, ["open", "-a", "Terminal", "."])
        XCTAssertNil(spawn?.macos)
    }

    func testMacOverride_ReplacesOnlyTheGivenFields() throws {
        let yaml = """
        hotkeys:
          - keys: Win+Return
            command: spawn
            args: ["wt.exe"]
            macos:
              args: ["open", "-a", "iTerm"]
        blacklist:
          - processName: '^explorer$'
            macos:
              processName: '^Finder$'
        tagRules:
          - processName: '^slack$'
            tag: 3
            macos:
              tag: 4
              follow: true
        """
        let config = try ConfigLoader.load(yaml).config
        XCTAssertEqual(config.hotkeys, [HotkeyBinding(keys: "Win+Return", command: "spawn", args: ["open", "-a", "iTerm"])])
        XCTAssertEqual(config.blacklist, [BlacklistRule(processName: "^Finder$")])
        XCTAssertEqual(config.tagRules, [TagRule(processName: "^slack$", tag: 4, follow: true)])
    }

    func testMacOverride_EnabledFalse_DropsTheEntry() throws {
        let yaml = """
        hotkeys:
          - keys: Win+B
            command: toggle-bar
            macos:
              enabled: false
          - keys: Win+Q
            command: kill-window
        blacklist:
          - processName: '^ShellExperienceHost$'
            macos: { enabled: false }
        tagRules:
          - processName: '^outlook$'
            tag: 2
            macos: { enabled: false }
        """
        let result = try ConfigLoader.load(yaml)
        XCTAssertEqual(result.config.hotkeys.map(\.keys), ["Win+Q"])
        XCTAssertTrue(result.config.blacklist.isEmpty)
        XCTAssertTrue(result.config.tagRules.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testMacosWinKey_IsNormalized() throws {
        let result = try ConfigLoader.load("general:\n  macosWinKey: ' Command '\n")
        XCTAssertEqual(result.config.general.macosWinKey, "command")
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(MacWinKey.from(result.config.general.macosWinKey), .command)
    }

    func testMacosWinKey_Invalid_WarnsAndDefaultsToOption() throws {
        let result = try ConfigLoader.load("general:\n  macosWinKey: cmd\n")
        XCTAssertEqual(result.config.general.macosWinKey, "option")
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("macosWinKey"))
    }

    func testLaunchOnBoot_BareOffAndInvalidValues() throws {
        XCTAssertEqual(try ConfigLoader.load("general:\n  launchOnBoot: off\n").config.general.launchOnBoot, "off")
        XCTAssertEqual(try ConfigLoader.load("general:\n  launchOnBoot: User\n").config.general.launchOnBoot, "user")
        let bad = try ConfigLoader.load("general:\n  launchOnBoot: always\n")
        XCTAssertEqual(bad.config.general.launchOnBoot, "off")
        XCTAssertEqual(bad.warnings.count, 1)
    }

    func testOutOfRangeValues_AreClampedWithWarnings() throws {
        let yaml = """
        general:
          tagCount: 0
          borderGap: -4
        layouts:
          - name: master-stack
            mfact: 2
            nmaster: -1
            gap: -2
        bar:
          position: left
          height: 0
        """
        let result = try ConfigLoader.load(yaml)
        let c = result.config
        XCTAssertEqual(c.general.tagCount, 9)
        XCTAssertEqual(c.general.borderGap, 0)
        XCTAssertEqual(c.layouts[0].mfact, 0.95)
        XCTAssertEqual(c.layouts[0].nmaster, 0)
        XCTAssertEqual(c.layouts[0].gap, 0)
        XCTAssertEqual(c.bar.position, "top")
        XCTAssertEqual(c.bar.height, 24)
        XCTAssertEqual(result.warnings.count, 7)
    }

    func testInvalidEntries_AreDroppedWithWarnings() throws {
        let yaml = """
        general:
          tagCount: 5
        hotkeys:
          - keys: Win+Nope
            command: focus-next
          - keys: Win+J
            command: ''
          - keys: Win+K
            command: focus-prev
        blacklist:
          - title: ''
          - processName: '([unclosed'
        tagRules:
          - processName: '^x$'
            tag: 6
          - processName: '^y$'
            tag: 1
            monitor: -1
          - processName: '^z$'
            tag: 5
        """
        let result = try ConfigLoader.load(yaml)
        XCTAssertEqual(result.config.hotkeys.map(\.keys), ["Win+K"])
        XCTAssertTrue(result.config.blacklist.isEmpty)
        XCTAssertEqual(result.config.tagRules.map(\.processName), ["^z$"])
        XCTAssertEqual(result.warnings.count, 6)
    }

    func testMalformedYaml_Throws() {
        XCTAssertThrowsError(try ConfigLoader.load("general: [unclosed"))
    }
}
