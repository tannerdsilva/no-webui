import Logging
import Synchronization

// MARK: - error boundary

/// a container that renders `content` and answers a failing descendant
/// handler with `fallback` rendered in the content's place (W4.2).
///
/// the mechanism is render-time: while `content` renders, every component id
/// the subtree registers is recorded, and the boundary then registers the
/// fallback for exactly those ids. when one of their handlers later throws,
/// the router's ``HandlerOutcome/fail(code:message:fallback:)`` path (W0.3)
/// patches the boundary's wrapper element — a `div` carrying a stable id
/// minted per render — with the rendered fallback. a failing handler outside
/// any boundary keeps the pre-W4.2 behaviour: the error frame fires and the
/// page keeps whatever it had.
///
/// a nested boundary claims its own subtree: ids are recorded against the
/// innermost active boundary only, so a failure inside an inner boundary
/// patches the inner fallback and the outer one answers nothing it does not
/// surround. stable-id controls (`controlAttributes`, tables, charts) are
/// covered like any other control — their registration is recorded too.
///
/// what this boundary is NOT is a trap boundary. a swift trap
/// (`precondition`, a force unwrap, an out-of-bounds index) cannot be caught
/// in-process — no view or server layer here pretends otherwise, and the
/// limit is recorded in `STABILITY.md`.
public struct ErrorBoundary<Content: View, Fallback: View>: View {
	public let content: Content
	public let fallback: Fallback

	// single-view closures, not `@ViewBuilder`: this package's `ViewBuilder`
	// is array-shaped (its `buildExpression` wraps every view into
	// `[any View]`), so a builder-returned `Content: View` can never be
	// inferred from a single view expression — the same constraint `Route.page`
	// documents. a multi-view subtree is composed as one view (`VStack { ... }`).
	public init(content: () -> Content, fallback: () -> Fallback) {
		self.content = content()
		self.fallback = fallback()
	}

	public func render(into buffer: inout HTMLBuffer) {
		guard var context = RenderContext.current else {
			BoundaryLog.log.warning("ErrorBoundary used without RenderContext. Wrap your render call in RenderContext.$current.withValue(...). The fallback will not fire.")
			content.render(into: &buffer)
			return
		}
		// the wrapper a failure replaces, by element id. minted through the
		// element counter so a re-render of the same page mints the same id
		// and the engine's replace-by-id always finds it.
		let elementID = context.nextElementID().value
		let record = ErrorBoundaryRecord(elementID: elementID)
		var scoped = context
		scoped.boundary = record
		RenderContext.$current.withValue(scoped) {
			buffer.append("<div id=\"\(htmlEscape(elementID))\">")
			content.render(into: &buffer)
			buffer.append("</div>")
		}
		// the fallback renders outside the boundary scope, so ids its own
		// controls mint are not recorded against this boundary.
		let fallbackHTML = fallback.markup.html
		let updates = [FragmentUpdate(id: elementID, html: fallbackHTML)]
		let registration: EventHandler = { _ in updates }
		for componentID in record.componentIDs() {
			context.register(fallback: registration, for: componentID)
		}
	}
}

/// the capability's first real conformer: a boundary can supply a fallback
/// for the subtree it guards.
extension ErrorBoundary: Recoverable {}

// MARK: - the modifier

public extension View {
	/// guard this view's interactive subtree with an error boundary: a failing
	/// handler inside renders `fallback` in this view's place.
	func errorBoundary<V: View>(_ fallback: () -> V) -> some View {
		ErrorBoundary(content: { self }, fallback: fallback)
	}
}

// MARK: - the logger

/// the boundary's logger, parked on a non-generic type: a generic
/// `ErrorBoundary` cannot hold a `static let` of its own.
private enum BoundaryLog {
	static let log = Logger(label: "webui.boundary")
}

// MARK: - render-time record

/// the accumulation a boundary makes while its content renders: every
/// component id its subtree registered, and the wrapper element a failure
/// replaces. single render pass, but `Mutex`-backed like the rest of the
/// router state so the type is provably `Sendable` without `@unchecked`.
final class ErrorBoundaryRecord: Sendable {
	let elementID: String
	private let state = Mutex<[ComponentID]>([])

	init(elementID: String) {
		self.elementID = elementID
	}

	func record(_ componentID: ComponentID) {
		state.withLock { $0.append(componentID) }
	}

	func componentIDs() -> [ComponentID] {
		state.withLock { $0 }
	}
}
