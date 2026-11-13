// the behavior primitives — the 22 rows of the attribute register.
//
// one row is two types: a `Behavior` the view author holds, and the
// `AttributeRepresentable` it serializes to. the split is what makes the
// attribute name a static constant rather than a string a call site can
// misspell, and it is what lets `BehaviourVocabularyTests` compare the engine's
// attribute set with `Documentation/BEHAVIOUR.md` in both directions.
//
// the value semantics are the register's, verbatim: a mode enum serializes its
// raw value, a numeric pair serializes as `min,max`, and a presence behavior
// carries no payload and serializes the empty value — which `AttributeRepresentable`
// spells as the bare attribute, because `data-dismiss=""` and `data-dismiss` are
// one consequence with one canonical spelling.

// MARK: - 1. scroll follow

/// how a scrolling region follows new content.
///
/// `bottom` sticks while the reader is at the bottom and releases on upward
/// movement; `off` states that a region must not follow at all, which is
/// different from saying nothing (the engine's default is per-region policy).
public enum ScrollFollowMode: String, Sendable {
	/// stick while at the bottom, release on upward movement.
	case bottom
	/// no scroll-follow behavior.
	case off
}

/// keep a scrolling region pinned to the bottom while the reader is there.
///
/// the state that shows the jump control is the engine's — it writes
/// `data-follow-state="away"` when the reader detaches. this behavior only
/// states the policy.
public struct ScrollFollow: Behavior {
	/// the follow mode.
	public let mode: ScrollFollowMode

	/// - parameter mode: the follow mode; `bottom` unless the page opts out.
	public init(mode: ScrollFollowMode = .bottom) {
		self.mode = mode
	}

	public func attribute() -> ScrollFollowAttribute {
		ScrollFollowAttribute(mode: mode)
	}
}

/// `data-follow` — the serialized form of ``ScrollFollow``.
public struct ScrollFollowAttribute: AttributeRepresentable {
	public static let name = "data-follow"

	/// the follow mode this attribute states.
	public let mode: ScrollFollowMode

	public init(mode: ScrollFollowMode) {
		self.mode = mode
	}

	public var value: String { mode.rawValue }
}

// MARK: - 2. per-key scroll

/// a key whose scroll offset survives a patch.
///
/// the engine remembers a region's offset by this key rather than by DOM
/// position, so a re-render that reorders siblings keeps the reader's place.
public struct ScrollKey: Behavior {
	/// the key the offset is remembered under.
	public let key: String

	public init(key: String) {
		self.key = key
	}

	public func attribute() -> ScrollKeyAttribute {
		ScrollKeyAttribute(key: key)
	}
}

/// `data-scroll-key` — the serialized form of ``ScrollKey``.
public struct ScrollKeyAttribute: AttributeRepresentable {
	public static let name = "data-scroll-key"

	public let key: String

	public init(key: String) {
		self.key = key
	}

	public var value: String { key }
}

// MARK: - 3. scroll to

/// scroll an element into view, with the 1.4 s flash contract.
///
/// the id names the element to scroll to; the flash is the engine's way of
/// saying which element moved, so a link that jumps across a long page does not
/// leave the reader guessing. an empty id is the document top — the back-to-top
/// affordance's own promise — and flashes nothing, because no element moved.
public struct ScrollTo: Behavior {
	/// the element id to scroll to.
	public let id: String

	public init(id: String) {
		self.id = id
	}

	public func attribute() -> ScrollToAttribute {
		ScrollToAttribute(id: id)
	}
}

/// `data-scroll-to` — the serialized form of ``ScrollTo``.
public struct ScrollToAttribute: AttributeRepresentable {
	public static let name = "data-scroll-to"

	public let id: String

	public init(id: String) {
		self.id = id
	}

	public var value: String { id }
}

// MARK: - 4. draft identity

/// the draft key a control's unsubmitted value is remembered under.
///
/// a patch replaces the markup; the draft is the reader's in-progress value,
/// which is content the server never saw. the key is what keeps the two apart
/// when two controls live in the same form.
public struct DraftIdentity: Behavior {
	/// the draft key.
	public let key: String

	public init(key: String) {
		self.key = key
	}

	public func attribute() -> DraftIdentityAttribute {
		DraftIdentityAttribute(key: key)
	}
}

/// `data-draft-id` — the serialized form of ``DraftIdentity``.
public struct DraftIdentityAttribute: AttributeRepresentable {
	public static let name = "data-draft-id"

