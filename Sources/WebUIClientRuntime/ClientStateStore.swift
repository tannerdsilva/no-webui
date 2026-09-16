import Foundation
import WebUICore
import Synchronization

/// errors from setting client state.
public enum ClientStateError: Error, Equatable, Sendable {
	/// a path segment hit the prototype-pollution denylist
	/// (`__proto__`, `constructor`, `prototype`).
	case invalidPath(String)
}

/// the client state store contract (house pattern: protocol first,
/// backend-provided — the same shape as `AuthSessionStore`). the wasm client
/// keeps its view state behind this store; a persistence backend
/// (localStorage/IndexedDB behind the bridge) can conform later without
/// changing the contract.
public protocol ClientStateStore: Sendable {
	func get(_ path: String) -> JSONValue?
	func set(_ path: String, _ value: JSONValue) throws
	func remove(_ path: String)
	func subscribe(_ path: String, _ handler: @escaping @Sendable (JSONValue?) -> Void) -> UUID
	func unsubscribe(_ id: UUID)
}

/// a thread-safe in-memory backend. paths are flat keys; every dotted segment
/// is checked against the prototype-pollution denylist (mirroring the js
/// runtime's `StateStore`).
public struct InMemoryClientStateStore: ClientStateStore {
	private let box = ClientStateBox()

	public init() {}

	// MARK: - ClientStateStore

	public func get(_ path: String) -> JSONValue? {
		box.get(path)
	}

	public func set(_ path: String, _ value: JSONValue) throws {
		try ClientStatePaths.validate(path)
		box.set(path, value)
	}

	public func remove(_ path: String) {
		box.remove(path)
	}

	public func subscribe(_ path: String, _ handler: @escaping @Sendable (JSONValue?) -> Void) -> UUID {
		box.subscribe(path, handler)
	}

	public func unsubscribe(_ id: UUID) {
		box.unsubscribe(id)
	}
}

/// shared path validation for every backend (prototype-pollution denylist).
enum ClientStatePaths {
	static let denied: Set<Substring> = ["__proto__", "constructor", "prototype"]

	static func validate(_ path: String) throws {
		for segment in path.split(separator: ".") where denied.contains(segment) {
			throw ClientStateError.invalidPath(String(segment))
		}
	}
}

/// the in-memory backend's shared state box (flat keys + prefix subscriptions).
final class ClientStateBox: @unchecked Sendable {
	private struct Values {
		var values: [String: JSONValue] = [:]
		var subscriptions: [UUID: (path: String, handler: @Sendable (JSONValue?) -> Void)] = [:]
	}
	private let mutex = Mutex(Values())

	init() {}

	func get(_ path: String) -> JSONValue? {
		mutex.withLock { $0.values[path] }
	}

	func set(_ path: String, _ value: JSONValue) {
		let previous = mutex.withLock { box -> JSONValue? in
			let old = box.values[path]
			box.values[path] = value
			return old
		}
		fanOut(path: path, previous: previous, value: value)
	}

	func remove(_ path: String) {
		let previous = mutex.withLock { box -> JSONValue? in
			box.values.removeValue(forKey: path)
		}
		fanOut(path: path, previous: previous, value: nil)
	}

	func subscribe(_ path: String, _ handler: @escaping @Sendable (JSONValue?) -> Void) -> UUID {
		let id = UUID()
		mutex.withLock { $0.subscriptions[id] = (path, handler) }
		return id
	}

	func unsubscribe(_ id: UUID) {
		mutex.withLock { _ = $0.subscriptions.removeValue(forKey: id) }
	}

	/// notify exact-path and prefix subscribers.
	private func fanOut(path: String, previous: JSONValue?, value: JSONValue?) {
		let matches = mutex.withLock { box -> [(String, @Sendable (JSONValue?) -> Void)] in
			box.subscriptions.values
				.filter { entry in entry.path == path || path.hasPrefix(entry.path + ".") }
				.map { ($0.path, $0.handler) }
		}
		for (_, handler) in matches where !(previous == value) {
			handler(value)
		}
	}
}
