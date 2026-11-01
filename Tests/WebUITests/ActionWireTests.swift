import Testing
import Synchronization
import WebUI

// slice 5a: the action wire identity. a family names the control kind, slot 0
// names the verb (§5.2), and `ActionKey` is a total codec (§5.3) — so the
// attribute the view emits and the value the handler receives are one string,
// decoded once, at the trust boundary.

// the fixture the plan names in §4.2: it exists to prove a malformed wire id is
// dropped rather than dispatched, and that a payload survives the wire.
private enum FixtureAction: Action {
	case open
	case edit(String)
	case delete(String)

	static let family = "fixture"

	var parts: [ActionPart] {
		switch self {
		case .open: return []
		case .edit(let value): return [ActionPart("edit"), ActionPart(value)]
		case .delete(let value): return [ActionPart("delete"), ActionPart(value)]
		}
	}

	init?(key: ActionKey, event: EventData) {
		guard key.family == Self.family else { return nil }
		guard let verb = key.parts.first?.decoded else {
			guard key.parts.isEmpty else { return nil }
			self = .open
			return
		}
		switch verb {
		case "edit", "delete":
			guard key.parts.count == 2, let value = key.parts[1].decoded else { return nil }
			self = verb == "edit" ? .edit(value) : .delete(value)
		default:
			return nil
		}
	}
}

private func fragments(_ id: String) -> [FragmentUpdate] {
	[FragmentUpdate(id: id, html: "<span>\(id)</span>")]
}

extension WebUITestRoot {
	@Suite("action wire", .serialized)
	struct ActionWireTests {
		// MARK: - the codec

		@Test("a payload-bearing wire id round-trips its family and every slot")
		func roundTripsSlots() throws {
			let value = "conn/1+ünïcode"
			let key = ActionKey(FixtureAction.family, [ActionPart("edit"), ActionPart(value)])
			let wireID = key.wireID

			#expect(wireID.hasPrefix("fixture~"))
			#expect(wireID.split(separator: ActionKey.separator).count == 3)
			// base64url, not standard base64: neither character the value carries
			// (`/`, `+`) can leak into the id, and neither can collide with `~`.
			#expect(!wireID.contains("/"))
			#expect(!wireID.contains("+"))

			let decoded = try #require(ActionKey(wireID: wireID))
			#expect(decoded == key)
			#expect(decoded.family == "fixture")
			#expect(decoded.parts.map(\.decoded) == ["edit", value])
		}

		@Test("a payload-free wire id is its family, byte for byte")
		func payloadFreeIdentity() throws {
			// the ids the app spells today: an exact-id dispatch keeps routing them
			// unchanged, which is what §11 buys.
			#expect(ActionKey("storage-edit").wireID == "storage-edit")
			#expect(FixtureAction.open.key.wireID == "fixture")

			let decoded = try #require(ActionKey(wireID: "storage-edit"))
			#expect(decoded.family == "storage-edit")
			#expect(decoded.parts.isEmpty)
		}

		@Test("an empty slot round-trips through the dot sentinel")
		func emptySlotSentinel() throws {
			let part = ActionPart("")
			#expect(part.encoded == ".")
			#expect(part.decoded == "")

			let key = ActionKey(FixtureAction.family, [ActionPart("edit"), part])
			#expect(key.wireID.hasSuffix("~."))
			let decoded = try #require(ActionKey(wireID: key.wireID))
			#expect(decoded == key)
			#expect(decoded.parts.map(\.decoded) == ["edit", ""])
		}

		@Test("a slot whose bytes are not utf8 has no value")
		func undecodableSlot() throws {
			// `_w` is base64url for the single byte 0xFF, which is not utf8.
			let key = try #require(ActionKey(wireID: "fixture~_w"))
			#expect(key.parts.count == 1)
			#expect(key.parts[0].decoded == nil)
		}

		@Test("a malformed wire id decodes to nil")
		func malformedWireID() {
			#expect(ActionKey(wireID: "") == nil)
			#expect(ActionKey(wireID: "~a") == nil)
			#expect(ActionKey(wireID: "a~~b") == nil)
			#expect(ActionKey(wireID: "a~") == nil)
		}

		// MARK: - dispatch

		@Test("dispatch decodes a wire id and runs the typed handler")
		func dispatchDecodesPayload() async throws {
			let router = EventRouter()
			let action = FixtureAction.edit("conn-1")
			let seen = Mutex<FixtureAction?>(nil)

			router.on(FixtureAction.self) { received, _ in
				seen.withLock { $0 = received }
				return fragments("row-1")
			}

			let outcome = await router.dispatch(
				EventData(component: ComponentID(action.key.wireID), event: .click)
			)

			#expect(seen.withLock { $0 } == action)
			#expect(outcome.fragments.map(\.id) == ["row-1"])
		}

