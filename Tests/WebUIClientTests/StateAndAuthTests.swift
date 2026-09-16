import Testing
import Synchronization
import WebUICore
@testable import WebUIClientRuntime

// p3-t2: ClientStateStore contract + in-memory backend.
struct ClientStateStoreTests {
	@Test("set/get/remove round-trip flat paths")
	func basicRoundTrip() throws {
		let store = InMemoryClientStateStore()
		#expect(store.get("search") == nil)
		try store.set("search.query", .string("swift"))
		#expect(store.get("search.query") == .string("swift"))
		store.remove("search.query")
		#expect(store.get("search.query") == nil)
	}

	@Test("subscribers hear exact and prefix paths, not unrelated ones")
	func subscriptions() throws {
		let store = InMemoryClientStateStore()
		let heard = Mutex<[String]>([])
		let id = store.subscribe("table", { value in
			heard.withLock { $0.append(value?.serialize() ?? "nil") }
		})
		try store.set("table.sort", .string("region"))
		_ = try store.set("table", .string("rows"))
		try store.set("html.title", .string("x"))
		let snapshot = heard.withLock { $0 }
		#expect(snapshot == ["\"region\"", "\"rows\""])
		store.unsubscribe(id)
		try store.set("table.sort", .string("ms"))
		#expect(heard.withLock { $0 }.count == 2)
	}

	@Test("prototype-pollution segments are rejected on set")
	func prototypeDenied() {
		let store = InMemoryClientStateStore()
		#expect(throws: ClientStateError.self) {
			try store.set("a.__proto__.polluted", .bool(true))
		}
		#expect(throws: ClientStateError.self) {
			try store.set("constructor", .bool(true))
		}
	}

	@Test("the runtime exposes the store for the vertical")
	func runtimeStore() throws {
		try ClientRuntime.state.set("runtime.key", .string("v"))
		#expect(ClientRuntime.state.get("runtime.key") == .string("v"))
	}
}

// p3-t6: authState mirror — advisory presence/roles, server-directed demotion
// (the mirror is a shared global; the two tests must not interleave).
@Suite(.serialized)
struct AuthStateMirrorTests {
	@Test("anonymous by default; envelope applies presence + roles")
	func envelopeParse() {
		#expect(AuthStateMirror.anonymous.sessionPresent == false)
		#expect(AuthStateMirror.anonymous.hasRole("admin") == false)

		ClientRuntime.demoteAuth()
		#expect(ClientRuntime.authMirror.sessionPresent == false)

		ClientRuntime.applyAuthState(#"{"sessionPresent":true,"roles":["member","admin"]}"#)
		#expect(ClientRuntime.authMirror.sessionPresent == true)
		#expect(ClientRuntime.authMirror.hasRole("admin"))
		#expect(ClientRuntime.hasRole("member"))
		#expect(!ClientRuntime.hasRole("editor"))

		// malformed envelopes are ignored (mirror stays).
		ClientRuntime.applyAuthState("not json")
		#expect(ClientRuntime.authMirror.sessionPresent == true)
	}

	@Test("server-directed revocation demotes the mirror")
	func demotionOnRevocation() {
		ClientRuntime.applyAuthState(#"{"sessionPresent":true,"roles":["admin"]}"#)
		#expect(ClientRuntime.hasRole("admin"))
		ClientRuntime.demoteAuth()
		#expect(ClientRuntime.authMirror == .anonymous)
		#expect(!ClientRuntime.hasRole("admin"))
	}
}
