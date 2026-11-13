import Testing
@testable import WebUI

// regression: arc's `modalHTML()` tuple pack, through the real framework types.
//
// the reported fault is this exact chain — a `Group` holding `if let`, whose
// `Div` pack is `Heading.id(_:)`, `Paragraph`, and `Div { ArcButton, ArcButton }
// .wire(...)`, with `.attribute` + `.aria` + `.aria` on the outer `Div`. adding
// ONE `Paragraph(req.body).data("probe","1")` SIGSEGVs in the report:
//
//   swift_retain < tuple_initializeWithCopy < initializeWithCopy for TupleView
//   < for Div < for ModifiedView < tuple_initializeWithCopy < TupleView.render
//   < Div.render < HTMLAttribute.decorate < ModifiedView.render
//
// measured at both named arc commits (5a8318a4 and e5410222): `ArcButton` stores
// NO closure — `String?`, `String?`, `ComponentID?`, `ClassName`, `ButtonType`,
// `Int?`, `Bool`, `Bool`, `String`. the measured shape is the primary axis
// below; the closure-bearing leaf is a separate discriminator, kept because the
// earlier hypothesis named it and a negative needs its own witness.
//
// the 36-configuration standalone sweep in `.hermes/scratch/tupleview-crash-repro`
// ran clean (both executable and test bundle). this file asks the same question
// with arc's real nesting: the opaque `some View` a modifier returns inside a
// three-element pack that itself sits inside two `ModifiedView` layers.

@Suite("arc modal tuple pack")
struct TupleViewPackCrashRegressionTests {

	// MARK: - fixtures

	struct ConfirmRequest: Sendable {
		let title: String
		let body: String
	}

	/// the heap box the closure-bearing leaf captures, so the closure context
	/// holds a real retain (a small inline string would never retain).
	final class ActionBox: Sendable {
		let note: String
		init(note: String) { self.note = note }
	}

	/// arc's measured `ArcButton` shape at `5a8318a4` / `e5410222`: a generic
	/// struct whose phantom `Views` parameter is pinned to `EmptyView` by the
	/// text init (exactly what `@HTMLComponent`'s generated init does).
	struct ArcButtonLike<Views: View>: View {
		enum Kind: Sendable {
			case label
			case views
		}

		enum ButtonType: String, Sendable {
			case button = "button"
			case submit = "submit"
		}

		var kind: Kind
		var label: String
		var views: Views

		var id: String? = nil
		var component: String? = nil
		var routing: ComponentID? = nil
		var `class`: ClassName
		var type: ButtonType = .button
		var tabIndex: Int? = nil
		var disabled: Bool = false
		var hidden: Bool = false
		var extraAttributes: String = ""

		init(
			_ label: String,
			id: String? = nil,
			component: String? = nil,
			routing: ComponentID? = nil,
			class: ClassName,
			type: ButtonType = .button,
			tabIndex: Int? = nil,
			disabled: Bool = false,
			hidden: Bool = false,
			extraAttributes: String = ""
		) where Views == EmptyView {
			self.kind = .label
			self.label = label
			self.views = EmptyView()
			self.id = id
			self.component = component
			self.routing = routing
			self.class = `class`
			self.type = type
			self.tabIndex = tabIndex
			self.disabled = disabled
			self.hidden = hidden
			self.extraAttributes = extraAttributes
		}

		func render(into buffer: inout HTMLBuffer) {
			var attributes = ""
			if let id { attributes += " id=\"\(htmlEscape(id))\"" }
			if !extraAttributes.isEmpty { attributes += extraAttributes }
			let componentId = routing.map { $0.value } ?? component
			if let componentId, !componentId.isEmpty {
				attributes += " data-component-id=\"\(htmlEscape(componentId))\""
			}
			if !self.class.value.isEmpty {
				attributes += " class=\"\(htmlEscape(self.class.value))\""
			}
			attributes += " type=\"\(type.rawValue)\""
			if let tabIndex { attributes += " tabindex=\"\(tabIndex)\"" }
			if disabled { attributes += " disabled=\"\"" }
			if hidden { attributes += " hidden=\"\"" }

			buffer.beginElement("button", attributes)
			buffer.endOpenTag()
			switch kind {
			case .label: Text(label).render(into: &buffer)
			case .views: views.render(into: &buffer)
			}
			buffer.endElement()
		}
	}

	/// the separate discriminator: a stored `String` beside a stored escaping
	/// closure. arc's source has no such stored closure — this axis exists to
	/// keep the discredited hypothesis falsifiable rather than assumed.
	struct ClosureLeaf: View {
		var id: String?
		var `class`: ClassName
		var extraAttributes: String
		var action: @Sendable () -> Void