	public let key: String

	public init(key: String) {
		self.key = key
	}

	public var value: String { key }
}

/// `data-draft-value` — the server-rendered text a draft starts from.
///
/// a **seed** on its own decides nothing: the engine iterates `[data-draft-id]`,
/// so a `DraftSeed` without a ``DraftIdentity`` on the same control is inert.
/// the pair is the consequence — the identity names the store, the seed is what
/// the server says the field held at render time.
///
/// the precedence rule is the reason the seed travels separately from the
/// element's own `value`: a patch that keeps the identity is the same draft and
/// keeps the reader's keystrokes, while a patch that changes the identity is a
/// different draft and the server's seed wins — the reader's unsubmitted text
/// belonged to the old identity and must not leak into the new one.
public struct DraftSeed: Behavior {
	/// the server-rendered draft text.
	public let text: String

	public init(text: String) {
		self.text = text
	}

	public func attribute() -> DraftSeedAttribute {
		DraftSeedAttribute(text: text)
	}
}

/// `data-draft-value` — the serialized form of ``DraftSeed``.
public struct DraftSeedAttribute: AttributeRepresentable {
	public static let name = "data-draft-value"

	public let text: String

	public init(text: String) {
		self.text = text
	}

	public var value: String { text }
}

// MARK: - 5. focus return

/// return focus to an id after the next patch.
///
/// an empty id means the element itself: the control that opened a layer gets
/// focus back when the layer closes, and a page that re-renders a form does not
/// strand the caret at the top of the document.
public struct FocusReturn: Behavior {
	/// the id to focus after a patch; empty is the element itself.
	public let id: String

	public init(id: String = "") {
		self.id = id
	}

	public func attribute() -> FocusReturnAttribute {
		FocusReturnAttribute(id: id)
	}
}

/// `data-focus-return` — the serialized form of ``FocusReturn``.
public struct FocusReturnAttribute: AttributeRepresentable {
	public static let name = "data-focus-return"

	public let id: String

	public init(id: String = "") {
		self.id = id
	}

	public var value: String { id }
}

// MARK: - 6. dismiss stack

/// mark a layer as dismissible, with the layer name the engine orders on.
///
/// the engine owns the ordering: Escape closes the topmost layer first, an
/// outside click closes the layers above the click. an empty layer name is the
/// plain marker — the same consequence, spelled bare.
public struct DismissStack: Behavior {
	/// the layer name the engine orders by; empty is the plain marker.
	public let layer: String

	public init(layer: String = "") {
		self.layer = layer
	}

	public func attribute() -> DismissStackAttribute {
		DismissStackAttribute(layer: layer)
	}
}

/// `data-dismiss` — the serialized form of ``DismissStack``.
public struct DismissStackAttribute: AttributeRepresentable {
	public static let name = "data-dismiss"

	public let layer: String

	public init(layer: String = "") {
		self.layer = layer
	}

	public var value: String { layer }
}

// MARK: - 7. reorder

/// let the engine write a new order into a hidden input.
///
/// the engine dispatches `change` on the input after it writes, so the order
/// travels the same wire a typed form control does — no second transport.
public struct Reorder: Behavior {
	/// the hidden input id the new order is written into.
	public let inputID: String

	public init(inputID: String) {
		self.inputID = inputID
	}

	public func attribute() -> ReorderAttribute {
		ReorderAttribute(inputID: inputID)
	}
}

/// `data-reorder` — the serialized form of ``Reorder``.
public struct ReorderAttribute: AttributeRepresentable {
	public static let name = "data-reorder"

	public let inputID: String

	public init(inputID: String) {
		self.inputID = inputID
	}

	public var value: String { inputID }
}

// MARK: - 8. clipboard

/// copy text to the clipboard on activation.
///
/// an empty text means the element's own text, which is the common case: a code
/// block or an address that is copied verbatim rather than re-spelled in two
/// places and left to drift.
public struct Clipboard: Behavior {
	/// the text to copy; empty is the element's own text.
	public let text: String

	public init(text: String = "") {
		self.text = text
	}

	public func attribute() -> ClipboardAttribute {
		ClipboardAttribute(text: text)
	}
}

/// `data-copy` — the serialized form of ``Clipboard``.
public struct ClipboardAttribute: AttributeRepresentable {
	public static let name = "data-copy"

	public let text: String

	public init(text: String = "") {
		self.text = text
	}

	public var value: String { text }
}

