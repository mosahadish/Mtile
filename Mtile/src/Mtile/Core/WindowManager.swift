import Foundation

/// Owns the live set of managed windows across every monitor, each monitor's per-tag layout
/// state and focus tracking; drives arrangement. A port of Wtile's WindowManager with every OS
/// call behind `WindowBackend`, so this file is plain, unit-testable Swift. Only ever used from
/// the main thread.
///
/// Hidden tags: macOS has no supported way to hide one window of another app, so -- like
/// AeroSpace -- a window on a non-visible tag is "parked": moved so it hangs off the bottom
/// corner of its monitor with only a sliver on screen. Its previous frame is remembered and put
/// back when its tag is shown again (or on quit, see `restoreAllWindows`).
public final class WindowManager {
    public private(set) var windows: [ManagedWindow] = []
    public private(set) var monitors: [Monitor] = []
    public private(set) var tagCount: Int
    public private(set) var currentMonitorIndex = 0
    public private(set) var focusedID: WindowID?
    public private(set) var focusedTitle = ""
    public private(set) var newIsMaster = true

    private let backend: WindowBackend
    private let layouts: LayoutRegistry
    private var defaultLayoutName: String
    private var defaultLayoutParams: [String: Double]
    private var blacklist: [CompiledWindowRule] = []
    private var tagRules: [CompiledTagRule] = []
    private var suppressMonitorFollow = false
    private let clock: () -> Double
    /// Focus events arriving right after Mtile itself switched tags/moved windows are echoes of
    /// that, not a request to jump to a parked window's tag (see onFocusChanged).
    private var ignoreParkedFocusUntil = 0.0

    /// Fires after any state change a bar might need to redraw for.
    public var onChange: [() -> Void] = []

    public init(backend: WindowBackend, layouts: LayoutRegistry, defaultLayoutName: String,
                defaultLayoutParams: [String: Double], tagCount: Int = 9,
                clock: @escaping () -> Double = { Date().timeIntervalSinceReferenceDate }) {
        self.backend = backend
        self.layouts = layouts
        self.defaultLayoutName = defaultLayoutName
        self.defaultLayoutParams = defaultLayoutParams
        self.tagCount = tagCount
        self.clock = clock
    }

    // MARK: - Monitors

    public func initializeMonitors() {
        let infos = sortedMonitorInfos()
        monitors = infos.map(makeMonitor)
        if monitors.isEmpty {
            // Headless (e.g. tests with no displays): keep one placeholder so indexing is safe.
            monitors = [Monitor(displayID: nil, isPrimary: true, frame: LayoutRect(x: 0, y: 0, width: 0, height: 0),
                                workArea: LayoutRect(x: 0, y: 0, width: 0, height: 0), tags: buildTags())]
        }
        currentMonitorIndex = max(0, monitors.firstIndex { $0.isPrimary } ?? 0)
    }

    /// Re-reads display geometry. Monitors are matched by display ID, so a monitor keeps its
    /// tags across sleep/wake and resolution changes. A newly connected display gets fresh tags
    /// (Wtile needs a restart for that). Windows on a display that went away move to the current
    /// monitor, keeping their tag, since macOS has already moved them onto a remaining screen.
    /// Returns true if the number of connected monitors changed (bars need rebuilding).
    @discardableResult
    public func refreshMonitors() -> Bool {
        let infos = sortedMonitorInfos()
        if infos.isEmpty { return false }
        let connectedBefore = monitors.filter { $0.displayID != nil }.count

        var seen = Set<Int>()
        for info in infos {
            if let index = monitors.firstIndex(where: { $0.displayID == info.displayID }) {
                apply(info, to: monitors[index])
                seen.insert(index)
            } else if let index = monitors.firstIndex(where: { $0.displayID == nil }) {
                apply(info, to: monitors[index]) // a returning display reuses a vacant slot
                seen.insert(index)
            } else {
                monitors.append(makeMonitor(info))
                seen.insert(monitors.count - 1)
            }
        }
        for (index, monitor) in monitors.enumerated() where !seen.contains(index) {
            monitor.displayID = nil
            monitor.isPrimary = false
        }

        if monitors[currentMonitorIndex].displayID == nil {
            currentMonitorIndex = monitors.firstIndex { $0.isPrimary } ?? seen.min() ?? 0
        }
        for w in windows where monitors[w.monitorIndex].displayID == nil {
            w.monitorIndex = currentMonitorIndex
            w.parkedFrom = nil // its remembered spot was on the display that's gone
            if !isVisibleOn(w, monitors[currentMonitorIndex], currentMonitorIndex) {
                hideForTag(w)
            }
        }

        arrange()
        return monitors.filter { $0.displayID != nil }.count != connectedBefore
    }

