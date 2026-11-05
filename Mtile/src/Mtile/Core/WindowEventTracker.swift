#if os(macOS)
import AppKit
import ApplicationServices

/// Feeds window events into WindowManager. Counterpart of Wtile's WinEventTracker, built from
/// one AXObserver per app plus NSWorkspace notifications. macOS doesn't deliver these reliably for
/// every app (Electron and Java apps are notorious), so a periodic `resync` backs them up: events
/// make Mtile fast, the resync makes it correct.
public final class WindowEventTracker {
    private let inspector: WindowInspector
    private let manager: WindowManager
    private var observers: [pid_t: AXObserver] = [:]
    private var tokens: [NSObjectProtocol] = []
    private var timer: Timer?

    /// Called after the display configuration changed and the manager re-read it; the Bool says
    /// whether the number of connected displays changed (bars must be rebuilt).
    public var onScreensChanged: ((Bool) -> Void)?

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXTitleChangedNotification,
    ]

    public init(inspector: WindowInspector, manager: WindowManager) {
        self.inspector = inspector
        self.manager = manager
    }

    public func start() {
        for app in WindowInspector.managedApps() { observe(app.processIdentifier) }

        let center = NSWorkspace.shared.notificationCenter
        func on(_ name: Notification.Name, _ handler: @escaping (NSRunningApplication) -> Void) {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { handler(app) }
            })
        }
        on(NSWorkspace.didLaunchApplicationNotification) { [weak self] app in
            guard let self, app.activationPolicy == .regular else { return }
            self.observe(app.processIdentifier)
            // Windows of a freshly launched app often aren't readable yet; look again shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.manager.resync() }
        }
        on(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            guard let self else { return }
            self.observers.removeValue(forKey: app.processIdentifier)
            self.manager.onAppTerminated(pid: app.processIdentifier)
        }
        on(NSWorkspace.didActivateApplicationNotification) { [weak self] _ in
            guard let self else { return }
            self.manager.onFocusChanged(self.inspector.focusedWindow())
        }
        on(NSWorkspace.didHideApplicationNotification) { [weak self] app in
            self?.manager.onAppHiddenChanged(pid: app.processIdentifier, hidden: true)
        }
        on(NSWorkspace.didUnhideApplicationNotification) { [weak self] app in
            self?.manager.onAppHiddenChanged(pid: app.processIdentifier, hidden: false)
        }
        tokens.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.manager.resync()
        })
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let countChanged = self.manager.refreshMonitors()
            self.onScreensChanged?(countChanged)
        })

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.manager.resync()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        for token in tokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        tokens.removeAll()
        observers.removeAll()
    }

    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, axCallback, &created) == .success, let observer = created else { return }

        let app = WindowInspector.appElement(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(observer, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer

        for window in WindowInspector.windowElements(ofApp: pid) ?? [] { watch(window, pid: pid) }
    }

    private func watch(_ window: AXUIElement, pid: pid_t) {
        guard let observer = observers[pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, window, name as CFString, refcon)
        }
    }

    fileprivate func handle(_ element: AXUIElement, _ notification: String) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        switch notification {
        case kAXWindowCreatedNotification:
            watch(element, pid: pid)
            let id = inspector.id(for: element, pid: pid)
            manager.onWindowCreated(id)
            // Some apps finish configuring a new window (subrole, size) a moment after creating
            // it; give the manageability check a second chance before the next resync.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.manager.onWindowCreated(id) }
        case kAXUIElementDestroyedNotification:
            if let id = inspector.existingID(for: element) {
                manager.onWindowDestroyed(id)
                inspector.forget(id)
            }
        case kAXFocusedWindowChangedNotification:
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                manager.onFocusChanged(inspector.id(for: element, pid: pid))
            }
        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            if let id = inspector.existingID(for: element) {
                manager.onMinimizeChanged(id, minimized: notification == kAXWindowMiniaturizedNotification)
            }
        case kAXTitleChangedNotification:
            if let id = inspector.existingID(for: element) { manager.onTitleChanged(id) }
        default:
            break
        }
    }
}

private func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<WindowEventTracker>.fromOpaque(refcon).takeUnretainedValue().handle(element, notification as String)
}
#endif