// MARK: - 9. table enhancement

/// which table enhancements a table opts into.
///
/// one attribute carries the pair because a table that sorts and filters is one
/// consequence, not two: the engine builds both affordances from one dispatch
/// row.
public enum TableEnhanceMode: String, Sendable {
	case sort
	case filter
	/// both at once; serializes `sort filter`.
	case sortAndFilter = "sort filter"
}

/// let the engine add sorting and filtering affordances to a table.
public struct TableEnhance: Behavior {
	/// the enhancements to apply.
	public let mode: TableEnhanceMode

	public init(mode: TableEnhanceMode = .sort) {
		self.mode = mode
	}

	public func attribute() -> TableEnhanceAttribute {
		TableEnhanceAttribute(mode: mode)
	}
}

/// `data-table-enhance` — the serialized form of ``TableEnhance``.
public struct TableEnhanceAttribute: AttributeRepresentable {
	public static let name = "data-table-enhance"

	public let mode: TableEnhanceMode

	public init(mode: TableEnhanceMode) {
		self.mode = mode
	}

	public var value: String { mode.rawValue }
}

// MARK: - 10. skip target

/// the id a skip link moves focus to.
///
/// a skip link is an `<a href="#main">` that exists so a keyboard reader does
/// not tab through the whole chrome; the engine moves real focus, which is what
/// makes the target reachable afterwards.
public struct SkipTarget: Behavior {
	/// the id focus moves to.
	public let id: String

	public init(id: String) {
		self.id = id
	}

	public func attribute() -> SkipTargetAttribute {
		SkipTargetAttribute(id: id)
	}
}

/// `data-skip-to` — the serialized form of ``SkipTarget``.
public struct SkipTargetAttribute: AttributeRepresentable {
	public static let name = "data-skip-to"

	public let id: String

	public init(id: String) {
		self.id = id
	}

	public var value: String { id }
}

// MARK: - 11. ticking label

/// a label that paints a relative time, then keeps ticking.
///
/// the epoch is milliseconds since 1970, the unit the browser already speaks —
/// a seconds-since value would need a second convention on the wire.
public struct TickingLabel: Behavior {
	/// the timestamp, in milliseconds since the unix epoch.
	public let epochMilliseconds: UInt64

	public init(epochMilliseconds: UInt64) {
		self.epochMilliseconds = epochMilliseconds
	}

	public func attribute() -> TickingLabelAttribute {
		TickingLabelAttribute(epochMilliseconds: epochMilliseconds)
	}
}

/// `data-reltime` — the serialized form of ``TickingLabel``.
public struct TickingLabelAttribute: AttributeRepresentable {
	public static let name = "data-reltime"

	public let epochMilliseconds: UInt64

	public init(epochMilliseconds: UInt64) {
		self.epochMilliseconds = epochMilliseconds
	}

	public var value: String { String(epochMilliseconds) }
}

// MARK: - 12. elapsed clock

/// a clock that counts up from a start instant.
///
/// the engine writes `data-elapsed` once it mounts the clock; this behavior
/// states only the start, so the page never carries a hand-computed duration
/// that goes stale between renders.
public struct ElapsedClock: Behavior {
	/// the start instant, in milliseconds since the unix epoch.
	public let startedMilliseconds: UInt64

	public init(startedMilliseconds: UInt64) {
		self.startedMilliseconds = startedMilliseconds
	}

	public func attribute() -> ElapsedClockAttribute {
		ElapsedClockAttribute(startedMilliseconds: startedMilliseconds)
	}
}

/// `data-started` — the serialized form of ``ElapsedClock``.
public struct ElapsedClockAttribute: AttributeRepresentable {
	public static let name = "data-started"

	public let startedMilliseconds: UInt64

	public init(startedMilliseconds: UInt64) {
		self.startedMilliseconds = startedMilliseconds
	}

	public var value: String { String(startedMilliseconds) }
}

// MARK: - 13. disclosure

/// keep a `<details>` element's open state across a patch.
///
/// explicit, not magic: a `<details>` without this attribute is not preserved.
/// native disclosure already knows how to open and close; the patch is what
/// would otherwise discard the reader's choice.
public struct Disclosure: Behavior {
	public init() {}

	public func attribute() -> DisclosureAttribute {
		DisclosureAttribute()
	}
}

/// `data-preserve-open` — the serialized form of ``Disclosure``.
public struct DisclosureAttribute: AttributeRepresentable {
	public static let name = "data-preserve-open"

