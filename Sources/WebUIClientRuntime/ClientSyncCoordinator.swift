import Foundation
import Synchronization

// p3-t4: the client-side sync authority discipline. local mutations sequence
// through this coordinator; when the server answers a `wsSend` with an
// authoritative `update(seq:)`, every local patch at or beyond that seq is
// superseded and must be redrawn from the authoritative fragment. stale
// (replayed) updates below `lastAuthoritySeq` are ignored — the same
// monotonicity the runtime enforces server-side, mirrored in wasm.

public final class ClientSyncCoordinator: Sendable {
	private struct State {
		var lastLocalSeq = 0
		var lastAuthoritySeq = 0
		var renderToken: String
	}
	private let state: Mutex<State>

	public init(renderToken: String = "") {
		state = Mutex(State(renderToken: renderToken))
	}

	/// the page-binding token echoed with every forwarded message (unchanged
	/// from server mode: unknown/missing tokens get redirect + close).
	public var renderToken: String {
		state.withLock { $0.renderToken }
	}

	/// begin a locally-applied mutation; returns the seq it will carry.
	@discardableResult
	public func beginLocalPatch() -> Int {
		state.withLock { box -> Int in
			box.lastLocalSeq += 1
			return box.lastLocalSeq
		}
	}

	/// how many locally-applied patches are awaiting server confirmation.
	public var pendingLocalPatches: Int {
		state.withLock { box in
			max(0, box.lastLocalSeq - box.lastAuthoritySeq)
		}
	}

	/// apply an authoritative update. returns the number of local patches it
	/// supersedes (0 if the update is stale and must be ignored).
	public func applyAuthoritative(seq: Int) -> Int {
		state.withLock { box -> Int in
			guard seq > box.lastAuthoritySeq else { return 0 }
			let superseded = max(0, box.lastLocalSeq - seq)
			box.lastAuthoritySeq = seq
			return superseded
		}
	}

	/// all local patches confirmed (nothing pending).
	public var isReconciled: Bool {
		state.withLock { box in box.lastLocalSeq <= box.lastAuthoritySeq }
	}
}
