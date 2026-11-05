/// A compiled tagRules: entry. `tagIndex` and `monitorIndex` are 0-based here (the config is
/// 1-based); `monitorIndex` nil means "the monitor it opened on".
public struct CompiledTagRule {
    public var match: CompiledWindowRule
    public var tagIndex: Int
    public var monitorIndex: Int?
    public var follow: Bool

    public init(match: CompiledWindowRule, tagIndex: Int, monitorIndex: Int? = nil, follow: Bool = false) {
        self.match = match
        self.tagIndex = tagIndex
        self.monitorIndex = monitorIndex
        self.follow = follow
    }
}

/// Decides which tag a newly-seen window belongs on: first matching rule wins.
public enum WindowTagRules {
    public static func resolve(_ rules: [CompiledTagRule], processNames: [String], className: String, title: String) -> CompiledTagRule? {
        rules.first { $0.match.matches(processNames: processNames, className: className, title: title) }
    }
}
