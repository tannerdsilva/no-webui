import WebUICore

// MARK: - render snapshots
//
// design E's wire half. a render is a set of regions — subtrees a client can
// replace by id — and an interaction ships only the ones whose bytes moved.
//
// the memory contract is the reason this type exists at all: a session keeps
// the previous render's *hashes* and nothing else. the bytes of a changed
// region are sliced out of the render that just finished, so the retained diff
// state is 8 bytes per region rather than a page.
//
// the hash is fnv-1a over the region's bytes, byte-for-byte the algorithm
// `HTMLBuffer.regionHash` runs, so a digest recorded from the buffer and a
// digest derived from finished markup agree for the same region boundaries.

/// where one region's element starts and ends in a render's bytes.
///
/// `package`: a span is the differ's own vocabulary. it is derived inside the
/// module and read only by ``RenderDiffer``; a consumer patches by ``RegionID``
/// and a fragment, never by byte offset.
package struct RegionSpan: Sendable, Hashable {
	/// the id the client patches by — the element's DOM `id`.
	package let id: RegionID
	/// the first byte of the region's opening `<`.
	package let start: Int
	/// one past the region's last byte.
	package let end: Int

	package init(id: RegionID, start: Int, end: Int) {
		self.id = id
		self.start = start
		self.end = end
	}

	/// the byte range this span covers.
	package var range: Range<Int> { start..<end }
}

/// one finished render, ready to diff: the bytes, where each region sits in
/// them, and the hashes a differ compares.
public struct RenderSnapshot: Sendable {
	/// the render's bytes, exactly as they went (or will go) on the wire.
	public let bytes: [UInt8]
	/// region id → where it sits in ``bytes``, in byte order.
	///
	/// `package`: the spans are the differ's byte offsets, and nothing outside
	/// this module reads them — a consumer addresses a region by id. the snapshot
	/// itself stays public because the server derives one per render.
	package let spans: [RegionSpan]
	/// region id → hash of that region's bytes.
	public let digest: RenderDigest
	/// the byte range this snapshot diffs — a document's `<body>` subtree when
	/// it has one, else the whole render.
	///
	/// scoping the diff is what makes it correct on a real page: a document
	/// mints a fresh csp nonce and embeds its render token in the *head*, so the
	/// head differs on every render and can never be part of a byte diff.
	public let root: Range<Int>
	/// hash of every byte in ``root`` that no region covers.
	///
	/// it is what keeps a patch honest: a change *outside* every region — a
	/// heading bound to state, a row that appeared — moves the residue, and the
	/// differ answers that with a full page rather than a patch that would
	/// leave the client stale.
	///
	/// `package`: the residue is the differ's veto, not a number a caller acts
	/// on. the verdict it produces is what reaches a caller, through
	/// ``RenderPatch/isFullPage`` and ``PagePatch/fragments``.
	package let residue: UInt64

	/// a snapshot of a render whose region spans the caller recorded.
	///
	/// `root` defaults to the whole render; a document passes its `<body>`
	/// range so per-render head bytes stay out of the diff.
	///
	/// `package`: constructing a snapshot from caller-recorded spans is how this
	/// module's own scanner and tests build one. a consumer that has bytes asks
	/// for ``derived(fromMarkup:)``.
	package init(html: String, spans: [RegionSpan], root: Range<Int>? = nil) {
		self.init(bytes: Array(html.utf8), spans: spans, root: root)
	}

	package init(bytes: [UInt8], spans: [RegionSpan], root: Range<Int>? = nil) {
		let ordered = spans.sorted { $0.start < $1.start }
		var regions: [RegionID: UInt64] = [:]
		regions.reserveCapacity(ordered.count)
		for span in ordered {
			regions[span.id] = fnv1a(bytes, span.range)
		}
		let scope = root ?? 0..<bytes.count
		self.bytes = bytes
		self.spans = ordered
		self.digest = RenderDigest(regions: regions)
		self.root = scope
		self.residue = residueHash(bytes, scope: scope, spans: ordered)
	}

	/// the rendered html.
	public var html: String { String(decoding: bytes, as: UTF8.self) }

	/// the bytes of one region, sliced out of this render.
	public func regionHTML(_ id: RegionID) -> String? {
		guard let span = spans.first(where: { $0.id == id }) else { return nil }
		guard span.start >= 0, span.end <= bytes.count else { return nil }
		return String(decoding: bytes[span.start..<span.end], as: UTF8.self)
	}

	/// what a session stores for the next render: hashes, never html.
	public var baseline: RenderBaseline { RenderBaseline(digest: digest, residue: residue) }
}

// MARK: - markup-derived regions

