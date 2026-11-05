/// Maps config-referenced layout names (e.g. "master-stack") to implementations,
/// case-insensitively like Wtile's LayoutRegistry.
public final class LayoutRegistry {
    private var layouts: [String: Layout] = [:]

    public init() {}

    public func register(_ layout: Layout) {
        layouts[layout.name.lowercased()] = layout
    }

    public func get(_ name: String) -> Layout? {
        layouts[name.lowercased()]
    }

    public var names: [String] { layouts.values.map(\.name).sorted() }

    /// Registers the built-in layout set.
    public static func createDefault() -> LayoutRegistry {
        let registry = LayoutRegistry()
        registry.register(MasterStackLayout())
        registry.register(MasterStackLayout(masterOnRight: true))
        registry.register(MonocleLayout())
        registry.register(CenteredMasterLayout())
        registry.register(VerticalStackLayout())
        registry.register(DeckLayout())
        registry.register(DwindleLayout())
        return registry
    }
}
