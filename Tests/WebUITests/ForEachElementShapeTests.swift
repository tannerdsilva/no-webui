import Testing
@testable import WebUI

/// `ForEach`'s element is one concrete view, not `[any View]`.
///
/// these pins are the point of the typed-builder arc: if the element reverts to
/// an array, the array literal below stops type-checking (an array is not a
/// `View`), so the regression is a compile error here rather than a silent
/// per-row existential box.
@Suite("ForEach element shape")
struct ForEachElementShapeTests {
	@Test("the element is the concrete view the body produced")
	func elementIsConcrete() {
		let each = ForEach(0..<3) { i in Text("\(i)") }
		// a single-view body yields the view itself — no wrapper, no array
		#expect(type(of: each) == ForEach<Range<Int>, Text>.self)
		#expect(each.markup.html == "012")
	}

	@Test("a multi-view body yields a typed tuple, never an array")
	func multiViewBodyIsATuple() {
		let each = ForEach(0..<1) { i in
			Text("a")
			Div { Text("\(i)") }
		}
		#expect(type(of: each) == ForEach<Range<Int>, TupleView<Text, Div<Text>>>.self)
	}

	@Test("an if/else body composes without an array")
	func conditionalBody() {
		let on = true
		let html = ForEach(0..<2) { i in
			if on { Text("a") } else { Text("b") }
			Text("\(i)")
		}.markup.html
		#expect(html == "a0a1")
	}

	@Test("a for loop inside a body stays homogeneous")
	func loopBody() {
		let html = ForEach(0..<2) { i in
			for j in 0..<2 { Text("\(i)\(j)") }
		}.markup.html
		#expect(html == "00011011")
	}

	@Test("a multi-view body keeps its bytes")
	func multiViewBody() {
		let html = ForEach(0..<2) { i in
			Text("a")
			Div { Text("\(i)") }
		}.markup.html
		#expect(html == "a<div>0</div>a<div>1</div>")
	}

	@Test("an optional body counts no children")
	func optionalAbsentBody() {
		let show = false
		let html = ForEach(0..<2) { _ in
			if show { Text("x") }
			Text("y")
		}.markup.html
		#expect(html == "yy")
	}
}