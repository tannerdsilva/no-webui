import Testing
import WebUICore
import WebUIState

// design E's differ (plan §9.5 E4, §13 D1, §14 N25).
//
// the gate that matters is the property test at the bottom: a random mutation
// of a page's state, the patch applied to the pre-mutation markup, must equal a
// full re-render — byte for byte. it is the one test that can catch a differ
// that quietly under-sends, which is a stale page and the worst failure this
// design can produce.
//
// nothing here is a fixture the differ was written to handle: the page builder
// is a plain string, the "dom" applier re-finds elements by `id` the way a
// client does, and the mutations are drawn from a seeded generator.

// MARK: - the page under test

/// a page whose ten cells are the only regions, plus two pieces of state that
/// render *outside* every region (so a patch that only looks at regions is
/// caught) and one head field that moves on every render (a document's nonce,
/// which must never count as a change).
private struct Board: Sendable {
	var title = "board"
	var nonce = "n0"
	var heading = "board"
	var footer = "ready"
	var cells: [String] = (0..<10).map { "cell \($0)" }
	/// a per-render counter that only the head carries.
	var renderIndex = 0

	static func make() -> Board { Board() }

	/// the rendered page. a document, because a real page is one: the nonce and
	/// the title live in the head, and the diff must ignore them.
	func render() -> String {
		var html = "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
		html += "  <meta charset=\"UTF-8\">\n"
		html += "  <title>\(title)</title>\n"
		html += "  <meta name=\"render\" content=\"\(nonce)-\(renderIndex)\">\n"
		html += "</head>\n<body>\n"
		html += "  <h1 class=\"board-heading\">\(heading)</h1>\n"
		for (index, cell) in cells.enumerated() {
			html += "  <button id=\"cell-\(index)\" data-component-id=\"cell-\(index)\" "
			html += "data-event=\"click\">\(cell)</button>\n"
		}
		html += "  <p class=\"board-footer\">\(footer)</p>\n"
		html += "</body>\n</html>\n"
		return html
	}
}

// MARK: - a client's element lookup

/// the client's half of the contract: find the element a fragment names by its
/// `id`, replace its outer html. implemented by scanning tags with a stack,
/// which is what a browser's parser gives the engine — deliberately independent
/// of the differ's own scanner.
private enum ClientDOM {
	struct Located {
		let id: String
		let span: Range<Int>
	}

