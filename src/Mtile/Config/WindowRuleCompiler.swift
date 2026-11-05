import Foundation

/// Turns validated BlacklistRule/TagRule config entries into the compiled rules WindowManager
/// matches against. ConfigLoader already rejected invalid patterns, so failures here can't happen
/// in practice and just leave the field unconstrained.
public enum WindowRuleCompiler {
    public static func compileBlacklist(_ rules: [BlacklistRule]) -> [CompiledWindowRule] {
        rules.map { compile($0.processName, $0.className, $0.title) }
    }

    public static func compileTagRules(_ rules: [TagRule]) -> [CompiledTagRule] {
        rules.map {
            CompiledTagRule(
                match: compile($0.processName, $0.className, $0.title),
                tagIndex: $0.tag - 1,
                monitorIndex: $0.monitor == 0 ? nil : $0.monitor - 1,
                follow: $0.follow)
        }
    }

    static func compile(_ processName: String, _ className: String, _ title: String) -> CompiledWindowRule {
        CompiledWindowRule(processName: build(processName), className: build(className), title: build(title))
    }

    static func build(_ pattern: String) -> NSRegularExpression? {
        if pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
