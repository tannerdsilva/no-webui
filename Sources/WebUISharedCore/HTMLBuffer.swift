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

// MARK: - Regions

/// a subtree that can be patched by id.
///
/// a region is declared by the view that renders it (`beginRegion` /
/// `endRegion` around the subtree); the buffer records only its hash, never its
/// bytes, so a session's diff state is 8 bytes per region rather than a page.
public struct RegionID: Hashable, Sendable, ExpressibleByStringLiteral {
	/// the id the page knows the region by.
	public let rawValue: String

	public init(rawValue: String) {
		self.rawValue = rawValue
	}

	/// a literal id, so a policy or a test can name a region directly:
	/// `excluded: ["live-turn-text"]`.
	public init(stringLiteral: String) {
		self.rawValue = stringLiteral
	}
}

/// per-region hashes of a finished render: 8 bytes per region, not the html.
///
/// a differ compares two digests and asks the live buffer for the bytes of the
/// regions that changed — which is why the previous render's html is never
/// stored.
public struct RenderDigest: Sendable {
	/// region id → hash of the bytes that region rendered.
	public let regions: [RegionID: UInt64]

	public init(regions: [RegionID: UInt64]) {
		self.regions = regions
	}
}

/// fnv-1a, 64-bit, over a region's bytes.
///
/// it lives here rather than in a crypto module for three reasons: the recorder
/// must not import Foundation (the wasm islands render through this type), the
/// hash needs no secrecy (it detects change, it does not authenticate), and one
/// dependency-free function is cheaper than pulling `CryptoKit`'s
/// platform-split facade into the leaf target.
@inline(__always)
private func regionHash(_ bytes: ArraySlice<UInt8>) -> UInt64 {
	var hash: UInt64 = 0xcbf2_9ce4_8422_2325
	for byte in bytes {
		hash ^= UInt64(byte)
		hash = hash &* 0x0000_0100_0000_01b3
	}
	return hash
}

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
///
/// the type is `public` only because `View.render(into:)` names it in a
/// protocol requirement, and a requirement is implicitly as visible as its
/// protocol. every member stays `package`: this is the framework's own render
/// path, not yet a consumer API. the members open up with the 2.0 flip, when
/// `render(into:)` becomes *the* requirement and consumer views must write
/// into a buffer of their own.
public struct HTMLBuffer {
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
	/// region id → hash of the bytes that region's subtree rendered.
	private var regions: [RegionID: UInt64] = [:]

	/// create an empty buffer.
	///
	/// `capacity` is a starting-size hint, not a limit: the buffer grows as views
	/// write into it.
	public init(capacity: Int = 256) {
		storage = []
		storage.reserveCapacity(capacity)
	}

	// MARK: writing

	/// raw bytes — no escaping. callers that echo data use `appendEscaped`.
	public mutating func append(_ text: String) {
		storage.append(contentsOf: text.utf8)
	}

	/// `htmlEscape`d text: the safe way to write a value into content.
	public mutating func appendEscaped(_ text: String) {
		storage.append(contentsOf: htmlEscape(text).utf8)
	}

	/// append bytes verbatim (already-encoded utf-8, or genuinely binary content).
	public mutating func appendBytes(_ bytes: some Sequence<UInt8>) {
		storage.append(contentsOf: bytes)
	}

	// MARK: element framing

	/// open an element. `attributes` is the element's own attribute text (the
	/// same spelling the string path emits, minus the tag name); anything the
	/// wrapping layers contributed is merged in at `endOpenTag`.
	public mutating func beginElement(_ tag: String, _ attributes: String = "") {
		frames.append(Frame(tag: tag, base: attributes, startOffset: storage.count))
		// the first element to open drains the pending slot
		if !pending.isEmpty {
			frames[frames.count - 1].incoming = pending
			pending = ""
		}
	}

	/// write the opening tag: `<tag` + the merged attribute list + `>`.
	///
	/// with nothing contributed, the element's own attribute text re-emits
	/// verbatim — which is exactly what the string path wrote after the tag
	/// name, and it skips the parse/merge/serialize round trip that otherwise
	/// runs per element (measured on the reference box: that round trip cost
	/// ~25% of a page render while no contributions existed to merge, and the
	/// verbatim path is closer to the old bytes, not further from them).
	public mutating func endOpenTag() {
		precondition(!frames.isEmpty, "endOpenTag with no open element")
		precondition(!frames[frames.count - 1].openTagWritten, "endOpenTag called twice")
		let frame = frames[frames.count - 1]
		writeOpenTag(frame.tag, base: frame.base, incoming: frame.incoming)
		frames[frames.count - 1].openTagWritten = true
	}

