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
	/// region id → hash of that region's *own* bytes: its range minus every
	/// tracked descendant's range.
	///
	/// this is what finest coverage compares, and it exists for the same
	/// memory reason the digest does: a parent's own hash moves when the
	/// parent's markup moves and not when a child inside it moves, so a
	/// changed child can ship alone without the differ keeping last render's
	/// bytes to prove it. 8 bytes per region, exactly like ``digest``.
	///
	/// an excluded region gets no entry: it can never ship, so its own hash is
	/// never consulted and is not retained.
	package let own: [RegionID: UInt64]
	/// the region ids this snapshot was derived with excluded — subtrees that
	/// never ship.
	///
	/// `package`: the differ reads it to answer "is this span inside an
	/// excluded subtree"; a consumer states exclusion once, in its
	/// ``RegionPolicy``.
	package let excluded: Set<RegionID>

	/// a snapshot of a render whose region spans the caller recorded.
	///
	/// `root` defaults to the whole render; a document passes its `<body>`
	/// range so per-render head bytes stay out of the diff.
	///
	/// `package`: constructing a snapshot from caller-recorded spans is how this
	/// module's own scanner and tests build one. a consumer that has bytes asks
	/// for ``derived(fromMarkup:policy:)``.
	package init(
		html: String, spans: [RegionSpan], root: Range<Int>? = nil,
		excluded: Set<RegionID> = []
	) {
		self.init(bytes: Array(html.utf8), spans: spans, root: root, excluded: excluded)
	}

	package init(
		bytes: [UInt8], spans: [RegionSpan], root: Range<Int>? = nil,
		excluded: Set<RegionID> = []
	) {
		let ordered = spans.sorted { $0.start < $1.start }
		var regions: [RegionID: UInt64] = [:]
		regions.reserveCapacity(ordered.count)
		for span in ordered {
			regions[span.id] = fnv1a(bytes, span.range)
		}
		let scope = root ?? 0..<bytes.count
		var own: [RegionID: UInt64] = [:]
		own.reserveCapacity(ordered.count)
		for span in ordered where !excluded.contains(span.id) {
			own[span.id] = ownHash(bytes, span: span, spans: ordered)
		}
		self.bytes = bytes
		self.spans = ordered
		self.digest = RenderDigest(regions: regions)
		self.root = scope
		// the span list is passed *whole*: an excluded region keeps its span,
		// so its bytes stay covered and reach neither the residue nor (through
		// `own`) an ancestor. dropping an excluded span here is the bug this
		// line exists to prevent — its bytes would fall into the residue, and
		// a token write would then force a full page on every render.
		self.residue = residueHash(bytes, scope: scope, spans: ordered)
		self.own = own
		self.excluded = excluded
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
	public var baseline: RenderBaseline {
		RenderBaseline(digest: digest, residue: residue, own: own, excluded: excluded)
	}
}

// MARK: - markup-derived regions

extension RenderSnapshot {
	/// the snapshot of a finished page: every element the policy's identity
	/// names is a region — `data-component-id` for the default, the element's
	/// DOM `id` for `.elementID`, exactly as design E specifies for
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
	public static func derived(fromMarkup html: String, policy: RegionPolicy = .default) -> RenderSnapshot {
		let bytes = Array(html.utf8)
		// the identity is a scan input, not a post-processing step: spans are
		// what the digest, the own-bytes hashes and the patch ids are all keyed
		// by, so resolving it here carries to every consumer at once.
		let scanned = MarkupScan.scan(bytes, identity: policy.identity)
		let root = scanned.body ?? 0..<bytes.count
		// a region outside the diff root (a control in the head, which no page
		// emits) is not addressable by an in-place patch.
		let spans = scanned.spans.filter { $0.start >= root.lowerBound && $0.end <= root.upperBound }
		// `policy.excluded` reaches the snapshot because exclusion changes the
		// hashes it records.
		return RenderSnapshot(bytes: bytes, spans: spans, root: root, excluded: policy.excluded)
	}
}

