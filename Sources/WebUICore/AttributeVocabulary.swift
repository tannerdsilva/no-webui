// the attribute vocabulary the element layer was missing.
//
// `Aria`, `ClassName`, `HTMLEvent` and `ComponentID` shipped as value types,
// but a page author could only reach them by writing `attribute("aria-label",
// …)` strings — so every consumer re-spelled the framework's own vocabulary.
// this file adds the missing emitters.
//
// two rules hold everything here together:
//
// 1. every modifier contributes through `HTMLBuffer.addAttribute`, so the
//    merge path folds duplicate `class` and `style` attributes instead of
//    letting the last one win. a modifier that skips it is a modifier that can
//    silently erase another.
// 2. an attribute modifier takes `when:` — presence-only attributes cannot be
//    expressed by an empty value (`hidden=""` is not "absent"), and the
//    `Group { if … }` dance that works around it is where types get erased.

// MARK: - the contribution

/// contributes raw attribute text to the element that opens next.
///
/// the public modifiers below all funnel through here so there is exactly one
/// place that knows how to reach the buffer. empty text is a no-op, which is
/// what makes `when: false` free.
public struct AttributeContribution: ViewModifier {
	public let text: String

	public init(_ text: String) {
		self.text = text
	}

	public func apply(to html: String) -> String {
		text.isEmpty ? html : injectAttributes(into: html, text)
	}

	public func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer) {
		guard !text.isEmpty else {
			content.render(into: &buffer)
			return
		}
		let mark = buffer.mark
		buffer.addAttribute(text)
		content.render(into: &buffer)
		buffer.settlePendingAttributes(from: mark)
	}
}

private func attributeText(_ pairs: [(String, String)]) -> String {
	pairs.map { " \(htmlEscape($0.0))=\"\(htmlEscape($0.1))\"" }.joined()
}

// MARK: - aria

extension View {
	/// several typed aria attributes at once, optionally only when a condition
	/// holds.
	///
	/// the single-attribute `aria(_:)` shipped first; this is the same emitter
	/// with the two things a real form needs: more than one attribute on one
	/// element (`aria-invalid` travels with `aria-describedby`), and the
	/// condition under which both appear.
	public func aria(_ attributes: [Aria], when condition: Bool = true) -> some View {
		ModifiedView(
			content: self,
			modifier: AttributeContribution(
				condition ? Aria.attributes(attributes) : ""
			)
		)
	}
}

// MARK: - data-*

extension View {
	/// one `data-*` payload attribute.
	///
	/// the `data-` prefix is added here rather than by the caller: it is the
	/// contract between markup and whatever reads it (the engine, an app's
	/// client script), and 32 hand-written spellings is how one of them ends up
	/// on the wrong element.
	public func data(_ name: String, _ value: String, when condition: Bool = true) -> some View {
		let clean = name.hasPrefix("data-") ? String(name.dropFirst(5)) : name
		return ModifiedView(
			content: self,
			modifier: AttributeContribution(condition ? attributeText([("data-" + clean, value)]) : "")
		)
	}
}

// MARK: - presence-only attributes

/// an attribute whose meaning is its PRESENCE, not its value.
///
/// `hidden=""` is not the same as absent, so these cannot ride the generic
/// attribute emitter and cannot be expressed with a defaulted value.
public enum PresenceAttribute: String, Sendable, CaseIterable {
	case hidden
	case readonly
	case disabled
	case required
	case checked
	case selected
	case multiple
	case autofocus
	case novalidate
	case inert
	case open
}

extension View {
	/// a presence-only attribute, emitted bare when `condition` holds and not
	/// at all when it does not.
	public func flag(_ attribute: PresenceAttribute, when condition: Bool = true) -> some View {
		ModifiedView(
			content: self,
			modifier: AttributeContribution(condition ? " " + attribute.rawValue : "")
		)
	}
}

// MARK: - wiring

/// the client-owned half of an event: the component id and event name a client
/// script matches on.
///
/// the server-owned half is `on(_:perform:)`, which allocates an id and
/// dispatches back to a Swift handler. both spellings must agree on the
/// attribute names, so both go through `ComponentID` and `HTMLEvent` — a second
/// enum here would be the duplication this file exists to remove.
public struct Wire: Sendable, Hashable {
	public let component: ComponentID
	public let event: HTMLEvent

	public init(_ component: ComponentID, on event: HTMLEvent = .click) {
		self.component = component
		self.event = event
	}
}

extension View {
	/// address this element from the client: `data-component-id` +
	/// `data-event`.
	public func wire(_ wire: Wire) -> some View {
		ModifiedView(
			content: self,
			modifier: AttributeContribution(
				attributeText([("data-component-id", wire.component.value),
				               ("data-event", wire.event.rawValue)])
			)
		)
	}

	/// the common case: a click, addressed by component id.
	public func wire(_ component: ComponentID, on event: HTMLEvent = .click) -> some View {
		wire(Wire(component, on: event))
	}
}

// MARK: - engine identity

extension View {
	/// the key the engine uses to reconcile this node across patches.
	///
	/// the engine already reads `data-webui-key`; emitting it from the same
	/// place that reads it is what stops a keyed list from silently losing its
	/// identity (and with it, focus) on the next render.
	public func webuiKey(_ key: String, when condition: Bool = true) -> some View {
		ModifiedView(
			content: self,
			modifier: AttributeContribution(condition ? attributeText([("data-webui-key", key)]) : "")
		)
	}
}