	public init() {}

	public var value: String { "" }
}

// MARK: - 14. inline edit

/// enter edit mode locally, with no round-trip.
///
/// the edit itself is local; saving is a native form submit or a typed event,
/// so the server still sees one write per save rather than one per keystroke.
public struct InlineEdit: Behavior {
	public init() {}

	public func attribute() -> InlineEditAttribute {
		InlineEditAttribute()
	}
}

/// `data-inline-edit` — the serialized form of ``InlineEdit``.
public struct InlineEditAttribute: AttributeRepresentable {
	public static let name = "data-inline-edit"

	public init() {}

	public var value: String { "" }
}

// MARK: - 15. roving tabindex

/// one tab stop for a group, with arrow keys moving it.
///
/// a list of forty rows is forty tab stops without this; the roving owner keeps
/// exactly one, which is the difference between a navigable list and a trap.
public struct Roving: Behavior {
	public init() {}

	public func attribute() -> RovingAttribute {
		RovingAttribute()
	}
}

/// `data-roving` — the serialized form of ``Roving``.
public struct RovingAttribute: AttributeRepresentable {
	public static let name = "data-roving"

	public init() {}

	public var value: String { "" }
}

// MARK: - 16. scrollspy

/// highlight the nav entry for the section in view.
///
/// the attribute marks the container whose sections are watched; the nav it
/// drives is found by the section ids it already carries, not by a selector the
/// page has to keep in sync.
public struct Scrollspy: Behavior {
	public init() {}

	public func attribute() -> ScrollspyAttribute {
		ScrollspyAttribute()
	}
}

/// `data-scrollspy` — the serialized form of ``Scrollspy``.
public struct ScrollspyAttribute: AttributeRepresentable {
	public static let name = "data-scrollspy"

	public init() {}

	public var value: String { "" }
}

// MARK: - 17. theme choice

/// the three modes a theme picker offers.
///
/// `system` follows the OS and is the default: a page that states a mode
/// explicitly overrides the reader's own preference, so it should say so on
/// purpose.
public enum ThemeChoiceMode: String, Sendable {
	case light
	case dark
	case system
}

/// a theme picker's mode, reconciled by the engine.
///
/// the engine applies the choice and reconciles `aria-pressed` on the picker,
/// so the pressed state cannot disagree with the theme the page is rooted at.
public struct ThemeChoice: Behavior {
	/// the chosen mode.
	public let mode: ThemeChoiceMode

	public init(mode: ThemeChoiceMode = .system) {
		self.mode = mode
	}

	public func attribute() -> ThemeChoiceAttribute {
		ThemeChoiceAttribute(mode: mode)
	}
}

/// `data-theme-choice` — the serialized form of ``ThemeChoice``.
public struct ThemeChoiceAttribute: AttributeRepresentable {
	public static let name = "data-theme-choice"

	public let mode: ThemeChoiceMode

	public init(mode: ThemeChoiceMode) {
		self.mode = mode
	}

	public var value: String { mode.rawValue }
}

// MARK: - 18. autogrow

/// a textarea that grows with its content.
///
/// the rows a textarea renders with are a guess; the content is the answer, and
/// only the client has it after the reader types.
public struct Autogrow: Behavior {
	public init() {}

	public func attribute() -> AutogrowAttribute {
		AutogrowAttribute()
	}
}

/// `data-autogrow` — the serialized form of ``Autogrow``.
public struct AutogrowAttribute: AttributeRepresentable {
	public static let name = "data-autogrow"

	public init() {}

	public var value: String { "" }
}

// MARK: - 19. submit on enter

/// enter submits the form.
///
/// a single-line composer has no other submit gesture a reader reaches for; the
/// behavior says the control accepts it rather than leaving the client to guess
/// by element type.
public struct SubmitOnEnter: Behavior {
	public init() {}

	public func attribute() -> SubmitOnEnterAttribute {
		SubmitOnEnterAttribute()
	}
}

/// `data-submit-on-enter` — the serialized form of ``SubmitOnEnter``.
public struct SubmitOnEnterAttribute: AttributeRepresentable {
	public static let name = "data-submit-on-enter"

	public init() {}

	public var value: String { "" }
}

// MARK: - 20. clear on submit

/// clear the control on a successful submit.
///
/// successful is the whole contract: a failed submit keeps the text the reader
/// typed, which is the one thing they cannot retype from memory.
public struct ClearOnSubmit: Behavior {
	public init() {}

