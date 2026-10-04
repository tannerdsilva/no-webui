// MARK: - UndoStack (t3.4, input parity primitives)
//
// a pure, generic undo/redo stack over any sendable action value — the same
// source runs natively (N tests) and inside islands (wasm-linked via the
// parity corpus's `undo.stack` case). no timestamps, no coalescing, no doc
// model — the ACTION is opaque; the stack only records order and count.
//
// semantics (each pinned natively):
//   push  appends to the undo lane and CLEARS the redo lane (a new action
//         branches history);
//   undo  pops the most recent undo action, returns it, and moves it to the
//         redo lane (nil when the undo lane is empty);
//   redo  the mirror of undo;
//   undoLimit  drops the OLDEST action once the undo lane exceeds it
//         (0 = unlimited; a bounded stack means memory is bounded too).

public struct UndoStack<Action>: Sendable where Action: Sendable {
	/// maximum retained undo actions; 0 = unlimited.
	public let undoLimit: Int

	private var undoActions: [Action]
	private var redoActions: [Action]

	public init(undoLimit: Int = 100) {
		self.undoLimit = max(undoLimit, 0)
		undoActions = []
		redoActions = []
	}

	/// push a performed action onto the undo lane, clearing the redo lane.
	public mutating func push(_ action: Action) {
		undoActions.append(action)
		redoActions.removeAll()
		trimUndoIfNeeded()
	}

	/// undo the most recent action, returning it (nil when nothing to undo).
	@discardableResult
	public mutating func undo() -> Action? {
		guard let action = undoActions.popLast() else { return nil }
		redoActions.append(action)
		return action
	}

	/// redo the most recently undone action, returning it (nil when nothing).
	@discardableResult
	public mutating func redo() -> Action? {
		guard let action = redoActions.popLast() else { return nil }
		undoActions.append(action)
		trimUndoIfNeeded()
		return action
	}

	public var canUndo: Bool { !undoActions.isEmpty }
	public var canRedo: Bool { !redoActions.isEmpty }

	/// number of actions currently undoable.
	public var undoCount: Int { undoActions.count }

	/// number of actions currently redoable.
	public var redoCount: Int { redoActions.count }

	/// drop everything.
	public mutating func clear() {
		undoActions.removeAll()
		redoActions.removeAll()
	}

	private mutating func trimUndoIfNeeded() {
		guard undoLimit > 0 else { return }
		while undoActions.count > undoLimit {
			undoActions.removeFirst()
		}
	}
}
