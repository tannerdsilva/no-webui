import Testing
import WebUI
import WebUISharedCore

// MARK: - 0.5 region accounting
//
// the region recorder is an OBSERVER: it hashes the bytes a subtree wrote and
// must not write a byte of its own. every test here is one of the three claims
// §9.2 makes — byte-identity, nesting covers children, an empty region still
// has a hash.

private let fnvOffsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325

private func render(_ body: (inout HTMLBuffer) -> Void) -> (bytes: [UInt8], digest: RenderDigest) {
	var buffer = HTMLBuffer()
	body(&buffer)
	return (buffer.bytes, buffer.renderDigest)
}

@Suite("HTMLBuffer regions")
struct HTMLBufferRegionTests {

	@Test("recording a region does not move a byte")
	func byteIdentity() {
		let withRegions = render { buffer in
			let outer = buffer.beginRegion(RegionID(rawValue: "outer"))
			Div(id: "card", class: "card") {
				Span(class: "pill") { Text("hello") }
			}.render(into: &buffer)
			buffer.endRegion(RegionID(rawValue: "outer"), from: outer)
		}
		let withoutRegions = render { buffer in
			Div(id: "card", class: "card") {
				Span(class: "pill") { Text("hello") }
			}.render(into: &buffer)
		}
		#expect(withRegions.bytes == withoutRegions.bytes)
		#expect(withRegions.digest.regions.keys.contains(RegionID(rawValue: "outer")))
	}

	@Test("an empty region hashes to the empty-input basis")
	func emptyRegion() {
		let measured = render { buffer in
			let mark = buffer.beginRegion(RegionID(rawValue: "empty"))
			buffer.endRegion(RegionID(rawValue: "empty"), from: mark)
		}
		#expect(measured.bytes.isEmpty)
		#expect(measured.digest.regions[RegionID(rawValue: "empty")] == fnvOffsetBasis)
	}

	@Test("a region hashes exactly the bytes it covers")
	func regionCoversItsBytes() {
		var measured = HTMLBuffer()
		measured.append("before")
		let mark = measured.beginRegion(RegionID(rawValue: "middle"))
		measured.append("middle")
		measured.endRegion(RegionID(rawValue: "middle"), from: mark)
		measured.append("after")

		// the same bytes hashed on their own produce the same hash: the
		// surrounding content is outside the mark and cannot leak in
		var standalone = HTMLBuffer()
		let other = standalone.beginRegion(RegionID(rawValue: "x"))
		standalone.append("middle")
		standalone.endRegion(RegionID(rawValue: "x"), from: other)

		#expect(
			measured.renderDigest.regions[RegionID(rawValue: "middle")]
				== standalone.renderDigest.regions[RegionID(rawValue: "x")]
		)
		// …and a different byte string in the same spot is a different hash
		var different = HTMLBuffer()
		let third = different.beginRegion(RegionID(rawValue: "y"))
		different.append("middlE")
		different.endRegion(RegionID(rawValue: "y"), from: third)
		#expect(
			measured.renderDigest.regions[RegionID(rawValue: "middle")]
				!= different.renderDigest.regions[RegionID(rawValue: "y")]
		)
	}

	@Test("an outer region's hash covers its children")
	func nesting() {
		func renderNested(child: String) -> RenderDigest {
			var buffer = HTMLBuffer()
			let outer = buffer.beginRegion(RegionID(rawValue: "outer"))
			buffer.append("<section>")
			let inner = buffer.beginRegion(RegionID(rawValue: "inner"))
			buffer.append(child)
			buffer.endRegion(RegionID(rawValue: "inner"), from: inner)
			buffer.append("</section>")
			buffer.endRegion(RegionID(rawValue: "outer"), from: outer)
			return buffer.renderDigest
		}

		let first = renderNested(child: "one")
		let second = renderNested(child: "two")
		#expect(first.regions[RegionID(rawValue: "inner")] != second.regions[RegionID(rawValue: "inner")])
		// the outer hash moved because the child's bytes are inside its range
		#expect(first.regions[RegionID(rawValue: "outer")] != second.regions[RegionID(rawValue: "outer")])

		// identical renders produce identical digests — the property the differ
		// depends on
		#expect(renderNested(child: "one").regions == first.regions)
	}

	@Test("sibling regions hash independently")
	func siblings() {
		var buffer = HTMLBuffer()
		let left = buffer.beginRegion(RegionID(rawValue: "left"))
		buffer.append("L")
		buffer.endRegion(RegionID(rawValue: "left"), from: left)
		let right = buffer.beginRegion(RegionID(rawValue: "right"))
		buffer.append("R")
		buffer.endRegion(RegionID(rawValue: "right"), from: right)
		let digest = buffer.renderDigest
		#expect(digest.regions[RegionID(rawValue: "left")] != digest.regions[RegionID(rawValue: "right")])
		#expect(buffer.bytes == Array("LR".utf8))
	}

	@Test("the digest is a plain value of 8-byte hashes")
	func digestShape() {
		var buffer = HTMLBuffer()
		let mark = buffer.beginRegion(RegionID(rawValue: "id"))
		buffer.append("x")
		buffer.endRegion(RegionID(rawValue: "id"), from: mark)

		let digest = buffer.renderDigest
		let copy = RenderDigest(regions: digest.regions)
		#expect(copy.regions == digest.regions)
		// a region id is a value, so two spellings of the same id are one key
		#expect(digest.regions[RegionID(rawValue: "id")] != nil)
	}
}

