/// Turns config bindings into the lookup table the event tap consults. Pure, so the "which keys
/// does Mtile grab" rules are testable off-Mac:
/// - Windows-only commands (CommandRegistry.windowsOnlyCommands) are skipped with one note each,
///   so their keys keep working normally in other apps.
/// - Unknown commands are skipped with a warning, so a typo never swallows a keystroke.
/// - The first binding for a combo wins, like Wtile where RegisterHotKey fails for the second.
public enum HotkeyTable {
    public static func build(_ bindings: [HotkeyBinding], isRegistered: (String) -> Bool) -> (table: [KeyCombo: HotkeyBinding], notes: [String]) {
        var table: [KeyCombo: HotkeyBinding] = [:]
        var notes: [String] = []
        var noted = Set<String>()
        for binding in bindings {
            let command = binding.command.lowercased()
            if CommandRegistry.windowsOnlyCommands.contains(command) {
                if noted.insert(command).inserted {
                    notes.append("'\(binding.command)' is Windows-only; its hotkeys are left unbound on macOS.")
                }
                continue
            }
            guard isRegistered(command) else {
                notes.append("hotkey '\(binding.keys)' references unknown command '\(binding.command)'; ignored.")
                continue
            }
            guard let combo = KeyComboParser.tryParse(binding.keys) else {
                notes.append("hotkey '\(binding.keys)' can't be parsed; ignored.")
                continue
            }
            if table[combo] != nil {
                notes.append("hotkey '\(binding.keys)' is bound more than once; keeping the first binding.")
                continue
            }
            table[combo] = binding
        }
        return (table, notes)
    }
}

#if os(macOS)
import AppKit
import CoreGraphics

/// Global hotkeys via a CGEventTap -- the macOS counterpart of Wtile's RegisterHotKey-based
/// HotkeyManager. Matching key-downs are swallowed and dispatched through the CommandRegistry on
/// the main queue; everything else passes through untouched. Needs the Accessibility permission
/// (already required for window management). "Win"/"Alt" map to Option/Command per MacWinKey.
public final class HotkeyManager {
    private let commands: CommandRegistry
    private var table: [KeyCombo: HotkeyBinding] = [:]
    private var winKey = MacWinKey.option
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var recreateFailed = false

    public init(commands: CommandRegistry) {
        self.commands = commands
    }

    public func applyBindings(_ bindings: [HotkeyBinding], winKey: MacWinKey) {
        let result = HotkeyTable.build(bindings) { commands.get($0) != nil }
        table = result.table
        self.winKey = winKey
        for note in result.notes { print("[hotkeys] \(note)") }
    }

    /// Returns false if the tap couldn't be created (no Accessibility permission).
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: hotkeyTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Re-enables a tap the system switched off, or rebuilds one it invalidated (both can happen
    /// across sleep/wake without the callback ever seeing a "disabled" event).
    public func ensureRunning() {
        if let tap, CFMachPortIsValid(tap) {
            if !CGEvent.tapIsEnabled(tap: tap) {
                print("[hotkeys] Keyboard tap was disabled; re-enabling it.")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        if tap != nil { print("[hotkeys] Keyboard tap was invalidated; recreating it.") }
        stop()
        let ok = start()
        if !ok && !recreateFailed { print("[hotkeys] Couldn't recreate the keyboard event tap; will keep retrying.") }
        if ok && recreateFailed { print("[hotkeys] Keyboard event tap recreated.") }
        recreateFailed = !ok
    }

    static func modifiers(_ flags: CGEventFlags, _ winKey: MacWinKey) -> HotkeyModifiers {
        winKey.modifiers(command: flags.contains(.maskCommand), option: flags.contains(.maskAlternate),
                         control: flags.contains(.maskControl), shift: flags.contains(.maskShift))
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap whose callback is too slow or on some user input; turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let combo = KeyCombo(modifiers: Self.modifiers(event.flags, winKey), keyCode: keyCode)
        guard let binding = table[combo] else { return Unmanaged.passUnretained(event) }

        // Held hotkeys auto-repeat, like RegisterHotKey without MOD_NOREPEAT in Wtile.
        DispatchQueue.main.async { [commands] in commands.tryExecute(binding.command, binding.args) }
        return nil
    }
}

private func hotkeyTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
#endif
