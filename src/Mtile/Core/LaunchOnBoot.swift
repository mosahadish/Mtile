/// Maps the shared config's `general.launchOnBoot` to what macOS supports. Wtile's "admin" (an
/// elevated scheduled task) has no macOS meaning -- window management needs the Accessibility
/// permission, not root -- so it is treated as "user".
public enum LaunchOnBootMode: Equatable {
    case off
    case atLogin

    public static func from(_ setting: String) -> LaunchOnBootMode {
        switch setting.lowercased() {
        case "user", "admin": return .atLogin
        default: return .off
        }
    }
}

/// The per-user LaunchAgent used when Mtile runs as a bare binary (not an .app bundle), where
/// SMAppService can't register a login item. launchd starts the agent at the next login only:
/// writing the file doesn't start a second copy of an already-running Mtile.
public enum LaunchAgent {
    public static let label = "com.hollowthorn.mtile"

    public static func plist(executable: String, logPath: String) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]
    }
}

#if os(macOS)
import Foundation
import ServiceManagement

/// Applies `general.launchOnBoot`. From a signed .app bundle this registers a login item via
/// SMAppService (macOS 13+). A bare binary (e.g. `.build/release/Mtile`) can't be a login item,
/// so it gets a LaunchAgent in ~/Library/LaunchAgents pointing at the running executable instead.
public enum LaunchOnBoot {
    public static func apply(_ setting: String) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            applyLaunchAgent(LaunchOnBootMode.from(setting))
            return
        }
        let service = SMAppService.mainApp
        do {
            switch (LaunchOnBootMode.from(setting), service.status) {
            case (.atLogin, .enabled), (.off, .notRegistered), (.off, .notFound):
                break
            case (.atLogin, _):
                try service.register()
            case (.off, _):
                try service.unregister()
            }
        } catch {
            print("[launchOnBoot] Failed to apply '\(setting)': \(error)")
        }
    }

    private static func applyLaunchAgent(_ mode: LaunchOnBootMode) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let agentURL = home.appendingPathComponent("Library/LaunchAgents/\(LaunchAgent.label).plist")
        do {
            switch mode {
            case .off:
                if fm.fileExists(atPath: agentURL.path) {
                    try fm.removeItem(at: agentURL)
                    print("[launchOnBoot] Removed \(agentURL.path)")
                }
            case .atLogin:
                guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
                    print("[launchOnBoot] Couldn't resolve the Mtile executable path.")
                    return
                }
                let log = home.appendingPathComponent("Library/Logs/Mtile.log").path
                let data = try PropertyListSerialization.data(
                    fromPropertyList: LaunchAgent.plist(executable: exe, logPath: log),
                    format: .xml, options: 0)
                if (try? Data(contentsOf: agentURL)) == data { return }
                try fm.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: agentURL, options: .atomic)
                print("[launchOnBoot] Wrote \(agentURL.path) -> \(exe)")
            }
        } catch {
            print("[launchOnBoot] Failed to update \(agentURL.path): \(error)")
        }
    }
}
#endif
