import WebUICore

/// the baseline view both hosts render for the hydration gate. built from
/// WebUICore primitives, layouts, and icons only (no design-system targets,
/// no rawdog) so the wasm client links nothing beyond the render core. the
/// p2 vertical enables live handlers on this page; the p1 shape proves
/// byte-identity across hosts for the same state.
public struct HydrationViewModel: Sendable, Equatable {
	public var count: Int
	public var query: String
	public init(count: Int = 3, query: String = "swift") {
		self.count = count
		self.query = query
	}
}

public struct HydrationView: View {
	public let model: HydrationViewModel
	public init(model: HydrationViewModel = HydrationViewModel()) {
		self.model = model
	}

	public func render() -> String {
		Div(class: "smoke") {
			Header(class: "smoke__header") {
				Heading("Hydration Gate — client render core", level: .h1)
				Div(class: "smoke__subtitle") {
					Text("the same WebUICore render() output on both hosts.")
				}
			}
			Main(class: "smoke__content") {
				Div(class: "smoke__card") {
					Heading("Counter", level: .h3)
					Div(id: "counter-value", class: "counter-value") {
						Text("\(model.count)")
					}
					Span(class: "pill") {
						WebUIIcon(.star, size: .small)
						Text("same bytes")
					}
				}
				Div(class: "smoke__card") {
					Heading("Search (p2 vertical)", level: .h3)
					Input(id: "search", placeholder: "filter…", type: .text, value: model.query)
				}
				Div(class: "smoke__card") {
					Heading("Table (primitives)", level: .h3)
					Table(
						headers: ["name", "region", "p95"],
						rows: [
							[Text("web"), Text("us-east-1"), Text("42 ms")],
							[Text("api"), Text("eu-west-2"), Text("18 ms")]
						]
					)
				}
			}
		}
		.render()
	}
}