/// the byte-level element scan region derivation stands on.
///
/// it is a scanner, not a parser: it finds a tag's name, its end, and the close
/// that matches it, and it never builds a node. attribute values are html-escaped
/// by every framework emitter, so a raw `<` inside one cannot forge a tag start.
private enum MarkupScan {
	static let componentIDPrefix: [UInt8] = Array("data-component-id=\"".utf8)
	/// the element `id` attribute's name and quote. searched only with an
	/// attribute-name boundary in front of it — see ``elementID(in:tag:)``.
	static let elementIDPrefix: [UInt8] = Array("id=\"".utf8)
	static let bodyTag: [UInt8] = Array("body".utf8)
	/// elements that never have a closing tag.
	static let voidTags: [[UInt8]] = [
		"area", "base", "br", "col", "embed", "hr", "img", "input",
		"link", "meta", "param", "source", "track", "wbr",
	].map { Array($0.utf8) }

	/// one tag walk: the document's `<body>` span (when there is one) and every
	/// element the policy's identity makes a region.
	///
	/// a single pass with an open-element stack, so the cost is O(bytes) once —
	/// not one rescan per region, which is what a real page (38 controls over
	/// 168 KB) makes unaffordable. no node is built and no tag name is
	/// materialized: the stack holds byte ranges into the render.
	static func scan(
		_ bytes: [UInt8], identity: RegionPolicy.Identity
	) -> (body: Range<Int>?, spans: [RegionSpan]) {
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
				let id = regionID(in: bytes, tag: index..<tagClose, identity: identity)
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

	/// the id a region is keyed by, per the policy's identity.
	///
	/// `.componentAttribute` — the default — is the routing id a control
	/// declares, and that path is byte-for-byte the read it has always been.
	/// `.elementID` is the DOM `id` the engine resolves with
	/// `getElementById`, which is what a `replace` addresses; the component
	/// attribute only stands in when the element carries no `id` at all, so a
	/// page that never emits one keeps working.
	static func regionID(
		in bytes: [UInt8], tag: Range<Int>, identity: RegionPolicy.Identity
	) -> String? {
		switch identity {
		case .componentAttribute:
			return componentID(in: bytes, tag: tag)
		case .elementID:
			return elementID(in: bytes, tag: tag) ?? componentID(in: bytes, tag: tag)
		}
	}

	/// the value of the element's `id` attribute, when its opening tag carries
	/// one.
	///
	/// the match is anchored to an attribute-name boundary: the byte before
	/// `id=` must be ascii whitespace. that anchor is the whole correctness of
	/// this read — `data-component-id="` *ends* with `id="`, so an unanchored
	/// search resolves such an element to its component id while looking
	/// perfectly healthy, and the two differ for exactly the controls this
	/// identity exists for. `<` is never whitespace, so `id=` can neither open
	/// the tag nor follow the tag name.
	///
	/// only a double-quoted value is read, exactly as `componentID` does: every
	/// framework emitter escapes `"` inside an attribute value, so a
	/// single-quoted or entity-encoded `id` is not a shape this scanner has to
	/// survive.
	static func elementID(in bytes: [UInt8], tag: Range<Int>) -> String? {
		var from = tag.lowerBound
		while let hit = find(elementIDPrefix, in: bytes, from: from, limit: tag.upperBound) {
			if hit > tag.lowerBound, isSpace(bytes[hit - 1]) {
				let valueStart = hit + elementIDPrefix.count
				guard let valueEnd = findByte(quote, in: bytes, from: valueStart) else { return nil }
				guard valueEnd <= tag.upperBound, valueEnd > valueStart else { return nil }
				return String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
			}
			// this `id=` is the tail of another attribute's name (`data-id=`,
			// `data-component-id=`): keep looking.
			from = hit + 1
		}
		return nil
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

// MARK: - region policy

/// how a render's regions are diffed, once a caller opts out of today's
/// coarse contract.
///
/// `.default` is exactly the behaviour every existing caller already has:
/// regions are `data-component-id` elements, a changed parent carries its
/// changed children, an appeared or vanished region is a full page, nothing is
/// excluded, and an update leaves the client's transition policy alone. a
/// policy that names `.finest` opts into the finer contract; a caller that
/// never mentions a policy cannot observe this type at all.
public struct RegionPolicy: Sendable, Equatable {
	/// where a region's patch id comes from.
	///
	/// `componentAttribute` is the routing id a control declares; `elementID`
	/// is the DOM `id` the engine resolves with `getElementById`, falling back
	/// to `data-component-id` only when the element carries no `id`. the id a
	/// region is keyed by is resolved during the scan, so the digest, the
	/// own-bytes hashes and the ids a patch carries all agree.
	public enum Identity: Sendable, Equatable {
		case componentAttribute
		case elementID
	}

	/// how overlapping changed regions are collapsed.
	public enum Coverage: Sendable, Equatable {
		/// a changed region ships whole, children included — today's shape.
		case coarse
		/// a region ships only when its *own* bytes moved: its range minus
		/// every tracked descendant's range. a changed child therefore ships
		/// the child, not the parent that contains it.
		case finest
	}

	/// what a region the previous render did not have escalates to.
	public enum Escalation: Sendable, Equatable {
		/// the whole page. an insertion has no wire shape, so a client cannot
		/// place bytes it has no element for.
		case fullPage
		/// the nearest ancestor region both renders have, which does have a
		/// wire shape (`replace`) and carries the inserted subtree with it.
		/// a full page only when no ancestor is tracked in both renders.
		case nearestTrackedAncestor
	}

	/// where a region's patch id comes from.
	public var identity: Identity
	/// how overlapping changed regions are collapsed.
	public var coverage: Coverage
	/// what appeared regions escalate to.
	public var escalation: Escalation
	/// subtrees that never ship, and whose bytes are invisible to every
	/// ancestor's own-bytes hash.
	///
	/// this is the token-owned region's escape hatch: a region some other
	/// writer owns (`live-turn-text`, written by `FragmentUpdate.text` on every
	/// streaming token) must not make its ancestors look changed, or every
	/// structural render inside the same subtree would ship a parent just to
	/// carry text the client already has.
	public var excluded: Set<RegionID>
	/// the transition flag every update this policy emits carries.
	///
	/// `nil` — the default — leaves the client's transition policy in charge,
	/// which is what today's differ does.
	public var transition: Bool?

	/// coarse coverage, component-attribute identity, full-page escalation,
	/// nothing excluded, no transition override — today's behaviour.
	public static let `default` = RegionPolicy()

	/// explicit: a public memberwise init is internal, so the shape every
	/// caller builds a policy through is spelled here.
	public init(
		identity: Identity = .componentAttribute,
		coverage: Coverage = .coarse,
		escalation: Escalation = .fullPage,
		excluded: Set<RegionID> = [],
		transition: Bool? = nil
	) {
		self.identity = identity
		self.coverage = coverage
		self.escalation = escalation
		self.excluded = excluded
		self.transition = transition
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
	/// region id → hash of that region's own bytes, carried from the render
	/// this baseline was taken of so finest coverage can compare own bytes
	/// across renders. hashes only — the bytes are sliced out of the render
	/// that just finished.
	package let own: [RegionID: UInt64]
	/// the exclusions the render was derived with, so a differ built from this
	/// baseline and a policy that disagrees still knows what the previous
	/// render treated as invisible.
	package let excluded: Set<RegionID>

	package init(
		digest: RenderDigest, residue: UInt64, own: [RegionID: UInt64],
		excluded: Set<RegionID> = []
	) {
		self.digest = digest
		self.residue = residue
		self.own = own
		self.excluded = excluded
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
	/// outside every region, a region that vanished, or a region that appeared
	/// with no tracked ancestor to carry it. a `.finest` policy with
	/// ``RegionPolicy/Escalation/nearestTrackedAncestor`` answers an insertion
	/// with that ancestor's update instead, so this stays `false` there.
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
///
/// the `policy` decides *which* region answers a change. `.default` is the
/// coarse contract this type has always had; `.finest` ships the region whose
/// own bytes moved, so a changed child no longer drags its parent along.
public struct RenderDiffer: Sendable {
	private let previous: RenderBaseline?
	/// how this differ collapses changes: `.default` is the contract every
	/// caller already has, `.finest` is the opt-in finer one.
	private let policy: RegionPolicy

	/// a differ for a page that has rendered before.
	///
	/// `nil` means "no previous render", which every patch answers as a full
	/// page rather than as a patch against an empty baseline.
	public init(previous: RenderBaseline?, policy: RegionPolicy = .default) {
		self.previous = previous
		self.policy = policy
	}

	/// a differ for a page's first render.
	public init(policy: RegionPolicy = .default) {
		self.previous = nil
		self.policy = policy
	}

	/// what moved from the baseline to `next`.
	public func patch(_ next: RenderSnapshot) -> RenderPatch {
		guard let previous else {
			return RenderPatch(changed: [], removed: [], isFullPage: true)
		}
		switch policy.coverage {
		case .coarse:
			return coarsePatch(next, previous: previous)
		case .finest:
			return finestPatch(next, previous: previous)
		}
	}

	/// the contract every caller already has: a changed region ships whole, so
	/// a changed parent carries its changed children and only the outermost
	/// moved region reaches the wire.
	private func coarsePatch(_ next: RenderSnapshot, previous: RenderBaseline) -> RenderPatch {
		let before = previous.digest.regions
		let after = next.digest.regions
		let excluded = exclusions(next, previous)

		var removed: [RegionID] = []
		for id in before.keys where after[id] == nil && !excluded.contains(id) {
			removed.append(id)
		}
		removed.sort { $0.rawValue < $1.rawValue }

		// a region the previous render did not have is an insertion, and an
		// insertion has no wire shape: the client cannot place bytes it has no
		// element for. so it is a full page too.
		let appeared = after.keys.contains { before[$0] == nil && !excluded.contains($0) }
		if next.residue != previous.residue || appeared || !removed.isEmpty {
			return RenderPatch(changed: [], removed: removed, isFullPage: true)
		}

		var moved: [RegionSpan] = []
		for span in next.spans where before[span.id] != after[span.id] {
			// an excluded region never ships, and this guard is vacuous for
			// `.default` (nothing is excluded), so today's shape is unchanged.
			if excluded.contains(span.id) { continue }
			// an outer region's bytes already contain its children's, so a
			// changed child inside a changed parent would ship twice; the parent
			// carries it.
			if let outer = moved.last, span.start >= outer.start, span.end <= outer.end {
				continue
			}
			moved.append(span)
		}

		return RenderPatch(
			changed: updates(moved, from: next), removed: [], isFullPage: false)
	}

	/// the opt-in contract: a region ships iff its *own* bytes moved — its
	/// range minus every tracked descendant's range — so a changed child ships
	/// the child and not the parent that contains it.
	private func finestPatch(_ next: RenderSnapshot, previous: RenderBaseline) -> RenderPatch {
		let excluded = exclusions(next, previous)
		// the set names regions; what it excludes is the subtree under each,
		// because a descendant's bytes are inside its ancestor's.
		let excludedRoots = next.spans.filter { excluded.contains($0.id) }
		func isExcluded(_ span: RegionSpan) -> Bool {
			if excluded.contains(span.id) { return true }
			return excludedRoots.contains { span.start >= $0.start && span.end <= $0.end }
		}

		// a region the previous render had and this one does not is a removal.
		// the wire has no remove op, and a baseline keeps hashes only — no
		// offsets — so there is no ancestor to escalate to: a full page.
		var vanished: [RegionID] = []
		for id in previous.digest.regions.keys
		where next.digest.regions[id] == nil && !excluded.contains(id) {
			vanished.append(id)
		}
		vanished.sort { $0.rawValue < $1.rawValue }
		if !vanished.isEmpty {
			return RenderPatch(changed: [], removed: vanished, isFullPage: true)
		}

		// an insertion has no wire shape either. `.nearestTrackedAncestor`
		// answers it with an update the client can apply — the whole subtree of
		// an ancestor both renders have, which now contains the new region.
		var escalated: [RegionSpan] = []
		var unresolved = false
		for span in next.spans where previous.digest.regions[span.id] == nil {
			if isExcluded(span) { continue }
			if policy.escalation == .nearestTrackedAncestor,
				let ancestor = nearestTrackedAncestor(
					of: span, in: next.spans, tracked: previous.digest.regions, excluded: excluded)
			{
				escalated.append(ancestor)
			} else {
				unresolved = true
			}
		}
		if unresolved {
			// bytes no region the client has can carry: only a full page puts
			// them on screen.
			return RenderPatch(changed: [], removed: [], isFullPage: true)
		}

		// the residue is bytes *outside* every tracked span, so no region can
		// carry a change in it — not even an ancestor, which is why this stays
		// a full page under either escalation.
		if next.residue != previous.residue {
			return RenderPatch(changed: [], removed: [], isFullPage: true)
		}

		var targets: [RegionID: RegionSpan] = [:]
		for span in escalated { targets[span.id] = span }
		for span in next.spans {
			if isExcluded(span) { continue }
			// an appeared region is answered by its ancestor above; shipping it
			// too would duplicate bytes the ancestor's update already carries,
			// and a client that applied the ancestor first would address an id
			// it has just re-created.
			guard previous.digest.regions[span.id] != nil else { continue }
			// both hashes exist for every region neither render excluded; a
			// missing one is a policy that moved mid-session, and the safe
			// direction is to ship the region rather than leave it stale.
			guard let was = previous.own[span.id], let now = next.own[span.id] else {
				targets[span.id] = span
				continue
			}
			if was != now { targets[span.id] = span }
		}

		let moved = targets.values.sorted { $0.start < $1.start }
		return RenderPatch(
			changed: updates(moved, from: next), removed: [], isFullPage: false)
	}

	/// the exclusion set a diff must honour: what this render was derived with,
	/// plus what the baseline was. a region excluded in either render has no
	/// comparable own-bytes hash, so it can carry no change.
	private func exclusions(_ next: RenderSnapshot, _ previous: RenderBaseline) -> Set<RegionID> {
		next.excluded.union(previous.excluded)
	}

	/// the nearest region containing `span` that the previous render also had —
	/// so the client already has the element a `replace` addresses.
	private func nearestTrackedAncestor(
		of span: RegionSpan, in spans: [RegionSpan], tracked: [RegionID: UInt64],
		excluded: Set<RegionID>
	) -> RegionSpan? {
		var best: RegionSpan?
		for candidate in spans {
			guard candidate.start <= span.start, candidate.end >= span.end else { continue }
			guard candidate.start < span.start || candidate.end > span.end else { continue }
			guard tracked[candidate.id] != nil else { continue }
			guard !excluded.contains(candidate.id) else { continue }
			if let current = best, current.end - current.start <= candidate.end - candidate.start {
				continue
			}
			best = candidate
		}
		return best
	}

	/// one `.replace` per region, in the order given, carrying the policy's
	/// transition flag (`nil` for `.default`, which is what today's differ
	/// emits).
	private func updates(_ spans: [RegionSpan], from next: RenderSnapshot) -> [FragmentUpdate] {
		var changed: [FragmentUpdate] = []
		changed.reserveCapacity(spans.count)
		for span in spans {
			changed.append(
				FragmentUpdate(
					id: span.id.rawValue,
					html: String(decoding: next.bytes[span.start..<span.end], as: UTF8.self),
					transition: policy.transition
				)
			)
		}
		return changed
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

/// the hash of one region's *own* bytes: its range minus every tracked
/// descendant's range.
///
/// the ranges are disjoint once the descendants are removed, so this walks the
/// span list in start order and hashes the gaps — the region's opening tag and
/// whatever markup it holds outside a tracked child. `spans` is the whole
/// ordered list; a span contained in `span` is a descendant, and a nested one
/// (a grandchild) is already inside a descendant that advanced the cursor.
private func ownHash(_ bytes: [UInt8], span: RegionSpan, spans: [RegionSpan]) -> UInt64 {
	var hash: UInt64 = 0xcbf2_9ce4_8422_2325
	var cursor = span.start
	for child in spans {
		guard child.start >= cursor, child.end <= span.end, child.end > child.start else { continue }
		guard child.start > span.start || child.end < span.end else { continue }
		if child.start > cursor {
			for index in cursor..<child.start {
				hash ^= UInt64(bytes[index])
				hash = hash &* 0x0000_0100_0000_01b3
			}
		}
		cursor = max(cursor, child.end)
	}
	if cursor < span.end {
		for index in cursor..<span.end {
			hash ^= UInt64(bytes[index])
			hash = hash &* 0x0000_0100_0000_01b3
		}
	}
	return hash
}

/// the hash of everything in `scope` that no span covers.
///
/// spans are disjoint after merging (a nested region's bytes are also its
/// parent's, and the parent's span already excludes them from the gaps).
///
/// an excluded region is passed here like any other: its span keeps its bytes
/// *out* of the residue, which is the whole point — a token-owned region whose
/// text changes on every render must not move the residue, or every structural
/// render would be forced to a full page. exclusion is subtracted where it
/// belongs instead, from ``ownHash``.
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
