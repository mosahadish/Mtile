import Foundation

/// The builtin command set, named and argument-compatible with Wtile's BuiltinCommands.cs so the
/// same hotkeys: section drives both. Commands that need app-level objects (quit, reload,
/// open-config, toggle-bar) are registered by Program, same split as Wtile.
public enum BuiltinCommands {
    public static func createDefault(
        _ manager: WindowManager,
        spawn: @escaping ([String]) -> Void = { ProcessLauncher.spawn($0) }
    ) -> CommandRegistry {
        let registry = CommandRegistry()

        // Args: ["<1-based tag number>"].
        registry.register(ClosureCommand("view-tag") { args in
            if let n = singleInt(args) { manager.activateTag(n - 1) }
        })
        registry.register(ClosureCommand("move-window-to-tag") { args in
            if let n = singleInt(args) { manager.moveWindowToTag(n - 1) }
        })
        registry.register(ClosureCommand("focus-next") { _ in manager.focusNext() })
        registry.register(ClosureCommand("focus-prev") { _ in manager.focusPrev() })
        registry.register(ClosureCommand("swap-master") { _ in manager.swapMaster() })
        registry.register(ClosureCommand("toggle-floating") { _ in manager.toggleFloating() })
        registry.register(ClosureCommand("toggle-pinned") { _ in manager.togglePinned() })
        registry.register(ClosureCommand("view-all-tags") { _ in manager.viewAllTags() })
        // Args: ["<signed delta>"].
        registry.register(ClosureCommand("adjust-mfact") { args in
            if let d = singleDouble(args) { manager.adjustMfact(d) }
        })
        registry.register(ClosureCommand("adjust-nmaster") { args in
            if let d = singleDouble(args) { manager.adjustNmaster(d) }
        })
        registry.register(ClosureCommand("adjust-gap") { args in
            if let d = singleDouble(args) { manager.adjustGap(d) }
        })
        registry.register(ClosureCommand("toggle-gap") { _ in manager.toggleGap() })
        registry.register(ClosureCommand("set-layout") { args in
            if args.count == 1 { manager.setLayout(args[0]) }
        })
        registry.register(ClosureCommand("shuffle-window") { args in
            if let n = singleInt(args) { manager.shuffleWindow(n) }
        })
        registry.register(ClosureCommand("shift-view") { args in
            if let n = singleInt(args) { manager.shiftView(n) }
        })
        registry.register(ClosureCommand("toggle-last-tag") { _ in manager.toggleLastTag() })
        registry.register(ClosureCommand("focus-monitor") { args in
            if let n = singleInt(args) { manager.focusMonitor(n) }
        })
        registry.register(ClosureCommand("move-window-to-monitor") { args in
            if let n = singleInt(args) { manager.moveWindowToMonitor(n) }
        })
        // Presses the window's close button (AXCloseButton), same as Wtile's WM_CLOSE.
        registry.register(ClosureCommand("kill-window") { _ in manager.closeFocusedWindow() })
        // Force-terminates the owning app -- no save prompt.
        registry.register(ClosureCommand("force-kill-window") { _ in manager.forceCloseFocusedWindow() })
        // Args: [executable or app name, ...args]. See ProcessLauncher for macOS name resolution.
        registry.register(ClosureCommand("spawn") { args in
            if !args.isEmpty { spawn(args) }
        })
        // Prints the focused window's process/class/title so they can be pasted into rules.
        registry.register(ClosureCommand("inspect-window") { _ in
            print(manager.describeFocusedWindow())
        })
        return registry
    }

    /// Same acceptance as .NET's int.TryParse with default styles: optional surrounding
    /// whitespace and a leading sign.
    static func singleInt(_ args: [String]) -> Int? {
        guard args.count == 1 else { return nil }
        return Int(args[0].trimmingCharacters(in: .whitespaces))
    }

    static func singleDouble(_ args: [String]) -> Double? {
        guard args.count == 1 else { return nil }
        let value = Double(args[0].trimmingCharacters(in: .whitespaces))
        return value?.isFinite == true ? value : nil
    }
}

/// Toggles the dmenu-style app launcher popup (PATH executables + .app bundles, fuzzy-filtered).
/// Not part of createDefault -- like Wtile's AppLauncherCommand it needs the launcher window,
/// which Program builds after the registry. Args: ["elevated"] is accepted for config
/// compatibility (see LauncherWindow.toggle); anything else means a plain toggle.
public struct AppLauncherCommand: Command {
    public let name = "app-launcher"
    private let toggle: (Bool) -> Void

    public init(toggle: @escaping (Bool) -> Void) {
        self.toggle = toggle
    }

    public func execute(_ args: [String]) { toggle(args.contains("elevated")) }
}
