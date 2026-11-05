/// Maps config-referenced command names to their `Command` implementation (case-insensitive,
/// like Wtile's OrdinalIgnoreCase dictionary).
public final class CommandRegistry {
    private var commands: [String: Command] = [:]

    /// Commands that exist in Wtile but have no macOS equivalent (yet). A shared config may bind
    /// them; Mtile leaves those keys unbound instead of warning or swallowing the keystroke.
    public static let windowsOnlyCommands: Set<String> = []

    public init() {}

    public func register(_ command: Command) {
        commands[command.name.lowercased()] = command
    }

    public func get(_ name: String) -> Command? {
        commands[name.lowercased()]
    }

    public var names: [String] { Array(commands.keys) }

    /// Looks up and executes `name`; returns false if no such command is registered.
    @discardableResult
    public func tryExecute(_ name: String, _ args: [String]) -> Bool {
        guard let command = get(name) else { return false }
        command.execute(args)
        return true
    }
}
