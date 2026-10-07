import WebUICore

// ============================================================================
// MARK: - Tag emission (feature G4 — the framework's own markup, centralized)
// ============================================================================
//
// the ONE tag/attribute emission helper for the design system's own markup
// (lane R, MACRO_DX feature G4): the five renderers in this module used to
// hand-wire attribute strings (`"<div class=\"...\""`, `" id=\"...\""` …);
// they now name tag, classes and attributes and this file owns the quoting,
// the escaping and the framing. the classes stay — the win is *scattering*,
// never a shrink (decision d-t).
//
// byte-identity with the hand-written spellings is by construction:
//
// - an attribute renders as ` name="value"` (leading space), so
//   concatenation is exact and attribute order is preserved as written;
// - `flag` renders a boolean attribute (` disabled`, ` checked`, …);
// - `escAttr` escapes its value, `attr` emits it verbatim — the caller
//   makes the same escaping decision the old string made (a value that was
//   already html-escaped, or a numeric interpolation, goes through `attr`;
//   user data goes through `escAttr`);
// - `classes` joins class segments with a single space, inserting one only
//   when the incoming segment does not already lead with a space — which
//   reproduces every hand-written spelling, whose modifiers either carry
//   their own leading space (`Size.sm = " slider--sm"`) or were joined by a
//   literal space in the template (`"banner \(variant.rawValue)"`). empty
//   segments drop, so conditional modifiers vanish without double spaces.
//   where the old template left a trailing space on an empty segment, the
//   call site spells that segment `" "` explicitly rather than letting the
//   helper normalise it away (the gantt bar state is the one such wart,
//   pinned by the base-captured fixtures).
// - `begin`/`end`/`element`/`void`/`selfClose` are the only place `<tag`,
//   `>`, `</tag>` and `/>` are assembled in these files.

/// tag and attribute assembly for the design system's own markup. all
/// members are `package` — a framework-internal emission helper, not
/// consumer API (the 2.0 flip governs when this opens).
package enum Tag {

    /// ` name` — a boolean attribute (`disabled`, `checked`, `selected`, …).
    package static func flag(_ name: String) -> String {
        " \(name)"
    }

    /// ` name="value"` — the value is emitted verbatim. use for values that
    /// were already escaped at the call site (`htmlEscape`d bases like the
    /// pagination ids), for numeric interpolations (`min="\(min)"`), and for
    /// literal attribute values (`type="search"`).
    package static func attr(_ name: String, _ value: String) -> String {
        " \(name)=\"\(value)\""
    }

    /// ` name="value"` — the value is html-escaped before emission. use for
    /// caller-supplied strings (`aria-label`, `href`, `placeholder`, …).
    package static func escAttr(_ name: String, _ value: String) -> String {
        " \(name)=\"\(htmlEscape(value))\""
    }

    /// the space-joined class list as one `class` attribute (empty when
    /// every segment is empty). segments keep their exact bytes; the smart
    /// single-space join reproduces the old spellings whether a modifier
    /// carries its own leading space or not (see the file comment).
    package static func classes(_ segments: [String]) -> String {
        var joined = ""
        for segment in segments {
            guard !segment.isEmpty else { continue }
            if joined.isEmpty {
                joined = segment
            } else if segment.hasPrefix(" ") {
                joined += segment
            } else {
                joined += " " + segment
            }
        }
        return joined.isEmpty ? "" : " class=\"\(joined)\""
    }

    /// `<tag>` or `<tag attrs…>` — each attribute piece carries its own
    /// leading space; empty pieces are dropped, so a conditional attribute
    /// spells `condition ? Tag.attr(…) : ""` at the call site.
    package static func begin(_ tag: String, _ attrs: String...) -> String {
        var out = "<" + tag
        for a in attrs where !a.isEmpty { out += a }
        return out + ">"
    }

    /// `</tag>`
    package static func end(_ tag: String) -> String {
        "</" + tag + ">"
    }

    /// `<tag attrs>content</tag>` — the whole element in one call.
    package static func element(_ tag: String, _ attrs: [String] = [], _ content: String = "") -> String {
        var out = "<" + tag
        for a in attrs where !a.isEmpty { out += a }
        return out + ">" + content + "</" + tag + ">"
    }

    /// `<tag attrs>` for a void element (`input`, `img`, `br` — no closing
    /// tag in html).
    package static func void(_ tag: String, _ attrs: String...) -> String {
        var out = "<" + tag
        for a in attrs where !a.isEmpty { out += a }
        return out + ">"
    }

    /// `<tag attrs/>` — the self-closing spelling the svg children use
    /// (`circle`, `path`, `polyline` in this module).
    package static func selfClose(_ tag: String, _ attrs: String...) -> String {
        var out = "<" + tag
        for a in attrs where !a.isEmpty { out += a }
        return out + "/>"
    }
}