extension RenderSnapshot {
	/// the snapshot of a finished page: every element carrying
	/// `data-component-id` is a region, exactly as design E specifies for
	/// `controlAttributes` controls.
	///
	/// this is the door the server has. a render through `HTMLBuffer` records
	/// hashes but not spans (the buffer never writes, and the caller's marks are
	/// its own), so a page that only exists as bytes is scanned here — one pass,
	/// no tree kept, no second representation of the page.
	///
	/// the diff root is the `<body>` subtree when the render is a document, and
	/// the whole render otherwise. every region is a descendant of that root and
	/// carries the same string as its `id`, which is what makes the update
	/// addressable by the client's `getElementById`.
	public static func derived(fromMarkup html: String) -> RenderSnapshot {
		let bytes = Array(html.utf8)
		let scanned = MarkupScan.scan(bytes)
		let root = scanned.body ?? 0..<bytes.count
		// a region outside the diff root (a control in the head, which no page
		// emits) is not addressable by an in-place patch.
		let spans = scanned.spans.filter { $0.start >= root.lowerBound && $0.end <= root.upperBound }
		return RenderSnapshot(bytes: bytes, spans: spans, root: root)
	}
}

/// the byte-level element scan region derivation stands on.
///
/// it is a scanner, not a parser: it finds a tag's name, its end, and the close
/// that matches it, and it never builds a node. attribute values are html-escaped
/// by every framework emitter, so a raw `<` inside one cannot forge a tag start.
private enum MarkupScan {
	static let componentIDPrefix: [UInt8] = Array("data-component-id=\"".utf8)
	static let bodyTag: [UInt8] = Array("body".utf8)
	/// elements that never have a closing tag.
	static let voidTags: [[UInt8]] = [
		"area", "base", "br", "col", "embed", "hr", "img", "input",
		"link", "meta", "param", "source", "track", "wbr",
	].map { Array($0.utf8) }

	/// one tag walk: the document's `<body>` span (when there is one) and every
	/// element carrying a `data-component-id`.
	///
	/// a single pass with an open-element stack, so the cost is O(bytes) once —
	/// not one rescan per region, which is what a real page (38 controls over
	/// 168 KB) makes unaffordable. no node is built and no tag name is
	/// materialized: the stack holds byte ranges into the render.
	static func scan(_ bytes: [UInt8]) -> (body: Range<Int>?, spans: [RegionSpan]) {
		struct Open {
			let name: Range<Int>
			let start: Int
			let openEnd: Int
			let id: String?
		}
		var spans: [RegionSpan] = []
		var body: Range<Int>?
		var stack: [Open] = []
		var index = 0
		while index < bytes.count {
			guard bytes[index] == lt else {
				index += 1
				continue
			}
			let afterAngle = index + 1
			guard afterAngle < bytes.count else { break }
			// a comment is skipped whole: its body is not markup.
			if bytes[afterAngle] == bang, afterAngle + 2 < bytes.count,
				bytes[afterAngle + 1] == dash, bytes[afterAngle + 2] == dash
			{
				guard let close = find([dash, dash, gt], in: bytes, from: afterAngle + 3) else { break }
				index = close + 3
				continue
			}
			// a declaration or a processing instruction carries no element.
			if bytes[afterAngle] == bang || bytes[afterAngle] == question {
				guard let close = tagEnd(in: bytes, from: afterAngle) else { break }
				index = close + 1
				continue
			}
			let isClose = bytes[afterAngle] == slash
			let nameStart = isClose ? afterAngle + 1 : afterAngle
			var nameEnd = nameStart
			while nameEnd < bytes.count, !isSpace(bytes[nameEnd]), bytes[nameEnd] != gt,
				bytes[nameEnd] != slash
			{
				nameEnd += 1
			}
			guard nameEnd > nameStart, let tagClose = tagEnd(in: bytes, from: nameEnd) else {
				index += 1
				continue
			}
			let name = nameStart..<nameEnd
			if isClose {
				// pop through the matching open: well-formed markup closes the
				// innermost element, and an unclosed one above it is dropped
				// with the span its own open tag recorded.
				if let position = stack.lastIndex(where: { equalsTag(bytes, $0.name, bytes, name) }) {
					let opened = stack[position]
					stack.removeSubrange(position...)
					if equalsTag(bytes, name, bodyTag) {
						body = opened.start..<(tagClose + 1)
					} else if let id = opened.id {
						spans.append(RegionSpan(id: RegionID(rawValue: id), start: opened.start, end: tagClose + 1))
					}
				}
			} else {
				let selfClosing = tagClose > index && bytes[tagClose - 1] == slash
				let isVoid = voidTags.contains { equalsTag(bytes, name, $0) }
				let id = componentID(in: bytes, tag: index..<tagClose)
				if selfClosing || isVoid {
					if let id {
						spans.append(RegionSpan(id: RegionID(rawValue: id), start: index, end: tagClose + 1))
					}
				} else {
					stack.append(Open(name: name, start: index, openEnd: tagClose + 1, id: id))
				}
			}
			index = tagClose + 1
		}
		// an element left open has its opening tag as its region, so a digest
		// still detects a change to what was written.
		for opened in stack {
			if let id = opened.id {
				spans.append(RegionSpan(id: RegionID(rawValue: id), start: opened.start, end: opened.openEnd))
			}
		}
		return (body, spans.sorted { $0.start < $1.start })
	}