    private func sortedMonitorInfos() -> [MonitorInfo] {
        // Primary first, then left-to-right: the same order focus-monitor cycles through.
        backend.monitors().sorted {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
            return ($0.frame.x, $0.frame.y) < ($1.frame.x, $1.frame.y)
        }
    }

    private func makeMonitor(_ info: MonitorInfo) -> Monitor {
        Monitor(displayID: info.displayID, isPrimary: info.isPrimary, frame: info.frame, workArea: info.workArea, tags: buildTags())
    }

    private func apply(_ info: MonitorInfo, to monitor: Monitor) {
        monitor.displayID = info.displayID
        monitor.isPrimary = info.isPrimary
        monitor.frame = info.frame
        monitor.workArea = info.workArea
    }

    private func buildTags() -> [Tag] {
        (0..<tagCount).map { _ in Tag(layoutName: defaultLayoutName, layoutParams: defaultLayoutParams) }
    }

    private var currentMonitor: Monitor { monitors[currentMonitorIndex] }
    private var currentTag: Tag { currentMonitor.tags[currentMonitor.activeTagIndex] }

    public func layoutSymbol(monitorIndex: Int) -> String {
        let monitor = monitors[monitorIndex]
        return layouts.get(monitor.tags[monitor.activeTagIndex].layoutName)?.symbol ?? "?"
    }

    public func hasWindowsOnTag(monitorIndex: Int, tagIndex: Int) -> Bool {
        windows.contains { $0.monitorIndex == monitorIndex && !$0.isHiddenByApp && ($0.tagIndex == tagIndex || $0.isPinned) }
    }

    public var isFocusedFloating: Bool { find(focusedID)?.isFloating ?? false }

    // MARK: - Config

    public func setBlacklist(_ rules: [CompiledWindowRule]) { blacklist = rules }
    public func setTagRules(_ rules: [CompiledTagRule]) { tagRules = rules }
    public func setNewIsMaster(_ enabled: Bool) { newIsMaster = enabled }

    public func setBarInsets(monitorIndex: Int, top: Int, bottom: Int) {
        guard monitors.indices.contains(monitorIndex) else { return }
        monitors[monitorIndex].reservedTopInset = top
        monitors[monitorIndex].reservedBottomInset = bottom
    }

    /// Resets every monitor's every tag layout from a reloaded config, discarding runtime
    /// divergence (e.g. from adjust-mfact) -- same as Wtile's reload.
    public func resetAllTagLayoutParams(_ layoutName: String, _ params: [String: Double]) {
        defaultLayoutName = layoutName
        defaultLayoutParams = params
        for monitor in monitors {
            for tag in monitor.tags {
                tag.layoutName = layoutName
                tag.layoutParams = params
                tag.rememberedGap = (params["gap"] ?? 0) > 0 ? params["gap"] : nil
            }
        }
        arrange()
    }

    /// Applies a new tag count; windows on a removed tag are clamped onto the last one.
    public func updateTagCount(_ count: Int) {
        guard count != tagCount, count >= 1 else { return }
        tagCount = count
        for monitor in monitors {
            let template = monitor.tags[0]
            monitor.tags = (0..<count).map { i in
                i < monitor.tags.count ? monitor.tags[i] : Tag(layoutName: template.layoutName, layoutParams: template.layoutParams)
            }
            monitor.activeTagIndex = min(monitor.activeTagIndex, count - 1)
            monitor.previousTagIndex = min(monitor.previousTagIndex, count - 1)
        }
        for w in windows where w.tagIndex >= count { w.tagIndex = count - 1 }
        resyncVisibility()
        arrange()
    }

    // MARK: - Lifecycle

    /// Adopts every already-open window, then arranges.
    public func seed() {
        for id in backend.allWindows() { tryAdd(id, arrange: false) }
        arrange()
        onFocusChanged(backend.focusedWindow())
    }

