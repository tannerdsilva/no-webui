// MARK: - ElementBuilder
//
// the framework's one result builder. an `ElementBuilder` block becomes a
// *tuple of concrete views*: the element's own type flows into the render loop,
// so there is no array and no existential box per child.
//
// erasure is still expressible, and it is deliberately narrow: a caller who
// already holds an `[any View]` (a runtime-heterogeneous list from a data model)
// reaches for ``ErasedViews``. `buildExpression(_ expression: [any View])` picks
// an array literal up automatically, so the door is `ErasedViews` and nothing
// else — there is no second, weaker builder that erases implicitly. the former
// `ViewBuilder` was exactly that weaker builder: it turned *every* block into
// `[any View]`, one array plus one box per child, because its `buildExpression`
// intercepted every expression. it is gone.
//
// what a typed block cannot do is the reason `ErasedViews` stays: a block is a
// tuple, so it has no `count`, no `isEmpty`, no `enumerated`, and no reverse
// walk. a component whose *markup* depends on one of those reads a stored
// `hasX` flag decided once at init (``blockIsEmpty(_:)``) or takes an erased
// array, and says so at the parameter.
//
// measured on 2000 rows (release, byte-identical output): an erased element
// costs 366 ns/row, a typed one 244 ns/row.

/// a block of elements, held as a tuple of concrete views.
///
/// the product of ``ElementBuilder``; a consumer meets it as an inferred type,
/// never by writing it.
public struct TupleView<each C: View>: View {
	public var content: (repeat each C)

	public init(content: (repeat each C)) {
		self.content = content
	}

	@inline(__always)
	public func render(into buffer: inout HTMLBuffer) {
		repeat (each content).render(into: &buffer)
	}
}

/// an `if` with no `else`, as a value.
public struct OptionalView<C: View>: View {
	public let content: C?

	public init(_ content: C?) {
		self.content = content
	}

	@inline(__always)
	public func render(into buffer: inout HTMLBuffer) {
		content?.render(into: &buffer)
	}
}

/// an `if`/`else` or `switch`, as a value.
public enum EitherView<First: View, Second: View>: View {
	case first(First)
	case second(Second)

	@inline(__always)
	public func render(into buffer: inout HTMLBuffer) {
		switch self {
		case .first(let view): view.render(into: &buffer)
		case .second(let view): view.render(into: &buffer)
		}
	}
}

/// a `for` loop inside a block, as a value.
	///
	/// homogeneous by construction — a loop body has one type — so the repetition
	/// needs no erasure either.
	public struct RepeatedView<C: View>: View {
		public let content: [C]

		public init(_ content: [C]) {
			self.content = content
		}

		@inline(__always)
		public func render(into buffer: inout HTMLBuffer) {
			for view in content {
				view.render(into: &buffer)
			}
		}
	}

	/// an array of views that was already erased by its holder.
	///
	/// the one place a typed block keeps erasure: the caller reached for an
	/// `[any View]` themselves, so the block repeats it rather than pretending
	/// otherwise. spelled as its own type — not `Group` — so a builder block
	/// cannot recurse through `Group`'s own initializer.
	public struct ErasedViews: View {
		public let content: [any View]

		public init(_ content: [any View]) {
			self.content = content
		}

		public func render(into buffer: inout HTMLBuffer) {
			for view in content {
				view.render(into: &buffer)
			}
		}
	}

/// a view that stands for its children without framing an element.
///
/// the builder's products (`TupleView`, `OptionalView`, `EitherView`,
/// `RepeatedView`) and ``Group`` are all this: bookkeeping between the page and
/// the children, emitting no bytes of their own. a walk that needs to reach the
/// real children — the chart resolving marks out of a `ForEach` element — reads
/// `elements` instead of knowing each combinator by name.
///
/// `elements` allocates, so it belongs on setup-time walks, never in a render
/// loop: `render(into:)` stays pack-expanded and allocation-free.
public protocol ElementGroup: View {
	var elements: [any View] { get }
}

extension Group: ElementGroup {
	public var elements: [any View] { [content] }
}

extension TupleView: ElementGroup {
	public var elements: [any View] {
		var out: [any View] = []
		repeat out.append(each content)
		return out
	}
}

extension OptionalView: ElementGroup {
	public var elements: [any View] { content.map { [$0 as any View] } ?? [] }
}

extension EitherView: ElementGroup {
	public var elements: [any View] {
		switch self {
		case .first(let view): return [view as any View]
		case .second(let view): return [view as any View]
		}
	}
}

extension RepeatedView: ElementGroup {
	public var elements: [any View] { content.map { $0 as any View } }
}

extension ErasedViews: ElementGroup {
	public var elements: [any View] { content }
}

/// whether a builder block produced nothing.
///
/// the design-system components branch on "did the caller supply children" (a
/// footer div exists only when the footer has content), and a generic
/// `Content: View` has no `isEmpty`. the builder products that *can* be empty
/// answer here; a single view is never empty. this walks the products once, at
/// init — never inside a render, which is the cost the typed builder exists to
/// remove.
public func blockIsEmpty<C: View>(_ content: C) -> Bool {
	guard let group = content as? ElementGroup else { return false }
	return group.elements.isEmpty
}

/// the result builder: a block becomes concrete views, not an array.
///
/// every block in the framework and the design system takes it — a component
/// parameter, `ForEach`'s body, a page's body. the attribute lives on the
/// parameter, so a call site never names the builder. a caller who genuinely
/// holds an erased list passes it as ``ErasedViews`` (or as an `[any View]`
/// array parameter, which is the same door).
@resultBuilder
public enum ElementBuilder {
	/// several elements, as a tuple.
	public static func buildBlock<each C: View>(_ components: repeat each C) -> TupleView<repeat each C> {
		TupleView(content: (repeat each components))
	}

	/// a single element is the element — no wrapper for the common one-view body.
	///
	/// measured: wrapping a single child in `TupleView` costs ~30 ns/row on a
	/// 2000-row render (a 12% tax on the row), so the dominant case skips it.
	public static func buildBlock<C: View>(_ component: C) -> C { component }

	/// an expression keeps its own type.
	public static func buildExpression<C: View>(_ expression: C) -> C { expression }

	/// an array of views is a repetition — homogeneous, so it stays typed.
	public static func buildExpression<C: View>(_ expression: [C]) -> RepeatedView<C> {
		RepeatedView(expression)
	}

	/// an erased array is a repetition too, and keeps the erasure the caller
	/// already chose by holding one.
	public static func buildExpression(_ expression: [any View]) -> ErasedViews {
		ErasedViews(expression)
	}

	/// `if` with no `else`.
	public static func buildOptional<C: View>(_ component: C?) -> OptionalView<C> {
		OptionalView(component)
	}

	/// the `if` branch of an `if`/`else` or a `switch`.
	public static func buildEither<First: View, Second: View>(first: First) -> EitherView<First, Second> {
		.first(first)
	}

	/// the `else` branch of an `if`/`else` or a `switch`.
	public static func buildEither<First: View, Second: View>(second: Second) -> EitherView<First, Second> {
		.second(second)
	}

	/// `if #available` — the component stands as-is.
	public static func buildLimitedAvailability<C: View>(_ component: C) -> C { component }

	/// a `for` loop — homogeneous, so it repeats without erasure.
	public static func buildArray<C: View>(_ components: [C]) -> RepeatedView<C> {
		RepeatedView(components)
	}
}