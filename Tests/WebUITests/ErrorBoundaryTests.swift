import Foundation
import Synchronization
import Testing
import WebUI
import WebUIServer

// error boundaries (W4.2; G9, C3).
//
// W0.3 made a throwing handler answer with `HandlerOutcome.fail` and let a
// component register its own fallback fragments — but a whole region had no
// way to offer one fallback for all of its controls. `ErrorBoundary` records
// every component id its subtree registers at render time, and a later
// failure of any of them patches the boundary's wrapper element (replaced by
// id) with the rendered fallback.

/// a control whose click handler always throws, minting its own component id
/// exactly as `.onClick` does.
private struct ThrowingControl: View {
	let label: String
	var captured: IDBox? = nil
	func render(into buffer: inout HTMLBuffer) {
		guard var context = RenderContext.current else { return }
		let id = context.nextComponentID()
		captured?.set(label, id)
		context.register(outcome: { _ -> HandlerOutcome in throw BoundaryError.failed }, for: id)
		buffer.append("<button data-component-id=\"\(id.value)\" data-event=\"click\">\(label)</button>")
	}
}

/// a capture box for the ids a render mints, so the tests dispatch on the
/// exact ids the boundary saw rather than assuming the counter's order.
private final class IDBox: Sendable {
	private let state = Mutex<[String: ComponentID]>([:])
	func set(_ key: String, _ id: ComponentID) {
		state.withLock { $0[key] = id }
	}
	func get(_ key: String) -> ComponentID {
		state.withLock { $0[key]! }
	}
}

private enum BoundaryError: Error {
	case failed
}

/// a page with one control inside a boundary and one outside it.
private struct BoundaryPage: View {
	let box: IDBox
	func render(into buffer: inout HTMLBuffer) {
		ErrorBoundary(content: {
			ThrowingControl(label: "inside", captured: box)
		}, fallback: {
			Text("inside recovered")
		}).render(into: &buffer)
		ThrowingControl(label: "outside", captured: box).render(into: &buffer)
	}
}

/// the same page built through the `.errorBoundary` modifier.
private struct ModifierPage: View {
	let box: IDBox
	func render(into buffer: inout HTMLBuffer) {
		ThrowingControl(label: "inside", captured: box)
			.errorBoundary {
				Text("modifier recovered")
			}
			.render(into: &buffer)
	}
}

@Suite("error boundaries")
struct ErrorBoundaryTests {

	@Test("a failing handler inside a boundary patches the fallback in")
	func failingHandlerInsideBoundaryPatchesFallback() async {
		let router = EventRouter()
		let box = IDBox()
		let html = RenderContext.$current.withValue(RenderContext(router: router)) {
			BoundaryPage(box: box).renderThroughBuffer()
		}

		// the boundary wraps its content in a patchable element.
		#expect(html.contains("<div id=\"e0\">"), "got \(html)")

		let outcome = await router.dispatch(EventData(component: box.get("inside"), event: "click"))
		#expect(outcome.isFailure)
		guard case .fail(_, _, let fallback) = outcome else {
			Issue.record("expected a failure outcome")
			return
		}
		// the control's own fallback is the boundary's: the wrapper element
		// is replaced by the rendered fallback.
		#expect(fallback.count == 1)
		#expect(fallback.first?.id == "e0", "got \(fallback)")
		#expect(fallback.first?.html.contains("inside recovered") == true)
	}

	@Test("a failing handler outside a boundary does not patch anything")
	func failingHandlerOutsideBoundaryDoesNot() async {
		let router = EventRouter()
		let box = IDBox()
		RenderContext.$current.withValue(RenderContext(router: router)) {
			_ = BoundaryPage(box: box).renderThroughBuffer()
		}

		let outcome = await router.dispatch(EventData(component: box.get("outside"), event: "click"))
		#expect(outcome.isFailure)
		// the page is told, but nothing is invented to fill the gap.
		#expect(outcome.fragments.isEmpty)
		#expect(outcome.wireMessages.count == 1)
	}

	@Test("the errorBoundary modifier wires a boundary over the view")
	func errorBoundaryModifierWires() async {
		let router = EventRouter()
		let box = IDBox()
		RenderContext.$current.withValue(RenderContext(router: router)) {
			_ = ModifierPage(box: box).renderThroughBuffer()
		}

		let outcome = await router.dispatch(EventData(component: box.get("inside"), event: "click"))
		guard case .fail(_, _, let fallback) = outcome else {
			Issue.record("expected a failure outcome")
			return
		}
		#expect(fallback.first?.html.contains("modifier recovered") == true)
	}

	@Test("a boundary is inert without a render context — content renders plain")
	func boundaryInertWithoutContext() {
		// no routing context, so there is nothing to register against and no
		// wrapper element to patch — the content renders exactly as it would
		// without the boundary.
		let html = ErrorBoundary(
			content: { Text("plain content") },
			fallback: { Text("never") }
		).renderThroughBuffer()
		#expect(html == "plain content")
	}
}

#if !os(Linux)

@Suite("render failure over the wire", .serialized)
struct RenderFailureWireTests {

	private enum RenderBoom: Error {
		case exploded
	}

	@Test("a throwing render answers 500 with the host's error page")
	func throwingRenderAnswers500() async throws {
		let router = Router {
			Route.get("/") { _ in HTTPResponse(body: .html("ok")) }
			Route.page("/boom") { (_: HTTPRequest) -> Text in
				throw RenderBoom.exploded
			}
		}
		var config = WebUIServerConfig()
		config.onRenderFailure = { error in
			"<html><body>the page broke: \(error)</body></html>"
		}
		try await withRouterServer(router, portBase: 40_000, config: config) { port in
			let (_, okStatus) = try await get("http://127.0.0.1:\(port)/")
			#expect(okStatus == 200)
			let (body, status) = try await get("http://127.0.0.1:\(port)/boom")
			#expect(status == 500, "got \(status)")
			#expect(body.contains("the page broke"), "got \(body)")
		}
	}

	@Test("without onRenderFailure a failed render answers a plain-text 500")
	func failedRenderStillAnswers500() async throws {
		let router = Router {
			Route.get("/") { _ in HTTPResponse(body: .html("ok")) }
			Route.page("/boom") { (_: HTTPRequest) -> Text in
				throw RenderBoom.exploded
			}
		}
		try await withRouterServer(router, portBase: 40_000) { port in
			let (body, status) = try await get("http://127.0.0.1:\(port)/boom")
			#expect(status == 500, "got \(status)")
			#expect(body.contains("failed to render"), "got \(body)")
		}
	}
}

#endif
