/// Per-tag layout state: each tag remembers its own layout selection and params (nmaster/mfact/
/// gap), matching dwm/bug.n -- adjusting mfact on tag 3 doesn't affect tag 1.
public final class Tag {
    public var layoutName: String
    public var layoutParams: [String: Double]

    /// Last known non-zero gap, restored by toggle-gap.
    public var rememberedGap: Double?

    /// dwm's per-tag "sel": the window last focused while this tag was active on its monitor.
    public var lastFocused: WindowID?

    public init(layoutName: String, layoutParams: [String: Double]) {
        self.layoutName = layoutName
        self.layoutParams = layoutParams
        if let g = layoutParams["gap"], g > 0 { rememberedGap = g }
    }
}