	/// every element carrying an `id`, with the span of its whole subtree.
	static func elements(in html: String) -> [Located] {
		let bytes = Array(html.utf8)
		var located: [Located] = []
		struct Open {
			let tag: String
			let start: Int
			let id: String?
		}
		var stack: [Open] = []
		var index = 0
		while index < bytes.count {
			guard bytes[index] == UInt8(ascii: "<") else {
				index += 1
				continue
			}
			guard index + 1 < bytes.count else { break }
			let isClose = bytes[index + 1] == UInt8(ascii: "/")
			let nameStart = isClose ? index + 2 : index + 1
			var nameEnd = nameStart
			while nameEnd < bytes.count, !isSpace(bytes[nameEnd]), bytes[nameEnd] != UInt8(ascii: ">") {
				nameEnd += 1
			}
			guard nameEnd > nameStart else {
				index += 1
				continue
			}
			let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self).lowercased()
			let tagClose = scanToTagEnd(bytes, from: nameEnd)
			if isClose {
				if let match = stack.lastIndex(where: { $0.tag == name }) {
					let open = stack.remove(at: match)
					if let id = open.id {
						located.append(Located(id: id, span: open.start..<tagClose + 1))
					}
				}
			} else {
				let id = attribute("id", in: bytes, from: nameEnd, to: tagClose)
				let selfClosing = tagClose > index && bytes[tagClose - 1] == UInt8(ascii: "/")
				if selfClosing || voidElements.contains(name) {
					if let id { located.append(Located(id: id, span: index..<tagClose + 1)) }
				} else {
					stack.append(Open(tag: name, start: index, id: id))
				}
			}
			index = tagClose + 1
		}
		return located
	}

	/// `html` with every fragment's element replaced — the engine's
	/// `applyFragments`, reduced to what this file asserts.
	static func apply(_ patch: RenderPatch, newHTML: String, to html: String) -> String {
		if patch.isFullPage { return newHTML }
		var current = html
		for update in patch.changed {
			guard let element = elements(in: current).first(where: { $0.id == update.id }) else {
				return "<missing:\(update.id)>"
			}
			var bytes = Array(current.utf8)
			bytes.replaceSubrange(element.span, with: Array(update.html.utf8))
			current = String(decoding: bytes, as: UTF8.self)
		}
		return current
	}

	private static let voidElements: Set<String> = [
		"area", "base", "br", "col", "embed", "hr", "img", "input",
		"link", "meta", "param", "source", "track", "wbr",
	]

	private static func isSpace(_ byte: UInt8) -> Bool {
		byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d
	}

	private static func scanToTagEnd(_ bytes: [UInt8], from: Int) -> Int {
		var index = from
		var quote: UInt8?
		while index < bytes.count {
			let byte = bytes[index]
			if let active = quote {
				if byte == active { quote = nil }
			} else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
				quote = byte
			} else if byte == UInt8(ascii: ">") {
				return index
			}
			index += 1
		}
		return bytes.count - 1
	}

	private static func attribute(_ name: String, in bytes: [UInt8], from: Int, to: Int) -> String? {
		let needle = Array(" \(name)=\"".utf8)
		var index = from
		while index + needle.count <= min(to, bytes.count) {
			var matched = true
			for offset in 0..<needle.count where bytes[index + offset] != needle[offset] {
				matched = false
				break
			}
			if matched {
				let valueStart = index + needle.count
				var valueEnd = valueStart
				while valueEnd < bytes.count, bytes[valueEnd] != UInt8(ascii: "\"") { valueEnd += 1 }
				return String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
			}
			index += 1
		}
		return nil
	}
}

// MARK: - unit gates

/// the byte offset of `needle` in `html`, without importing Foundation for one
/// `range(of:)`.
private func indexOf(_ needle: String, in html: String) -> Int? {
	let haystack = Array(html.utf8)
	let needleBytes = Array(needle.utf8)
	guard !needleBytes.isEmpty, haystack.count >= needleBytes.count else { return nil }
	for start in 0...(haystack.count - needleBytes.count)
	where Array(haystack[start..<(start + needleBytes.count)]) == needleBytes {
		return start
	}
	return nil
}

@Suite("design e — render differ")
struct RenderDifferTests {
	/// a page rendered once, and the baseline a session would keep for it.
	private func baseline(_ board: Board) -> RenderBaseline {
		RenderSnapshot.derived(fromMarkup: board.render()).baseline
	}

	@Test("the ten cells are ten regions, and the head is not one")
	func regionsAreDerivedFromControls() {
		let html = Board.make().render()
		let snapshot = RenderSnapshot.derived(fromMarkup: html)
		#expect(snapshot.spans.count == 10)
		#expect(snapshot.digest.regions.count == 10)
		#expect(snapshot.spans.map(\.id.rawValue) == (0..<10).map { "cell-\($0)" })
		// the root is the body: head bytes (nonce, title) are outside the diff.
		guard let bodyStart = indexOf("<body>", in: html) else {
			Issue.record("fixture lost its body")
			return
		}
		#expect(snapshot.root.lowerBound == bodyStart)
	}

	@Test("mutating one region is exactly one update, and it is that region's bytes")
	func oneChangeIsOneFragment() {
		let before = Board.make()
		var after = before
		after.cells[4] = "cell four, changed"
		let newHTML = after.render()

		let patch = RenderDiffer(previous: baseline(before))
			.patch(RenderSnapshot.derived(fromMarkup: newHTML))

		#expect(!patch.isFullPage)
		#expect(patch.changed.count == 1)
		#expect(patch.changed.first?.id == "cell-4")
		#expect(patch.changed.first?.html == "<button id=\"cell-4\" data-component-id=\"cell-4\" data-event=\"click\">cell four, changed</button>")
		#expect(ClientDOM.apply(patch, newHTML: newHTML, to: before.render()) == newHTML)
	}

