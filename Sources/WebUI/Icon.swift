import Foundation

// MARK: - IconSize

/// Semantic icon sizes. `.medium` maps to the base `1em` (scales with the
/// surrounding font); the others are multiples of that, so an icon always
/// sits in proportion to its text context (deference).
public enum IconSize: String, CaseIterable, Sendable {
	case small = "sm"
	case medium = "md"
	case large = "lg"
	case extraLarge = "xl"
	/// No explicit size — the icon takes the size of its container slot
	/// (the component's icon-slot CSS). Use for icons placed inside a
	/// fixed-size slot like an alert, tree, or empty state.
	case slot = "slot"

	/// The size class appended to `icon` (or just `icon` for `.slot`).
	public var suffixClass: String {
		switch self {
		case .slot: return "icon"
		default: return "icon--\(rawValue)"
		}
	}

	/// `1em` for the base size, a multiple otherwise.
	public var em: String {
		switch self {
		case .small: return "0.75em"
		case .medium, .slot: return "1em"
		case .large: return "1.25em"
		case .extraLarge: return "1.5em"
		}
	}
}

// MARK: - WebUIIcon

/// A typed icon rendered as a self-contained inline `<svg>`. The glyph is
/// stroke-based and inherits `currentColor`, so it picks up the surrounding
/// text color by default and can be recolored with `.foregroundColor(_:)`.
///
/// The geometry (path/circle/line/...) comes from the generated catalog, so a
/// single icon can be emitted inline without shipping a separate asset.
public struct WebUIIcon: View {
	public let name: IconName
	public let size: IconSize
	public let title: String?

	public init(_ name: IconName, size: IconSize = .medium, title: String? = nil) {
		self.name = name
		self.size = size
		self.title = title
	}

	public func render() -> String {
		let classes = iconClass(for: size)
		var aria: String
		if let title, !title.isEmpty {
			aria = " role=\"img\" aria-label=\"\(htmlEscape(title))\""
		} else {
			aria = " aria-hidden=\"true\""
		}
		return "<svg class=\"\(classes)\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"butt\" stroke-linejoin=\"miter\"\(aria)>\(name.body)</svg>"
	}
}

/// The root `class` attribute value for an icon of the given size.
func iconClass(for size: IconSize) -> String {
	size == .slot ? "icon" : "icon icon--\(size.rawValue)"
}

// MARK: - WebUIIconCustom

/// An icon supplied by the caller (your own path data) rather than the
/// catalog. The body is allowlist-sanitized before emission (`IconSanitizer`):
/// only geometry elements and stroke/fill presentation attributes re-emit —
/// script, event handlers, url-bearing attributes, and embedded documents are
/// dropped by construction, so free-form geometry can never become a vector.
public struct WebUIIconCustom: View {
	public let name: String
	public let body: String
	public let size: IconSize
	public let title: String?

	/// - Parameters:
	///   - name: a stable, identifier-safe key (used only for the `data-icon`
	///     attribute, never for routing).
	///   - body: the inner SVG geometry, e.g. `"<path d=\"M12 2l...\"/>"`.
	///   - size: semantic size.
	///   - title: accessible label; omit for decorative icons.
	public init(name: String, body: String, size: IconSize = .medium, title: String? = nil) {
		self.name = name
		self.body = IconSanitizer.sanitize(body)
		self.size = size
		self.title = title
	}

	public func render() -> String {
		let classes = iconClass(for: size)
		var aria: String
		if let title, !title.isEmpty {
			aria = " role=\"img\" aria-label=\"\(htmlEscape(title))\""
		} else {
			aria = " aria-hidden=\"true\""
		}
		let dataIcon = " data-icon=\"\(htmlEscape(name))\""
		return "<svg class=\"\(classes)\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"butt\" stroke-linejoin=\"miter\"\(dataIcon)\(aria)>\(body)</svg>"
	}
}

// MARK: - IconSanitizer