		func render(into buffer: inout HTMLBuffer) {
			var attributes = ""
			if let id { attributes += " id=\"\(htmlEscape(id))\"" }
			if !extraAttributes.isEmpty { attributes += extraAttributes }
			if !self.class.value.isEmpty {
				attributes += " class=\"\(htmlEscape(self.class.value))\""
			}
			buffer.beginElement("button", attributes)
			buffer.endOpenTag()
			buffer.appendEscaped("leaf")
			buffer.endElement()
		}
	}

	// MARK: - the chain

	/// (a) the measured shape with no probe modifier — arc's `modalHTML()`.
	func measuredModal(_ confirm: ConfirmRequest?) -> some View {
		Group {
			if let req = confirm {
				Div(id: "modal-overlay", class: "modal-overlay") {
					Div(class: "modal-card") {
						Heading(req.title, level: .h3)
							.id("modal-title")
						Paragraph(req.body)
						Div(class: "modal-actions") {
							ArcButtonLike("Cancel", id: "modal-cancel", component: nil, class: "ghost-btn",
							              extraAttributes: DismissStack().attribute().attributeText)
							ArcButtonLike("Delete", id: "modal-confirm", component: nil, class: "danger-btn")
						}
						.wire("modal")
					}
					.attribute("role", "dialog")
					.aria(.modal(.yes))
					.aria(.labelledby("modal-title"))
				}
			}
		}
	}

	/// (b) the reported edit: one `.data` on the `Paragraph` in the pack.
	func measuredModalWithProbe(_ confirm: ConfirmRequest?) -> some View {
		Group {
			if let req = confirm {
				Div(id: "modal-overlay", class: "modal-overlay") {
					Div(class: "modal-card") {
						Heading(req.title, level: .h3)
							.id("modal-title")
						Paragraph(req.body).data("probe", "1")
						Div(class: "modal-actions") {
							ArcButtonLike("Cancel", id: "modal-cancel", component: nil, class: "ghost-btn",
							              extraAttributes: DismissStack().attribute().attributeText)
							ArcButtonLike("Delete", id: "modal-confirm", component: nil, class: "danger-btn")
						}
						.wire("modal")
					}
					.attribute("role", "dialog")
					.aria(.modal(.yes))
					.aria(.labelledby("modal-title"))
				}
			}
		}
	}

	/// (c) the closure-bearing leaf in the same pack, no modifier.
	func closureModal(_ confirm: ConfirmRequest?, box: ActionBox) -> some View {
		Group {
			if let req = confirm {
				Div(id: "modal-overlay", class: "modal-overlay") {
					Div(class: "modal-card") {
						Heading(req.title, level: .h3)
							.id("modal-title")
						Paragraph(req.body)
						Div(class: "modal-actions") {
							ClosureLeaf(id: "modal-cancel", class: "ghost-btn",
							            extraAttributes: DismissStack().attribute().attributeText,
							            action: { _ = box.note.utf8.count })
							ClosureLeaf(id: "modal-confirm", class: "danger-btn",
							            extraAttributes: "",
							            action: { _ = box.note.utf8.count })
						}
						.wire("modal")
					}
					.attribute("role", "dialog")
					.aria(.modal(.yes))
					.aria(.labelledby("modal-title"))
				}
			}
		}
	}

	/// (d) the closure-bearing leaf with the reported edit.
	func closureModalWithProbe(_ confirm: ConfirmRequest?, box: ActionBox) -> some View {
		Group {
			if let req = confirm {
				Div(id: "modal-overlay", class: "modal-overlay") {
					Div(class: "modal-card") {
						Heading(req.title, level: .h3)
							.id("modal-title")
						Paragraph(req.body).data("probe", "1")
						Div(class: "modal-actions") {
							ClosureLeaf(id: "modal-cancel", class: "ghost-btn",
							            extraAttributes: DismissStack().attribute().attributeText,
							            action: { _ = box.note.utf8.count })
							ClosureLeaf(id: "modal-confirm", class: "danger-btn",
							            extraAttributes: "",
							            action: { _ = box.note.utf8.count })
						}
						.wire("modal")
					}
					.attribute("role", "dialog")
					.aria(.modal(.yes))
					.aria(.labelledby("modal-title"))
				}
			}
		}
	}

	// MARK: - the actor boundary

