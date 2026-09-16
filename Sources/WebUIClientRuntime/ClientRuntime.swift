import Foundation
import WebUICore
import WebUIDesignSystemCore
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
	nonisolated(unsafe) private static let sortBox = Mutex((column: 0, ascending: true))
	nonisolated(unsafe) private static let authBox = Mutex(AuthStateMirror.anonymous)
	nonisolated(unsafe) public private(set) static var router = EventRouter()
	nonisolated(unsafe) public private(set) static var bootPageHTML = ""

	/// the client state store (in-memory backend shipped; the wasm build
	/// swaps a localStorage backend in when the boot envelope requests
	/// persistence — the contract stays the same).
	nonisolated(unsafe) public static var state: any ClientStateStore = InMemoryClientStateStore()

	/// the local/authority sync discipline (p3-t4); the renderToken from the
	/// boot envelope binds it to the page.
	nonisolated(unsafe) public static var sync = ClientSyncCoordinator(renderToken: "")

	/// the observability ring (p3-t5); drained by the transport owner.
	nonisolated(unsafe) public static let telemetry = ClientTelemetry()

	/// the read-only session-presence mirror (advisory ui gating only, d4).
	public static var authMirror: AuthStateMirror {
		authBox.withLock { $0 }
	}

	/// apply the boot authState envelope (non-secret presence + roles).
	public static func applyAuthState(_ envelope: String) {
		if let mirror = AuthStateMirror(envelope: envelope) {
			authBox.withLock { $0 = mirror }
		}
	}

	/// server-directed revocation: flips the mirror to anonymous so ui gating
	/// demotes immediately (the server remains the authority).
	public static func demoteAuth() {
		authBox.withLock { $0 = .anonymous }
	}

	public static func hasRole(_ role: String) -> Bool {
		authBox.withLock { $0.hasRole(role) }
	}

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

	/// prefix index over record names, rebuilt at boot (p5-t3): local-search
	/// keystrokes answer from this trie, not from a linear scan.
	nonisolated(unsafe) public private(set) static var nameIndex = ClientPrefixIndex()

	private static func buildNameIndex() -> ClientPrefixIndex {
		var index = ClientPrefixIndex()
		for record in searchRecords {
			index.insert(record.name)
		}
		return index
	}

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
	/// filters the client-resident dataset, and a `WebUITable` whose typed
	/// `.onSort` handler re-sorts it — both re-rendered entirely in wasm, the
	/// websocket silent on the hot path. `webui_init` boots this once per page
	/// load.
	public static func bootSearch() {
		queryBox.withLock { $0 = "" }
		sortBox.withLock { $0 = (column: 0, ascending: true) }
		router.reset()
		nameIndex = buildNameIndex()
		// the persistence self-proof: with a localStorage backend wired by the
		// boot envelope, this count survives page reloads (each fresh wasm
		// instance reads the previous count through the bridge and increments
		// it). with the in-memory backend it always reads 1.
		let bootCount = Self.persistBootCount()
		let context = RenderContext(router: router)
		bootPageHTML = RenderContext.$current.withValue(context) {
			Div(class: "search") {
				Div(class: "search__field") {
					Input(id: "search-input", placeholder: "filter…", type: .text, value: queryBox.withLock { $0 })
						.onInput { event in
							let query = event.string("value") ?? ""
							queryBox.withLock { $0 = query }
							return [FragmentUpdate(id: "search-rows", html: Self.searchRowsHTML(query: query))]
						}
				}
				Raw(Self.searchRowsHTML(query: queryBox.withLock { $0 }))
				if bootCount > 1 {
					// only rendered when persistence is actually working
					Raw("<div id=\"boot-count\" class=\"search__meta\">boot \(bootCount)</div>")
				}
			}
			.render()
		}
	}

	private static func persistBootCount() -> Int {
		let current: Int
		if case .number(let value)? = state.get("boot.count") {
			current = Int(value)
		} else {
			current = 1
		}
		let next = max(1, current + 1)
		try? state.set("boot.count", .number(Double(next)))
		return next
	}

	/// filter + sort the client-resident dataset into a `WebUITable` render. the
	/// fragment carries the table's own stable `client-table` id so a sort
	/// click can replace the table in place (the input handler targets the
	/// `#search-rows` wrapper instead).
	private static func tableHTML(query: String) -> String {
		let needle = query.lowercased()
		// the name side of the filter answers from the prefix trie; regions
		// stay a linear prefix check (small cardinality).
		let nameMatches: Set<String> = needle.isEmpty ? [] : Set(nameIndex.search(prefix: needle))
		let filtered = searchRecords.filter { record in
			needle.isEmpty
				|| nameMatches.contains(record.name.lowercased())
				|| record.region.lowercased().hasPrefix(needle)
		}
		let (column, ascending) = sortBox.withLock { $0 }
		var records = filtered
		records.sort { a, b in
			let less: Bool
			switch column {
			case 1: less = a.region.localizedCaseInsensitiveCompare(b.region) == .orderedAscending
			case 2: less = a.ms < b.ms
			default: less = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
			}
			return ascending ? less : !less
		}
		let rows = records.map { record -> [any View] in
			[Text(record.name), Text(record.region), Text("\(record.ms) ms")]
		}
		return WebUITable(
			headers: ["name", "region", "p95"],
			rows: rows,
			id: "client-table",
			sortableColumns: [0, 1, 2],
			sort: (column, ascending ? .ascending : .descending)
		)
		.onSort { me, column in
			if sortBox.withLock({ $0.column }) == column {
				sortBox.withLock { $0.ascending.toggle() }
			} else {
				sortBox.withLock { $0 = (column: column, ascending: true) }
			}
			return [me.replace(with: Self.tableHTML(query: queryBox.withLock { $0 }))]
		}
		.render()
	}

	/// the `#search-rows` wrapper around the table (the input handler's patch
	/// target).
	private static func searchRowsHTML(query: String) -> String {
		"<div id=\"search-rows\" class=\"search__rows\">\(tableHTML(query: query))</div>"
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
		var data: [String: JSONValue] = [:]
		if case .object(let dataObj)? = dict["data"] {
			data = dataObj
		}
		let eventData = EventData(component: ComponentID(comp), event: event, data: data)
		let result = Mutex<[FragmentUpdate]>([])
		Task {
			let updates = await router.handle(eventData)
			ClientRuntime.telemetry.emit(.eventHandled(component: comp, event: event, fragmentCount: updates.count))
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
