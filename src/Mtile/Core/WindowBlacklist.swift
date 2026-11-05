/// Decides whether a window should be excluded from management entirely: blacklisted if any rule
/// matches. Checked once, when a window is first seen (WindowManager.tryAdd).
public enum WindowBlacklist {
    public static func isBlacklisted(_ rules: [CompiledWindowRule], processNames: [String], className: String, title: String) -> Bool {
        rules.contains { $0.matches(processNames: processNames, className: className, title: title) }
    }
}