    /// Puts every parked window back where it was, so nothing is left stranded off-screen when
    /// Mtile quits (normally, on SIGINT/SIGTERM, or via its crash handler).
    public func restoreAllWindows() {
        for w in windows { showManagedWindow(w) }
    }

    /// Periodic safety net behind the Accessibility notifications, which macOS doesn't deliver
    /// reliably for every app: adopts windows the events missed, drops ones that are gone and
    /// picks up minimize/app-hide/title changes. Cheap enough to run every couple of seconds.
    public func resync() {
        let live = backend.allWindows()
        let liveSet = Set(live)
        var changed = false

        for w in windows where !liveSet.contains(w.id) {
            onWindowDestroyed(w.id)
            changed = true
        }
        for id in live where find(id) == nil {
            tryAdd(id, arrange: false)
            changed = changed || find(id) != nil
        }
        for w in windows {
            guard let snapshot = backend.describe(w.id) else { continue }
            if w.isMinimized != snapshot.isMinimized || w.isHiddenByApp != snapshot.isAppHidden {
                w.isMinimized = snapshot.isMinimized
                w.isHiddenByApp = snapshot.isAppHidden
                changed = true
            }
            w.title = snapshot.title
        }
        if changed { arrange() } else { notifyChanged() }
    }

    // MARK: - Events (from WindowEventTracker)

    public func onWindowCreated(_ id: WindowID) {
        tryAdd(id, arrange: true)
    }

    public func onWindowDestroyed(_ id: WindowID) {
        let wasFocused = id == focusedID
        if wasFocused { suppressMonitorFollow = true }
        guard remove(id) else { return }
        arrange()
        if wasFocused { focusSomethingOnCurrentMonitor() }
    }

    public func onAppTerminated(pid: Int32) {
        let ids = windows.filter { $0.pid == pid }.map(\.id)
        for id in ids { onWindowDestroyed(id) }
    }

    public func onMinimizeChanged(_ id: WindowID, minimized: Bool) {
        guard let w = find(id), w.isMinimized != minimized else { return }
        w.isMinimized = minimized
        arrange()
    }

    public func onAppHiddenChanged(pid: Int32, hidden: Bool) {
        var changed = false
        for w in windows where w.pid == pid && w.isHiddenByApp != hidden {
            w.isHiddenByApp = hidden
            changed = true
        }
        guard changed else { return }
        arrange()
        if hidden, let f = find(focusedID), f.pid == pid { focusSomethingOnCurrentMonitor() }
    }

    public func onTitleChanged(_ id: WindowID) {
        let title = backend.title(id)
        find(id)?.title = title
        if id == focusedID {
            focusedTitle = title
            notifyChanged()
        }
    }

    public func onFocusChanged(_ id: WindowID?) {
        guard let id else {
            suppressMonitorFollow = false
            focusedID = nil
            focusedTitle = ""
            notifyChanged()
            return
        }
        if find(id) == nil { tryAdd(id, arrange: true) }

        // Cmd+Tab, a Dock click or an app activating itself focused a window Mtile has parked on
        // another tag: follow it there (AeroSpace does the same) instead of leaving keyboard
        // focus on an invisible window.
        if let w = find(id), !isVisibleOn(w, monitors[w.monitorIndex], w.monitorIndex), clock() >= ignoreParkedFocusUntil {
            focusedID = id // so activateTag sees it as still visible there and doesn't refocus another window
            selectMonitor(w.monitorIndex)
            activateTag(w.tagIndex)
        }

        focusedID = id
        focusedTitle = find(id)?.title ?? backend.title(id)
        if let w = find(id) {
            if suppressMonitorFollow {
                suppressMonitorFollow = false
            } else {
                currentMonitorIndex = w.monitorIndex
            }
            monitors[w.monitorIndex].tags[w.tagIndex].lastFocused = id
        }
        notifyChanged()
    }

    // MARK: - Commands

    public func focusNext() { focusRelative(+1) }
    public func focusPrev() { focusRelative(-1) }

