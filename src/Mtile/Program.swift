import Foundation

// Mtile: a dwm-style tiling window manager for macOS, inspired by and modelled on Wtile
// (https://github.com/HollowThorn/Wtile), its Windows sibling. Same config file
// (docs/config.sample.yaml), same commands and layouts. Reads
// $XDG_CONFIG_HOME/mtile/config.yaml (default ~/.config/mtile/config.yaml), writing the default
// config there on first run. Like Wtile, the config isn't watched live: press the "reload" hotkey
// (Win+Shift+R, i.e. Option+Shift+R with the default general.macosWinKey) after editing.

@main
enum Program {
    static func main() {
        #if os(macOS)
        MtileApp.run()
        #else
        // The layouts, config, commands and window-manager logic build and test anywhere; only
        // the Accessibility/AppKit layer is macOS-specific.
        FileHandle.standardError.write(Data("Mtile only runs on macOS.\n".utf8))
        exit(1)
        #endif
    }
}

#if os(macOS)
import AppKit

/// The one running instance, reachable from the C signal/exception handlers (which can't capture).
private var runningApp: MtileApp?

final class MtileApp {
    private let configPath: String
    private let inspector = WindowInspector()
    private let dock = DockController()
    private let theme: BarTheme
    private let manager: WindowManager
    private let commands: CommandRegistry
    private let tracker: WindowEventTracker
    private let hotkeys: HotkeyManager
    private var barConfig: BarConfig
    private var bars: [BarWindow] = []
    private var tray: TrayIcon?
    private var launcher: LauncherWindow!
    private var applier: ConfigApplier!
    private var clockTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var wakeTokens: [NSObjectProtocol] = []
    private var cleanedUp = false

    static func run() {
        // Under launchd stdout is a file and would be block-buffered: messages (e.g. "waiting for
        // permission") would never reach ~/Library/Logs/Mtile.log while Mtile is still running.
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)

        guard acquireSingleInstanceLock() else {
            print("Mtile is already running.")
            exit(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // no Dock icon, no menu bar of its own

        if WindowInspector.ensureAccessibilityPermission(prompt: true) {
            launch()
        } else {
            PermissionWaiter.begin(then: launch)
        }
        app.run()
    }

    private static func launch() {
        let mtile = MtileApp(configPath: prepareConfigFile())
        runningApp = mtile
        mtile.start()
    }

    private init(configPath: String) {
        self.configPath = configPath
        let config = Self.loadAndReport(configPath)
        barConfig = config.bar
        theme = BarTheme(config.bar.colors)
        inspector.dockHidden = dock.isHidden // before the first monitor read: a previous run may have left it hidden
        if dock.rememberedHidden && !dock.isHidden {
            dock.setHidden(true)
            inspector.dockHidden = dock.isHidden
        }

        let params = ConfigApplier.layoutParams(config) ?? ["nmaster": 1, "mfact": 0.55, "gap": 0]
        manager = WindowManager(backend: inspector, layouts: LayoutRegistry.createDefault(),
                                defaultLayoutName: config.general.defaultLayout, defaultLayoutParams: params,
                                tagCount: config.general.tagCount)
        manager.initializeMonitors()
        manager.setBlacklist(WindowRuleCompiler.compileBlacklist(config.blacklist))
        manager.setTagRules(WindowRuleCompiler.compileTagRules(config.tagRules))
        manager.setNewIsMaster(config.general.newIsMaster)
        LaunchOnBoot.apply(config.general.launchOnBoot)

        commands = BuiltinCommands.createDefault(manager)
        tracker = WindowEventTracker(inspector: inspector, manager: manager)
        hotkeys = HotkeyManager(commands: commands)

        applier = ConfigApplier(
            manager: manager,
            applyBar: { [unowned self] bar in
                self.barConfig = bar
                self.theme.apply(bar.colors)
                for b in self.bars { b.applyConfig(bar) }
                self.launcher.applyConfig(bar)
            },
            applyHotkeys: { [unowned self] bindings, winKey in self.hotkeys.applyBindings(bindings, winKey: winKey) },
            applyLaunchOnBoot: LaunchOnBoot.apply)

        launcher = LauncherWindow(manager: manager, config: config.bar)
        registerAppCommands()
        hotkeys.applyBindings(config.hotkeys, winKey: MacWinKey.from(config.general.macosWinKey))
    }

    private func start() {
        // Bars first: they reserve their height before the first arrange.
        rebuildBars()
        manager.onChange.append { [unowned self] in for b in self.bars { b.invalidate() } }
        manager.seed()

        tracker.onScreensChanged = { [unowned self] countChanged in
            if countChanged { self.rebuildBars() } else { for b in self.bars { b.reposition() } }
            self.manager.arrange()
        }
        tracker.start()

        if !hotkeys.start() {
            print("[hotkeys] Couldn't install the keyboard event tap; check the Accessibility permission.")
        }
        tray = TrayIcon(commands: commands)
        observeWake()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [unowned self] _ in
            for b in self.bars { b.invalidate() }
            self.hotkeys.ensureRunning()
        }
        installCleanupHandlers()
        if dock.isHidden { refreshGeometrySoon() }
        print("Mtile (inspired by Wtile) is running. Tracking \(manager.windows.count) window(s). Config: \(configPath). Waiting for events...")
    }

