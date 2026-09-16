import Testing
import WebUICore
@testable import WebUIClientRuntime

// p3-t4: the local/authority sync discipline.
struct ClientSyncCoordinatorTests {
	@Test("local mutations sequence and pending shrinks on authoritative updates")
	func sequencing() {
		let coordinator = ClientSyncCoordinator(renderToken: "tok-1")
		#expect(coordinator.renderToken == "tok-1")
		#expect(coordinator.pendingLocalPatches == 0)
		_ = coordinator.beginLocalPatch() // 1
		_ = coordinator.beginLocalPatch() // 2
		_ = coordinator.beginLocalPatch() // 3
		#expect(coordinator.pendingLocalPatches == 3)
		#expect(!coordinator.isReconciled)

		// an authoritative update at seq 2 supersedes one local patch.
		let superseded = coordinator.applyAuthoritative(seq: 2)
		#expect(superseded == 1)
		#expect(coordinator.pendingLocalPatches == 1)

		// authoritative seq 5 confirms everything.
		#expect(coordinator.applyAuthoritative(seq: 5) == 0)
		#expect(coordinator.isReconciled)
	}

	@Test("stale (replayed) authoritative updates are ignored")
	func staleUpdatesIgnored() {
		let coordinator = ClientSyncCoordinator()
		_ = coordinator.beginLocalPatch()
		_ = coordinator.applyAuthoritative(seq: 4)
		// a replay of an older seq must not move the watermark back.
		let superseded = coordinator.applyAuthoritative(seq: 3)
		#expect(superseded == 0)
		#expect(coordinator.isReconciled)
	}
}

// p3-t5: the observability ring + hand-rolled JSON dialect.
struct ClientTelemetryTests {
	@Test("events land in the ring and drain")
	func ringAndDrain() {
		let telemetry = ClientTelemetry()
		telemetry.emit(.eventHandled(component: "c0", event: "click", fragmentCount: 2))
		telemetry.emit(.fragmentSent(fragmentCount: 1, seq: 3))
		telemetry.emit(.viewRendered(viewType: "WebUITable", durationNanoseconds: 42))
		#expect(telemetry.count == 3)
		let drained = telemetry.drain()
		#expect(drained.count == 3)
		#expect(telemetry.count == 0)
	}

	@Test("drainJSON emits the framework JSON dialect with escaped strings")
	func drainJSONShape() throws {
		let telemetry = ClientTelemetry()
		telemetry.emit(.eventHandled(component: "c\"0", event: "cl\\ick", fragmentCount: 1))
		let text = String(decoding: telemetry.drainJSON(), as: UTF8.self)
		let root = try JSONValue.parse(text)
		guard case .array(let items) = root else {
			Issue.record("expected an array envelope")
			return
		}
		#expect(items.count == 1)
		guard case .object(let dict) = items.first else {
			Issue.record("expected an object")
			return
		}
		#expect(dict["type"] == .string("eventHandled"))
		#expect(dict["component"] == .string("c\"0"))
		#expect(dict["event"] == .string("cl\\ick"))
		#expect(dict["fragments"] == .number(1))
	}

	@Test("emitting through ClientRuntime records into the shared ring")
	func runtimeTelemetry() throws {
		ClientRuntime.telemetry.drain() // clear
		ClientRuntime.telemetry.emit(.eventReceived(component: "c0", event: "input"))
		_ = ClientRuntime.telemetry.drain()
		ClientRuntime.telemetry.emit(.eventReceived(component: "c0", event: "input"))
		#expect(ClientRuntime.telemetry.count == 1)
		_ = ClientRuntime.telemetry.drain()
	}
}
