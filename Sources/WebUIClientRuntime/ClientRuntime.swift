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
	nonisolated(unsafe) public private(set) static var router = EventRouter()
	nonisolated(unsafe) public private(set) static var bootPageHTML = ""

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
