import Testing
import WebUISharedCore

// MARK: - t3.4 native tests (input parity primitives)
//
// pure, wasm-visible types in WebUISharedCore — the same source the probe
// island links through the parity corpus (its `key.*`/`modifiers.*`/
// `selection.*`/`clipboard.*`/`undo.*` cases hash the same behaviour in wasm).

// MARK: Key

@Suite("key")
struct InputKeySuite {
	@Test("wire identifiers round-trip through Key(identifier:)")
	func identifiers() {
		let names = ["Enter", "Tab", "Escape", "Backspace", "Delete",
		             "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight",
		             "Home", "End", "PageUp", "PageDown", "Space"]
		for name in names {
			let key = Key(identifier: name)
			#expect(key.identifier == name, "\(name) round-trips")
		}
	}

	@Test("function row and printable single scalars")
	func functionAndPrintable() {
		#expect(Key(identifier: "F1") == .function(1))
		#expect(Key(identifier: "F24") == .function(24))
		#expect(Key(identifier: "F25") == .unknown)
		#expect(Key(identifier: "F0") == .unknown)
		#expect(Key(identifier: "a").identifier == "a")
		#expect(Key(identifier: "+").identifier == "+")
		#expect(Key(identifier: "🔍").identifier == "🔍") // single scalar passes
		#expect(Key(identifier: "ab") == .unknown) // multi-scalar is not printable
	}

	@Test("printableScalar exposes exactly the carried scalar")
	func printableScalar() {
		#expect(Key(identifier: "x").printableScalar?.value == 0x78)
		#expect(Key.arrowUp.printableScalar == nil)
		#expect(Key.printable("é").printableScalar?.value == 0xE9)
	}

	@Test("parse never traps; unknown survives round-trip")
	func unknown() {
		let key = Key(identifier: "MediaPlayPause")
		#expect(key == .unknown)
		#expect(key.identifier == "Unknown")
		#expect(Key(identifier: "Unknown") == .unknown)
	}
}

// MARK: ModifierSet

@Suite("modifiers")
struct InputModifiersSuite {
	@Test("option-set arithmetic")
	func compose() {
		var m: ModifierSet = [.shift, .command]
		#expect(m.contains(.shift))
		#expect(m.contains(.command))
		#expect(!m.contains(.control))
		#expect(m.rawValue == 0b1001)
		m.insert(.control)
		#expect(m.contains(.control))
		m.remove(.command)
		#expect(!m.contains(.command))
		#expect(m.rawValue == 0b0011)
	}

	@Test("union / intersection / toggle")
	func ops() {
		let a: ModifierSet = [.shift, .option]
		let b: ModifierSet = [.option, .command]
		#expect(a.union(b) == [.shift, .option, .command])
		#expect(a.intersection(b) == [.option])
		#expect(([.shift, .command] as ModifierSet).symmetricDifference([.command, .control])
			== [.shift, .control])
	}

	@Test("empty set")
	func empty() {
		let m = ModifierSet()
		#expect(m.isEmpty)
		#expect(m.rawValue == 0)
	}
}

// MARK: KeyEvent

@Suite("keyevent")
struct InputKeyEventSuite {
	@Test("carries key + modifiers + repeat flag")
	func fields() {
		let event = KeyEvent(key: .arrowUp, modifiers: [.shift, .command], isRepeat: true)
		#expect(event.key == .arrowUp)
		#expect(event.modifiers == [.shift, .command])
		#expect(event.isRepeat)
		#expect(KeyEvent(key: .tab, modifiers: []) == KeyEvent(key: .tab, modifiers: []))
	}
}

// MARK: Selection

@Suite("selection")
struct InputSelectionSuite {
	@Test("anchor/focus normalize into start/end/range")
	func geometry() {
		var sel = Selection(anchor: 5, focus: 2)
		#expect(sel.start == 2)
		#expect(sel.end == 5)
		#expect(sel.range == 2..<5)
		#expect(sel.length == 3)
		#expect(!sel.isEmpty)
		sel.collapse(at: 4)
		#expect(sel.isEmpty)
		#expect(sel.anchor == 4 && sel.focus == 4)
	}

	@Test("negative indices clamp at 0, never trap")
	func clamping() {
		#expect(Selection(anchor: -3, focus: 2).anchor == 0)
		#expect(Selection(anchor: 1, focus: 1).shifted(by: -5).anchor == 0)
	}

