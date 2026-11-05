#if os(macOS)
import AppKit

/// One bar per monitor: a borderless, non-activating panel above normal windows on every Space,
/// painted by BarRenderer. Reserves its height from the monitor's tiling area via
/// WindowManager.setBarInsets (macOS has no AppBar API, and nothing else needs to know). Config
/// reloads are applied in place, like Wtile's BarWindow.ApplyConfig.
public final class BarWindow {
    private let manager: WindowManager
    private let commands: CommandRegistry
    private let theme: BarTheme
    private let monitorIndex: Int
    private let panel: NSPanel
    private let view: BarView
    private var height = 24
    private var isBottom = false
    private var useNotch = true
    /// Points actually reserved from the tiling area (0 when the bar lives in the notch strip,
    /// which visibleFrame already excludes).
    private var reservedHeight = 24
    public private(set) var isVisible = true

    public init(manager: WindowManager, commands: CommandRegistry, theme: BarTheme, monitorIndex: Int, config: BarConfig) {
        self.manager = manager
        self.commands = commands
        self.theme = theme
        self.monitorIndex = monitorIndex

        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.isOpaque = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        view = BarView(frame: .zero)
        panel.contentView = view

        applyConfig(config)
        panel.orderFrontRegardless()
    }

    public func applyConfig(_ config: BarConfig) {
        view.font = NSFont(name: config.fontFamily, size: CGFloat(config.fontSize))
            ?? NSFont.systemFont(ofSize: CGFloat(config.fontSize))
        view.renderer = BarRenderer(left: makeSegments(config.segments.left, config),
                                    right: makeSegments(config.segments.right, config), theme: theme)
        height = config.height
        isBottom = config.position == "bottom"
        useNotch = config.notch
        reposition()
    }

    /// Re-reads the monitor's geometry (after a display change) and moves/resizes the bar.
    public func reposition() {
        guard manager.monitors.indices.contains(monitorIndex), let primary = NSScreen.screens.first else { return }
        let monitor = manager.monitors[monitorIndex]
        let work = monitor.workArea
        if !isBottom, useNotch, let screen = screen(for: monitor), let notch = Self.notchStrip(screen) {
            // Sit in the menu-bar strip beside the notch, flush with the top of the display.
            let stripHeight = Int(notch.height.rounded())
            let barRect = LayoutRect(x: monitor.frame.x, y: monitor.frame.y, width: monitor.frame.width, height: stripHeight)
            panel.setFrame(WindowInspector.toAppKit(barRect, primaryHeight: primary.frame.height), display: true)
            view.obstruction = notch.obstruction
            reservedHeight = max(0, monitor.frame.y + stripHeight - work.y)
        } else {
            let barRect = LayoutRect(x: work.x, y: isBottom ? work.y + work.height - height : work.y, width: work.width, height: height)
            panel.setFrame(WindowInspector.toAppKit(barRect, primaryHeight: primary.frame.height), display: true)
            view.obstruction = nil
            reservedHeight = height
        }
        updateInsets()
        invalidate()
    }

    private func screen(for monitor: Monitor) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == monitor.displayID
        }
    }

    /// The notch strip's height and the notch's bar-local x range, or nil without a notch.
    private static func notchStrip(_ screen: NSScreen) -> (height: CGFloat, obstruction: ClosedRange<Double>?)? {
        guard #available(macOS 12.0, *), screen.safeAreaInsets.top > 0 else { return nil }
        var obstruction: ClosedRange<Double>?
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, right.minX > left.maxX {
            obstruction = Double(left.maxX - screen.frame.minX)...Double(right.minX - screen.frame.minX)
        }
        return (screen.safeAreaInsets.top, obstruction)
    }

    public func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        updateInsets()
    }

    public func invalidate() { view.needsDisplay = true }

    public func close() { panel.orderOut(nil) }

    private func updateInsets() {
        let reserved = isVisible ? reservedHeight : 0
        manager.setBarInsets(monitorIndex: monitorIndex, top: isBottom ? 0 : reserved, bottom: isBottom ? reserved : 0)
    }

    private func makeSegments(_ names: [String], _ config: BarConfig) -> [Segment] {
        names.compactMap { name -> Segment? in
            switch name {
            case "tags":
                return TagsSegment(manager: manager, commands: commands, theme: theme, monitorIndex: monitorIndex,
                                   useBackgroundIndicator: config.occupiedTagIndicator == "background")
            case "layout-symbol": return LayoutSymbolSegment(manager: manager, theme: theme, monitorIndex: monitorIndex)
            case "window-title": return TitleSegment(manager: manager, theme: theme)
            case "clock": return ClockSegment(theme: theme)
            case "cpu": return CpuSegment(theme: theme, format: Self.format(for: "cpu", config))
            case "memory": return MemorySegment(theme: theme, format: Self.format(for: "memory", config))
            case "battery": return BatterySegment(theme: theme, format: Self.format(for: "battery", config))
            case "network": return NetworkSegment(theme: theme, format: Self.format(for: "network", config))
            case "volume": return VolumeSegment(theme: theme, format: Self.format(for: "volume", config))
            case "gpu": return GpuSegment(theme: theme, format: Self.format(for: "gpu", config))
            default:
                print("[bar] Unknown segment '\(name)' in config, skipping.")
                return nil
            }
        }
    }

    /// The module's `format` override, or nil (built-in default) when absent or empty. Names
    /// match case-insensitively, like Wtile's FormatFor.
    static func format(for name: String, _ config: BarConfig) -> String? {
        guard let match = config.modules.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
              !match.format.isEmpty else { return nil }
        return match.format
    }
}

/// Flipped so bar coordinates match BarRenderer's top-left origin.
private final class BarView: NSView, BarCanvas {
    var renderer: BarRenderer?
    var obstruction: ClosedRange<Double>?
    var font = NSFont.systemFont(ofSize: 12)
    private var hits: [SegmentHit] = []

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let renderer else { return }
        hits = renderer.draw(self, BarRect(x: 0, y: 0, width: Double(bounds.width), height: Double(bounds.height)),
                             obstruction: obstruction)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        BarRenderer.click(hits, x: Double(point.x))
    }

    func measure(_ text: String) -> Double {
        Double((text as NSString).size(withAttributes: [.font: font]).width)
    }

    func fill(_ rect: BarRect, _ color: RGBColor) {
        nsColor(color).setFill()
        NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height).fill()
    }

    func drawText(_ text: String, in rect: BarRect, color: RGBColor, alignment: BarTextAlignment) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment == .center ? .center : .left
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: nsColor(color), .paragraphStyle: style]
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let textRect = NSRect(x: rect.x, y: rect.y + (rect.height - Double(lineHeight)) / 2, width: rect.width, height: Double(lineHeight))
        (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

    private func nsColor(_ c: RGBColor) -> NSColor {
        NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }
}
#endif