/// Parse-and-reemit sanitizer for caller-supplied SVG geometry. Catalog icons
/// are generated and trusted; only `WebUIIconCustom` funnels user input here.
///
/// the previous implementation was a string-regex denylist — the same class
/// the fragment sanitizer was rebuilt to eliminate (a regex pass runs before
/// the browser's tokenizer decodes entities and quoting, so whitespace- and
/// entity-obfuscated `javascript:`/`data:` schemes slip through). this pass
/// is a real by-construction allowlist:
///
/// - only geometry elements re-emit (`path`, `line`, `circle`, ...); every
///   other element — `script`, `a`, `use`, `image`, `foreignObject`, ... — is
///   dropped along with its text content;
/// - only geometry/stroke/fill presentation attributes survive, so `href`/
///   `src`/`xlink:href`/`formaction`/`style` and every `on*` handler are
///   absent from the allowlist rather than merely scrubbed;
/// - attribute values are html-escaped on emission (entities cannot smuggle
///   scheme obfuscation through), and any value containing `url(` (external
///   paint-server / filter references) is dropped;
/// - output is always well-formed self-closing tags.
public enum IconSanitizer {
	/// elements allowed through the tokenizer.
	private static let allowedElements: Set<String> = [
		"path", "line", "circle", "rect", "polyline", "polygon", "ellipse",
	]

	/// attributes allowed on allowed elements. geometry + stroke/fill
	/// presentation only — no url-bearing or handler attributes exist in the
	/// allowlist at all.
	private static let allowedAttributes: Set<String> = [
		"d", "cx", "cy", "r", "x", "y", "x1", "y1", "x2", "y2",
		"width", "height", "rx", "ry", "points",
		"stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
		"stroke-dasharray", "stroke-dashoffset", "stroke-miterlimit",
		"stroke-opacity", "fill", "fill-opacity", "fill-rule",
		"opacity", "transform", "vector-effect", "color",
	]

	public static func sanitize(_ body: String) -> String {
		var out = ""
		var pos = body.startIndex

		func atEnd() -> Bool { pos >= body.endIndex }
		func peek() -> Character? { pos < body.endIndex ? body[pos] : nil }
		func consume() { if pos < body.endIndex { pos = body.index(after: pos) } }
		func starts(with prefix: String) -> Bool { body[pos...].hasPrefix(prefix) }

		while !atEnd() {
			guard peek() == "<" else {
				// text between tags — icons carry no text; dropping it also
				// buries any script body whose start tag was stripped.
				consume()
				continue
			}

			// comments, CDATA, processing instructions, doctype: drop.
			if starts(with: "<!--") {
				while !atEnd(), !starts(with: "-->") { consume() }
				for _ in 0..<3 where !atEnd() { consume() }
				continue
			}
			if starts(with: "<![CDATA[") {
				while !atEnd(), !starts(with: "]]>") { consume() }
				for _ in 0..<3 where !atEnd() { consume() }
				continue
			}
			if starts(with: "<?") {
				while !atEnd(), !starts(with: "?>") { consume() }
				for _ in 0..<2 where !atEnd() { consume() }
				continue
			}
			if starts(with: "<!") {
				while !atEnd(), peek() != ">" { consume() }
				if !atEnd() { consume() }
				continue
			}

			consume() // the `<`; pos now at the tag content
			var isClosing = false
			if peek() == "/" { isClosing = true; consume() }

			// tag name
			var name = ""
			while let c = peek(), c.isLetter || c.isNumber || c == "-" || c == ":" || c == "_" || c == "." {
				name.append(c)
				consume()
			}
			let lowerName = name.lowercased()

			// attributes
			var attrs: [(name: String, value: String)] = []
			var malformed = false
			while !atEnd() {
				while let c = peek(), c == " " || c == "\t" || c == "\n" || c == "\r" { consume() }
				guard let c = peek() else { break }
				if c == ">" { consume(); break }
				if c == "/" {
					consume()
					if peek() == ">" {
						consume()
					} else {
						malformed = true
					}
					break
				}
				// attribute name
				var attrName = ""
				while let ac = peek(),
				      ac != "=" && ac != " " && ac != "\t" && ac != "\n" && ac != "\r" && ac != ">" && ac != "/" {
					attrName.append(ac)
					consume()
				}
				while let c = peek(), c == " " || c == "\t" || c == "\n" || c == "\r" { consume() }
				var value = ""
				if peek() == "=" {
					consume()
					while let c = peek(), c == " " || c == "\t" || c == "\n" || c == "\r" { consume() }
					if let quote = peek(), quote == "\"" || quote == "'" {
						consume()
						while let vc = peek(), vc != quote {
							value.append(vc)
							consume()
						}
						if peek() == quote { consume() }
					} else {
						while let vc = peek(),
						      vc != " " && vc != "\t" && vc != "\n" && vc != "\r" && vc != ">" && vc != "/" {
							value.append(vc)
							consume()
						}
					}
					attrs.append((attrName.lowercased(), value))
				}
				// a bare attribute (no `=`): dropped by continuing the loop.
			}

			guard !isClosing, !malformed, allowedElements.contains(lowerName) else {
				continue
			}
			out += "<\(lowerName)"
			for (name, value) in attrs {
				guard allowedAttributes.contains(name), !value.localizedCaseInsensitiveContains("url(") else {
					continue
				}
				out += " \(name)=\"\(htmlEscape(value))\""
			}
			out += "/>"
		}
		return out
	}
}