	public func attribute() -> ClearOnSubmitAttribute {
		ClearOnSubmitAttribute()
	}
}

/// `data-clear-on-submit` — the serialized form of ``ClearOnSubmit``.
public struct ClearOnSubmitAttribute: AttributeRepresentable {
	public static let name = "data-clear-on-submit"

	public init() {}

	public var value: String { "" }
}

// MARK: - 21. number clamp

/// the accepted numeric range for a number control.
///
/// `min`/`max` are `Int` and serialize as `min,max`; a caller that passes an
/// inverted range gets it serialized as given, because a behavior is a value
/// and a render path must not trap to report a caller error.
public struct NumberClamp: Behavior {
	/// the lowest accepted value.
	public let min: Int
	/// the highest accepted value.
	public let max: Int

	public init(min: Int, max: Int) {
		self.min = min
		self.max = max
	}

	public func attribute() -> NumberClampAttribute {
		NumberClampAttribute(min: min, max: max)
	}
}

/// `data-clamp` — the serialized form of ``NumberClamp``.
public struct NumberClampAttribute: AttributeRepresentable {
	public static let name = "data-clamp"

	public let min: Int
	public let max: Int

	public init(min: Int, max: Int) {
		self.min = min
		self.max = max
	}

	public var value: String { "\(min),\(max)" }
}

// MARK: - 22. filter list

/// filter a rendered list by what the reader types into a field.
///
/// the region owns the items the query hides, not necessarily the field the
/// query arrives in. `source` names that field when it lives outside the
/// region — a selector or a bare id (a composer textarea a palette filters and
/// writes back into is the motivating case). the default is empty, which means
/// the region's own `input`; that is also the spelling the bare attribute takes,
/// so every existing region renders byte-identically.
///
/// a list is filtered by the text its items already render, so a server render
/// needs no second copy of the labels on the wire. a region that names a source
/// which does not resolve is inert, exactly like a region with no input.
public struct FilterList: Behavior {
	/// the field that carries the query: a selector, a bare id, or empty for
	/// the region's own `input`.
	public let source: String

	/// the contained form: the region's own `input` carries the query.
	public init() {
		self.source = ""
	}

	/// the external form: `source` names the field (a selector, or a bare id).
	public init(source: String) {
		self.source = source
	}

	public func attribute() -> FilterListAttribute {
		FilterListAttribute(source: source)
	}
}

/// `data-filter-list` — the serialized form of ``FilterList``.
public struct FilterListAttribute: AttributeRepresentable {
	public static let name = "data-filter-list"

	public let source: String

	public init() {
		self.source = ""
	}

	public init(source: String) {
		self.source = source
	}

	public var value: String { source }
}

/// `data-filter-insert` — the id of the field a selected item is written into.
///
/// one behavior, one attribute (the register's law): `FilterInsert` names the
/// destination, ``FilterTemplate`` carries the text, and ``FilterClear`` decides
/// whether the typed query is stripped first. the three are read together inside
/// the filter binder, and the pairing is load-bearing — an insert with no
/// template is inert, and a template with no insert is inert.
public struct FilterInsert: Behavior {
	/// the id of the field the selection is written into.
	public let target: String

	public init(target: String) {
		self.target = target
	}

	public func attribute() -> FilterInsertAttribute {
		FilterInsertAttribute(target: target)
	}
}

/// `data-filter-insert` — the serialized form of ``FilterInsert``.
public struct FilterInsertAttribute: AttributeRepresentable {
	public static let name = "data-filter-insert"

	public let target: String

	public init(target: String) {
		self.target = target
	}

	public var value: String { target }
}

/// `data-filter-template` — the text a selected item is written as.
///
/// `{value}` stands for the item's trimmed text; every occurrence is replaced.
/// a template with no ``FilterInsert`` is inert, because the destination is the
/// insert's to name.
public struct FilterTemplate: Behavior {
	/// the text, with `{value}` standing for the item's label.
	public let text: String

	public init(text: String) {
		self.text = text
	}

	public func attribute() -> FilterTemplateAttribute {
		FilterTemplateAttribute(text: text)
	}
}

/// `data-filter-template` — the serialized form of ``FilterTemplate``.
public struct FilterTemplateAttribute: AttributeRepresentable {
	public static let name = "data-filter-template"

	public let text: String

	public init(text: String) {
		self.text = text
	}

	public var value: String { text }
}

