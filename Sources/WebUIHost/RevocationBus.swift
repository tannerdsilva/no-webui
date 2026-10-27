import WebUI
import WebUIServer
import WebUIAuth

// MARK: - SocketRevocationBus

/// the session → live connections registry, promoted from
/// `WebUIAuthExample`'s `AuthConnectionRegistry`.
///
/// it is an `actor`: **shared mutable state mutated from accept tasks, logout
/// tasks and idle reapers, where async serialization is the requirement.** the
/// registry is written from at least three concurrent places (a socket
/// completing its upgrade, a logout, a reaper noticing a dead peer) and every
/// one of them must see a consistent map — an actor is the language's own
/// answer to exactly that, and it costs one hop on a path that already awaited
/// a store.
///
/// what revoking does: close every connection tracked under the session and
/// forget it. the close action is carried by the ``ConnectionToken``, so this
/// type never links a transport and a test can hand it anything closeable.
/// a connection that ends on its own is `untrack`ed by its own handler — the
/// bus must never close a descriptor the kernel already reclaimed, which is why
/// `revoke` closes only what is still tracked.
public actor SocketRevocationBus: RevocationBus {

	private var bySession: [SessionKey: [UInt64: ConnectionToken]] = [:]
	/// a connection's session, so `untrack` needs only the token.
	private var sessionByConnection: [UInt64: SessionKey] = [:]

	public init() {}

	public func track(_ connection: ConnectionToken, session: SessionKey) async {
		// one live connection belongs to exactly one session. a re-track under a
		// different session moves it rather than leaving a stale entry that a
		// later revoke would close twice.
		if let previous = sessionByConnection[connection.id] {
			bySession[previous]?.removeValue(forKey: connection.id)
			if bySession[previous]?.isEmpty == true {
				bySession.removeValue(forKey: previous)
			}
		}
		bySession[session, default: [:]][connection.id] = connection
		sessionByConnection[connection.id] = session
	}

	public func untrack(_ connection: ConnectionToken) async {
		guard let session = sessionByConnection.removeValue(forKey: connection.id) else { return }
		bySession[session]?.removeValue(forKey: connection.id)
		if bySession[session]?.isEmpty == true {
			bySession.removeValue(forKey: session)
		}
	}

	public func revoke(session: SessionKey) async {
		guard let connections = bySession.removeValue(forKey: session) else { return }
		for id in connections.keys {
			sessionByConnection.removeValue(forKey: id)
		}
		// the map is drained *before* any close runs, so a close that
		// re-enters this actor (a handler reporting its own disconnect) finds
		// nothing to untrack and nothing to close a second time.
		for connection in connections.values {
			connection.close()
		}
	}

	// MARK: inspection

	/// how many live connections are tracked under `session`.
	public func connectionCount(for session: SessionKey) -> Int {
		bySession[session]?.count ?? 0
	}

	/// how many live connections are tracked in total — the number a leak test
	/// asserts on after every socket it opened has closed.
	public var trackedCount: Int {
		sessionByConnection.count
	}
}