	@Test("a render that changes nothing is an empty patch")
	func noChangeIsNoFrame() {
		let board = Board.make()
		let snapshot = RenderSnapshot.derived(fromMarkup: board.render())
		let patch = RenderDiffer(previous: snapshot.baseline)
			.patch(RenderSnapshot.derived(fromMarkup: board.render()))
		#expect(patch.isEmpty)
		#expect(patch.changed.isEmpty)
		#expect(!patch.isFullPage)
	}

	@Test("a head-only change — a fresh nonce, a render counter — is not a patch")
	func headVolatilityIsNotAChange() {
		let before = RenderSnapshot.derived(fromMarkup: Board.make().render())
		var after = Board.make()
		after.nonce = "n1"
		after.renderIndex = 1
		let patch = RenderDiffer(previous: before.baseline)
			.patch(RenderSnapshot.derived(fromMarkup: after.render()))
		#expect(patch.isEmpty, "a document mints a new nonce per render; the diff must not see it")
	}

	@Test("a change outside every region is a full page, never a silent patch")
	func outOfRegionChangeIsFullPage() {
		var after = Board.make()
		after.heading = "renamed board"
		let patch = RenderDiffer(previous: baseline(Board.make()))
			.patch(RenderSnapshot.derived(fromMarkup: after.render()))
		#expect(patch.isFullPage)
		#expect(patch.changed.isEmpty)
	}

	@Test("a region that vanishes is a full page — the wire has no remove op")
	func removedRegionIsFullPage() {
		var after = Board.make()
		after.cells.removeLast()
		let patch = RenderDiffer(previous: baseline(Board.make()))
			.patch(RenderSnapshot.derived(fromMarkup: after.render()))
		#expect(patch.isFullPage)
		#expect(patch.removed.map(\.rawValue) == ["cell-9"])
	}

	@Test("a region that appears is a full page — the client has no element for it")
	func addedRegionIsFullPage() {
		var after = Board.make()
		after.cells.append("cell 10")
		let patch = RenderDiffer(previous: baseline(Board.make()))
			.patch(RenderSnapshot.derived(fromMarkup: after.render()))
		#expect(patch.isFullPage)
	}

	@Test("a first render is a full page")
	func firstRenderIsFullPage() {
		let patch = RenderDiffer().patch(RenderSnapshot.derived(fromMarkup: Board.make().render()))
		#expect(patch.isFullPage)
	}

	@Test("several changed regions ship in byte order, one update each")
	func severalChanges() {
		var after = Board.make()
		after.cells[1] = "one"
		after.cells[7] = "seven"
		let patch = RenderDiffer(previous: baseline(Board.make()))
			.patch(RenderSnapshot.derived(fromMarkup: after.render()))
		#expect(patch.changed.map(\.id) == ["cell-1", "cell-7"])
	}

	// MARK: the policy's finer coverage