	@Test("extend keeps the anchor, move the focus; shift moves both")
	func extendShift() {
		let sel = Selection(anchor: 3, focus: 3)
		let extended = sel.extending(to: 7)
		#expect(extended.anchor == 3 && extended.focus == 7)
		#expect(extended.range == 3..<7)
		#expect(sel.shifted(by: 10) == Selection(anchor: 13, focus: 13))
	}

	@Test("union covers both and normalized orders the pair")
	func unionAndNormalize() {
		let a = Selection(anchor: 2, focus: 6)
		let b = Selection(anchor: 4, focus: 9)
		#expect(a.union(b) == Selection(anchor: 2, focus: 9))
		#expect(Selection(anchor: 8, focus: 3).normalized == Selection(anchor: 3, focus: 8))
	}
}

// MARK: ClipboardPayload

@Suite("clipboard")
struct InputClipboardSuite {
	@Test("tsv rows round-trip")
	func roundTrip() {
		let rows = [["h1", "h2"], ["a", "b c"], ["d", "e"]]
		let tsv = ClipboardPayload.tsv(rows: rows)
		#expect(tsv == "h1\th2\na\tb c\nd\te")
		#expect(ClipboardPayload.rows(fromTSV: tsv) == rows)
		let payload = ClipboardPayload(text: tsv, tsv: tsv)
		#expect(payload.hasTabularData)
		#expect(payload.tsvRows() == rows)
	}

	@Test("empty and degenerate payloads")
	func empty() {
		#expect(ClipboardPayload.rows(fromTSV: "") == [[""]])
		#expect(ClipboardPayload.rows(fromTSV: "a\tb") == [["a", "b"]])
		#expect(ClipboardPayload.rows(fromTSV: "a\nb") == [["a"], ["b"]])
		#expect(ClipboardPayload(text: "x").hasTabularData == false)
		#expect(ClipboardPayload(text: "x").tsvRows() == [[""]])
	}

	@Test("cells are not escaped — embedded tab/newline split deterministically")
	func naiveSplit() {
		// deliberately naive (documented): a cell cannot contain \t or \n.
		#expect(ClipboardPayload.rows(fromTSV: "a\tb\tc") == [["a", "b", "c"]])
		#expect(ClipboardPayload.rows(fromTSV: "a\n\tb") == [["a"], ["", "b"]])
	}
}

// MARK: UndoStack

@Suite("undo")
struct InputUndoSuite {
	@Test("push/undo/redo orders actions LIFO and restores them")
	func lifo() {
		var stack = UndoStack<String>()
		stack.push("a")
		stack.push("b")
		stack.push("c")
		#expect(stack.undoCount == 3)
		#expect(stack.undo() == "c")
		#expect(stack.undo() == "b")
		#expect(stack.canRedo)
		#expect(stack.redo() == "b")
		#expect(stack.redoCount == 1)
	}

	@Test("push clears the redo lane (history branches)")
	func pushBranches() {
		var stack = UndoStack<String>()
		stack.push("a")
		stack.push("b")
		_ = stack.undo()
		#expect(stack.canRedo)
		stack.push("c")
		#expect(!stack.canRedo)
		#expect(stack.undoCount == 2)
	}

	@Test("empty stacks return nil and clear() resets")
	func emptyAndClear() {
		var stack = UndoStack<Int>()
		#expect(stack.undo() == nil)
		#expect(stack.redo() == nil)
		stack.push(1)
		_ = stack.undo()
		stack.clear()
		#expect(stack.undoCount == 0 && stack.redoCount == 0)
		#expect(!stack.canUndo && !stack.canRedo)
	}

	@Test("undoLimit drops the oldest action")
	func limit() {
		var stack = UndoStack<Int>(undoLimit: 2)
		stack.push(1)
		stack.push(2)
		stack.push(3)
		// action 1 was dropped; 2 and 3 remain, newest-first.
		#expect(stack.undoCount == 2)
		#expect(stack.undo() == 3)
		#expect(stack.undo() == 2)
		#expect(stack.undo() == nil)
	}

	@Test("generic over any sendable value type")
	func generic() {
		struct Tag: Sendable, Equatable { let value: Int }
		var stack = UndoStack<Tag>()
		stack.push(Tag(value: 7))
		#expect(stack.undo() == Tag(value: 7))
	}
}