    private func focusRelative(_ direction: Int) {
        let visible = visibleWindowsOnCurrentMonitor()
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == focusedID }
        let next = current.map { wrap($0 + direction, visible.count) } ?? 0
        focus(visible[next])
    }

    /// dwm's zoom: master swaps with the next window; anything else becomes the new master.
    public func swapMaster() {
        guard let focused = find(focusedID), !focused.isFloating, isVisibleOn(focused, currentMonitor, currentMonitorIndex) else { return }
        let tiled = tiledWindowsOn(currentMonitor, currentMonitorIndex)
        guard tiled.count >= 2 else { return }
        let target = focused === tiled[0] ? tiled[1] : focused
        swapInStack(tiled[0], target)
        arrange()
    }

    /// bug.n's shuffleWindow: swaps the focused window with its stack neighbor.
    public func shuffleWindow(_ direction: Int) {
        guard let focused = find(focusedID), !focused.isFloating, isVisibleOn(focused, currentMonitor, currentMonitorIndex) else { return }
        let tiled = tiledWindowsOn(currentMonitor, currentMonitorIndex)
        guard let index = tiled.firstIndex(where: { $0 === focused }) else { return }
        let other = index + direction
        guard other >= 0, other < tiled.count else { return }
        swapInStack(focused, tiled[other])
        arrange()
    }

    /// Moves the focused window to another tag on its own monitor (unpinning it).
    public func moveWindowToTag(_ tagIndex: Int) {
        guard tagIndex >= 0, tagIndex < tagCount, let w = find(focusedID), w.isPinned || w.tagIndex != tagIndex else { return }
        w.isPinned = false
        w.tagIndex = tagIndex
        ignoreParkedFocusUntil = clock() + 0.5
        let monitor = monitors[w.monitorIndex]
        if isVisibleOn(w, monitor, w.monitorIndex) {
            showManagedWindow(w)
        } else {
            hideForTag(w)
        }
        arrange()
        if !isVisibleOn(w, monitor, w.monitorIndex) { focusSomethingOnCurrentMonitor() }
    }

    public func toggleFloating() {
        guard let w = find(focusedID) else { return }
        w.isFloating.toggle()
        print("[float] '\(w.title)' -> \(w.isFloating ? "floating" : "tiled")")
        arrange()
    }

    public func togglePinned() {
        guard let w = find(focusedID) else { return }
        w.isPinned.toggle()
        let monitor = monitors[w.monitorIndex]
        let hidden = !w.isPinned && !monitor.isViewingAllTags && w.tagIndex != monitor.activeTagIndex
        if hidden {
            ignoreParkedFocusUntil = clock() + 0.5
            hideForTag(w)
        }
        arrange()
        if hidden { focusSomethingOnCurrentMonitor() }
    }

    /// Nudges mfact, sign-flipped for master-stack-right so the key keeps its spatial feel.
    public func adjustMfact(_ delta: Double) {
        let tag = currentTag
        let d = tag.layoutName.lowercased() == MasterStackLayout.rightLayoutName ? -delta : delta
        tag.layoutParams["mfact"] = LayoutMath.clamp((tag.layoutParams["mfact"] ?? 0.55) + d, 0.05, 0.95)
        arrange()
    }

    public func adjustNmaster(_ delta: Double) {
        let tag = currentTag
        tag.layoutParams["nmaster"] = max(0, (tag.layoutParams["nmaster"] ?? 1) + delta)
        arrange()
    }

    public func setLayout(_ name: String) {
        currentTag.layoutName = name
        arrange()
    }

    public func adjustGap(_ delta: Double) {
        let tag = currentTag
        let updated = max(0, (tag.layoutParams["gap"] ?? 0) + delta)
        tag.layoutParams["gap"] = updated
        if updated > 0 { tag.rememberedGap = updated }
        arrange()
    }

    public func toggleGap() {
        let tag = currentTag
        tag.layoutParams["gap"] = (tag.layoutParams["gap"] ?? 0) > 0 ? 0 : (tag.rememberedGap ?? 0)
        arrange()
    }

    public func closeFocusedWindow() {
        if let id = focusedID { backend.close(id) }
    }

    public func forceCloseFocusedWindow() {
        if let id = focusedID { backend.terminateOwner(id) }
    }

    public func describeFocusedWindow() -> String {
        guard let id = focusedID, let s = backend.describe(id) else { return "[inspect] no focused window" }
        return "[inspect] process='\(s.processNameAliases.first ?? "")' class='\(s.className)' title='\(s.title)' "
            + "(processName also matches: \(s.processNameAliases.joined(separator: ", ")))"
    }

    public func shiftView(_ delta: Int) { activateTag(wrap(currentMonitor.activeTagIndex + delta, tagCount)) }
    public func toggleLastTag() { activateTag(currentMonitor.previousTagIndex) }

    /// dwm's view(~0) on the current monitor.
    public func viewAllTags() {
        let monitor = currentMonitor
        guard !monitor.isViewingAllTags else { return }
        monitor.isViewingAllTags = true
        for w in windows where w.monitorIndex == currentMonitorIndex { showManagedWindow(w) }
        arrange()
    }

    /// Switches the current monitor's visible tag: parks windows that shouldn't be visible
    /// anymore, unparks ones that should, arranges the new set.
    public func activateTag(_ tagIndex: Int) {
        guard tagIndex >= 0, tagIndex < tagCount else { return }
        let monitor = currentMonitor
        let monitorIndex = currentMonitorIndex
        if tagIndex == monitor.activeTagIndex && !monitor.isViewingAllTags { return }

        monitor.isViewingAllTags = false
        monitor.previousTagIndex = monitor.activeTagIndex
        monitor.activeTagIndex = tagIndex
        ignoreParkedFocusUntil = clock() + 0.5

        let previouslyFocused = find(focusedID)
        for w in windows where w.monitorIndex == monitorIndex {
            if isVisibleOn(w, monitor, monitorIndex) {
                showManagedWindow(w)
            } else {
                hideForTag(w)
            }
        }
        arrange()

        if previouslyFocused.map({ !isVisibleOn($0, monitor, monitorIndex) }) ?? true {
            focusSomethingOnCurrentMonitor()
        }
        notifyChanged()
    }

    /// Sets which monitor commands target without moving focus (bar tag clicks).
    public func selectMonitor(_ index: Int) {
        if monitors.indices.contains(index) { currentMonitorIndex = index }
    }

    /// dwm's focusmon.
    public func focusMonitor(_ delta: Int) {
        let connected = monitors.indices.filter { monitors[$0].displayID != nil }
        guard connected.count >= 2, let pos = connected.firstIndex(of: currentMonitorIndex) else { return }
        currentMonitorIndex = connected[wrap(pos + delta, connected.count)]
        let candidates = visibleWindowsOnCurrentMonitor()
        let remembered = candidates.first { $0.id == currentTag.lastFocused }
        if let target = remembered ?? candidates.first { focus(target) }
        notifyChanged()
    }

    /// dwm's tagmon: moves the focused window onto another monitor's active tag.
    public func moveWindowToMonitor(_ delta: Int) {
        let connected = monitors.indices.filter { monitors[$0].displayID != nil }
        guard connected.count >= 2, let w = find(focusedID), let pos = connected.firstIndex(of: w.monitorIndex) else { return }
        let target = connected[wrap(pos + delta, connected.count)]
        guard target != w.monitorIndex else { return }
        w.isPinned = false
        w.monitorIndex = target
        w.tagIndex = monitors[target].activeTagIndex
        w.parkedFrom = nil
        currentMonitorIndex = target
        ignoreParkedFocusUntil = clock() + 0.5
        arrange()
        if w.isFloating, let frame = backend.frame(w.id) {
            backend.setFrame(w.id, centered(frame, in: monitors[target].workArea))
        }
    }

    // MARK: - Arrange

    public func arrange() {
        for i in monitors.indices { arrangeMonitor(i, retry: true) }
        notifyChanged()
    }

    private func arrangeMonitor(_ index: Int, retry: Bool) {
        let monitor = monitors[index]
        guard monitor.displayID != nil else { return }
        let tiled = tiledWindowsOn(monitor, index)
        guard !tiled.isEmpty else { return }

        let tag = monitor.tags[monitor.activeTagIndex]
        guard let layout = layouts.get(tag.layoutName) else {
            print("[layout] Unknown layout '\(tag.layoutName)' for tag \(monitor.activeTagIndex + 1) on monitor \(index + 1); skipping arrange.")
            return
        }

        var area = monitor.workArea
        area.y += monitor.reservedTopInset
        area.height -= monitor.reservedTopInset + monitor.reservedBottomInset
        guard !area.isEmpty else { return }

        let rects = layout.arrange(LayoutContext(workArea: area, tiledWindowCount: tiled.count, params: tag.layoutParams))
        var anyFailed = false
        for (w, rect) in zip(tiled, rects) {
            if backend.setFrame(w.id, rect) { continue }
            // Typically a window that can't be moved/resized at all (fixed-size dialogs,
            // unresponsive apps). Float it so it stops holding a slot it never fills.
            print("[arrange] Failed to reposition '\(w.title)' (class='\(w.className)'); floating it instead.")
            w.isFloating = true
            anyFailed = true
        }
        if anyFailed && retry { arrangeMonitor(index, retry: false) }
    }

    // MARK: - Internals

    private func tryAdd(_ id: WindowID, arrange shouldArrange: Bool) {
        guard find(id) == nil, let snapshot = backend.describe(id) else { return }

        if !snapshot.isManageable {
            recoverIfParked(id, snapshot)
            return
        }

        let names = snapshot.processNameAliases
        if WindowBlacklist.isBlacklisted(blacklist, processNames: names, className: snapshot.className, title: snapshot.title) {
            print("[blacklist] Skipped '\(snapshot.title)' (process='\(names.first ?? "")', class='\(snapshot.className)')")
            recoverIfParked(id, snapshot)
            return
        }

        let rule = WindowTagRules.resolve(tagRules, processNames: names, className: snapshot.className, title: snapshot.title)
        let monitorIndex = rule?.monitorIndex.map { LayoutMath.clamp($0, 0, monitors.count - 1) } ?? resolveMonitorIndex(snapshot.frame)
        let monitor = monitors[monitorIndex]

        let w = ManagedWindow(id: id, pid: snapshot.pid)
        w.title = snapshot.title
        w.className = snapshot.className
        w.processNames = names
        w.monitorIndex = monitorIndex
        w.tagIndex = rule?.tagIndex ?? monitor.activeTagIndex
        w.isMinimized = snapshot.isMinimized
        w.isHiddenByApp = snapshot.isAppHidden
        print("[manage] '\(w.title)' (process='\(names.first ?? "")', class='\(w.className)')")

        if newIsMaster {
            windows.insert(w, at: 0)
        } else {
            let master = windows.firstIndex { $0.monitorIndex == w.monitorIndex && $0.tagIndex == w.tagIndex && !$0.isFloating }
            windows.insert(w, at: master.map { $0 + 1 } ?? 0)
        }

        if let rule, !isVisibleOn(w, monitor, monitorIndex) {
            if rule.follow && shouldArrange {
                selectMonitor(monitorIndex)
                activateTag(rule.tagIndex)
                return
            }
            hideForTag(w)
        }

        if shouldArrange {
            arrange()
            if isVisibleOn(w, monitor, monitorIndex) { focus(w) }
        }
    }

    /// A window left parked by a previous Mtile that died without cleaning up (SIGKILL, power
    /// loss) and that this run won't manage: bring it back onto its monitor rather than leaving
    /// it stranded. Managed ones need nothing -- arrange() moves them back anyway.
    private func recoverIfParked(_ id: WindowID, _ snapshot: WindowSnapshot) {
        let f = snapshot.frame
        for m in monitors where m.displayID != nil {
            let mf = m.frame
            let atBottom = f.y >= mf.y + mf.height - 2 && f.y <= mf.y + mf.height
            let atRight = f.x >= mf.x + mf.width - 2 && f.x <= mf.x + mf.width
            let atLeft = f.x + f.width <= mf.x + 2 && f.x + f.width >= mf.x
            if atBottom && (atRight || atLeft) {
                print("[recover] '\(snapshot.title)' was left off-screen by a previous run; moving it back.")
                backend.setFrame(id, centered(f, in: m.workArea))
                return
            }
        }
    }

    private func resolveMonitorIndex(_ frame: LayoutRect) -> Int {
        let cx = frame.x + frame.width / 2
        let cy = frame.y + frame.height / 2
        let index = monitors.firstIndex { m in
            m.displayID != nil && cx >= m.frame.x && cx < m.frame.x + m.frame.width && cy >= m.frame.y && cy < m.frame.y + m.frame.height
        }
        return index ?? currentMonitorIndex
    }

    private func hideForTag(_ w: ManagedWindow) {
        guard !w.isParked else { return }
        let frame = backend.frame(w.id) ?? LayoutRect(x: 0, y: 0, width: 400, height: 300)
        w.parkedFrom = frame
        backend.setFrame(w.id, parkRect(for: frame, on: monitors[w.monitorIndex]))
    }

    private func showManagedWindow(_ w: ManagedWindow) {
        guard let frame = w.parkedFrom else { return }
        w.parkedFrom = nil
        backend.setFrame(w.id, frame) // tiled windows get re-laid-out by the next arrange anyway
    }

    /// AeroSpace's trick: hang the window off whichever bottom corner of its monitor doesn't
    /// border another monitor, leaving a 1-point sliver on screen (macOS insists on that).
    func parkRect(for frame: LayoutRect, on monitor: Monitor) -> LayoutRect {
        let mf = monitor.frame
        let bottom = mf.y + mf.height - 1
        let rightX = mf.x + mf.width - 1
        let leftX = mf.x - frame.width + 1
        let rightIsFree = !monitors.contains { $0 !== monitor && $0.displayID != nil && $0.frame.x == mf.x + mf.width }
        return LayoutRect(x: rightIsFree ? rightX : leftX, y: bottom, width: frame.width, height: frame.height)
    }

    private func centered(_ frame: LayoutRect, in area: LayoutRect) -> LayoutRect {
        let width = min(frame.width, area.width)
        let height = min(frame.height, area.height)
        return LayoutRect(x: area.x + (area.width - width) / 2, y: area.y + (area.height - height) / 2, width: width, height: height)
    }

    private func resyncVisibility() {
        for (index, monitor) in monitors.enumerated() {
            for w in windows where w.monitorIndex == index {
                if isVisibleOn(w, monitor, index) { showManagedWindow(w) } else { hideForTag(w) }
            }
        }
    }

    private func focus(_ w: ManagedWindow) {
        focusedID = w.id
        focusedTitle = w.title
        backend.focus(w.id)
    }

    /// dwm's focus(NULL): picks the tag's last-focused window, else top of stack, else nothing.
    private func focusSomethingOnCurrentMonitor() {
        let visible = visibleWindowsOnCurrentMonitor()
        let remembered = visible.first { $0.id == currentTag.lastFocused }
        if let target = remembered ?? visible.first {
            focus(target)
        } else {
            focusedID = nil
            focusedTitle = ""
            backend.focusNothing()
        }
        notifyChanged()
    }

    /// True if this window is supposed to be visible on this monitor: on its active tag, pinned,
    /// or every tag is while viewing all tags. Same rule as Wtile's IsVisibleOn.
    func isVisibleOn(_ w: ManagedWindow, _ monitor: Monitor, _ monitorIndex: Int) -> Bool {
        w.monitorIndex == monitorIndex && (monitor.isViewingAllTags || w.tagIndex == monitor.activeTagIndex || w.isPinned)
    }

    private func tiledWindowsOn(_ monitor: Monitor, _ index: Int) -> [ManagedWindow] {
        windows.filter { isVisibleOn($0, monitor, index) && !$0.isMinimized && !$0.isFloating && !$0.isHiddenByApp }
    }

    private func visibleWindowsOnCurrentMonitor() -> [ManagedWindow] {
        windows.filter { isVisibleOn($0, currentMonitor, currentMonitorIndex) && !$0.isMinimized && !$0.isHiddenByApp }
    }

    private func swapInStack(_ a: ManagedWindow, _ b: ManagedWindow) {
        guard let i = windows.firstIndex(where: { $0 === a }), let j = windows.firstIndex(where: { $0 === b }) else { return }
        windows.swapAt(i, j)
    }

    @discardableResult
    private func remove(_ id: WindowID) -> Bool {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return false }
        windows.remove(at: index)
        for monitor in monitors {
            for tag in monitor.tags where tag.lastFocused == id { tag.lastFocused = nil }
        }
        return true
    }

    private func find(_ id: WindowID?) -> ManagedWindow? {
        guard let id else { return nil }
        return windows.first { $0.id == id }
    }

    private func wrap(_ value: Int, _ count: Int) -> Int { ((value % count) + count) % count }

    private func notifyChanged() {
        for handler in onChange { handler() }
    }
}
