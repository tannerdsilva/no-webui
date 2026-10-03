// MARK: - HTML Escaping
//
// the leaf escaping primitive every layer reuses — foundation-free by
// construction, so the wasm island core can link it without any logging,
// icu, or platform surface.

/// escapes `&`, `<`, `>`, `"`, and `'` to their named/numeric entities;
/// returns the input unchanged when nothing needs escaping.
public func htmlEscape(_ string: String) -> String {
    // scanned as scalars, not utf-8 bytes: the byte form was tried and measured
    // *slower* (its closure cost 4.15% of a page render against 2.05% here,
    // per `perf`), because `String.UTF8View.contains` does not specialise the
    // way `UnicodeScalarView.contains` does.
    guard string.unicodeScalars.contains(where: { c in
        c == "&" || c == "<" || c == ">" || c == "\"" || c == "'"
    }) else { return string }

    var result = ""
    result.reserveCapacity(string.utf8.count + 8)
    for c in string.unicodeScalars {
        switch c {
        case "&":  result += "&amp;"
        case "<":  result += "&lt;"
        case ">":  result += "&gt;"
        case "\"": result += "&quot;"
        case "'":  result += "&#39;"
        default:   result.unicodeScalars.append(c)
        }
    }
    return result
}
