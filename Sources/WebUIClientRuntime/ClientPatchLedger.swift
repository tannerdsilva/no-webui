import Foundation
import Synchronization

// p5-t1: wasm-computed optimistic patching. a local handler renders + ships
// the fragment in the SAME turn (zero latency), sequencing the patch through
// the sync coordinator; when the server's authoritative update arrives, every
// local patch at or beyond its seq is superseded and redrawn from the
// authoritative bytes. this is the client-side half of the optimistic story:
// predictions are swift-computed state, not js bootstrap logic.

public final class ClientPatchLedger: Sendable {
	private struct Entry: Sendable {
		let seq: Int
		let id: String
		let html: String
	}
	private let state: Mutex<[Entry]>

	public init() {
		state = Mutex([])
	}

	/// record a locally-applied (optimistic) patch; returns its seq so the
	/// caller can thread it through the sync coordinator.
	@discardableResult
	public func record(seq: Int, id: String, html: String) -> Int {
		state.withLock { entries in
			entries.append(Entry(seq: seq, id: id, html: html))
		}
		return seq
	}

	/// patches still pending confirmation.
	public var pending: [String: Int] {
		state.withLock { entries in
			Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.seq) })
		}
	}

	/// prune every ledger entry with seq <= confirmed (authoritative update may
	/// re-render those fragments with its own bytes). returns the fragment ids
	/// that were superseded (the chamber swaps their html from the update).
	public func confirm(authoritativeSeq: Int) -> Set<String> {
		state.withLock { entries -> Set<String> in
			let superseded = Set(entries.filter { $0.seq <= authoritativeSeq }.map { $0.id })
			entries.removeAll { $0.seq <= authoritativeSeq }
			return superseded
		}
	}

	/// drop a single optimistic fragment (rollback) and return its previous
	/// html so the caller can restore it.
	public func rollback(id: String) -> String? {
		state.withLock { entries -> String? in
			guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
			return entries.remove(at: index).html
		}
	}
}
