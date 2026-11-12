// the behavior vocabulary's compile-time half.
//
// a behavior is a description of a client consequence, not a string the
// engine guesses at. the Swift value carries the decision; the attribute is
// derived from it, so a typo cannot reach markup and the vocabulary is
// enumerable in one place (`AttributeRepresentable.name`).
//
// the engine's half is a dispatch table keyed by exactly these attribute
// names (slice S3). `Documentation/BEHAVIOUR.md` is the contract between the
// two, and `BehaviourVocabularyTests` fails when the engine reads an
// attribute the document does not name.

import WebUISharedCore

// MARK: - attribute

/// a Swift value that serializes to one HTML attribute.
///
/// one behavior maps to exactly one attribute type; the mapping is injective,
/// so two behaviors cannot claim the same attribute by accident. the name is
/// the contract with the engine's dispatch table, which is why it is a static
/// constant rather than a parameter.
public protocol AttributeRepresentable: Sendable {
	/// the attribute name, e.g. `data-follow`.
	static var name: String { get }
	/// the attribute value. escaped on the way out, never by the caller.
	var value: String { get }
}

extension AttributeRepresentable {
	/// ` name="value"` for a value-bearing attribute, ` name` when the value is
	/// empty — the one spelling of an attribute, ready to splice into a tag.
	///
	/// the empty case is a rule, not an optimization: a presence attribute
	/// cannot be expressed by an empty value (`data-dismiss=""` is not "absent",
	/// so the generic attribute emitter cannot carry it), and `data-dismiss=""`
	/// and `data-dismiss` read the same to `hasAttribute` — which makes the
	/// quoted-empty form a second spelling of one consequence. the bare form is
	/// canonical: `DismissStack()`, `Disclosure()` and `Clipboard()` all emit it.
	/// the name is a compile-time constant and is not caller-controlled; a
	/// non-empty value goes through `htmlEscape`.
	public var attributeText: String {
		let value = self.value
		guard !value.isEmpty else { return " \(Self.name)" }
		return " \(Self.name)=\"\(htmlEscape(value))\""
	}
}

// MARK: - behavior

/// a compile-time description of a client consequence — patch or interaction.
///
/// one job: name the consequence and derive its attribute. a behavior never
/// performs I/O, never touches the DOM, and cannot be a runtime string.
public protocol Behavior: Sendable {
	associatedtype Attribute: AttributeRepresentable
	/// the serialized attribute for this behavior, derived from the value.
	func attribute() -> Attribute
}

extension Behavior {
	/// ` data-name="value"` for this behavior.
	public var attributeText: String { attribute().attributeText }
}

// MARK: - emission

/// writes a behavior's attribute onto the element that opens next.
public struct BehaviorModifier<B: Behavior>: ViewModifier {
	public let behavior: B

	public init(_ behavior: B) {
		self.behavior = behavior
	}

	public func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer) {
		AttributeContribution(behavior.attributeText).decorate(content, into: &buffer)
	}
}

extension View {
	/// attach one behavior to this element.
	///
	/// concrete return type, not `some View`: an opaque result cannot be
	/// inferred as the element type of an `@ElementBuilder` loop body, the
	/// same reason `.title(_:)` returns its `ModifiedView`.
	public func behavior<B: Behavior>(_ behavior: B) -> ModifiedView<Self, BehaviorModifier<B>> {
		ModifiedView(content: self, modifier: BehaviorModifier(behavior))
	}
}
