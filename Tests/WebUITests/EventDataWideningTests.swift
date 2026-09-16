import Testing
import Synchronization
import WebUI
import WebUICore

// p3-t1: `EventData.data` widened from `[String: String]` to
// `[String: JSONValue]` — the wire bytes are unchanged; typed values (numbers,
// booleans, nested structures) now ride through instead of being rejected or
// string-coerced. accessors (`string(_:)`/`number(_:)`) keep handlers terse.
struct EventDataWideningTests {
	@Test("event payloads carry typed json values end to end")
	func typedPayloadValues() async throws {
		let router = EventRouter()
		let context = RenderContext(router: router)
		let payload: [String: JSONValue] = [
			"query": "swift", "page": 2, "active": true, "tags": ["a", "b"],
		]
		let captured = Mutex<EventData?>(nil)
		_ = RenderContext.$current.withValue(context) {
			Button("go", type: .button).onClick { event in
				captured.withLock { $0 = event }
				return []
			}
			.render()
		}
		await router.handle(EventData(component: "c0", event: "click", data: payload))
		let event = try #require(captured.withLock { $0 })
		#expect(event.data["query"] == JSONValue.string("swift"))
		#expect(event.data["page"] == JSONValue.number(2))
		#expect(event.data["active"] == JSONValue.bool(true))
		#expect(event.data["tags"] == JSONValue.array([.string("a"), .string("b")]))
		#expect(event.string("query") == "swift")
		#expect(event.number("page") == 2)
		#expect(event.string("missing") == nil)
	}

	@Test("WSIncoming decodes typed data values (no rejection)")
	func wsIncomingTypedData() throws {
		let msg = try WSIncoming(jsonText: #"{"type":"event","component":"c0","event":"input","data":{"value":"a","page":2,"active":true},"token":"t"}"#)
		guard case .event(_, _, let data, let token) = msg else {
			Issue.record("expected an event message")
			return
		}
		#expect(data["value"] == JSONValue.string("a"))
		#expect(data["page"] == JSONValue.number(2))
		#expect(data["active"] == JSONValue.bool(true))
		#expect(token == "t")
	}

	@Test("json literal conformances feed typed dictionaries")
	func literalConformances() {
		let data: [String: JSONValue] = ["value": "a", "page": 50]
		let event = EventData(component: "c0", event: "input", data: data)
		#expect(event.string("value") == "a")
		#expect(event.number("page") == 50)
	}
}
