// MARK: - HTML Buffer
//
// one growable buffer for a whole render. the framework's `View.render()`
// builds one `String` per node, and the profile in
// `.hermes/plans/2026-09-28_123131-render-buffer-v2.md` shows that per-node
// allocation plus its ARC traffic is the entire cost of a page render
// (~5.7 µs per node, no symbol above 4.5%), with a second pass re-parsing the
// finished html to inject attributes. this type replaces both: elements write
// into one buffer, and attribute-contributing layers merge at open-tag time
// through the shared attribute model in `Attributes.swift`.
//
// it lives in the zero-dep leaf and imports nothing, so the wasm islands can
// render through it too.

/// a growable utf-8 html buffer with element framing and a pending-attribute
/// slot.
///
/// the three operations an element performs:
///
/// ```swift
/// buffer.beginElement("div", "class=\"card\"")
/// buffer.endOpenTag()                 // writes <div class="card">
/// buffer.appendEscaped(title)
/// buffer.endElement()                 // writes </div>
/// ```
///
/// and the one a modifier performs: `addAttribute(_:)`, which contributes
/// attribute text to the element that is about to open.
package struct HTMLBuffer {
	/// an open element, from `beginElement` to `endElement`.
	private struct Frame {
		let tag: String
		/// the element's own attributes, as declared at `beginElement`.
		let base: String
		/// attributes contributed by the layers wrapping this element.
		var incoming: String = ""
		var openTagWritten: Bool = false
		/// where `<tag` begins — the anchor a span fallback wraps from.
		let startOffset: Int
	}

	private var storage: [UInt8]
	/// attributes contributed before any element opened: the next
	/// `beginElement` drains them.
	private var pending: String = ""
	private var frames: [Frame] = []

	package init(capacity: Int = 256) {
		storage = []
		storage.reserveCapacity(capacity)
	}

	// MARK: writing

	/// raw bytes — no escaping. callers that echo data use `appendEscaped`.
	package mutating func append(_ text: String) {
		storage.append(contentsOf: text.utf8)
	}

	/// `htmlEscape`d text: the safe way to write a value into content.
	package mutating func appendEscaped(_ text: String) {
		storage.append(contentsOf: htmlEscape(text).utf8)
	}

	package mutating func appendBytes(_ bytes: some Sequence<UInt8>) {
		storage.append(contentsOf: bytes)
	}

	// MARK: element framing

	/// open an element. `attributes` is the element's own attribute text (the
	/// same spelling the string path emits, minus the tag name); anything the
	/// wrapping layers contributed is merged in at `endOpenTag`.
	package mutating func beginElement(_ tag: String, _ attributes: String = "") {
		frames.append(Frame(tag: tag, base: attributes, startOffset: storage.count))
		// the first element to open drains the pending slot
		if !pending.isEmpty {
			frames[frames.count - 1].incoming = pending
			pending = ""
		}
	}

	/// write the opening tag: `<tag` + the merged attribute list + `>`.
	package mutating func endOpenTag() {
		precondition(!frames.isEmpty, "endOpenTag with no open element")
		precondition(!frames[frames.count - 1].openTagWritten, "endOpenTag called twice")
		let frame = frames[frames.count - 1]
		append("<" + frame.tag + mergedAttributeText(base: frame.base, incoming: frame.incoming) + ">")
		frames[frames.count - 1].openTagWritten = true
	}

	/// write the closing tag and pop the element.
	package mutating func endElement() {
		precondition(!frames.isEmpty, "endElement with no open element")
		let frame = frames.removeLast()
		precondition(frame.openTagWritten, "endElement before endOpenTag")
		append("</" + frame.tag + ">")
	}

	/// contribute attribute text.
	///
	/// it PREPENDS: a layer wrapping an element runs *before* the element
	/// renders, so the first contribution is the outermost layer — and the
	/// string path applies the outermost layer *last*, which puts its attributes
	/// last in the tag. prepending reproduces that order exactly, which is what
	/// keeps a chained `style` reading `padding:…; color:…` rather than the
	/// reverse.
	///
	/// with an element open but its tag unwritten, the text joins that element;
	/// otherwise it waits for the next element (and is still pending if the
	/// content turns out to open none — see `hasPendingAttributes`).
	package mutating func addAttribute(_ text: String) {
		if let last = frames.indices.last, !frames[last].openTagWritten {
			frames[last].incoming = frames[last].incoming.isEmpty ? text : text + " " + frames[last].incoming
		} else {
			// the separator matters: without it two valueless attributes
			// (`disabled` + `required`) would parse as one bogus key.
			pending = pending.isEmpty ? text : text + " " + pending
		}
	}

	/// contribute `name="value"`, escaping both halves. the escape happens here
	/// rather than at the call site so a contributed value cannot reach the
	/// wire unescaped.
	package mutating func addAttributeValue(_ name: String, _ value: String) {
		addAttribute("\(htmlEscape(name))=\"\(htmlEscape(value))\"")
	}

	// MARK: inspect + conclude

	/// the current byte count — also the mark a caller records before rendering
	/// content it may need to wrap (see `wrapSpan(from:attributes:)`).
	package var mark: Int { storage.count }

	package var byteCount: Int { storage.count }

	/// true when contributions are still waiting: the content that was
	/// supposed to carry them opened no element.
	package var hasPendingAttributes: Bool { !pending.isEmpty }

	/// take the undrained contributions (clearing the slot) so a caller can
	/// decide what to do with them — the string path wraps such content in a
	/// `<span>`, or drops the attributes when the content opens with `<!--`,
	/// doctype, or closing tag.
	package mutating func takePendingAttributes() -> String {
		let taken = pending
		pending = ""
		return taken
	}

	/// wrap everything written since `mark` in `<span attributes>…</span>`.
	///
	/// this is the fallback for content with no element to attach attributes
	/// to. it moves the content once (`storage.insert`); that cost is bounded
	/// by the wrapped content, and the case is rare — the string path re-parses
	/// the whole document for every modifier, which is what this replaces.
	package mutating func wrapSpan(from mark: Int, attributes: String) {
		precondition(mark >= 0 && mark <= storage.count, "wrapSpan mark out of range")
		storage.insert(contentsOf: "<span \(attributes)>".utf8, at: mark)
		append("</span>")
	}

	/// the rendered bytes.
	package var bytes: [UInt8] { storage }

	/// the rendered html.
	package func finish() -> String {
		String(decoding: storage, as: UTF8.self)
	}
}