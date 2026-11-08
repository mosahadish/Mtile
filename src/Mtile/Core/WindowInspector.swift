#if os(macOS)
import AppKit
import ApplicationServices

/// The macOS `WindowBackend`: other apps' windows via the public Accessibility API (AXUIElement),
/// displays via NSScreen. Counterpart of Wtile's Win32 WindowInspector.
///
/// Robustness rules:
///   - every app gets a short AX messaging timeout, so one hung app can't freeze the WM;
///   - an app whose window list can't be read this time keeps its previously known windows
///     (a timeout is not a close);
///   - window identity is the AXUIElement itself (CFEqual/CFHash), no private API.
public final class WindowInspector: WindowBackend {
    private struct ElementKey: Hashable {
        let element: AXUIElement
        static func == (a: ElementKey, b: ElementKey) -> Bool { CFEqual(a.element, b.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }

    private struct Entry {
        let element: AXUIElement
        let pid: pid_t
    }

    private var idsByElement: [ElementKey: WindowID] = [:]
    private var entries: [WindowID: Entry] = [:]
    private var nextID: WindowID = 1
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private static let messagingTimeout: Float = 1.0
    /// Set while toggle-taskbar has hidden the Dock: work areas then reclaim the Dock's edge.
    public var dockHidden = false

    public init() {}

    // MARK: - Identity

    /// Returns the id for `element`, allocating one the first time it's seen.
    public func id(for element: AXUIElement, pid: pid_t) -> WindowID {
        let key = ElementKey(element: element)
        if let id = idsByElement[key] { return id }
        let id = nextID
        nextID += 1
        idsByElement[key] = id
        entries[id] = Entry(element: element, pid: pid)
        return id
    }

    /// The id for an element already known, without allocating (destroy notifications).
    public func existingID(for element: AXUIElement) -> WindowID? {
        idsByElement[ElementKey(element: element)]
    }

    public func forget(_ id: WindowID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        idsByElement.removeValue(forKey: ElementKey(element: entry.element))
    }

    public func element(_ id: WindowID) -> AXUIElement? { entries[id]?.element }

    // MARK: - Apps

    public static func managedApps() -> [NSRunningApplication] {
        let own = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != own
        }
    }

    public static func appElement(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return app
    }

    /// nil when the app couldn't be asked (not responding, still launching, no AX support).
    public static func windowElements(ofApp pid: pid_t) -> [AXUIElement]? {
        guard let value = copy(appElement(pid), kAXWindowsAttribute) else { return nil }
        return value as? [AXUIElement]
    }

    // MARK: - WindowBackend