/// `data-filter-clear` — strip the typed query before the selection is written.
///
/// presence only: the engine removes the run of non-whitespace immediately
/// before the destination's caret (the token the reader was typing) and then
/// inserts the resolved template there. absent, the template is inserted with
/// the query left in place.
public struct FilterClear: Behavior {
	public init() {}

	public func attribute() -> FilterClearAttribute {
		FilterClearAttribute()
	}
}

/// `data-filter-clear` — the serialized form of ``FilterClear``.
public struct FilterClearAttribute: AttributeRepresentable {
	public static let name = "data-filter-clear"

	public init() {}

	public var value: String { "" }
}

// MARK: - 23. upload destination

/// where an upload lands, as the route named it.
///
/// a value, not a string convention inside the engine: ``WebUIDropZone``
/// serializes the destination to `data-upload-into` and the engine composes
/// the file path from it (`<directory>/<name>`) before sending
/// `X-Upload-Path`, so the transport never parses a destination out of a url
/// or a class name. what the directory means is the route's business — the
/// framework owns the wire and the tray, never the storage (plan §22.3,
/// risk 4).
public enum UploadDestination: AttributeRepresentable, Sendable, Equatable, Hashable {
	/// the host's attachment store.
	case attachments
	/// one directory inside that store, as a relative path.
	///
	/// the value is a **relative directory**, never a scheme: `.folder(path:
	/// "docs")` serializes as `docs`, not `folder:docs`. the case distinction
	/// is Swift-side intent only — the wire carries a relative directory and
	/// the route decides where it lands.
	case folder(path: String)

	public static let name = "data-upload-into"

	/// the value, normalized: split on `/`, drop empty, `.` and `..` segments,
	/// rejoin with `/`.
	///
	/// the value is a behavior, so it never traps and never resolves: `..`
	/// segments are **dropped**, not applied — `a/../b` is `a/b`, and `../etc`
	/// is `etc`. `..` alone (or an empty path) is the empty value, which the
	/// engine reads as "no directory" and composes the bare filename.
	public var value: String {
		switch self {
			case .attachments: return "attachments"
			case .folder(let path):
				return path
					.split(separator: "/", omittingEmptySubsequences: true)
					.map(String.init)
					.filter { $0 != "." && $0 != ".." }
					.joined(separator: "/")
		}
	}
}

/// a filename template for an upload, as the route named it.
///
/// `data-upload-name-template` is read by the engine's upload binder, not by an
/// entry of its own in the dispatch table: it parameterizes the one transport
/// `data-upload-into` already owns. tokens are resolved before the path is
/// composed, so two uploads through one zone cannot collide:
///
/// - `{name}` — the file's name with the final extension stripped;
/// - `{ext}` — the final extension without the dot (empty when there is none);
/// - `{ts}` — `Date.now()`, in milliseconds;
/// - `{seq}` — a per-page counter starting at 1, incremented once per upload
///   whose template names it;
///
/// an unknown token stays literal, and a template that resolves to an empty
/// string falls back to the file's original name.
public struct UploadNameTemplate: AttributeRepresentable, Sendable, Equatable, Hashable {
	public static let name = "data-upload-name-template"

	/// the template text, e.g. `{name}-{seq}.{ext}`.
	public let template: String

	public init(template: String) { self.template = template }

	public var value: String { template }
}

// MARK: - 24. reading keys

/// a scrolling region a reader can drive from the keyboard.
///
/// the element that carries this attribute is the region, not a control inside
/// it: while focus is anywhere inside the region, `ArrowUp`/`PageUp` scroll it
/// by a line/a page, `Home`/`End` jump to the top/the bottom, and `Escape`
/// returns to the live tail — but only when no layer is open, because a layer's
/// `Escape` is the reader's first intent. the element needs a `tabindex` (0) to
/// take focus at all; a scroller without one is inert.
///
/// deliberately not a plural of `data-scroll-key`: that attribute names a
/// *memory* (an offset that survives a patch), this one names a *keyboard*
/// consequence. one spelling for two unrelated consequences would make each
/// unreadable at the site that carries only one of them.
public struct ReadingKeys: Behavior {
	public init() {}

	public func attribute() -> ReadingKeysAttribute {
		ReadingKeysAttribute()
	}
}

/// `data-reading-keys` — the serialized form of ``ReadingKeys``.
public struct ReadingKeysAttribute: AttributeRepresentable {
	public static let name = "data-reading-keys"

	public init() {}

	public var value: String { "" }
}
