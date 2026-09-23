import Testing
import WebUI
import WebUIDesignSystem

// MARK: - WebUIButton onTap

@Suite("WebUIButton onTap", .serialized)
struct WebUIButtonOnTapTests {
	@Test("onTap self-wires under the stable id and registers the handler")
	func selfWires() {
		let router = EventRouter()
		let handler: EventHandler = { _ in [] }
		let html = renderIn(router) {
			WebUIButton("Go", variant: .primary, id: "btn-go", onTap: handler)
		}
		#expect(html.contains("data-component-id=\"btn-go\""))
		#expect(html.contains("data-event=\"click\""))
		#expect(router.handlerCount == 1)
	}

	@Test("nil onTap keeps the static button (backward compatible)")
	func staticByDefault() {
		let router = EventRouter()
		let html = renderIn(router) {
			WebUIButton("Go", variant: .primary, id: "btn-go")
		}
		#expect(!html.contains("data-component-id"))
		#expect(router.handlerCount == 0)
	}

	@Test("a context-free re-render re-emits the anchor without re-registering")
	func reRenderSurvives() {
		let router = EventRouter()
		let handler: EventHandler = { _ in [] }
		let first = renderIn(router) {
			WebUIButton("Go", id: "btn-go", onTap: handler)
		}
		// the handler-producing re-render has no RenderContext (the page-build
		// registration persists), so the anchor must re-emit identically.
		let second = renderSansContext {
			WebUIButton("Go", id: "btn-go", onTap: handler)
		}
		#expect(first.contains("data-component-id=\"btn-go\""))
		#expect(second.contains("data-component-id=\"btn-go\""))
		#expect(router.handlerCount == 1)
	}

	@Test("onTap without id mints a component id from the render context")
	func mintsWhenIdNil() {
		let router = EventRouter()
		let handler: EventHandler = { _ in [] }
		let html = renderIn(router) {
			WebUIButton("Go", onTap: handler)
		}
		#expect(html.contains("data-component-id=\"c0\""))
		#expect(router.handlerCount == 1)
	}

	// helpers
	private func renderIn<R: View>(_ router: EventRouter, _ build: () -> R) -> String {
		let ctx = RenderContext(router: router)
		return RenderContext.$current.withValue(ctx) { build().render() }
	}

	private func renderSansContext<R: View>(_ build: () -> R) -> String {
		build().render()
	}
}