// MARK: - 0.6 byte-append framing
//
// the framing rewrite writes bytes instead of building `<tag …>` strings. these
// pin the exact bytes for the three primitives that moved onto the contribution
// slot, in declaration order — the property the showcase pin measures at page
// scale, asserted here at element scale so a failure names the element.

@Suite("element framing")
struct ElementFramingTests {

	private func html(_ view: some View) -> String {
		var buffer = HTMLBuffer()
		view.render(into: &buffer)
		return buffer.finish()
	}

	@Test("div keeps id before class")
	func divOrder() {
		#expect(html(Div(id: "a", class: "b") { Text("x") }) == #"<div id="a" class="b">x</div>"#)
		#expect(html(Div(class: "only") { Text("x") }) == #"<div class="only">x</div>"#)
		#expect(html(Div { Text("x") }) == "<div>x</div>")
	}

	@Test("span keeps id before class")
	func spanOrder() {
		#expect(html(Span(id: "a", class: "b") { Text("x") }) == #"<span id="a" class="b">x</span>"#)
		#expect(html(Span { Text("x") }) == "<span>x</span>")
	}

	@Test("button keeps id, class, name, type, disabled in that order")
	func buttonOrder() {
		#expect(
			html(Button("Go", id: "go", class: "cta", type: .submit, disabled: true, name: "act"))
				== #"<button id="go" class="cta" name="act" type="submit" disabled>Go</button>"#
		)
		#expect(html(Button("Go")) == #"<button type="submit">Go</button>"#)
	}

	@Test("a wrapping modifier still lands after the element's own attributes")
	func modifierAfterElementAttributes() {
		let view = Div(id: "a", class: "card") { Text("x") }.class("extra")
		#expect(html(view) == #"<div id="a" class="card extra">x</div>"#)
		let styled = Div(class: "card") { Text("x") }.style("color", "red")
		#expect(html(styled) == #"<div class="card" style="color: red;">x</div>"#)
	}

	@Test("a value is escaped exactly once, by the contribution slot")
	func escapingIsUnchanged() {
		#expect(
			html(Div(id: "a\"b", class: "c&d") { Text("x") })
				== #"<div id="a&quot;b" class="c&amp;d">x</div>"#
		)
	}
}
