import Foundation
import WebUICore
import Synchronization

// p3-t5: the observability bridge. `Logger.emit` events produced inside wasm
// (eventHandled, fragmentSent) land in a bounded ring; `drain()` hands them to
// whoever owns the transport (the chamber forwards the serialized envelope to
// server observers at low frequency). no new wire message type: the envelope
// reuses the `ObservableEvent` Codable shape.

public struct ClientTelemetry: Sendable {
	private static let capacity = 50

	private final class Box: @unchecked Sendable {
		private let mutex = Mutex<[ObservableEvent]>([])
		func record(_ event: ObservableEvent) {
			mutex.withLock { events in
				events.append(event)
				if events.count > ClientTelemetry.capacity {
					events.removeFirst(events.count - ClientTelemetry.capacity)
				}
			}
		}
		func drain() -> [ObservableEvent] {
			mutex.withLock { events in
				let snapshot = events
				events.removeAll(keepingCapacity: true)
				return snapshot
			}
		}
		var count: Int {
			mutex.withLock { $0.count }
		}
	}
	private let box = Box()

	public init() {}

	/// record a lifecycle/telemetry event from the client renderer.
	public func emit(_ event: ObservableEvent) {
		box.record(event)
	}

	/// snapshot and clear the ring (call this from the transport owner — the
	/// chamber — at a low cadence).
	public func drain() -> [ObservableEvent] {
		box.drain()
	}

	public var count: Int {
		box.count
	}
}

extension ClientTelemetry {
	/// serialize events into the framework's own JSON dialect (`[UInt8]`,
	/// not `Data`) — the shape a server observer already understands.
	public func drainJSON() -> [UInt8] {
		let events = drain()
		let items = events.map { event -> String in event.serialized() }
		return Array("[\(items.joined(separator: ","))]".utf8)
	}
}

extension ObservableEvent {
	/// hand-rolled serialization to the framework's JSON dialect (the Codable
	/// conformance exists, but the wire stays on `JSONValue`).
	func serialized() -> String {
		switch self {
		case .viewRendered(let viewType, let durationNanoseconds):
			return "{\"type\":\"viewRendered\",\"view\":\"\(escape(viewType))\",\"ns\":\(durationNanoseconds)}"
		case .eventReceived(let component, let event):
			return "{\"type\":\"eventReceived\",\"component\":\"\(escape(component))\",\"event\":\"\(escape(event))\"}"
		case .eventHandled(let component, let event, let fragmentCount):
			return "{\"type\":\"eventHandled\",\"component\":\"\(escape(component))\",\"event\":\"\(escape(event))\",\"fragments\":\(fragmentCount)}"
		case .fragmentSent(let fragmentCount, let seq):
			let seqPart = seq.map { ",\"seq\":\($0)" } ?? ""
			return "{\"type\":\"fragmentSent\",\"fragments\":\(fragmentCount)\(seqPart)}"
		case .websocketConnected:
			return "{\"type\":\"websocketConnected\"}"
		case .websocketDisconnected:
			return "{\"type\":\"websocketDisconnected\"}"
		case .websocketError(let error):
			return "{\"type\":\"websocketError\",\"error\":\"\(escape(error))\"}"
		case .error(let message):
			return "{\"type\":\"error\",\"message\":\"\(escape(message))\"}"
		case .debug(let message):
			return "{\"type\":\"debug\",\"message\":\"\(escape(message))\"}"
		}
	}

	private func escape(_ value: String) -> String {
		value
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
	}
}
