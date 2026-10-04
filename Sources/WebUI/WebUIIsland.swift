import WebUICore

// MARK: - WebUIIsland — the region view primitive (CONTINUUM_DX DX-4a / W1-D)

/// The island region view: emits the region element the engine mounts —
/// byte-identical to the hand-written `Raw(…)` markup it replaces
/// (`Sources/WebUISmokeTest/main.swift:421–422`).
///
/// ### the pinned serialization contract (red-team, plan §2.4)
///
/// - **fixed attribute order**: `id` → `data-webui-island` → `data-webui-args`;
/// - **single-quoted args**: `data-webui-args='{…}'` — the JSON's structural
///   double quotes pass through raw; the browser decodes the attribute and the
///   engine's `JSON.parse` reads the exact payload;
/// - **a declaration-ordered args type**: `WebUIIslandArgs` below — never
///   `[String: Any]`/`JSONSerialization`, whose per-process key order cannot
///   match a pinned capture (and whose `Double` bridge would emit `4.0`, not
///   the capture's `4`).
///
/// `name` is the island's capability — the engine's mount key
/// (`data-webui-island`); `id` is the region element id — the engine's
/// window/event routing anchor. the W0 capture pins both independently: the
/// `validate` region derives (`name "validate"` → `id "island-validate"`),
/// while `never-built`'s region id is the shorter hand-chosen `island-never` —
/// so the designated init takes `id` explicitly, and the convenience init
/// derives `"island-" + name` for the common case (the appendix-A template's
/// `WebUIIsland("feed")` spelling).
public struct WebUIIsland: View {
	/// the island's capability name — the engine's mount key
	/// (`data-webui-island`).
	public let name: String
	/// the region element id — the engine's routing anchor and the byte
	/// identity of the captured `id` attribute.
	public let id: String
	/// the declaration-ordered args payload (`data-webui-args`, single-quoted).
	public let args: WebUIIslandArgs

	/// Designated: everything explicit.
	public init(id: String, name: String, args: WebUIIslandArgs = .empty) {
		self.id = id
		self.name = name
		self.args = args
	}

	/// Convenience: the region id derives from the name as `"island-" + name`
	/// — the smoke capture's common form (`validate` → `island-validate`), and
	/// the plan's `WebUIIsland("feed", args: …)` spelling.
	public init(_ name: String, args: WebUIIslandArgs = .empty) {
		self.init(id: "island-" + name, name: name, args: args)
	}

	public func render() -> String {
		"<div id=\"\(htmlEscape(id))\""
			+ " data-webui-island=\"\(htmlEscape(name))\""
			+ " data-webui-args='\(WebUIIslandArgs.attributeSafe(from: args.json))'></div>"
	}

	public func render(into buffer: inout HTMLBuffer) {
		buffer.append(render())
	}
}

// MARK: - the declaration-ordered args type (the byte-identity carrier)

/// A JSON *value* for `WebUIIslandArgs`. `string`/`int`/`bool`/`null` are the
/// leaves; `array`/`object` recurse (`indirect` — they wrap `Self`/`Pair`).
/// `int` renders as `4`, never `4.0`: a JSON `Int` is unambiguous, and the
/// capture pins the integer form.
public indirect enum WebUIIslandArgsValue: Sendable, Equatable {
	case string(String)
	case int(Int)
	case bool(Bool)
	case null
	case array([WebUIIslandArgsValue])
	case object([WebUIIslandArgs.Pair])
}

/// The declaration-ordered argument payload for an island region — the ONLY
/// faithful model of the capture's wired args (`{"value":"a","rules":[…]}`,
/// key order value, `rules`; inner objects `rule`, `arg`; int `4`).
///
/// `[String: Any]` is unusable here: `Dictionary` iteration order is
/// per-process random (the two most common causes of key-order churn), and
/// `JSONSerialization` would bridge a small `Int` to `Double` and emit `4.0`.
/// Serialization is hand-rolled over the ordered `pairs`, so two declarations
/// with the same entries in different orders genuinely differ — which is the
/// point: the bytes of the page are authored, not sorted.
public struct WebUIIslandArgs: Sendable, Equatable {
	/// one ordered key → value pair. the convenience overloads let a literal
	/// read naturally: `.init("value", "a")`, `.init("arg", 4)`,
	/// `.init("rules", [.object([…])])`.
	public struct Pair: Sendable, Equatable {
		public let key: String
		public let value: WebUIIslandArgsValue