	// MARK: bytes

	static let lt = UInt8(ascii: "<")
	static let gt = UInt8(ascii: ">")
	static let slash = UInt8(ascii: "/")
	static let quote = UInt8(ascii: "\"")
	static let bang = UInt8(ascii: "!")
	static let question = UInt8(ascii: "?")
	static let dash = UInt8(ascii: "-")

	/// the value of the element's `data-component-id`, when its opening tag
	/// carries one.
static func componentID(in bytes: [UInt8], tag: Range<Int>) -> String? {
		guard let hit = find(componentIDPrefix, in: bytes, from: tag.lowerBound, limit: tag.upperBound)
		else { return nil }
		let valueStart = hit + componentIDPrefix.count
		guard let valueEnd = findByte(quote, in: bytes, from: valueStart) else { return nil }
		guard valueEnd <= tag.upperBound, valueEnd > valueStart else { return nil }
		return String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
	}

	/// the first index of `needle` at or after `from`, before `limit`.
	static func find(
		_ needle: [UInt8], in bytes: [UInt8], from: Int, limit: Int? = nil
	) -> Int? {
		let end = limit ?? bytes.count
		guard !needle.isEmpty, from <= end else { return nil }
		var index = from
		while index + needle.count <= end {
			if bytes[index] == needle[0] {
				var offset = 1
				var matched = true
				while offset < needle.count {
					if bytes[index + offset] != needle[offset] {
						matched = false
						break
					}
					offset += 1
				}
				if matched { return index }
			}
			index += 1
		}
		return nil
	}

	static func findByte(_ byte: UInt8, in bytes: [UInt8], from: Int) -> Int? {
		var index = from
		while index < bytes.count {
			if bytes[index] == byte { return index }
			index += 1
		}
		return nil
	}

	/// the index of the `>` closing an opening tag, quote-aware.
	static func tagEnd(in bytes: [UInt8], from: Int) -> Int? {
		var index = from
		var activeQuote: UInt8?
		while index < bytes.count {
			let byte = bytes[index]
			if let active = activeQuote {
				if byte == active { activeQuote = nil }
			} else if byte == quote || byte == UInt8(ascii: "'") {
				activeQuote = byte
			} else if byte == gt {
				return index
			}
			index += 1
		}
		return nil
	}

	/// true when `bytes[range]` is `tag`, comparing ascii case-insensitively.
	static func equalsTag(_ bytes: [UInt8], _ range: Range<Int>, _ tag: [UInt8]) -> Bool {
		guard range.count == tag.count, range.upperBound <= bytes.count else { return false }
		var index = range.lowerBound
		var offset = 0
		while offset < tag.count {
			var byte = bytes[index]
			if byte >= 65, byte <= 90 { byte += 32 }
			if byte != tag[offset] { return false }
			index += 1
			offset += 1
		}
		return true
	}

	/// true when two byte ranges name the same tag, ignoring ascii case.
	static func equalsTag(_ bytes: [UInt8], _ lhs: Range<Int>, _ other: [UInt8], _ rhs: Range<Int>) -> Bool {
		guard lhs.count == rhs.count else { return false }
		var left = lhs.lowerBound
		var right = rhs.lowerBound
		while left < lhs.upperBound {
			var a = bytes[left]
			var b = other[right]
			if a >= 65, a <= 90 { a += 32 }
			if b >= 65, b <= 90 { b += 32 }
			if a != b { return false }
			left += 1
			right += 1
		}
		return true
	}

	static func isSpace(_ byte: UInt8) -> Bool {
		byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d
	}
}

// MARK: - baselines, patches, the differ

/// what a session keeps between two renders of one page: region hashes plus the
/// residue hash. 8 bytes per region, never the html.
public struct RenderBaseline: Sendable {
	public let digest: RenderDigest
	/// the residue hash the next diff vetoes on.
	///
	/// `package`: like ``RenderSnapshot/residue``, it is the differ's input, not
	/// a caller's. a baseline is obtained from ``RenderSnapshot/baseline`` and
	/// handed back to ``RenderDiffer``; nothing outside this module inspects it.
	package let residue: UInt64

	package init(digest: RenderDigest, residue: UInt64) {
		self.digest = digest
		self.residue = residue
	}
}

