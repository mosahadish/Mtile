/// A named, invocable action (e.g. `focus-next`, `view-tag`, `spawn`). Hotkeys and bar clicks both
/// resolve to `(commandName, args)` and dispatch through the same `CommandRegistry`, so there is
/// exactly one execution surface for both trigger kinds. Mirrors Wtile's ICommand.
public protocol Command {
    /// Registry key, referenced by name from YAML hotkey bindings and bar click handlers.
    var name: String { get }
    func execute(_ args: [String])
}

/// A command backed by a closure -- every builtin is one of these (see BuiltinCommands).
public struct ClosureCommand: Command {
    public let name: String
    private let action: ([String]) -> Void

    public init(_ name: String, _ action: @escaping ([String]) -> Void) {
        self.name = name
        self.action = action
    }

    public func execute(_ args: [String]) { action(args) }
}
