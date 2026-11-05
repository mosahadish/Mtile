// Same shape and key names as Wtile's ConfigModel.cs, so one YAML file reads the same on both
// platforms. Every field falls back to its default when missing; unknown keys are ignored.
// Fields marked "Windows-only" are parsed (so a shared config doesn't produce errors) but have no
// effect on macOS.

public struct MtileConfig: Codable, Equatable {
    public var general = GeneralConfig()
    public var layouts: [LayoutConfig] = []
    public var bar = BarConfig()
    public var hotkeys: [HotkeyBinding] = []
    public var blacklist: [BlacklistRule] = []
    public var tagRules: [TagRule] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MtileConfig()
        general = try c.decodeIfPresent(GeneralConfig.self, forKey: .general) ?? d.general
        layouts = try c.decodeIfPresent([LayoutConfig].self, forKey: .layouts) ?? d.layouts
        bar = try c.decodeIfPresent(BarConfig.self, forKey: .bar) ?? d.bar
        hotkeys = try c.decodeIfPresent([HotkeyBinding].self, forKey: .hotkeys) ?? d.hotkeys
        blacklist = try c.decodeIfPresent([BlacklistRule].self, forKey: .blacklist) ?? d.blacklist
        tagRules = try c.decodeIfPresent([TagRule].self, forKey: .tagRules) ?? d.tagRules
    }
}

public struct GeneralConfig: Codable, Equatable {
    public var tagCount = 9
    public var focusFollowsMouse = false
    public var borderGap = 0

    /// Layout every tag on every monitor starts on; one of the names in LayoutRegistry.
    public var defaultLayout = "master-stack"

    /// Windows-only: macOS has no supported way to remove another app's title bar.
    public var hideTitlebars = false

    public var focusedBorderWidth = 2
    public var focusedBorderColor = "#89b4fa"
    public var rememberState = false

    /// "off" | "user" on macOS (registered through SMAppService). "admin" is Windows-only and is
    /// treated as "user" here.
    public var launchOnBoot = "off"

    /// dwm's attach vs. attachaside: a new window becomes master (true) or attaches after it.
    public var newIsMaster = true

    /// Mtile-only: which Mac key the config's "Win" means ("option" or "command"); "Alt" is the
    /// other one. Wtile ignores this key.
    public var macosWinKey = "option"

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GeneralConfig()
        tagCount = try c.decodeIfPresent(Int.self, forKey: .tagCount) ?? d.tagCount
        focusFollowsMouse = try c.decodeIfPresent(Bool.self, forKey: .focusFollowsMouse) ?? d.focusFollowsMouse
        borderGap = try c.decodeIfPresent(Int.self, forKey: .borderGap) ?? d.borderGap
        defaultLayout = try c.decodeIfPresent(String.self, forKey: .defaultLayout) ?? d.defaultLayout
        hideTitlebars = try c.decodeIfPresent(Bool.self, forKey: .hideTitlebars) ?? d.hideTitlebars
        focusedBorderWidth = try c.decodeIfPresent(Int.self, forKey: .focusedBorderWidth) ?? d.focusedBorderWidth
        focusedBorderColor = try c.decodeIfPresent(String.self, forKey: .focusedBorderColor) ?? d.focusedBorderColor
        rememberState = try c.decodeIfPresent(Bool.self, forKey: .rememberState) ?? d.rememberState
        launchOnBoot = try c.decodeIfPresent(String.self, forKey: .launchOnBoot) ?? d.launchOnBoot
        newIsMaster = try c.decodeIfPresent(Bool.self, forKey: .newIsMaster) ?? d.newIsMaster
        macosWinKey = try c.decodeIfPresent(String.self, forKey: .macosWinKey) ?? d.macosWinKey
    }
}

public struct LayoutConfig: Codable, Equatable {
    public var name = ""
    public var symbol = ""
    public var nmaster = 1
    public var mfact = 0.55
    public var gap = 0

    public init(name: String = "", symbol: String = "", nmaster: Int = 1, mfact: Double = 0.55, gap: Int = 0) {
        self.name = name
        self.symbol = symbol
        self.nmaster = nmaster
        self.mfact = mfact
        self.gap = gap
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LayoutConfig()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? d.symbol
        nmaster = try c.decodeIfPresent(Int.self, forKey: .nmaster) ?? d.nmaster
        mfact = try c.decodeIfPresent(Double.self, forKey: .mfact) ?? d.mfact
        gap = try c.decodeIfPresent(Int.self, forKey: .gap) ?? d.gap
    }
}

public struct BarConfig: Codable, Equatable {
    public var height = 24
    /// Empty or a font macOS doesn't have (e.g. Wtile's "Segoe UI") falls back to the system font.
    public var fontFamily = ""
    public var fontSize = 12.0
    public var position = "top"
    /// On a notched display, a top bar sits in the menu-bar strip beside the notch.
    public var notch = true
    public var occupiedTagIndicator = "marker"
    public var segments = BarSegmentsConfig()
    public var colors = BarColorsConfig()
    public var modules: [BarModuleConfig] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BarConfig()
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? d.height
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? d.fontFamily
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        position = try c.decodeIfPresent(String.self, forKey: .position) ?? d.position
        notch = try c.decodeIfPresent(Bool.self, forKey: .notch) ?? d.notch
        occupiedTagIndicator = try c.decodeIfPresent(String.self, forKey: .occupiedTagIndicator) ?? d.occupiedTagIndicator
        segments = try c.decodeIfPresent(BarSegmentsConfig.self, forKey: .segments) ?? d.segments
        colors = try c.decodeIfPresent(BarColorsConfig.self, forKey: .colors) ?? d.colors
        modules = try c.decodeIfPresent([BarModuleConfig].self, forKey: .modules) ?? d.modules
    }
}

