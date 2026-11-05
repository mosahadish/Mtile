#if os(macOS)
import AppKit

/// dmenu-style app launcher: a single-line popup spanning the current monitor's width, flush
/// against whichever edge the bar reserves (below a top bar, above a bottom bar). Port of
/// Wtile's LauncherWindow. Unlike the bar, this panel needs real keyboard focus, so showing it
/// activates Mtile and hiding it hands focus back to the app that was frontmost before. Text
/// input is hand-rolled (keyDown) rather than an NSTextField, matching Wtile's WM_CHAR handling.
public final class LauncherWindow: NSObject, NSWindowDelegate {
    private let manager: WindowManager
    private let theme: BarTheme
    private let panel: LauncherPanel
    private let view: LauncherView
    private var height = 24

    private var allEntries: [LauncherEntry] = []
    fileprivate private(set) var filtered: [LauncherEntry] = []
    fileprivate private(set) var query = ""
    fileprivate private(set) var selectedIndex = 0
    public private(set) var isVisible = false
    private var previousApp: NSRunningApplication?

    public init(manager: WindowManager, config: BarConfig) {
        self.manager = manager
        theme = BarTheme(config.colors)
        panel = LauncherPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = false
        panel.isOpaque = true
        panel.hidesOnDeactivate = false
        view = LauncherView(frame: .zero)
        panel.contentView = view
        super.init()
        view.owner = self
        view.theme = theme
        panel.delegate = self
        applyConfig(config)
    }

    /// Applies a reloaded bar config in place -- same font/color/height source the bar uses, so
    /// the launcher stays visually consistent with it.
    public func applyConfig(_ config: BarConfig) {
        theme.apply(config.colors)
        height = config.height
        view.font = NSFont(name: config.fontFamily, size: CGFloat(config.fontSize))
            ?? NSFont.systemFont(ofSize: CGFloat(config.fontSize))
        view.needsDisplay = true
    }

    /// `elevated` exists for config compatibility with Wtile's Win+Shift+Escape. macOS has no
    /// per-launch elevation, so it behaves exactly like the plain toggle -- the same thing Wtile
    /// does when it isn't itself running as administrator.
    public func toggle(elevated: Bool = false) {
        if isVisible { hide() } else { show() }
    }

    private func show() {
        guard manager.monitors.indices.contains(manager.currentMonitorIndex), let primary = NSScreen.screens.first else { return }
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front

        allEntries = AppCatalog.build()
        query = ""
        refilter()

        let monitor = manager.monitors[manager.currentMonitorIndex]
        let work = monitor.workArea
        let y = monitor.reservedBottomInset > 0 && monitor.reservedTopInset == 0
            ? work.y + work.height - monitor.reservedBottomInset - height
            : work.y + monitor.reservedTopInset
        let rect = LayoutRect(x: work.x, y: y, width: work.width, height: height)
        panel.setFrame(WindowInspector.toAppKit(rect, primaryHeight: primary.frame.height), display: false)

        isVisible = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        view.needsDisplay = true
    }

    /// `restoreFocus` is false when the panel lost focus because the user clicked elsewhere --
    /// that click already picked where focus should go.
    private func hide(restoreFocus: Bool = true) {
        guard isVisible else { return }
        isVisible = false
        panel.orderOut(nil)
        if restoreFocus { previousApp?.activate() }
        previousApp = nil
    }

    public func windowDidResignKey(_ notification: Notification) {
        hide(restoreFocus: false)
    }

    private func refilter() {
        filtered = AppCatalog.filter(allEntries, query: query)
        selectedIndex = 0
    }

    private func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        selectedIndex = ((selectedIndex + delta) % filtered.count + filtered.count) % filtered.count
        view.needsDisplay = true
    }

    private func launchSelected() {
        guard filtered.indices.contains(selectedIndex) else { return }
        launch(filtered[selectedIndex])
    }

    fileprivate func launch(_ entry: LauncherEntry) {
        ProcessLauncher.launch(entry.launchTarget, context: "launcher")
        hide()
    }

    fileprivate func handleKey(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case 0x33: // Delete (backspace)
            if !query.isEmpty {
                query.removeLast()
                refilter()
                view.needsDisplay = true
            }
        case 0x35: // Escape
            hide()
        case 0x24, 0x4C: // Return, keypad Enter
            launchSelected()
        case 0x30: // Tab
            moveSelection(event.modifierFlags.contains(.shift) ? -1 : 1)
        case 0x7C: // Right arrow
            moveSelection(1)
        case 0x7B: // Left arrow
            moveSelection(-1)
        default:
            guard event.modifierFlags.intersection([.command, .control]).isEmpty, let chars = event.characters else { return }
            // Same filter as Wtile's OnChar (no control characters), plus AppKit's private-use
            // range for function/arrow keys.
            let typed = String(String.UnicodeScalarView(chars.unicodeScalars.filter {
                $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value)
            }))
            guard !typed.isEmpty else { return }
            query += typed
            refilter()
            view.needsDisplay = true
        }
    }
}

/// Borderless panels refuse key status by default; the launcher needs it for typing.
private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Flipped so drawing matches Wtile's top-left origin.
private final class LauncherView: NSView {
    weak var owner: LauncherWindow?
    var theme: BarTheme?
    var font = NSFont.systemFont(ofSize: 12)
    private var hits: [(entry: LauncherEntry, minX: CGFloat, maxX: CGFloat)] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) { owner?.handleKey(event) }

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        if let hit = hits.first(where: { x >= $0.minX && x < $0.maxX }) { owner?.launch(hit.entry) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let owner, let theme else { return }
        let padding: CGFloat = 8
        hits = []

        color(theme.background).setFill()
        bounds.fill()

        var x = padding
        x += drawText(owner.query, at: x, color: theme.foreground)

        // A static caret bar right after the typed text -- no blink timer, like Wtile.
        let caretHeight = lineHeight
        color(theme.foreground).setFill()
        NSRect(x: x, y: (bounds.height - caretHeight) / 2, width: 2, height: caretHeight).fill()
        x += 4 + padding

        for (i, entry) in owner.filtered.enumerated() {
            guard x < bounds.width - padding else { break }
            let textWidth = measure(entry.displayName)
            let slotWidth = textWidth + padding
            let selected = i == owner.selectedIndex
            if selected {
                color(theme.activeTag).setFill()
                NSRect(x: x, y: 0, width: slotWidth, height: bounds.height).fill()
            }
            _ = drawText(entry.displayName, at: x + padding / 2, color: selected ? theme.background : theme.foreground)
            hits.append((entry, x, x + slotWidth))
            x += slotWidth + padding
        }
    }

    private var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }

    private func measure(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Draws `text` vertically centred at `x`; returns its width.
    private func drawText(_ text: String, at x: CGFloat, color rgb: RGBColor) -> CGFloat {
        let width = measure(text)
        let rect = NSRect(x: x, y: (bounds.height - lineHeight) / 2, width: width + 1, height: lineHeight)
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin],
                                attributes: [.font: font, .foregroundColor: color(rgb)])
        return width
    }

    private func color(_ c: RGBColor) -> NSColor {
        NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }
}
#endif