// MARK: - Icon convenience modifiers

/// Replaces the `icon--<suffix>` class on the root icon svg with the new size.
public struct IconSizeModifier: ViewModifier {
	public let size: IconSize
	public init(size: IconSize) {
		self.size = size
	}
	public func apply(to html: String) -> String {
		replaceIconSuffix(in: html, with: size == .slot ? "icon" : "icon--\(size.rawValue)")
	}
}

/// Replace the size class on an icon svg with the given suffix. Works whether
/// the icon already carries an `icon--<size>` (replaces it) or is the bare
/// `.slot` class `icon` (adds the size). A `slot` suffix leaves it bare.
func replaceIconSuffix(in html: String, with suffix: String) -> String {
	guard suffix != "icon" else {
		// strip any explicit size, keep just `icon`
		if let re = try? NSRegularExpression(pattern: " icon--(?:sm|md|lg|xl)") {
			return re.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
		}
		return html
	}
	if let re = try? NSRegularExpression(pattern: "icon--(?:sm|md|lg|xl)") {
		return re.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: suffix)
	}
	// bare .slot icon (class="icon"): add the size class
	return html.replacingOccurrences(of: "class=\"icon\"", with: "class=\"icon \(suffix)\"")
}

extension View where Self == WebUIIcon {
	/// Set an explicit icon size (overrides the size chosen in `init`).
	public func iconSize(_ size: IconSize) -> ModifiedView<Self, IconSizeModifier> {
		ModifiedView(content: self, modifier: IconSizeModifier(size: size))
	}
}

extension View where Self == WebUIIconCustom {
	/// Set an explicit icon size (overrides the size chosen in `init`).
	public func iconSize(_ size: IconSize) -> ModifiedView<Self, IconSizeModifier> {
		ModifiedView(content: self, modifier: IconSizeModifier(size: size))
	}
}

// MARK: - IconName lookup helpers

extension IconName {
	/// Case-insensitive lookup by raw name (for icon-name-from-data cases).
	public static func named(_ raw: String) -> IconName? {
		allCases.first { $0.rawValue == raw || $0.rawValue == raw.lowercased() }
	}
	/// True if this icon exists in the generated catalog.
	public var isKnown: Bool { WebUIIcons.meta(for: self) != nil }

	/// Map a legacy emoji glyph to its semantic icon (smooth migration path for
	/// existing call sites). Returns `nil` for unknown glyphs so a bad value is
	/// a compile-time / runtime signal rather than a silent fallback.
	public init?(emoji: String) {
		switch emoji {
		case "📭", "📪", "📥": self = .inbox
		case "📦", "🧰", "📦️": self = .package
		case "🔎", "🔍": self = .search
		case "📁", "🗂": self = .folder
		case "📄", "📃", "📑": self = .fileText
		case "📝", "✏️": self = .edit
		case "ℹ️", "i": self = .info
		case "⚠️", "❕": self = .alertTriangle
		case "❗", "❌", "✖️", "⛔": self = .xCircle
		case "✅", "✔️", "☑️": self = .checkCircle
		case "🔒", "🔐": self = .lock
		case "🔓": self = .unlock
		case "🔑": self = .key
		case "⭐", "☆": self = .star
		case "❤️", "💜": self = .heart
		case "📅", "🗓": self = .calendar
		case "🕒", "⏰": self = .clock
		case "📞", "☎️": self = .phone
		case "✉️", "📧": self = .mail
		case "💬": self = .messageCircle
		case "👤", "🙍": self = .user
		case "👥", "👪": self = .users
		case "⚙️", "🛠": self = .settings
		case "🏠", "🏡": self = .home
		case "🖥": self = .monitor
		case "📱": self = .smartphone
		default:
			// fall back to a raw-name lookup (allows "search", "check-circle", ...)
			if let m = WebUIIcons.meta(named: emoji), let name = IconName.allCases.first(where: { $0.rawValue == m.name }) {
				self = name
			} else {
				return nil
			}
		}
	}
}