/// what moved between two renders of one page.
public struct RenderPatch: Sendable {
	/// the regions whose bytes changed, in byte order. empty when ``isFullPage``.
	public let changed: [FragmentUpdate]
	/// regions the previous render had and this one does not.
	///
	/// the wire has no "remove" op, so a removal is always answered with a full
	/// page; the ids are carried for a caller that can express it (a client with
	/// its own remove path) and for diagnostics.
	public let removed: [RegionID]
	/// true when the caller must send the whole page: a first render, a change
	/// outside every region, a region that appeared, or one that vanished.
	public let isFullPage: Bool

	public init(changed: [FragmentUpdate], removed: [RegionID], isFullPage: Bool) {
		self.changed = changed
		self.removed = removed
		self.isFullPage = isFullPage
	}

	/// true when there is nothing to send at all — the render is byte-identical
	/// to the previous one over every region and the residue.
	public var isEmpty: Bool { !isFullPage && changed.isEmpty && removed.isEmpty }
}

/// compares a render to the previous one and describes what moved.
///
/// holds hashes only, so a session's diff state is O(regions), not O(page).
/// one instance per page instance: `previous` is the baseline of the render
/// this differ was built for.
public struct RenderDiffer: Sendable {
	private let previous: RenderBaseline?

	/// a differ for a page that has rendered before.
	///
	/// `nil` means "no previous render", which every patch answers as a full
	/// page rather than as a patch against an empty baseline.
	public init(previous: RenderBaseline?) {
		self.previous = previous
	}

	/// a differ for a page's first render.
	public init() {
		self.previous = nil
	}

	/// what moved from the baseline to `next`.
	public func patch(_ next: RenderSnapshot) -> RenderPatch {
		guard let previous else {
			return RenderPatch(changed: [], removed: [], isFullPage: true)
		}
		let before = previous.digest.regions
		let after = next.digest.regions

		var removed: [RegionID] = []
		for id in before.keys where after[id] == nil {
			removed.append(id)
		}
		removed.sort { $0.rawValue < $1.rawValue }

		// a region the previous render did not have is an insertion, and an
		// insertion has no wire shape: the client cannot place bytes it has no
		// element for. so it is a full page too.
		let appeared = after.keys.contains { before[$0] == nil }
		if next.residue != previous.residue || appeared || !removed.isEmpty {
			return RenderPatch(changed: [], removed: removed, isFullPage: true)
		}

		var moved: [RegionSpan] = []
		for span in next.spans where before[span.id] != after[span.id] {
			// an outer region's bytes already contain its children's, so a
			// changed child inside a changed parent would ship twice; the parent
			// carries it.
			if let outer = moved.last, span.start >= outer.start, span.end <= outer.end {
				continue
			}
			moved.append(span)
		}

		var changed: [FragmentUpdate] = []
		changed.reserveCapacity(moved.count)
		for span in moved {
			changed.append(
				FragmentUpdate(
					id: span.id.rawValue,
					html: String(decoding: next.bytes[span.start..<span.end], as: UTF8.self)
				)
			)
		}
		return RenderPatch(changed: changed, removed: [], isFullPage: false)
	}
}

// MARK: - hashing

/// fnv-1a, 64-bit — `HTMLBuffer.regionHash`'s exact algorithm, so a digest
/// recorded during a buffered render and one derived from finished markup agree
/// for the same region boundaries.
@inline(__always)
private func fnv1a(_ bytes: [UInt8], _ range: Range<Int>) -> UInt64 {
	var hash: UInt64 = 0xcbf2_9ce4_8422_2325
	for index in range {
		hash ^= UInt64(bytes[index])
		hash = hash &* 0x0000_0100_0000_01b3
	}
	return hash
}

/// the hash of everything in `scope` that no span covers.
///
/// spans are disjoint after merging (a nested region's bytes are also its
/// parent's, and the parent's span already excludes them from the gaps).
private func residueHash(_ bytes: [UInt8], scope: Range<Int>, spans: [RegionSpan]) -> UInt64 {
	var hash: UInt64 = 0xcbf2_9ce4_8422_2325
	var cursor = scope.lowerBound
	for span in spans {
		let start = max(span.start, scope.lowerBound)
		let end = min(span.end, scope.upperBound)
		guard end > start else { continue }
		if start > cursor {
			for index in cursor..<start {
				hash ^= UInt64(bytes[index])
				hash = hash &* 0x0000_0100_0000_01b3
			}
		}
		cursor = max(cursor, end)
	}
	if cursor < scope.upperBound {
		for index in cursor..<scope.upperBound {
			hash ^= UInt64(bytes[index])
			hash = hash &* 0x0000_0100_0000_01b3
		}
	}
	return hash
}
