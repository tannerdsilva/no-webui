import Testing
import WebUI
import WebUICore

// MARK: - Hot.KeyedList / Hot.AttrWrapper tests (t3.3 building blocks)
//
// keyed identity (reconcile by key, never by position) and the
// component-promotion carrier, both in the hot vocabulary. these are the
// primitives a hot viewport feeds its windowed rows through — the same
// `data-key` identity channel the server-side Viewport emits.

@Suite("Hot.KeyedList — keyed identity")
struct KeyedListTests {
	@Test("rows are keyed by their derived address and carry data-key")
	func structure() {
		let list = Hot.KeyedList(id: "feed", keys: ["a", "b", "c"], row: { key in
			Hot.Text(id: ElementID("t-\(key)"), key)
		})
		let html = list.render()
		// container + keyed rows + the engine's identity channel on each row
		#expect(html.hasPrefix("<div id=\"feed\">"))
		#expect(html.contains("<div id=\"feed-ka\" data-key=\"a\"><span id=\"t-a\">a</span></div>"))
		#expect(html.contains("<div id=\"feed-kb\" data-key=\"b\"><span id=\"t-b\">b</span></div>"))
		#expect(html.contains("<div id=\"feed-kc\" data-key=\"c\"><span id=\"t-c\">c</span></div>"))
	}

	@Test("a reorder diffs as moves, never remove+reinsert")
	func reorderIsMoves() {
		let before = Hot.KeyedList(id: "feed", keys: ["a", "b", "c"], row: { key in
			Hot.Text(id: ElementID("t-\(key)"), key)
		})
		let after = Hot.KeyedList(id: "feed", keys: ["c", "a", "b"], row: { key in
			Hot.Text(id: ElementID("t-\(key)"), key)
		})
		let ops = after.hotOps(previous: before)
		#expect(ops.contains { if case .move = $0 { return true } else { return false } })
		#expect(!ops.contains { if case .remove = $0 { return true } else { return false } })
		#expect(!ops.contains { if case .insert = $0 { return true } else { return false } })
	}

	@Test("an append inserts only the new row; a removal removes only it")
	func insertAndRemove() {
		let before = Hot.KeyedList(id: "feed", keys: ["a", "b"], row: { key in
			Hot.Text(id: ElementID("t-\(key)"), key)
		})
		let appended = Hot.KeyedList(id: "feed", keys: ["a", "b", "c"], row: { key in
			Hot.Text(id: ElementID("t-\(key)"), key)
		})
		let insertOps = appended.hotOps(previous: before)
		#expect(insertOps.count == 1)
		guard case .insert(let parent, let beforeKey, let html)? = insertOps.first else {
			Issue.record("expected one insert, got \(insertOps)")
			return
		}
		#expect(parent.raw == "feed")
		#expect(beforeKey == nil, "the appended row anchors at the end")
		#expect(html.contains("<div id=\"feed-kc\""))

		let removed = Hot.KeyedList(id: "feed", keys: ["b"], row: { key in
			Hot.Text(id: ElementID("t-\(key)"), key)
		})
		let removeOps = removed.hotOps(previous: appended)
		// removing "b" leaves a and c out of the list — two removes, no churn
		#expect(removeOps == [.remove(ElementID("feed-ka")), .remove(ElementID("feed-kc"))])
	}

	@Test("a changed row body at the same key is a leaf delta, not structural churn")
	func sameKeyMutation() {
		let before = Hot.KeyedList(id: "feed", keys: ["a", "b"], row: { key in
			Hot.Text(id: ElementID("t-\(key)"), "\(key)-old")
		})
		let after = Hot.KeyedList(id: "feed", keys: ["a", "b"], row: { key in
			Hot.Text(id: ElementID("t-\(key)"), "\(key)-new")
		})
		let ops = after.hotOps(previous: before)
		// two text deltas, no structural ops, no row churn
		#expect(ops == [.text(ElementID("t-a"), "a-new"), .text(ElementID("t-b"), "b-new")])
	}

	@Test("keys are escaped in data-key")
	func keyEscaping() {
		let list = Hot.KeyedList(id: "feed", keys: ["a\"<&"], row: { key in
			Hot.Text(id: "t", key)
		})
		let html = list.render()
		#expect(html.contains("data-key=\"a&quot;&lt;&amp;\""))
	}
}

@Suite("Hot.AttrWrapper — component promotion")
struct AttrWrapperTests {
	@Test("attributes laminate the container root (after id + class)")
	func containerPromotion() {
		let wrapped = Hot.AttrWrapper(attributes: [Hot.HotAttribute("data-key", "k1"), Hot.HotAttribute("aria-selected", "true")]) {
			Hot.Container(id: "row-1", tag: "div", className: "row") { Hot.Text(id: "t-1", "x") }.hotTree
		}
		let html = wrapped.render()
		#expect(html.contains("<div id=\"row-1\" class=\"row\" data-key=\"k1\" aria-selected=\"true\">"))
	}

	@Test("a text root carries the attributes into its span")
	func textPromotion() {
		let wrapped = Hot.AttrWrapper(attributes: [Hot.HotAttribute("data-key", "k2")]) {
			Hot.Text(id: "t-2", "x").hotTree
		}
		#expect(wrapped.render() == "<span id=\"t-2\" data-key=\"k2\">x</span>")
	}

	@Test("content that opens no element drops the attributes (pinned)")
	func anonymousDrops() {
		let wrapped = Hot.AttrWrapper(attributes: [Hot.HotAttribute("data-key", "k")]) {
			Hot.Spacer().hotTree
		}
		#expect(wrapped.render() == "<div class=\"spacer\" style=\"flex:1\"></div>")
	}

	@Test("attribute values are escaped")
	func escaping() {
		let wrapped = Hot.AttrWrapper(attributes: [Hot.HotAttribute("data-key", "a\"<&")]) {
			Hot.Container(id: "r") { Hot.Text(id: "t", "x") }.hotTree
		}
		#expect(wrapped.render().contains("data-key=\"a&quot;&lt;&amp;\""))
	}

	@Test("an attribute-only change yields no ops (v1 boundary, pinned)")
	func attributeChangeNoOps() {
		let before = Hot.AttrWrapper(attributes: [Hot.HotAttribute("data-key", "a")]) {
			Hot.Container(id: "r") { Hot.Text(id: "t", "x") }.hotTree
		}
		let after = Hot.AttrWrapper(attributes: [Hot.HotAttribute("data-key", "b")]) {
			Hot.Container(id: "r") { Hot.Text(id: "t", "x") }.hotTree
		}
		#expect(after.hotOps(previous: before).isEmpty)
	}

	@Test("promotion laminates over nested wrappers and composes with the diff")
	func nestedAndDiff() {
		let outer = Hot.AttrWrapper(attributes: [Hot.HotAttribute("data-outer", "1")]) {
			Hot.AttrWrapper(attributes: [Hot.HotAttribute("data-inner", "2")]) {
				Hot.Container(id: "r") { Hot.Text(id: "t", "x") }.hotTree
			}.hotTree
		}
		let html = outer.render()
		#expect(html.contains("id=\"r\" data-outer=\"1\" data-inner=\"2\""))

		// same inner structure → no ops
		let same = Hot.AttrWrapper(attributes: [Hot.HotAttribute("data-outer", "1")]) {
			Hot.AttrWrapper(attributes: [Hot.HotAttribute("data-inner", "2")]) {
				Hot.Container(id: "r") { Hot.Text(id: "t", "x") }.hotTree
			}.hotTree
		}
		#expect(same.hotOps(previous: outer).isEmpty)
	}
}
