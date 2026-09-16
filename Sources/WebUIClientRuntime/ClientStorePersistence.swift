import Foundation
import WebUICore
import Synchronization

// p3-t3: a persistence backend over the bridge's `storageGet`/`storageSet`
// imports (the chamber maps them to localStorage). the same `ClientStateStore`
// contract — backend-provided, like the auth store — so nothing above this
// cares which backend is wired.

#if os(WASI)
/// localStorage-backed client state. values are stored as the hand-rolled
/// `JSONValue.serialize()` bytes under a namespaced key (`webui.state.<path>`);
/// the chamber's `storageGet`/`storageSet` imports read/write the browser's
/// localStorage, so state survives page reloads.
public struct LocalStorageClientStateStore: ClientStateStore {
	private static let frameSize = 1 << 16

	private let prefix: String

	public init(prefix: String = "webui.state.") {
		self.prefix = prefix
	}

	// MARK: - ClientStateStore

	public func get(_ path: String) -> JSONValue? {
		guard let bytes = storageRead(prefix + path) else { return nil }
		guard let json = try? JSONValue.parse(String(decoding: bytes, as: UTF8.self)) else { return nil }
		return json
	}

	public func set(_ path: String, _ value: JSONValue) throws {
		try ClientStatePaths.validate(path)
		storageWrite(prefix + path, Array(value.serialize().utf8))
	}

	public func remove(_ path: String) {
		storageWrite(prefix + path, [])
	}

	public func subscribe(_ path: String, _ handler: @escaping @Sendable (JSONValue?) -> Void) -> UUID {
		// persistence is a leaf backend: callers observe through subscribing on
		// an in-memory front (e.g. InMemoryClientStateStore) that syncs here.
		UUID()
	}

	public func unsubscribe(_ id: UUID) {}

	// MARK: - bridge accessors

	private func storageRead(_ key: String) -> [UInt8]? {
		let scratch = UnsafeMutableRawPointer.allocate(byteCount: Self.frameSize, alignment: 16)
		defer { scratch.deallocate() }
		let keyBytes = Array(key.utf8)
		return keyBytes.withUnsafeBytes { keyPtr in
			let count = storageGet(keyPtr.baseAddress, keyBytes.count, scratch, Self.frameSize)
			guard count > 0 else { return nil }
			return [UInt8](UnsafeRawBufferPointer(start: scratch, count: count))
		}
	}

	private func storageWrite(_ key: String, _ value: [UInt8]) {
		let keyBytes = Array(key.utf8)
		keyBytes.withUnsafeBytes { keyPtr in
			value.withUnsafeBytes { valuePtr in
				storageSet(keyPtr.baseAddress, keyBytes.count, valuePtr.baseAddress, value.count)
			}
		}
	}
}
#endif