	/// write an element that has no closing tag — `img`, `input` — as the open
	/// tag and nothing else. it drains the pending slot exactly like a framed
	/// element, and it leaves no frame behind: there is no content to close.
	public mutating func voidElement(_ tag: String, _ attributes: String = "") {
		writeOpenTag(tag, base: attributes, incoming: takePendingAttributes())
	}

	/// the one place an opening tag is assembled, so a framed element and a
	/// void element cannot drift.
	///
	/// it writes bytes: the tag name, its attributes and the closing `>` are
	/// appended straight into `storage`, so framing an element allocates no
	/// intermediate `String`. the two shapes are exactly the string path's:
	/// with no contribution the element's own attribute text re-emits verbatim
	/// (one separator space unless it already leads with one), and with a
	/// contribution both lists merge through the shared attribute model.
	private mutating func writeOpenTag(_ tag: String, base: String, incoming: String) {
		storage.append(UInt8(ascii: "<"))
		storage.append(contentsOf: tag.utf8)
		if incoming.isEmpty {
			if !base.isEmpty {
				if !base.hasPrefix(" ") { storage.append(UInt8(ascii: " ")) }
				storage.append(contentsOf: base.utf8)
			}
		} else {
			writeMergedAttributes(base: base, incoming: incoming)
		}
		storage.append(UInt8(ascii: ">"))
	}

	/// append `mergeAttributes`'s output one attribute at a time.
	///
	/// `serializeAttr` already owns the quote and escape rules, so this appends
	/// its text rather than re-implementing them — the win over
	/// `mergedAttributeText` is that no whole-tag `String` is built and the
	/// pieces go straight into the buffer.
	private mutating func writeMergedAttributes(base: String, incoming: String) {
		let merged = mergeAttributes(
			base: parseAttributeString(base),
			incoming: parseAttributeString(incoming)
		)
		for attribute in merged {
			storage.append(contentsOf: serializeAttr(attribute).utf8)
		}
	}

	/// write the closing tag and pop the element.
	public mutating func endElement() {
		precondition(!frames.isEmpty, "endElement with no open element")
		let frame = frames.removeLast()
		precondition(frame.openTagWritten, "endElement before endOpenTag")
		storage.append(UInt8(ascii: "<"))
		storage.append(UInt8(ascii: "/"))
		storage.append(contentsOf: frame.tag.utf8)
		storage.append(UInt8(ascii: ">"))
	}

	// MARK: regions

	/// mark the start of `id`'s region and return the mark to hand back to
	/// `endRegion`.
	///
	/// nesting is free: an outer region's mark precedes its children's, so its
	/// hash covers every byte they wrote, including their own hashes' inputs.
	/// the recorder never writes to `storage` — rendered bytes are identical
	/// with and without regions, which is what keeps a region a pure
	/// observation.
	package mutating func beginRegion(_ id: RegionID) -> Int {
		storage.count
	}

	/// close `id`'s region, hashing everything written since `mark`.
	package mutating func endRegion(_ id: RegionID, from mark: Int) {
		precondition(mark >= 0 && mark <= storage.count, "endRegion mark out of range")
		regions[id] = regionHash(storage[mark...])
	}