public struct BarSegmentsConfig: Codable, Equatable {
    public var left = ["tags", "layout-symbol", "window-title"]
    public var right = ["clock"]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BarSegmentsConfig()
        left = try c.decodeIfPresent([String].self, forKey: .left) ?? d.left
        right = try c.decodeIfPresent([String].self, forKey: .right) ?? d.right
    }
}

public struct BarModuleConfig: Codable, Equatable {
    public var name = ""
    public var format = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
    }
}

public struct BarColorsConfig: Codable, Equatable {
    public var background = "#1e1e2e"
    public var foreground = "#cdd6f4"
    public var activeTag = "#89b4fa"
    public var urgentTag = "#f38ba8"
    public var occupiedTag = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BarColorsConfig()
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? d.background
        foreground = try c.decodeIfPresent(String.self, forKey: .foreground) ?? d.foreground
        activeTag = try c.decodeIfPresent(String.self, forKey: .activeTag) ?? d.activeTag
        urgentTag = try c.decodeIfPresent(String.self, forKey: .urgentTag) ?? d.urgentTag
        occupiedTag = try c.decodeIfPresent(String.self, forKey: .occupiedTag) ?? d.occupiedTag
    }
}

public struct HotkeyBinding: Codable, Equatable {
    public var keys = ""
    public var command = ""
    public var args: [String] = []
    /// Mtile-only; Wtile ignores this key. See `PlatformOverride`.
    public var macos: PlatformOverride?

    public init(keys: String = "", command: String = "", args: [String] = [], macos: PlatformOverride? = nil) {
        self.keys = keys
        self.command = command
        self.args = args
        self.macos = macos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keys = try c.decodeIfPresent(String.self, forKey: .keys) ?? ""
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        macos = try c.decodeIfPresent(PlatformOverride.self, forKey: .macos)
    }
}

/// An optional `macos:` block on a hotkey, blacklist or tagRules entry, so one config file can
/// serve Wtile and Mtile: any field set here replaces the entry's own value on macOS only, and
/// `enabled: false` drops the entry on macOS. Wtile's loader ignores unknown keys, so it never
/// sees this. Example:
///
///     - keys: "Win+Shift+T"
///       command: spawn
///       args: ["wt.exe"]
///       macos:
///         args: ["Terminal"]
public struct PlatformOverride: Codable, Equatable {
    public var enabled: Bool?
    public var keys: String?
    public var command: String?
    public var args: [String]?
    public var processName: String?
    public var className: String?
    public var title: String?
    public var tag: Int?
    public var monitor: Int?
    public var follow: Bool?

    public init(enabled: Bool? = nil, keys: String? = nil, command: String? = nil, args: [String]? = nil,
                processName: String? = nil, className: String? = nil, title: String? = nil,
                tag: Int? = nil, monitor: Int? = nil, follow: Bool? = nil) {
        self.enabled = enabled
        self.keys = keys
        self.command = command
        self.args = args
        self.processName = processName
        self.className = className
        self.title = title
        self.tag = tag
        self.monitor = monitor
        self.follow = follow
    }
}

/// A window is blacklisted (never managed) if every non-blank field matches it as a
/// case-insensitive, unanchored regex (same as Wtile). On macOS, `processName` is tried against
/// the app's name, bundle identifier, executable name and executable name + ".exe" (so
/// "^firefox\\.exe$" from a Windows config still matches Firefox), and `className` is the
/// window's AXSubrole (e.g. "AXStandardWindow", "AXDialog").
public struct BlacklistRule: Codable, Equatable {
    public var processName = ""
    public var className = ""
    public var title = ""
    public var macos: PlatformOverride?

    public init(processName: String = "", className: String = "", title: String = "", macos: PlatformOverride? = nil) {
        self.processName = processName
        self.className = className
        self.title = title
        self.macos = macos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        processName = try c.decodeIfPresent(String.self, forKey: .processName) ?? ""
        className = try c.decodeIfPresent(String.self, forKey: .className) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        macos = try c.decodeIfPresent(PlatformOverride.self, forKey: .macos)
    }
}

/// Drops a matching window onto `tag` (1-based) and optionally `monitor` (1-based, 0 = any)
/// when it's first seen. Same matching semantics as `BlacklistRule`.
public struct TagRule: Codable, Equatable {
    public var processName = ""
    public var className = ""
    public var title = ""
    public var tag = 0
    public var monitor = 0
    public var follow = false
    public var macos: PlatformOverride?

    public init(processName: String = "", className: String = "", title: String = "", tag: Int = 0, monitor: Int = 0, follow: Bool = false, macos: PlatformOverride? = nil) {
        self.processName = processName
        self.className = className
        self.title = title
        self.tag = tag
        self.monitor = monitor
        self.follow = follow
        self.macos = macos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        processName = try c.decodeIfPresent(String.self, forKey: .processName) ?? ""
        className = try c.decodeIfPresent(String.self, forKey: .className) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        tag = try c.decodeIfPresent(Int.self, forKey: .tag) ?? 0
        monitor = try c.decodeIfPresent(Int.self, forKey: .monitor) ?? 0
        follow = try c.decodeIfPresent(Bool.self, forKey: .follow) ?? false
        macos = try c.decodeIfPresent(PlatformOverride.self, forKey: .macos)
    }
}