	/// arc's `modalHTML()` is an `actor` method (`AppState.modalHTML() ->
	/// some WebUI.View`) whose result the test awaits. the isolation boundary
	/// is part of the reported shape, so the same chains also run from inside
	/// an actor — otherwise "method on an actor" is an unexercised difference.
	actor ModalHost {
		func measuredModal(_ confirm: ConfirmRequest?) -> some View {
			Group {
				if let req = confirm {
					Div(id: "modal-overlay", class: "modal-overlay") {
						Div(class: "modal-card") {
							Heading(req.title, level: .h3)
								.id("modal-title")
							Paragraph(req.body)
							Div(class: "modal-actions") {
								ArcButtonLike("Cancel", id: "modal-cancel", component: nil, class: "ghost-btn",
								              extraAttributes: DismissStack().attribute().attributeText)
								ArcButtonLike("Delete", id: "modal-confirm", component: nil, class: "danger-btn")
							}
							.wire("modal")
						}
						.attribute("role", "dialog")
						.aria(.modal(.yes))
						.aria(.labelledby("modal-title"))
					}
				}
			}
		}

		func measuredModalWithProbe(_ confirm: ConfirmRequest?) -> some View {
			Group {
				if let req = confirm {
					Div(id: "modal-overlay", class: "modal-overlay") {
						Div(class: "modal-card") {
							Heading(req.title, level: .h3)
								.id("modal-title")
							Paragraph(req.body).data("probe", "1")
							Div(class: "modal-actions") {
								ArcButtonLike("Cancel", id: "modal-cancel", component: nil, class: "ghost-btn",
								              extraAttributes: DismissStack().attribute().attributeText)
								ArcButtonLike("Delete", id: "modal-confirm", component: nil, class: "danger-btn")
							}
							.wire("modal")
						}
						.attribute("role", "dialog")
						.aria(.modal(.yes))
						.aria(.labelledby("modal-title"))
					}
				}
			}
		}
	}

	// MARK: - the assertions

	/// the structural attributes the overlay depends on, on every variant.
	func expectOverlayContract(_ html: String, sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(!html.isEmpty, sourceLocation: sourceLocation)
		#expect(html.contains("role=\"dialog\""), sourceLocation: sourceLocation)
		#expect(html.contains("aria-modal=\"true\""), sourceLocation: sourceLocation)
		#expect(html.contains("aria-labelledby=\"modal-title\""), sourceLocation: sourceLocation)
		#expect(html.contains("id=\"modal-title\""), sourceLocation: sourceLocation)
		#expect(html.contains("data-component-id=\"modal\""), sourceLocation: sourceLocation)
		#expect(html.contains("data-event=\"click\""), sourceLocation: sourceLocation)
		#expect(html.contains("data-dismiss"), sourceLocation: sourceLocation)
		#expect(html.contains("id=\"modal-cancel\""), sourceLocation: sourceLocation)
		#expect(html.contains("id=\"modal-confirm\""), sourceLocation: sourceLocation)
	}

	@Test("the measured ArcButton shape renders with and without the probe modifier")
	func measuredShape() async {
		let req = ConfirmRequest(
			title: "Delete conversation?",
			body: "The chat “Quarterly planning” will be permanently deleted. This cannot be undone.")

		let baseline = measuredModal(req).markup.html
		let probed = measuredModalWithProbe(req).markup.html

		expectOverlayContract(baseline)
		expectOverlayContract(probed)

		#expect(!baseline.contains("data-probe"))
		#expect(probed.contains("data-probe=\"1\""))
		// the modifier must settle on the element that opens inside it, not fall
		// back to a fragment: `Paragraph` emits `<p>`, so the attribute is on it.
		#expect(probed.contains("<p data-probe=\"1\">"))

		// the same two renders from inside an actor, the shape arc's method has.
		let host = ModalHost()
		let actorBaseline = await host.measuredModal(req).markup.html
		let actorProbed = await host.measuredModalWithProbe(req).markup.html

		expectOverlayContract(actorBaseline)
		expectOverlayContract(actorProbed)
		#expect(!actorBaseline.contains("data-probe"))
		#expect(actorProbed.contains("<p data-probe=\"1\">"))
	}

	@Test("the closure-bearing leaf renders with and without the probe modifier")
	func closureShape() {
		let req = ConfirmRequest(
			title: "Delete conversation?",
			body: "The chat “Quarterly planning” will be permanently deleted. This cannot be undone.")
		let box = ActionBox(note: String(repeating: "n", count: 32))

		let baseline = closureModal(req, box: box).markup.html
		let probed = closureModalWithProbe(req, box: box).markup.html

		expectOverlayContract(baseline)
		expectOverlayContract(probed)

		#expect(!baseline.contains("data-probe"))
		#expect(probed.contains("data-probe=\"1\""))
		#expect(probed.contains("<p data-probe=\"1\">"))
	}

	@Test("the pack copies as a value before it renders")
	func copiedPack() {
		let req = ConfirmRequest(
			title: "Delete conversation?",
			body: "The chat “Quarterly planning” will be permanently deleted. This cannot be undone.")

		// force `initializeWithCopy` of the whole pack twice — the glue the arc
		// traceback dies in (`tuple_initializeWithCopy` -> `TupleView` -> `Div`
		// -> `ModifiedView`), independent of any one render's inlining.
		let first = measuredModalWithProbe(req)
		let second = first
		let third = second
		let html = third.markup.html

		expectOverlayContract(html)
		#expect(html.contains("data-probe=\"1\""))
	}
}
