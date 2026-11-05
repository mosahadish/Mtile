import Foundation

/// A compiled window-matching rule, shared by the blacklist and tag rules: nil on a field means
/// "don't constrain on this field"; every non-nil field must match (AND). Case-insensitive and
/// unanchored, same as Wtile's RegexOptions.IgnoreCase.
public struct CompiledWindowRule {
    public var processName: NSRegularExpression?
    public var className: NSRegularExpression?
    public var title: NSRegularExpression?

    public init(processName: NSRegularExpression? = nil, className: NSRegularExpression? = nil, title: NSRegularExpression? = nil) {
        self.processName = processName
        self.className = className
        self.title = title
    }

    /// `processNames` are every name the window's app is known by (see
    /// `WindowSnapshot.processNameAliases`); the rule's processName matches if any of them does,
    /// which is what lets a Windows-style "^firefox\.exe$" keep working on macOS.
    public func matches(processNames: [String], className: String, title: String) -> Bool {
        (self.processName == nil || processNames.contains { Self.isMatch(self.processName!, $0) })
            && (self.className == nil || Self.isMatch(self.className!, className))
            && (self.title == nil || Self.isMatch(self.title!, title))
    }

    public func matches(_ processName: String, _ className: String, _ title: String) -> Bool {
        matches(processNames: [processName], className: className, title: title)
    }

    static func isMatch(_ regex: NSRegularExpression, _ input: String) -> Bool {
        regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) != nil
    }
}
