// MARK: - FieldID
//
// one identity for a form field.
//
// a field is the same string in up to five roles: the html `id`, the form
// `name` it posts under, the component id the event deck addresses, the key a
// handler reads, and — in a styled app — the CSS selector that lays it out.
// nothing in the toolchain connects them, so a rename that misses one produces
// a control that renders and posts nothing, or a field whose value silently
// reads as "".
//
// `FieldID` is that string with a name. it is the smallest possible type — one
// stored value and two conformances — which is what lets it be adopted one call
// site at a time without a migration flag.

/// the identity of a form control: its `id`, its `name`, and the key its value
/// is stored under.
///
/// `ExpressibleByStringLiteral` is deliberate: `Input(field: "cat-name-input")`
/// reads the same as the string spelling it replaces, so adoption is a
/// one-token edit per field rather than a rewrite.
public struct FieldID: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
	/// the string that reaches the wire — used for `id=`, `name=`, and the
	/// stored-value key alike.
	public let rawValue: String

	public init(_ rawValue: String) {
		self.rawValue = rawValue
	}

	public init(stringLiteral value: String) {
		self.rawValue = value
	}

	public var description: String { rawValue }

	/// the CSS selector that targets this field, for a sheet that needs one.
	/// `#cat-name-input` and `cat-name-input` are the same identity in two
	/// languages; naming both here is what lets a census check them against
	/// each other.
	public var selector: String { "#" + rawValue }
}

// MARK: - FieldValues
//
// the values a form is RENDERED with, so a patch does not clear what the user
// typed.
//
// not to be confused with `FormValues` (WebUIServer): that is the body a
// browser *submitted*, decoded off the wire and immutable. this is the draft
// the server is editing, which the view reads back field by field. they are
// two ends of the same pipe and must not share a name.

/// draft field values, keyed by ``FieldID``.
///
/// a string literal key resolves through `FieldID`'s literal conformance, so
/// existing `values["name"] ?? ""` reads and `values["name"] = text` writes
/// compile unchanged — the adoption path is the migration path.
public struct FieldValues: Sendable, Equatable, ExpressibleByDictionaryLiteral {
	private var storage: [FieldID: String]

	public init() {
		self.storage = [:]
	}

	public init(_ values: [FieldID: String]) {
		self.storage = values
	}

	public init(dictionaryLiteral elements: (FieldID, String)...) {
		self.storage = Dictionary(uniqueKeysWithValues: elements)
	}

	/// the draft value for `id`, or nil when the field has never been touched.
	///
	/// assigning `nil` removes the entry — that is how a form reset clears a
	/// field back to "not yet filled", as distinct from "filled with empty".
	public subscript(_ id: FieldID) -> String? {
		get { storage[id] }
		set { storage[id] = newValue }
	}

	/// the draft value for `id`, or `fallback` when untouched. the spelling arc
	/// uses at every render site.
	public subscript(_ id: FieldID, default fallback: String) -> String {
		storage[id] ?? fallback
	}

	public var isEmpty: Bool { storage.isEmpty }
	public var count: Int { storage.count }

	public mutating func removeAll() { storage.removeAll() }
}

// MARK: - convenience inits
//
// each one sets `id` and `name` from the SAME value, which is the whole point:
// there is no longer a pair of arguments that can disagree.

extension Input {
	/// an input whose `id` and `name` come from one identity.
	public init(
		field: FieldID,
		placeholder: String = "",
		type: InputType? = .text,
		value: String = "",
		disabled: Bool = false,
		required: Bool = false,
		accept: String = "",
		multiple: Bool = false,
		attributes: [(String, String)] = []
	) {
		self.init(
			id: field.rawValue,
			name: field.rawValue,
			placeholder: placeholder,
			type: type,
			value: value,
			disabled: disabled,
			required: required,
			accept: accept,
			multiple: multiple,
			attributes: attributes
		)
	}
}

extension TextArea {
	/// a textarea whose `id` and `name` come from one identity.
	public init(
		field: FieldID,
		placeholder: String = "",
		value: String = "",
		rows: Int = 3,
		class: String? = nil
	) {
		self.init(
			id: field.rawValue,
			name: field.rawValue,
			placeholder: placeholder,
			value: value,
			rows: rows,
			class: `class`
		)
	}
}

extension Select {
	/// a select whose `id` and `name` come from one identity.
	public init(
		field: FieldID,
		options: [SelectOption],
		selected: String? = nil,
		class: String? = nil
	) {
		self.init(
			id: field.rawValue,
			name: field.rawValue,
			options: options,
			selected: selected,
			class: `class`
		)
	}
}

extension Label {
	/// a label bound to a field, so `for=` cannot point somewhere else.
	public init(_ text: String, for field: FieldID, class: String? = nil) {
		self.init(text, for: field.rawValue, class: `class`)
	}
}