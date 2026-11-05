/// Applies a user-configurable .NET-style positional format string ("{0}", "{1}", "{{" / "}}"
/// escapes) to segment values, so `bar.modules[].format` strings from the shared config read the
/// same as in Wtile. A malformed format (bad placeholder, index out of range, stray brace) must
/// not break bar painting -- it falls back to the built-in default, like Wtile's SegmentFormat.
public enum SegmentFormat {
    public static func apply(_ format: String, fallback: String, _ args: [String]) -> String {
        tryFormat(format, args) ?? tryFormat(fallback, args) ?? fallback
    }

    /// Supports `{N}` and `{N:spec}` (the spec is ignored -- callers pass preformatted strings).
    static func tryFormat(_ format: String, _ args: [String]) -> String? {
        var out = ""
        var chars = Array(format)[...]
        while let c = chars.popFirst() {
            switch c {
            case "{":
                if chars.first == "{" {
                    chars.removeFirst()
                    out.append("{")
                    continue
                }
                guard let close = chars.firstIndex(of: "}") else { return nil }
                let inside = String(chars[chars.startIndex..<close])
                chars = chars[(close + 1)...]
                let indexText = inside.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                guard !indexText.isEmpty, indexText.allSatisfy(\.isASCII), let index = Int(indexText), index >= 0, index < args.count
                else { return nil }
                out += args[index]
            case "}":
                guard chars.first == "}" else { return nil }
                chars.removeFirst()
                out.append("}")
            default:
                out.append(c)
            }
        }
        return out
    }
}