	/// the hashes recorded so far — what a differ compares against the previous
	/// render.
	package var renderDigest: RenderDigest {
		RenderDigest(regions: regions)
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
	public mutating func addAttribute(_ text: String) {
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
	public mutating func addAttributeValue(_ name: String, _ value: String) {
		addAttribute("\(htmlEscape(name))=\"\(htmlEscape(value))\"")
	}

	// MARK: inspect + conclude

	/// the current byte count — also the mark a caller records before rendering
	/// content it may need to wrap (see `wrapSpan(from:attributes:)`).
	package var mark: Int { storage.count }

	/// how many bytes have been written so far.
	public var byteCount: Int { storage.count }

	/// true when contributions are still waiting: the content that was
	/// supposed to carry them opened no element.
	public var hasPendingAttributes: Bool { !pending.isEmpty }

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
	/// `attributes` is attribute text; a single separating space is inserted
	/// unless it already starts with one — the same allowance `endOpenTag`
	/// makes, so a merged attribute list (which always leads with a space) can
	/// be passed through unchanged.
	///
	/// this is the fallback for content with no element to attach attributes
	/// to. it moves the content once (`storage.insert`); that cost is bounded
	/// by the wrapped content, and the case is rare — the string path re-parses
	/// the whole document for every modifier, which is what this replaces.
	package mutating func wrapSpan(from mark: Int, attributes: String) {
		precondition(mark >= 0 && mark <= storage.count, "wrapSpan mark out of range")
		let separator = attributes.isEmpty || attributes.hasPrefix(" ") ? "" : " "
		storage.insert(contentsOf: ("<span" + separator + attributes + ">").utf8, at: mark)
		append("</span>")
	}

	/// the rendered bytes.
	public var bytes: [UInt8] { storage }

	// MARK: the string-path fallback

	/// apply contributions that no element drained to the bytes written since
	/// `mark`, in place — the buffer-side twin of `injectAttributes(into:_:)`,
	/// byte-for-byte:
	///
	/// - content with no `<` is wrapped as `<span attributes>…</span>`, the
	///   contributions folded exactly as sequential applications would have
	///   folded them (two styles become one declaration list, not two
	///   attributes);
	/// - content whose first tag is a closing tag, a declaration (`<!` — markup
	///   notes and doctypes), or a processing instruction (`<?`) keeps its bytes
	///   and the contributions are dropped;
	/// - otherwise the contributions merge into the first opening tag with the
	///   same `mergeAttributes` rules the string path used.
	///
	/// no content string is built and the rewrite moves only the bytes after the
	/// insertion point. a contribution reaches this fallback when the content it
	/// wrapped opened no element — because that content renders through the
	/// string path.
	///
	/// it reproduces `injectAttributes` down to its known wart: content that
	/// starts with two or more characters of text before its first tag reads the
	/// preamble as a tag name (`hi<div>…` → `<i <div …>`). that is
	/// bug-compatibility on purpose — this migration's contract is byte-identity,
	/// and the wart is pinned by tests; fixing it is its own decision.
	package mutating func settlePendingAttributes(from mark: Int) {
		precondition(mark >= 0 && mark <= storage.count, "settle mark out of range")
		let attributes = takePendingAttributes()
		guard !attributes.isEmpty else { return }

		guard let firstLessThan = storage[mark...].firstIndex(of: UInt8(ascii: "<")) else {
			wrapSpan(from: mark, attributes: mergedAttributeText(base: "", incoming: attributes))
			return
		}
		let afterLT = firstLessThan + 1
		guard afterLT < storage.count else {
			wrapSpan(from: mark, attributes: mergedAttributeText(base: "", incoming: attributes))
			return
		}
		let peek = storage[afterLT]
		guard peek != UInt8(ascii: "/"), peek != UInt8(ascii: "!"), peek != UInt8(ascii: "?") else {
			return
		}

		// quote-aware scan for the end of the opening tag
		var inQuote = false
		var quoteChar = UInt8(ascii: "\"")
		var tagEnd: Int?
		var i = afterLT
		while i < storage.count {
			let c = storage[i]
			if inQuote {
				if c == quoteChar { inQuote = false }
			} else if c == UInt8(ascii: "\"") || c == UInt8(ascii: "'") {
				inQuote = true
				quoteChar = c
			} else if c == UInt8(ascii: ">") {
				tagEnd = i
				break
			}
			i += 1
		}
		guard let end = tagEnd else {
			wrapSpan(from: mark, attributes: mergedAttributeText(base: "", incoming: attributes))
			return
		}

		// the tag runs from `mark` to `>` (or to the `/` of `/>`) — preamble
		// included, which is what the string path sliced
		let beforeEnd = end - 1
		let tagRangeEnd = storage[beforeEnd] == UInt8(ascii: "/") ? beforeEnd : end
		let tag = String(decoding: storage[mark..<tagRangeEnd], as: UTF8.self)

		guard let parsed = parseOpeningTag(tag) else {
			// unparseable tag — the legacy append, byte-for-byte
			storage.insert(contentsOf: (" " + attributes).utf8, at: tagRangeEnd)
			return
		}

		let merged = mergeAttributes(base: parsed.attrs, incoming: parseAttributeString(attributes))
		var out = "<" + parsed.name
		for a in merged { out += serializeAttr(a) }
		storage.replaceSubrange(mark..<tagRangeEnd, with: out.utf8)
	}

	/// the rendered html.
	package func finish() -> String {
		String(decoding: storage, as: UTF8.self)
	}
}