	@Test("finest coverage: a changed child ships instead of its parent")
	func finestChildSuppressesParent() {
		func outer(_ inner: String) -> String {
			#"<div id="outer" data-component-id="outer">\#(inner)</div>"#
		}
		let before = outer(#"<span data-component-id="a">1</span><span data-component-id="b">2</span>"#)
		let after  = outer(#"<span data-component-id="a">1</span><span data-component-id="b">CHANGED</span>"#)
		let p = RegionPolicy(identity: .componentAttribute, coverage: .finest)
		let pre = RenderSnapshot.derived(fromMarkup: before, policy: p)
		let patch = RenderDiffer(previous: pre.baseline, policy: p)
			.patch(RenderSnapshot.derived(fromMarkup: after, policy: p))
		#expect(!patch.isFullPage)
		#expect(patch.changed.map(\.id) == ["b"], "the child must ship, not #outer")
	}

	@Test("an appeared region inside a tracked ancestor ships the ancestor, not the page")
	func appearedRegionEscalatesToNearestTrackedAncestor() {
		func page(_ extra: String) -> String {
			#"<div id="app" data-component-id="app"><div id="panel" data-component-id="panel">\#(extra)</div></div>"#
		}
		let p = RegionPolicy(identity: .componentAttribute, coverage: .finest,
		                     escalation: .nearestTrackedAncestor)
		let before = RenderSnapshot.derived(fromMarkup: page(""), policy: p)
		let after = RenderSnapshot.derived(fromMarkup: page(#"<span data-component-id="row">x</span>"#), policy: p)
		let patch = RenderDiffer(previous: before.baseline, policy: p).patch(after)
		#expect(!patch.isFullPage)
		#expect(patch.changed.map(\.id) == ["panel"], "nearest tracked ancestor of #row")
	}

	@Test("an excluded region is invisible: it ships nothing, and cannot force the page")
	func excludedRegionShipsNothing() {
		func page(_ token: String) -> String {
			#"<div id="app" data-component-id="app"><span data-component-id="live">\#(token)</span><span data-component-id="static">ok</span></div>"#
		}
		let p = RegionPolicy(identity: .componentAttribute, coverage: .finest, excluded: ["live"])
		let before = RenderSnapshot.derived(fromMarkup: page("a"), policy: p)
		let after = RenderSnapshot.derived(fromMarkup: page("b"), policy: p)
		let patch = RenderDiffer(previous: before.baseline, policy: p).patch(after)
		#expect(!patch.isFullPage, "an excluded region's bytes must not reach the residue")
		#expect(patch.changed.isEmpty, "token-owned text is written by op:text, not by the diff")
	}

	// MARK: the scanner's edges

	@Test("a nested control is a region inside a region, and the outer one carries both")
	func nestedRegions() {
		let inner = "<span id=\"inner\" data-component-id=\"inner\">a</span>"
		let element = "<div class=\"panel\"><button id=\"outer\" data-component-id=\"outer\">\(inner)</button></div>"
		let elementChanged = "<div class=\"panel\"><button id=\"outer\" data-component-id=\"outer\">"
			+ "<span id=\"inner\" data-component-id=\"inner\">b</span></button></div>"
		let snapshot = RenderSnapshot.derived(fromMarkup: element)
		#expect(snapshot.spans.map(\.id.rawValue) == ["outer", "inner"])

		let patch = RenderDiffer(previous: snapshot.baseline)
			.patch(RenderSnapshot.derived(fromMarkup: elementChanged))
		#expect(!patch.isFullPage, "the inner change is inside the outer region's bytes")
		#expect(patch.changed.map(\.id) == ["outer"])
		#expect(ClientDOM.apply(patch, newHTML: elementChanged, to: element) == elementChanged)
	}

	@Test("a void element is its own region")
	func voidRegion() {
		let html = "<body><input id=\"q\" data-component-id=\"q\" type=\"text\"><p>after</p></body>"
		let snapshot = RenderSnapshot.derived(fromMarkup: html)
		#expect(snapshot.spans.count == 1)
		let span = snapshot.spans[0]
		#expect(String(decoding: snapshot.bytes[span.start..<span.end], as: UTF8.self)
			== "<input id=\"q\" data-component-id=\"q\" type=\"text\">")
	}

	@Test("the same tag nested does not end a region early")
	func sameTagNesting() {
		let html = "<body><div id=\"a\" data-component-id=\"a\"><div>x</div></div><p>z</p></body>"
		let snapshot = RenderSnapshot.derived(fromMarkup: html)
		#expect(snapshot.spans.count == 1)
		let span = snapshot.spans[0]
		#expect(String(decoding: snapshot.bytes[span.start..<span.end], as: UTF8.self)
			== "<div id=\"a\" data-component-id=\"a\"><div>x</div></div>")
	}

	@Test("an entity-encoded needle in text is not a region")
	func encodedNeedleIsNotARegion() {
		let html = "<body><p>data-component-id=&quot;fake&quot;</p></body>"
		#expect(RenderSnapshot.derived(fromMarkup: html).spans.isEmpty)
	}

	@Test("a markup-derived digest equals the buffer's hash for the same bytes")
	func digestMatchesTheBuffer() {
		let element = "<button id=\"c\" data-component-id=\"c\">v</button>"
		let html = "<body>\(element)</body>"
		let derived = RenderSnapshot.derived(fromMarkup: html)

		var buffer = HTMLBuffer()
		let mark = buffer.beginRegion(RegionID(rawValue: "c"))
		buffer.append(element)
		buffer.endRegion(RegionID(rawValue: "c"), from: mark)

		#expect(derived.digest.regions[RegionID(rawValue: "c")] == buffer.renderDigest.regions[RegionID(rawValue: "c")])
	}
}

// MARK: - the property gate (N25)

/// everything from `<body>` on — the part of a document an in-place patch can
/// change. a client that receives a patch does not re-fetch its `<head>`, so the
/// comparison is scoped exactly where the patch is.
private func bodySuffix(_ html: String) -> String {
	guard let start = indexOf("<body", in: html) else { return html }
	return String(decoding: Array(html.utf8)[start...], as: UTF8.self)
}

private struct SeededGenerator {
	var state: UInt64

	init(seed: UInt64) { state = seed }

	mutating func next() -> UInt64 {
		state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
		return state >> 33
	}

	mutating func int(below upper: Int) -> Int { Int(next() % UInt64(upper)) }
}

@Suite("design e — patch property")
struct RenderPatchPropertyTests {
	/// mutate the state, diff, apply the patch to the old markup, and demand the
	/// result is the full re-render. run enough times that every mutation shape
	/// (one cell, many cells, heading, footer, a combination) is exercised.
	@Test("random mutation → patched markup == full re-render (200 cases)")
	func patchAlwaysReconstructsThePage() {
		for seed in UInt64(1)...200 {
			var generator = SeededGenerator(seed: seed)
			var before = Board.make()
			before.nonce = "n\(seed)"
			before.renderIndex = Int(seed)
			let oldHTML = before.render()
			let oldSnapshot = RenderSnapshot.derived(fromMarkup: oldHTML)

			var after = before
			var mutations: [String] = []
			let rounds = 1 + generator.int(below: 3)
			for _ in 0..<rounds {
				switch generator.int(below: 13) {
				case 0:
					after.heading = "heading \(generator.next())"
					mutations.append("heading")
				case 1:
					after.footer = "footer \(generator.next())"
					mutations.append("footer")
				default:
					let cell = generator.int(below: after.cells.count)
					after.cells[cell] = "cell \(cell) v\(generator.next())"
					mutations.append("cell-\(cell)")
				}
			}
			// every render mints a fresh nonce, exactly as a document does.
			after.nonce = "n\(seed + 1)"
			after.renderIndex = Int(seed) + 1
			let newHTML = after.render()

			let patch = RenderDiffer(previous: oldSnapshot.baseline)
				.patch(RenderSnapshot.derived(fromMarkup: newHTML))
			let applied = ClientDOM.apply(patch, newHTML: newHTML, to: oldHTML)

			// the patch's *shape* is part of the assertion: a mutation confined
			// to regions must stay a patch, and one that touches anything else
			// must fall back to the whole page. a differ that always answers
			// "full page" would reconstruct correctly and pass a weaker test.
			let onlyCells = mutations.allSatisfy { $0.hasPrefix("cell-") }
			if onlyCells {
				#expect(!patch.isFullPage, "seed \(seed): region-only mutations must patch, not reload")
			} else {
				#expect(patch.isFullPage, "seed \(seed): an out-of-region mutation must be a full page")
			}

			if bodySuffix(applied) != bodySuffix(newHTML) {
				Issue.record(
					"seed \(seed) (\(mutations.joined(separator: ", "))): patch \(patch.isFullPage ? "full page" : "\(patch.changed.count) region(s)") did not reconstruct the page"
				)
				return
			}
			// and the patch is never bigger than the page it replaces.
			let patchBytes = patch.changed.reduce(0) { $0 + $1.html.utf8.count }
			#expect(patch.isFullPage || patchBytes <= newHTML.utf8.count)
		}
	}
}
