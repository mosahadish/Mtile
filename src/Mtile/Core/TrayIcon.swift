#if os(macOS)
import AppKit

/// Menu-bar status item -- the macOS counterpart of Wtile's notification-area icon, with the same
/// three entries, each dispatching an existing command.
public final class TrayIcon: NSObject {
    private let commands: CommandRegistry
    private let item: NSStatusItem

    public init(commands: CommandRegistry) {
        self.commands = commands
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.title = "Mtile"
        item.button?.toolTip = "Mtile — tiling for macOS, inspired by Wtile"

        let menu = NSMenu()
        menu.addItem(makeItem("Open config", #selector(openConfig)))
        menu.addItem(makeItem("Reload config", #selector(reload)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Mtile", #selector(quit)))
        item.menu = menu
    }

    public func remove() { NSStatusBar.system.removeStatusItem(item) }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc private func openConfig() { commands.tryExecute("open-config", []) }
    @objc private func reload() { commands.tryExecute("reload", []) }
    @objc private func quit() { commands.tryExecute("quit", []) }
}
#endif
