/// Applies a (re)loaded config to the live WindowManager, bars, hotkeys and launch-on-boot.
/// Must run on the main thread. Same order and semantics as Wtile's ConfigApplier; the
/// AppKit-owning pieces are passed in as closures so this stays plain, testable Swift.
/// `hideTitlebars`, `focusedBorder*` and `rememberState` are Windows-only for now and ignored.
public final class ConfigApplier {
    private let manager: WindowManager
    private let applyBar: (BarConfig) -> Void
    private let applyHotkeys: ([HotkeyBinding], MacWinKey) -> Void
    private let applyLaunchOnBoot: (String) -> Void

    public init(manager: WindowManager,
                applyBar: @escaping (BarConfig) -> Void,
                applyHotkeys: @escaping ([HotkeyBinding], MacWinKey) -> Void,
                applyLaunchOnBoot: @escaping (String) -> Void) {
        self.manager = manager
        self.applyBar = applyBar
        self.applyHotkeys = applyHotkeys
        self.applyLaunchOnBoot = applyLaunchOnBoot
    }

    /// The per-tag layout params a config seeds every tag with: Wtile reads them from the
    /// "master-stack" layout entry and applies them under `general.defaultLayout`.
    public static func layoutParams(_ config: MtileConfig) -> [String: Double]? {
        guard let masterStack = config.layouts.first(where: { $0.name == "master-stack" }) else { return nil }
        return ["nmaster": Double(masterStack.nmaster), "mfact": masterStack.mfact, "gap": Double(masterStack.gap)]
    }

    public func apply(_ config: MtileConfig) {
        if let params = Self.layoutParams(config) {
            manager.resetAllTagLayoutParams(config.general.defaultLayout, params)
        }
        manager.updateTagCount(config.general.tagCount)
        manager.setBlacklist(WindowRuleCompiler.compileBlacklist(config.blacklist))
        manager.setTagRules(WindowRuleCompiler.compileTagRules(config.tagRules))
        manager.setNewIsMaster(config.general.newIsMaster)
        applyLaunchOnBoot(config.general.launchOnBoot)
        applyBar(config.bar)
        applyHotkeys(config.hotkeys, MacWinKey.from(config.general.macosWinKey))
    }
}
