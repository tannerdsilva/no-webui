import WebUICore
import Synchronization

/// the client-mode resident runtime: one `EventRouter` per page load (house
/// rule), the boot render that registers handlers, and the synchronous event
/// entry that routes through `await router.handle` under the pump.
///
/// host note: `handleEvent` runs its `Task` via `ClientExecutor.pump()`, which
/// is a no-op on the host — this entry is wasm-only in practice; pure-logic
/// specs exercise `boot()` and the router directly.
public enum ClientRuntime {
	nonisolated(unsafe) private static let counterBox = Mutex(0)
	nonisolated(unsafe) private static let queryBox = Mutex("")
	nonisolated(unsafe) public private(set) static var router = EventRouter()
	nonisolated(unsafe) public private(set) static var bootPageHTML = ""

	private struct SearchRecord: Sendable {
		let name: String
		let region: String
		let ms: Int
	}

	// client-resident dataset: shipped once, filtered + re-rendered in wasm
	// (the websocket stays silent on the hot path).
	private static let searchRecords: [SearchRecord] = [
		SearchRecord(name: "web", region: "us-east-1", ms: 42),
		SearchRecord(name: "api", region: "eu-west-2", ms: 18),
		SearchRecord(name: "search", region: "us-west-2", ms: 61),
		SearchRecord(name: "auth", region: "ap-south-1", ms: 9),
	]

	/// boot the interactive proof page: render under a `RenderContext` so the
	/// `.onClick` handler registers into the resident router. called once per
	/// page load via `webui_init`.
	public static func boot() {
		counterBox.withLock { $0 = 0 }
		// one router per page load: reset clears handlers and the positional id
		// counters so the first registered control is always c0 / e0.
		router.reset()
		let context = RenderContext(router: router)
		bootPageHTML = RenderContext.$current.withValue(context) {
			Div(class: "proof") {
				Div(id: "client-counter", class: "proof__value") {
					Text("\(counterBox.withLock { $0 })")
				}
				Button("increment", id: "proof-inc", type: .button)
					.onClick { _ in
						let next = counterBox.withLock { $0 } + 1
						counterBox.withLock { $0 = next }
						return [FragmentUpdate(
							id: "client-counter",
							html: "<div id=\"client-counter\" class=\"proof__value\">\(next)</div>"
						)]
					}
			}
			.render()
		}
	}

	/// boot the local-search vertical: a search field whose `.onInput` handler
	/// filters the client-resident dataset and re-renders `#search-rows`
	/// entirely in wasm. `webui_init` boots this once per page load; ssr serves
	/// the same markup through the shared view.
	public static func bootSearch() {
		queryBox.withLock { $0 = "" }
		router.reset()
		let context = RenderContext(router: router)
		bootPageHTML = RenderContext.$current.withValue(context) {
			Div(class: "search") {
				Div(class: "search__field") {
					Input(id: "search-input", placeholder: "filter…", type: .text, value: queryBox.withLock { $0 })
						.onInput { event in
							let query = event.data["value"] ?? ""
							queryBox.withLock { $0 = query }
							return [FragmentUpdate(id: "search-rows", html: Self.searchRowsHTML(query: query))]
						}
				}
				Raw(Self.searchRowsHTML(query: queryBox.withLock { $0 }))
			}
			.render()
		}
	}

	/// filter the client-resident dataset and render the rows fragment. the
	/// fragment carries the stable `search-rows` id so the patcher (server or
	/// chamber) replaces the wrapper in place.
	private static func searchRowsHTML(query: String) -> String {
		let needle = query.lowercased()
		let filtered = searchRecords.filter { record in
			needle.isEmpty
				|| record.name.lowercased().hasPrefix(needle)
				|| record.region.lowercased().hasPrefix(needle)
		}
		let rows = filtered.map { record -> [any View] in
			[Text(record.name), Text(record.region), Text("\(record.ms) ms")]
		}
		let table = Table(headers: ["name", "region", "p95"], rows: rows, class: "search__table").render()
		return "<div id=\"search-rows\" class=\"search__rows\">\(table)</div>"
	}

	/// decode an event envelope (`{component, event, data}`), route it through
	/// the resident router, and return the produced fragments. the handler runs
	/// to completion inside one pump cycle (single-threaded cooperative).
	public static func handleEvent(_ jsonText: String) -> [FragmentUpdate] {
		guard let root = try? JSONValue.parse(jsonText),
		      case .object(let dict) = root,
		      let comp = stringField(dict, "component"),
		      let event = stringField(dict, "event") else {
			return []
		}
		var data: [String: String] = [:]
		if case .object(let dataObj)? = dict["data"] {
			for (key, value) in dataObj {
				switch value {
				case .string(let s): data[key] = s
				case .number, .bool: data[key] = value.serialize()
				default: break
				}
			}
		}
		let eventData = EventData(component: ComponentID(comp), event: event, data: data)
		let result = Mutex<[FragmentUpdate]>([])
		Task {
			let updates = await router.handle(eventData)
			result.withLock { $0 = updates }
		}
		ClientExecutor.pump()
		return result.withLock { $0 }
	}

	private static func stringField(_ dict: [String: JSONValue], _ key: String) -> String? {
		guard case .string(let value)? = dict[key] else { return nil }
		return value
	}
}