		@Test("a payload-free family dispatches through the family route too")
		func dispatchPayloadFree() async throws {
			let router = EventRouter()
			let seen = Mutex<FixtureAction?>(nil)

			router.on(FixtureAction.self) { received, _ in
				seen.withLock { $0 = received }
				return []
			}

			_ = await router.dispatch(EventData(component: ComponentID(FixtureAction.open.key.wireID), event: .click))
			#expect(seen.withLock { $0 } == .open)
		}

		@Test("the family registration belongs to the session it was made in")
		func dispatchRespectsSession() async throws {
			let router = EventRouter()
			let page = RenderSessionID("page")
			let seen = Mutex(0)

			router.on(FixtureAction.self, in: page) { _, _ in
				seen.withLock { $0 += 1 }
				return []
			}
			let action = FixtureAction.edit("conn-1")

			_ = await router.dispatch(EventData(component: ComponentID(action.key.wireID), event: .click), in: .default)
			#expect(seen.withLock { $0 } == 0)

			_ = await router.dispatch(EventData(component: ComponentID(action.key.wireID), event: .click), in: page)
			#expect(seen.withLock { $0 } == 1)
		}

		@Test("an exact component id wins over the family route")
		func exactIDPrecedence() async {
			let router = EventRouter()
			let action = FixtureAction.edit("conn-1")
			let wireID = ComponentID(action.key.wireID)
			let plain = Mutex(0)
			let family = Mutex(0)

			router.register({ _ in
				plain.withLock { $0 += 1 }
				return fragments("plain")
			}, for: wireID)
			router.on(FixtureAction.self) { _, _ in
				family.withLock { $0 += 1 }
				return fragments("family")
			}

			let outcome = await router.dispatch(EventData(component: wireID, event: .click))

			#expect(plain.withLock { $0 } == 1)
			#expect(family.withLock { $0 } == 0)
			#expect(outcome.fragments.map(\.id) == ["plain"])
		}

		@Test("an unknown family routes nowhere")
		func unknownFamily() async {
			let router = EventRouter()
			let invoked = Mutex(0)

			router.on(FixtureAction.self) { _, _ in
				invoked.withLock { $0 += 1 }
				return fragments("family")
			}

			let outcome = await router.dispatch(
				EventData(component: "other~edit~Y29ubi0x", event: .click)
			)

			#expect(outcome.fragments.isEmpty)
			#expect(invoked.withLock { $0 } == 0)
		}

		@Test("a known family with an undecodable payload is dropped, not dispatched")
		func undecodablePayload() async {
			let router = EventRouter()
			let invoked = Mutex(0)

			router.on(FixtureAction.self) { _, _ in
				invoked.withLock { $0 += 1 }
				return fragments("family")
			}

			// the family is registered; the slots do not split (a trailing empty
			// segment), so the frame is one this server could not have minted.
			let outcome = await router.dispatch(
				EventData(component: "fixture~edit~", event: .click)
			)

			#expect(outcome.fragments.isEmpty)
			#expect(invoked.withLock { $0 } == 0)
		}

		@Test("a family registration is one handler in the session table")
		func familyRegistrationCounts() {
			let router = EventRouter()
			let page = RenderSessionID("page")
			#expect(router.handlerCount(in: page) == 0)

			router.on(FixtureAction.self, in: page) { _, _ in [] }
			#expect(router.handlerCount(in: page) == 1)
			#expect(router.handlerCount == 1)

			// the family key is stable, so a second registration overwrites rather
			// than growing the table — the same contract an exact id has.
			router.on(FixtureAction.self, in: page) { _, _ in [] }
			#expect(router.handlerCount(in: page) == 1)
		}

		// MARK: - rendering

		@Test("View.action emits the wire identity and registers nothing")
		func viewActionRendersOnly() {
			let router = EventRouter()
			let context = RenderContext(router: router)
			let action = FixtureAction.edit("conn/1+ü")

			let html = RenderContext.$current.withValue(context) {
				Div { Text("row") }.action(action).markup.html
			}

			#expect(html.contains("data-component-id=\"\(action.key.wireID)\""), "got: \(html)")
			#expect(html.contains("data-event=\"click\""), "got: \(html)")
			#expect(router.handlerCount == 0, "rendering is a pure function — registration is the router's job")
		}

		@Test("View.action takes any event in the deck's vocabulary")
		func viewActionEvent() {
			let action = FixtureAction.edit("conn-1")
			let html = Div { Text("q") }.action(action, on: .input).markup.html
			#expect(html.contains("data-event=\"input\""), "got: \(html)")
		}
	}
}
