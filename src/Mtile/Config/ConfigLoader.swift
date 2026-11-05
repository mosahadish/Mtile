import Foundation
import Yams

public struct ConfigLoadResult {
    public var config: MtileConfig
    public var warnings: [String]
}

/// Parses YAML config text into a validated `MtileConfig`, applying defaults and clamping
/// out-of-range values rather than failing -- a hand-edited, hot-reloaded config should degrade
/// gracefully. Only YAML syntax/type errors throw (the caller keeps the previous config).
public enum ConfigLoader {
    public static func loadFromFile(_ path: String) throws -> ConfigLoadResult {
        try load(String(contentsOfFile: path, encoding: .utf8))
    }

    public static func load(_ yaml: String) throws -> ConfigLoadResult {
        var config: MtileConfig
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config = MtileConfig()
        } else {
            config = try YAMLDecoder().decode(MtileConfig.self, from: yaml)
        }

        var warnings: [String] = []
        applyMacOverrides(&config)
        validate(&config, &warnings)
        return ConfigLoadResult(config: config, warnings: warnings)
    }

    /// Folds each entry's `macos:` block into the entry itself and drops `enabled: false`
    /// entries, so everything downstream only ever sees the effective macOS values.
    static func applyMacOverrides(_ config: inout MtileConfig) {
        config.hotkeys = config.hotkeys.compactMap { binding in
            guard let o = binding.macos else { return binding }
            if o.enabled == false { return nil }
            var b = binding
            b.keys = o.keys ?? b.keys
            b.command = o.command ?? b.command
            b.args = o.args ?? b.args
            b.macos = nil
            return b
        }
        config.blacklist = config.blacklist.compactMap { rule in
            guard let o = rule.macos else { return rule }
            if o.enabled == false { return nil }
            var r = rule
            r.processName = o.processName ?? r.processName
            r.className = o.className ?? r.className
            r.title = o.title ?? r.title
            r.macos = nil
            return r
        }
        config.tagRules = config.tagRules.compactMap { rule in
            guard let o = rule.macos else { return rule }
            if o.enabled == false { return nil }
            var r = rule
            r.processName = o.processName ?? r.processName
            r.className = o.className ?? r.className
            r.title = o.title ?? r.title
            r.tag = o.tag ?? r.tag
            r.monitor = o.monitor ?? r.monitor
            r.follow = o.follow ?? r.follow
            r.macos = nil
            return r
        }
    }

    private static func validate(_ config: inout MtileConfig, _ warnings: inout [String]) {
        if config.general.tagCount < 1 {
            warnings.append("general.tagCount must be >= 1 (was \(config.general.tagCount)); defaulting to 9.")
            config.general.tagCount = 9
        }
        if config.general.borderGap < 0 {
            warnings.append("general.borderGap cannot be negative; clamped to 0.")
            config.general.borderGap = 0
        }
        if config.general.focusedBorderWidth < 0 {
            warnings.append("general.focusedBorderWidth cannot be negative; clamped to 0.")
            config.general.focusedBorderWidth = 0
        }

        var launchOnBoot = config.general.launchOnBoot.trimmingCharacters(in: .whitespaces).lowercased()
        // YAML 1.1 reads a bare `off` as a boolean; treat its spellings the same as "off".
        if ["false", "no", "n"].contains(launchOnBoot) { launchOnBoot = "off" }
        if !["off", "user", "admin"].contains(launchOnBoot) {
            warnings.append("general.launchOnBoot must be off, user or admin (was '\(config.general.launchOnBoot)'); defaulting to off.")
            launchOnBoot = "off"
        }
        config.general.launchOnBoot = launchOnBoot

        let winKey = config.general.macosWinKey.trimmingCharacters(in: .whitespaces).lowercased()
        if MacWinKey(rawValue: winKey) == nil {
            warnings.append("general.macosWinKey must be option or command (was '\(config.general.macosWinKey)'); defaulting to option.")
            config.general.macosWinKey = MacWinKey.option.rawValue
        } else {
            config.general.macosWinKey = winKey
        }

        if config.layouts.isEmpty {
            config.layouts.append(LayoutConfig(name: "master-stack", symbol: "[]=", nmaster: 1, mfact: 0.55, gap: config.general.borderGap))
        }

        for i in config.layouts.indices {
            let name = config.layouts[i].name
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                warnings.append("A layout entry is missing a name and will be unreachable from hotkeys/tags.")
            }
            if config.layouts[i].mfact < 0.05 || config.layouts[i].mfact > 0.95 {
                warnings.append("layouts[\(name)].mfact must be between 0.05 and 0.95 (was \(config.layouts[i].mfact)); clamped.")
                config.layouts[i].mfact = min(max(config.layouts[i].mfact, 0.05), 0.95)
            }
            if config.layouts[i].nmaster < 0 {
                warnings.append("layouts[\(name)].nmaster cannot be negative; clamped to 0.")
                config.layouts[i].nmaster = 0
            }
            if config.layouts[i].gap < 0 {
                warnings.append("layouts[\(name)].gap cannot be negative; clamped to 0.")
                config.layouts[i].gap = 0
            }
        }

        if config.bar.position != "top" && config.bar.position != "bottom" {
            warnings.append("bar.position must be 'top' or 'bottom' (was '\(config.bar.position)'); defaulting to 'top'.")
            config.bar.position = "top"
        }
        if config.bar.height <= 0 {
            warnings.append("bar.height must be positive (was \(config.bar.height)); defaulting to 24.")
            config.bar.height = 24
        }

        config.hotkeys = config.hotkeys.filter { binding in
            if binding.command.trimmingCharacters(in: .whitespaces).isEmpty {
                warnings.append("hotkeys entry '\(binding.keys)' has no command and will be ignored.")
                return false
            }
            if KeyComboParser.tryParse(binding.keys) == nil {
                warnings.append("hotkeys entry has an unparseable key combo '\(binding.keys)' and will be ignored.")
                return false
            }
            return true
        }

        config.blacklist = config.blacklist.filter { rule in
            if isBlank(rule.processName) && isBlank(rule.className) && isBlank(rule.title) {
                warnings.append("A blacklist entry has no processName/className/title set and would match every window; ignored.")
                return false
            }
            return isValidPattern(rule.processName, "blacklist", "processName", &warnings)
                && isValidPattern(rule.className, "blacklist", "className", &warnings)
                && isValidPattern(rule.title, "blacklist", "title", &warnings)
        }

        let tagCount = config.general.tagCount
        config.tagRules = config.tagRules.filter { rule in
            if isBlank(rule.processName) && isBlank(rule.className) && isBlank(rule.title) {
                warnings.append("A tagRules entry has no processName/className/title set and would match every window; ignored.")
                return false
            }
            if rule.tag < 1 || rule.tag > tagCount {
                warnings.append("tagRules entry has tag \(rule.tag), outside 1..\(tagCount) (general.tagCount); ignored.")
                return false
            }
            if rule.monitor < 0 {
                warnings.append("tagRules entry has monitor \(rule.monitor); must be 1 or higher (or omitted); ignored.")
                return false
            }
            return isValidPattern(rule.processName, "tagRules", "processName", &warnings)
                && isValidPattern(rule.className, "tagRules", "className", &warnings)
                && isValidPattern(rule.title, "tagRules", "title", &warnings)
        }
    }

    private static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isValidPattern(_ pattern: String, _ section: String, _ field: String, _ warnings: inout [String]) -> Bool {
        if isBlank(pattern) { return true }
        if (try? NSRegularExpression(pattern: pattern)) != nil { return true }
        warnings.append("\(section) entry has an invalid \(field) regex '\(pattern)' and will be ignored.")
        return false
    }
}