// MARK: - css custom properties

/// a CSS custom property name.
///
/// the `--` prefix is part of the type, not a convention: a property that does
/// not start with `--` is not a custom property, and the browser drops it
/// silently.
public struct CSSVariable: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
	public let name: String

	public init(_ name: String) {
		precondition(name.hasPrefix("--"), "a css custom property starts with `--`: \(name)")
		self.name = name
	}

	public init(stringLiteral value: String) {
		self.init(value)
	}

	public var description: String { name }
}

/// the value kinds a custom property carries in this codebase: a count, a
/// length, or a colour. anything richer belongs in the sheet, not in markup.
public enum CSSValue: Sendable, Hashable {
	case number(Int)
	case length(Int)
	case color(String)
	case raw(String)

	public var text: String {
		switch self {
		case .number(let n): return "\(n)"
		case .length(let n): return "\(n)px"
		case .color(let hex): return hex
		case .raw(let s): return s
		}
	}
}

extension View {
	/// set one CSS custom property on this element.
	///
	/// a `style` attribute may carry these and nothing else: the value is data
	/// the sheet cannot know (a depth, a colour the user picked), while every
	/// layout decision stays in the stylesheet. chained calls fold into ONE
	/// `style` attribute with the declarations in order.
	public func cssVar(_ variable: CSSVariable, _ value: CSSValue) -> some View {
		ModifiedView(
			content: self,
			modifier: InlineStyle(.custom(variable.name), value.text)
		)
	}
}

// MARK: - trusted markup

/// where a block of pre-rendered html came from.
public enum TrustedSource: Sendable, Hashable {
	case markdown
	case plugin(String)
	case icon
	case other(String)

	public var label: String {
		switch self {
		case .markdown: return "markdown"
		case .plugin(let name): return "plugin:" + name
		case .icon: return "icon"
		case .other(let name): return name
		}
	}
}

/// markup that is deliberately NOT escaped, carrying the reason it is trusted.
///
/// `Raw(.trusted(…))` says "trust me" and nothing else, so every one of those
/// call sites has to be found by reading the file. naming the source makes the
/// set enumerable — a census test can count the seams and fail when one appears
/// where it should not.
public struct TrustedMarkup: View {
	public let html: String
	public let source: TrustedSource

	public init(_ html: String, from source: TrustedSource) {
		self.html = html
		self.source = source
	}

	public func render(into buffer: inout HTMLBuffer) {
		buffer.append(html)
	}
}

// MARK: - class-name audit

/// checks a page's class names against the set its stylesheet declares.
///
/// `ClassName` is a type, but nothing stops a typo: `addClass("dd-pop-profie")`
/// renders, ships, and styles nothing. the sheet is the only authority on which
/// names exist, so the audit takes it as an argument rather than pretending the
/// framework knows.
public enum ClassNameAudit {
	/// class names used by views that the stylesheet does not declare.
	public static func undeclared(used: [ClassName], declared: Set<String>) -> [String] {
		var seen = Set<String>()
		var missing: [String] = []
		for name in used where !declared.contains(name.value) {
			if seen.insert(name.value).inserted { missing.append(name.value) }
		}
		return missing.sorted()
	}

	/// class names the stylesheet declares that no view uses.
	///
	/// reported separately because the two failures are different: a class used
	/// but not declared renders nothing, a class declared but unused is dead
	/// weight. collapsing them would hide one behind the other.
	public static func unused(declared: Set<String>, used: [ClassName]) -> [String] {
		declared.subtracting(used.map(\.value)).sorted()
	}
}

// MARK: - element authoring

/// the structural tags a hand-written component needs.
///
/// deliberately excludes the tags that already have a dedicated type
/// (`button`, `input`, `form`, `select`, `textarea`, `label`, `a`): two ways to
/// write `<button>` is how a codebase ends up with two button behaviours.
public enum Tag: String, Sendable {
	case div, span, section, article, header, footer, nav, main, aside
	case p, ul, ol, li, dl, dt, dd, pre, figure, figcaption
	case table, thead, tbody, tr, td, th
	case h1, h2, h3, h4, h5, h6
}

/// a structural element with content, for authoring components.
///
/// authoring one by hand means `beginElement` / `endOpenTag` / `endElement` plus
/// hand-built attribute text — enough boilerplate that repeating a string is
/// cheaper than factoring it, which is why a page accumulates one-off markup.
/// this is the cheap path.
public struct Element: View {
	public let tag: Tag
	public let className: String?
	public let id: String?
	/// children as `[any View]`, the shape `Group` uses: a `@ViewBuilder`
	/// closure holding more than one expression builds an array, and a generic
	/// `Content: View` parameter cannot accept it.
	public let content: [any View]

	public init(
		_ tag: Tag,
		class className: String? = nil,
		id: String? = nil,
		@ViewBuilder content: () -> [any View]
	) {
		self.tag = tag
		self.className = className
		self.id = id
		self.content = content()
	}

	public func render(into buffer: inout HTMLBuffer) {
		var attributes = ""
		if let id { attributes += " id=\"\(htmlEscape(id))\"" }
		if let className { attributes += " class=\"\(htmlEscape(className))\"" }
		buffer.beginElement(tag.rawValue, attributes)
		buffer.endOpenTag()
		for child in content { child.render(into: &buffer) }
		buffer.endElement()
	}
}