    private func registerAppCommands() {
        commands.register(ClosureCommand("quit") { [unowned self] _ in
            self.cleanup()
            NSApp.terminate(nil)
        })
        commands.register(ClosureCommand("open-config") { [configPath] _ in
            ProcessLauncher.openFile(configPath, context: "open-config")
        })
        commands.register(ClosureCommand("toggle-bar") { [unowned self] _ in
            let showing = self.bars.first?.isVisible ?? true
            for b in self.bars { b.setVisible(!showing) }
            self.manager.arrange()
        })
        commands.register(ClosureCommand("toggle-taskbar") { [unowned self] _ in
            self.dock.setHidden(!self.dock.isHidden) { [weak self] in self?.refreshGeometry() }
            self.dock.remember(self.dock.isHidden)
            self.inspector.dockHidden = self.dock.isHidden
            self.refreshGeometry()
            self.refreshGeometrySoon()
        })
        commands.register(AppLauncherCommand { [unowned self] elevated in self.launcher.toggle(elevated: elevated) })
        // Re-reads the config and applies it, then re-reads display geometry -- one hotkey for
        // both "I edited the config" and "a monitor change was missed", same as Wtile's reload.
        commands.register(ClosureCommand("reload") { [unowned self] _ in
            do {
                let result = try ConfigLoader.loadFromFile(self.configPath)
                for warning in result.warnings { print("[config] warning: \(warning)") }
                self.applier.apply(result.config)
            } catch {
                print("[config] Couldn't parse \(self.configPath); keeping the previous config. \(error)")
                return
            }
            self.refreshGeometry()
            print("[reload] Done.")
        })
    }

