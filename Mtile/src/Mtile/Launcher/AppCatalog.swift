import Foundation

/// One launchable thing: a PATH executable or an application bundle.
public struct LauncherEntry: Equatable {
    public var displayName: String
    public var launchTarget: String

    public init(displayName: String, launchTarget: String) {
        self.displayName = displayName
        self.launchTarget = launchTarget
    }
}

/// Builds the launcher's candidate list from two sources, mirroring Wtile's AppCatalog: PATH
/// executables (what a shell would run) plus `.app` bundles under the standard application
/// folders, macOS's stand-in for Start Menu shortcuts. Rebuilt fresh on every launcher open (see
/// LauncherWindow.show) rather than cached, same as Wtile -- plain directory enumeration is cheap
/// enough not to bother with staleness tracking.
public enum AppCatalog {
    /// Searched recursively (so /Applications/Utilities and ~/Applications/Edge Apps are found),
    /// never descending into a bundle itself.
    public static var defaultAppRoots: [String] {
        ["/Applications", "/System/Applications", (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
    }

    public static func build(pathVariable: String? = ProcessInfo.processInfo.environment["PATH"],
                             appRoots: [String] = AppCatalog.defaultAppRoots) -> [LauncherEntry] {
        var entries: [LauncherEntry] = []
        addPathExecutables(&entries, pathVariable)
        for root in appRoots { addApplications(&entries, under: root) }

        var seen = Set<String>()
        let distinct = entries.filter { seen.insert("\($0.displayName.uppercased())\u{0}\($0.launchTarget.uppercased())").inserted }
        // Stable, case-insensitive, like Wtile's OrderBy(..., OrdinalIgnoreCase).
        return distinct.enumerated()
            .sorted { a, b in
                let ka = a.element.displayName.uppercased(), kb = b.element.displayName.uppercased()
                return ka != kb ? ka < kb : a.offset < b.offset
            }
            .map(\.element)
    }

    /// Fuzzy-filters and ranks `entries` for `query`: best FuzzyMatcher score first, ties by
    /// display name (case-insensitive). Same ordering as Wtile's LauncherWindow.Refilter.
    public static func filter(_ entries: [LauncherEntry], query: String) -> [LauncherEntry] {
        entries.enumerated()
            .compactMap { item -> (offset: Int, entry: LauncherEntry, score: Int)? in
                guard let score = FuzzyMatcher.score(query, item.element.displayName) else { return nil }
                return (item.offset, item.element, score)
            }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                let ka = a.entry.displayName.uppercased(), kb = b.entry.displayName.uppercased()
                return ka != kb ? ka < kb : a.offset < b.offset
            }
            .map(\.entry)
    }

    private static func addPathExecutables(_ entries: inout [LauncherEntry], _ pathVariable: String?) {
        guard let pathVariable, !pathVariable.isEmpty else { return }
        let fm = FileManager.default
        for dir in pathVariable.split(separator: ":").map({ String($0).trimmingCharacters(in: .whitespaces) }) where !dir.isEmpty {
            // A stale/inaccessible PATH entry is common -- skip it and keep building the rest.
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names {
                let path = (dir as NSString).appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue, fm.isExecutableFile(atPath: path) {
                    entries.append(LauncherEntry(displayName: name, launchTarget: path))
                }
            }
        }
    }

    private static func addApplications(_ entries: inout [LauncherEntry], under root: String) {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { return }

        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "app" {
                entries.append(LauncherEntry(displayName: url.deletingPathExtension().lastPathComponent, launchTarget: url.path))
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isPackage == true || enumerator.level > 4 { enumerator.skipDescendants() }
        }
    }
}