		public init(_ key: String, _ value: WebUIIslandArgsValue) {
			self.key = key
			self.value = value
		}

		public init(_ key: String, _ value: String) { self.init(key, .string(value)) }
		public init(_ key: String, _ value: Int) { self.init(key, .int(value)) }
		public init(_ key: String, _ value: Bool) { self.init(key, .bool(value)) }
		public init(_ key: String, _ value: [WebUIIslandArgsValue]) { self.init(key, .array(value)) }
		public init(_ key: String, _ object: [Pair]) { self.init(key, .object(object)) }
	}

	/// the ordered entries, in declaration order.
	public let pairs: [Pair]

	public init(_ pairs: [Pair]) {
		self.pairs = pairs
	}

	/// the empty object — `{}` (an `@HotView` region with no args).
	public static let empty = WebUIIslandArgs([])

	/// The serialized JSON payload, declaration order preserved.
	public var json: String {
		Self.renderObject(pairs)
	}

	// MARK: serialization

	private static func renderObject(_ pairs: [Pair]) -> String {
		guard !pairs.isEmpty else { return "{}" }
		var out = "{"
		for (index, pair) in pairs.enumerated() {
			if index > 0 { out += "," }
			out += renderString(pair.key) + ":" + renderValue(pair.value)
		}
		out += "}"
		return out
	}

	private static func renderArray(_ values: [WebUIIslandArgsValue]) -> String {
		var out = "["
		for (index, value) in values.enumerated() {
			if index > 0 { out += "," }
			out += renderValue(value)
		}
		out += "]"
		return out
	}

	private static func renderValue(_ value: WebUIIslandArgsValue) -> String {
		switch value {
		case .string(let string): return renderString(string)
		case .int(let int): return String(int)
		case .bool(let bool): return bool ? "true" : "false"
		case .null: return "null"
		case .array(let values): return renderArray(values)
		case .object(let pairs): return renderObject(pairs)
		}
	}

	/// A JSON string literal: `"` and `\` escaped, control scalars as `\u00XX`.
	private static func renderString(_ string: String) -> String {
		var out = "\""
		for scalar in string.unicodeScalars {
			switch scalar.value {
			case 0x22: out += "\\\""
			case 0x5C: out += "\\\\"
			case 0x08: out += "\\b"
			case 0x09: out += "\\t"
			case 0x0A: out += "\\n"
			case 0x0C: out += "\\f"
			case 0x0D: out += "\\r"
			case 0x00...0x1F:
				// \u00XX, lowercase hex — no Foundation needed.
				let digits = Array("0123456789abcdef")
				let value = Int(scalar.value)
				out += "\\u00\(digits[(value >> 4) & 0xF])\(digits[value & 0xF])"
			default:
				out.unicodeScalars.append(scalar)
			}
		}
		out += "\""
		return out
	}

	/// Escape a serialized JSON payload for embedding in a SINGLE-quoted HTML
	/// attribute (`data-webui-args='…'`): `&` → `&amp;` first, then `'` →
	/// `&#39;`. the browser decodes the entities when it reads the attribute,
	/// so the engine's `JSON.parse` sees the original payload unchanged. both
	/// escapes are identity on every captured page (none contain `&`/`'`), so
	/// the byte-diff against the W0 smoke markup is unaffected.
	static func attributeSafe(from json: String) -> String {
		var out = ""
		for scalar in json.unicodeScalars {
			switch scalar.value {
			case 0x26: out += "&amp;"
			case 0x27: out += "&#39;"
			default: out.unicodeScalars.append(scalar)
			}
		}
		return out
	}
}