    /// After sleep the keyboard tap can come back disabled or invalidated (no "disabled" event
    /// reaches the callback then), and displays reattach a moment after wake, sometimes without a
    /// screen-parameters notification. Revive the tap and re-read geometry a few times.
    private func observeWake() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            wakeTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, !self.cleanedUp else { return }
                print("[wake] \(note.name.rawValue); re-checking hotkeys and displays.")
                for delay in [0.0, 1.0, 3.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self, !self.cleanedUp else { return }
                        self.hotkeys.ensureRunning()
                        self.refreshGeometry()
                    }
                }
            })
        }
    }

    /// The Dock restarts to apply a hide/show; visibleFrame only catches up once it's back (and,
    /// when hiding, has switched auto-hide on live).
    private func refreshGeometrySoon() {
        for delay in [1.0, 2.5, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refreshGeometry() }
        }
    }

    /// Re-reads display geometry, then re-places the bars and re-tiles.
    private func refreshGeometry() {
        guard !cleanedUp else { return }
        if manager.refreshMonitors() { rebuildBars() } else { for b in bars { b.reposition() } }
        manager.arrange()
    }

    private func rebuildBars() {
        for b in bars { b.close() }
        bars = manager.monitors.indices.map {
            BarWindow(manager: manager, commands: commands, theme: theme, monitorIndex: $0, config: barConfig)
        }
    }

    /// Puts every parked (hidden-tag) window back on screen. Idempotent; runs on quit, on
    /// SIGINT/SIGTERM and on an uncaught Objective-C exception, so a stopped Mtile never leaves
    /// windows hanging off the edge of the screen.
    func cleanup() {
        guard !cleanedUp else { return }
        cleanedUp = true
        clockTimer?.invalidate()
        for token in wakeTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        wakeTokens.removeAll()
        hotkeys.stop()
        tracker.stop()
        manager.restoreAllWindows()
        dock.setHidden(false) // give the Dock back before we stop managing it, like Wtile's taskbar
        for b in bars { b.close() }
        tray?.remove()
    }

    private func installCleanupHandlers() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN) // let the dispatch source handle it instead of the default action
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                runningApp?.cleanup()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
        NSSetUncaughtExceptionHandler { exception in
            print("[fatal] \(exception)")
            runningApp?.cleanup()
        }
    }

    // MARK: - Config file

    static func configDirectory() -> String {
        let env = ProcessInfo.processInfo.environment
        if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty { return (xdg as NSString).appendingPathComponent("mtile") }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".config/mtile")
    }

    private static func prepareConfigFile() -> String {
        let dir = configDirectory()
        let path = (dir as NSString).appendingPathComponent("config.yaml")
        if !FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try (DefaultConfig.yaml + "\n").write(toFile: path, atomically: true, encoding: .utf8)
                print("[config] No config found; wrote defaults to \(path)")
            } catch {
                print("[config] Couldn't write the default config to \(path): \(error)")
            }
        }
        return path
    }

    private static func loadAndReport(_ path: String) -> MtileConfig {
        do {
            let result = try ConfigLoader.loadFromFile(path)
            for warning in result.warnings { print("[config] warning: \(warning)") }
            return result.config
        } catch {
            print("[config] Couldn't parse \(path); using built-in defaults. \(error)")
            return (try? ConfigLoader.load(DefaultConfig.yaml).config) ?? MtileConfig()
        }
    }

    /// Two instances would both grab the same hotkeys and fight over the same windows. An
    /// advisory lock (released by the OS when the process dies) plays the role of Wtile's mutex.
    private static func acquireSingleInstanceLock() -> Bool {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("mtile-\(getuid()).lock")
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return true } // can't tell; don't block startup over it
        return flock(fd, LOCK_EX | LOCK_NB) == 0 // fd intentionally kept open for the process lifetime
    }
}

/// Shown while Mtile lacks the Accessibility permission. That happens whenever the binary isn't
/// trusted on its own -- typically when it's started at login by the LaunchAgent (no terminal to
/// inherit the permission from) after a rebuild changed its ad-hoc signature. Instead of
/// blocking the main thread invisibly, it puts a menu-bar item up, polls from the run loop, and
/// hands over to the real app once access is granted.
private enum PermissionWaiter {
    private static var item: NSStatusItem?
    private static var timer: Timer?
    private static let handler = MenuHandler()

    static func begin(then onGranted: @escaping () -> Void) {
        let exe = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
        print("Waiting for the Accessibility permission for \(exe) (System Settings > Privacy & Security > Accessibility). "
            + "If Mtile is already listed there, remove it and add it again: rebuilding changes its signature.")

        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "Mtile ⚠"
        status.button?.toolTip = "Mtile needs the Accessibility permission"
        let menu = NSMenu()
        let info = NSMenuItem(title: "Waiting for Accessibility permission…", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(handler.item("Open Accessibility settings", #selector(MenuHandler.openSettings)))
        menu.addItem(handler.item("Reveal Mtile binary in Finder", #selector(MenuHandler.reveal)))
        menu.addItem(.separator())
        menu.addItem(handler.item("Quit Mtile", #selector(MenuHandler.quit)))
        status.menu = menu
        item = status

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            guard WindowInspector.ensureAccessibilityPermission(prompt: false) else { return }
            timer?.invalidate()
            timer = nil
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            print("Accessibility permission granted; starting.")
            onGranted()
        }
    }

    private final class MenuHandler: NSObject {
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
            menuItem.target = self
            return menuItem
        }

        @objc func openSettings() {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }

        @objc func reveal() {
            if let url = Bundle.main.executableURL?.resolvingSymlinksInPath() {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }

        @objc func quit() { exit(0) }
    }
}
#endif
