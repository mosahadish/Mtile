import Foundation

/// Starts processes for `spawn` and `open-config`, never blocking the main thread. The spawn
/// target is resolved so a Wtile-style config keeps working on macOS:
///   - a trailing ".exe" is dropped ("firefox.exe" -> "firefox"),
///   - a path ("/opt/homebrew/bin/wezterm", "~/bin/x") or a command found on PATH runs directly,
///   - anything else is treated as an app name and opened via `open -a <name>` (LaunchServices
///     matches app names case-insensitively, so "firefox" finds Firefox.app).
/// Spawned processes start in the home directory, like dwm's.
public enum ProcessLauncher {
    public struct Invocation: Equatable {
        public var executable: String
        public var arguments: [String]
    }

    public static func resolve(_ args: [String], findOnPath: (String) -> String? = ProcessLauncher.findOnPath) -> Invocation? {
        guard var name = args.first?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        let rest = Array(args.dropFirst())
        if name.lowercased().hasSuffix(".exe") { name = String(name.dropLast(4)) }

        if name.hasPrefix("~") { name = NSString(string: name).expandingTildeInPath }
        if name.contains("/") && !name.lowercased().hasSuffix(".app") {
            return Invocation(executable: name, arguments: rest)
        }
        if !name.lowercased().hasSuffix(".app"), let path = findOnPath(name) {
            return Invocation(executable: path, arguments: rest)
        }
        return Invocation(executable: "/usr/bin/open", arguments: ["-a", name] + (rest.isEmpty ? [] : ["--args"] + rest))
    }

    public static func findOnPath(_ name: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    public static func spawn(_ args: [String]) {
        guard let invocation = resolve(args) else { return }
        start(invocation, context: "spawn")
    }

    /// The app launcher's equivalent of Wtile's ShellExecute: `open <target>` starts a .app
    /// bundle normally and runs a PATH executable in the default terminal (as Windows does with
    /// a console program).
    public static func launcherInvocation(_ target: String) -> Invocation {
        Invocation(executable: "/usr/bin/open", arguments: [target])
    }

    public static func launch(_ target: String, context: String) {
        start(launcherInvocation(target), context: context)
    }

    /// Opens a file in its default app (TextEdit, or whatever handles .yaml).
    public static func openFile(_ path: String, context: String) {
        start(Invocation(executable: "/usr/bin/open", arguments: ["-t", path]), context: context)
    }

    private static func start(_ invocation: Invocation, context: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        do {
            try process.run()
        } catch {
            print("[\(context)] Failed to start '\(invocation.executable)': \(error)")
        }
    }
}