    public func monitors() -> [MonitorInfo] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let primaryHeight = primary.frame.height
        return screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let frame = Self.toAX(screen.frame, primaryHeight: primaryHeight)
            let visible = Self.toAX(screen.visibleFrame, primaryHeight: primaryHeight)
            return MonitorInfo(
                displayID: number.uint32Value,
                isPrimary: screen == primary,
                frame: frame,
                workArea: dockHidden ? DockHiding.workArea(frame: frame, visible: visible) : visible)
        }
    }

    public func allWindows() -> [WindowID] {
        var result: [WindowID] = []
        var livePIDs = Set<pid_t>()
        for app in Self.managedApps() {
            let pid = app.processIdentifier
            livePIDs.insert(pid)
            guard let elements = Self.windowElements(ofApp: pid) else {
                // Couldn't ask this time: keep what we knew rather than treating it as closed.
                result += entries.filter { $0.value.pid == pid }.map(\.key)
                continue
            }
            let ids = elements.map { id(for: $0, pid: pid) }
            let current = Set(ids)
            for (id, entry) in entries where entry.pid == pid && !current.contains(id) { forget(id) }
            result += ids
        }
        for (id, entry) in entries where !livePIDs.contains(entry.pid) { forget(id) }
        return result
    }

    public func focusedWindow() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID,
              let value = Self.copy(Self.appElement(app.processIdentifier), kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return id(for: value as! AXUIElement, pid: app.processIdentifier)
    }

    public func describe(_ id: WindowID) -> WindowSnapshot? {
        guard let entry = entries[id] else { return nil }
        let el = entry.element
        guard let role = Self.copy(el, kAXRoleAttribute) as? String else { return nil } // gone or unresponsive
        let subrole = Self.copy(el, kAXSubroleAttribute) as? String ?? ""
        let app = NSRunningApplication(processIdentifier: entry.pid)
        let fullScreen = Self.copy(el, "AXFullScreen") as? Bool ?? false

        return WindowSnapshot(
            pid: entry.pid,
            title: Self.copy(el, kAXTitleAttribute) as? String ?? "",
            className: subrole,
            processNameAliases: WindowSnapshot.aliases(
                appName: app?.localizedName ?? "",
                bundleID: app?.bundleIdentifier ?? "",
                executableName: app?.executableURL?.lastPathComponent ?? ""),
            frame: frame(id) ?? LayoutRect(x: 0, y: 0, width: 0, height: 0),
            isMinimized: Self.copy(el, kAXMinimizedAttribute) as? Bool ?? false,
            isAppHidden: app?.isHidden ?? false,
            // Standard windows only: dialogs, sheets, panels, popovers and full-screen windows
            // (which live on their own Space) are left alone, like Wtile's WindowFilter.
            isManageable: role == kAXWindowRole && subrole == kAXStandardWindowSubrole && !fullScreen)
    }

    public func title(_ id: WindowID) -> String {
        guard let el = entries[id]?.element else { return "" }
        return Self.copy(el, kAXTitleAttribute) as? String ?? ""
    }

    public func frame(_ id: WindowID) -> LayoutRect? {
        guard let el = entries[id]?.element,
              let pos = Self.copy(el, kAXPositionAttribute), CFGetTypeID(pos) == AXValueGetTypeID(),
              let size = Self.copy(el, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return LayoutRect(x: Int(point.x.rounded()), y: Int(point.y.rounded()), width: Int(extent.width.rounded()), height: Int(extent.height.rounded()))
    }

    /// Position, then size, then position again: shrinking can be refused while the window
    /// would cross a screen edge, and growing can push it off the edge, so the second move
    /// lands it where it belongs either way.
    @discardableResult
    public func setFrame(_ id: WindowID, _ rect: LayoutRect) -> Bool {
        guard let entry = entries[id] else { return false }
        let el = entry.element
        if frame(id) == rect { return true }
        var point = CGPoint(x: rect.x, y: rect.y)
        var size = CGSize(width: rect.width, height: rect.height)
        guard let pos = AXValueCreate(.cgPoint, &point), let ext = AXValueCreate(.cgSize, &size) else { return false }
        // With AXEnhancedUserInterface on (set by assistive tools), apps animate frame changes
        // and drop size updates, so turn it off on the app while resizing and restore it after.
        let app = Self.appElement(entry.pid)
        let enhanced = Self.copy(app, Self.enhancedUIAttribute) as? Bool ?? false
        if enhanced { AXUIElementSetAttributeValue(app, Self.enhancedUIAttribute as CFString, kCFBooleanFalse) }
        defer { if enhanced { AXUIElementSetAttributeValue(app, Self.enhancedUIAttribute as CFString, kCFBooleanTrue) } }
        let moved = AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, pos)
        let sized = AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, ext)
        AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, pos)
        return moved == .success && (sized == .success || frame(id)?.width == rect.width)
    }

    public func focus(_ id: WindowID) {
        guard let entry = entries[id] else { return }
        // AXFrontmost on the app works from a background agent on every macOS version, where
        // NSRunningApplication.activate can be refused by macOS 14's cooperative activation.
        AXUIElementSetAttributeValue(Self.appElement(entry.pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(entry.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString)
    }

    public func focusNothing() {
        // dwm focuses the root window; the macOS equivalent is the desktop, owned by Finder.
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            AXUIElementSetAttributeValue(Self.appElement(finder.processIdentifier), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
    }

    public func close(_ id: WindowID) {
        guard let el = entries[id]?.element, let button = Self.copy(el, kAXCloseButtonAttribute),
              CFGetTypeID(button) == AXUIElementGetTypeID() else { return }
        AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
    }

    public func terminateOwner(_ id: WindowID) {
        guard let pid = entries[id]?.pid else { return }
        NSRunningApplication(processIdentifier: pid)?.forceTerminate()
    }

    public func cursorPosition() -> (x: Int, y: Int) {
        let location = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return (Int(location.x), Int(primaryHeight - location.y))
    }

    // MARK: - Helpers

    static let enhancedUIAttribute = "AXEnhancedUserInterface"

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    /// AppKit's global coordinates have their origin at the bottom-left of the primary screen,
    /// y up; Accessibility's at its top-left, y down.
    static func toAX(_ rect: NSRect, primaryHeight: CGFloat) -> LayoutRect {
        LayoutRect(x: Int(rect.minX), y: Int(primaryHeight - rect.maxY), width: Int(rect.width), height: Int(rect.height))
    }

    static func toAppKit(_ rect: LayoutRect, primaryHeight: CGFloat) -> NSRect {
        NSRect(x: CGFloat(rect.x), y: primaryHeight - CGFloat(rect.y + rect.height), width: CGFloat(rect.width), height: CGFloat(rect.height))
    }

    /// Prompts for the Accessibility permission (System Settings > Privacy & Security >
    /// Accessibility) if it isn't granted yet. Mtile can't manage windows or see hotkeys without it.
    public static func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
#endif
