import Foundation

/// The user's own Dock settings from before Mtile hid it, saved to disk so a crashed or killed
/// Mtile can still give them back on its next run. nil means "key wasn't set" (macOS default).
public struct SavedDockSettings: Codable, Equatable {
    public var autohide: Bool?
    public var autohideDelay: Double?

    public init(autohide: Bool?, autohideDelay: Double?) {
        self.autohide = autohide
        self.autohideDelay = autohideDelay
    }
}

/// Pure pieces of the Dock hiding, testable off-Mac.
public enum DockHiding {
    /// Seconds the pointer must rest at the screen edge before an auto-hidden Dock reveals
    /// itself. Large enough that it never does in practice -- the Dock is effectively gone,
    /// unlike plain auto-hide which pops it up on every hover (same distinction as Wtile's
    /// toggle-taskbar vs Windows' own taskbar auto-hide).
    public static let revealDelay: Double = 1000

    /// Whether these Dock settings are the ones Mtile writes to hide it.
    public static func isHidden(autohide: Bool?, autohideDelay: Double?) -> Bool {
        autohide == true && (autohideDelay ?? 0) >= revealDelay
    }

    /// Work area to tile into while the Dock is hidden: the display's full frame minus only the
    /// menu bar. An auto-hidden Dock still keeps a few points of `visibleFrame` at its edge (its
    /// hover strip) on whichever side it lives, so reclaim left/right/bottom from the frame and
    /// keep the top (menu bar) edge from the visible area. Accessibility coordinates (y down).
    public static func workArea(frame: LayoutRect, visible: LayoutRect) -> LayoutRect {
        let top = max(frame.y, visible.y)
        return LayoutRect(x: frame.x, y: top, width: frame.width, height: frame.y + frame.height - top)
    }
}

#if os(macOS)
import AppKit

/// Hides/shows the macOS Dock for `toggle-taskbar`. There's no public API to hide the Dock for
/// other apps, so this does what `defaults write com.apple.dock autohide-delay` tricks do: turn
/// on auto-hide with a huge reveal delay, then restart the Dock to apply it. The user's previous
/// values are saved first and restored on show (and on quit).
public final class DockController {
    private static let domain = "com.apple.dock" as CFString
    private static let autohideKey = "autohide" as CFString
    private static let delayKey = "autohide-delay" as CFString

    private let savePath: String
    private let rememberPath: String
    public private(set) var isHidden = false

    public init(savePath: String = DockController.defaultSavePath()) {
        self.savePath = savePath
        rememberPath = ((savePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent("dock-hidden")
        syncInitialState()
    }

    /// The user's last toggle-taskbar choice, kept across restarts. Quitting still gives the
    /// Dock back (so it's never stuck hidden without Mtile running); this is what the next start
    /// re-applies.
    public var rememberedHidden: Bool { FileManager.default.fileExists(atPath: rememberPath) }

    public func remember(_ hidden: Bool) {
        let fm = FileManager.default
        if hidden {
            try? fm.createDirectory(atPath: (rememberPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            fm.createFile(atPath: rememberPath, contents: Data())
        } else {
            try? fm.removeItem(atPath: rememberPath)
        }
    }

    public static func defaultSavePath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support")
        return ((base as NSString).appendingPathComponent("Mtile") as NSString).appendingPathComponent("dock-restore.json")
    }

    /// A previous run that hid the Dock and died before restoring it leaves its save file behind:
    /// pick that up as "hidden" so toggling (or quitting) still restores the user's settings. If
    /// the Dock was un-hidden by hand meanwhile, the stale save is dropped.
    private func syncInitialState() {
        guard FileManager.default.fileExists(atPath: savePath) else { return }
        if DockHiding.isHidden(autohide: Self.readBool(Self.autohideKey), autohideDelay: Self.readDouble(Self.delayKey)) {
            isHidden = true
        } else {
            try? FileManager.default.removeItem(atPath: savePath)
        }
    }

    public func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        if hidden {
            let current = SavedDockSettings(autohide: Self.readBool(Self.autohideKey), autohideDelay: Self.readDouble(Self.delayKey))
            guard save(current) else {
                print("[dock] Couldn't save the current Dock settings to \(savePath); not hiding the Dock.")
                return
            }
            Self.write(Self.autohideKey, true as CFBoolean)
            Self.write(Self.delayKey, DockHiding.revealDelay as CFNumber)
        } else {
            let saved = load() ?? SavedDockSettings(autohide: nil, autohideDelay: nil)
            Self.write(Self.autohideKey, saved.autohide.map { $0 as CFBoolean })
            Self.write(Self.delayKey, saved.autohideDelay.map { $0 as CFNumber })
            try? FileManager.default.removeItem(atPath: savePath)
        }
        CFPreferencesAppSynchronize(Self.domain)
        Self.restartDock()
        isHidden = hidden
    }

    private func save(_ settings: SavedDockSettings) -> Bool {
        do {
            let dir = (savePath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try JSONEncoder().encode(settings).write(to: URL(fileURLWithPath: savePath), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func load() -> SavedDockSettings? {
        guard let data = FileManager.default.contents(atPath: savePath) else { return nil }
        return try? JSONDecoder().decode(SavedDockSettings.self, from: data)
    }

    private static func readBool(_ key: CFString) -> Bool? {
        CFPreferencesCopyAppValue(key, domain) as? Bool
    }

    private static func readDouble(_ key: CFString) -> Double? {
        (CFPreferencesCopyAppValue(key, domain) as? NSNumber)?.doubleValue
    }

    /// nil removes the key, giving back the macOS default.
    private static func write(_ key: CFString, _ value: CFPropertyList?) {
        CFPreferencesSetAppValue(key, value, domain)
    }

    /// The Dock only reads these settings at launch; launchd relaunches it right away.
    private static func restartDock() {
        for dock in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock") {
            kill(dock.processIdentifier, SIGTERM)
        }
    }
}
#endif
