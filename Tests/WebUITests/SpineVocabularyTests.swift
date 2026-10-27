import Synchronization
import Testing
import WebUI
import WebUIServer

// MARK: - stage 0 vocabulary
//
// the value types the multi-tenant plan adds before any behaviour does: a
// failure vocabulary, the two session keys, and the state port. each is a
// shape, so each test is about the shape holding — comparable by value, safe to
// send across a task boundary, constructible from outside the module.

/// a compile-time `Sendable` assertion: the generic constraint is the check.
private func requireSendable<T: Sendable>(_ value: T) -> T { value }

// MARK: - 0.1 failures

@Suite("WebUIFailure")
struct WebUIFailureTests {

	@Test("cases compare by value, not by identity")
	func equatable() {
		#expect(
			WebUIFailure.atCapacity(kind: .connections, limit: 256)
				== WebUIFailure.atCapacity(kind: .connections, limit: 256)
		)
		#expect(
			WebUIFailure.atCapacity(kind: .connections, limit: 256)
				!= WebUIFailure.atCapacity(kind: .sessions, limit: 256)
		)
		#expect(
			WebUIFailure.atCapacity(kind: .sessions, limit: 8)
				!= WebUIFailure.atCapacity(kind: .sessions, limit: 9)
		)
		#expect(
			WebUIFailure.handlerCapReached(session: "s", limit: 3)
				== WebUIFailure.handlerCapReached(session: "s", limit: 3)
		)
		#expect(
			WebUIFailure.handlerCapReached(session: "s", limit: 3)
				!= WebUIFailure.handlerCapReached(session: "t", limit: 3)
		)
		#expect(WebUIFailure.sessionEvicted(session: "s") == WebUIFailure.sessionEvicted(session: "s"))
		#expect(WebUIFailure.entropyUnavailable == WebUIFailure.entropyUnavailable)
		#expect(WebUIFailure.unknownComponent("c7") == WebUIFailure.unknownComponent("c7"))
		#expect(WebUIFailure.unknownComponent("c7") != WebUIFailure.unknownComponent("c8"))
		#expect(WebUIFailure.renderThrew("boom") == WebUIFailure.renderThrew("boom"))
		#expect(WebUIFailure.renderThrew("boom") != WebUIFailure.entropyUnavailable)
	}

	@Test("a failure crosses a task boundary unchanged")
	func sendable() async {
		let failure = requireSendable(WebUIFailure.atCapacity(kind: .handlers, limit: 10_000))
		let echoed = await Task { failure }.value
		#expect(echoed == failure)
	}

	@Test("the capacity kinds carry their wire spelling")
	func capacityKinds() {
		#expect(CapacityKind.connections.rawValue == "connections")
		#expect(CapacityKind.sessions.rawValue == "sessions")
		#expect(CapacityKind.handlers.rawValue == "handlers")
		let kinds = requireSendable([CapacityKind.connections, .sessions, .handlers])
		#expect(Set(kinds.map(\.rawValue)).count == 3)
	}

	@Test("the policy has exactly the two documented stances")
	func policy() {
		let policies = requireSendable([FailurePolicy.strict, FailurePolicy.degrade])
		var strictCount = 0
		for policy in policies {
			switch policy {
			case .strict: strictCount += 1
			case .degrade: break
			}
		}
		#expect(strictCount == 1)
	}
}

// MARK: - 0.3 session keys

@Suite("Session values")
struct SessionValueTests {

	@Test("a session key is equal iff its hash bytes are")
	func sessionKeyEquality() {
		#expect(SessionKey(hash: [1, 2, 3]) == SessionKey(hash: [1, 2, 3]))
		#expect(SessionKey(hash: [1, 2, 3]) != SessionKey(hash: [1, 2, 4]))
		#expect(SessionKey(hash: []) == SessionKey(hash: []))
	}

	@Test("session keys are usable as dictionary and set keys")
	func sessionKeyHashing() {
		let first = SessionKey(hash: [0xde, 0xad])
		let second = SessionKey(hash: [0xbe, 0xef])
		let counts = [first: 1, second: 2]
		#expect(counts[SessionKey(hash: [0xde, 0xad])] == 1)
		var seen: Set<SessionKey> = [first, first, second]
		#expect(seen.count == 2)
		seen.insert(first)
		#expect(seen.count == 2)
	}

	@Test("a render key is equal iff its value is")
	func renderKeyEquality() {
		#expect(RenderKey(value: "abc") == RenderKey(value: "abc"))
		#expect(RenderKey(value: "abc") != RenderKey(value: "abd"))
		#expect([RenderKey(value: "abc"): 7][RenderKey(value: "abc")] == 7)
	}

	@Test("both keys cross a task boundary")
	func sendable() async {
		let session = requireSendable(SessionKey(hash: [1, 2, 3]))
		let render = requireSendable(RenderKey(value: "abc"))
		let pair = await Task { (session, render) }.value
		#expect(pair.0 == session)
		#expect(pair.1 == render)
	}
}

// MARK: - 0.4 state port

/// a minimal conformer: the shape exists so stage 1 can conform it, so the test
/// conforms it too — that is the only proof a protocol requirement set is
/// actually satisfiable.
private struct PageState: Sendable, Equatable {
	var count = 0
}

private final class CounterStore: StateStore, Sendable {
	private struct Values {
		var state = PageState()
		var revision: UInt64 = 0
	}

	private let values = Mutex(Values())

	func read() -> PageState {
		values.withLock { $0.state }
	}

	func mutate<R>(_ body: @Sendable (inout PageState) throws -> R) throws -> R {
		try values.withLock { values in
			let result = try body(&values.state)
			values.revision += 1
			return result
		}
	}

	var revision: UInt64 {
		values.withLock { $0.revision }
	}
}

private enum StoreError: Error, Equatable {
	case rejected
}

@Suite("StateStore")
struct StateStoreTests {

	@Test("a conformer reads, mutates, and bumps its revision")
	func roundTrip() throws {
		let store = CounterStore()
		#expect(store.read().count == 0)
		#expect(store.revision == 0)

		try store.mutate { $0.count += 1 }
		#expect(store.read().count == 1)
		#expect(store.revision == 1)

		let doubled: Int = try store.mutate { state in
			state.count *= 2
			return state.count
		}
		#expect(doubled == 2)
		#expect(store.revision == 2)
	}

	@Test("a throwing mutation propagates and leaves no revision behind")
	func throwingMutation() {
		let store = CounterStore()
		#expect(throws: StoreError.rejected) {
			try store.mutate { state in
				state.count += 1
				throw StoreError.rejected
			}
		}
		#expect(store.revision == 0)
	}

	@Test("the port's state is Sendable, so a read can cross a task boundary")
	func sendableRead() async {
		let store = CounterStore()
		let state = await Task { store.read() }.value
		#expect(state == PageState())
	}
}
