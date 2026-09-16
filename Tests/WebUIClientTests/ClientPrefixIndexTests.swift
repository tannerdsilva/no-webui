import Testing
import WebUICore
@testable import WebUIClientRuntime

// p5-t3: the prefix trie powering local search in wasm.
struct ClientPrefixIndexTests {
	@Test("insert + prefix search over a small dataset")
	func prefixSearch() {
		var index = ClientPrefixIndex()
		for value in ["web", "api", "search", "auth", "websocket"] {
			index.insert(value)
		}
		#expect(index.search(prefix: "w") == ["web", "websocket"])
		#expect(index.search(prefix: "a") == ["api", "auth"])
		#expect(index.search(prefix: "se") == ["search"])
		#expect(index.search(prefix: "x").isEmpty)
		#expect(!index.isEmpty)
	}

	@Test("search is case-insensitive; empty prefix returns everything")
	func caseInsensitiveAndEmpty() {
		var index = ClientPrefixIndex()
		index.insert("Web")
		index.insert("WEB")
		index.insert("web")
		// dedupe: one terminal per lowercase key.
		#expect(index.search(prefix: "WEB") == ["web"])
		#expect(index.search(prefix: "") == ["web"])
	}

	@Test("limit bounds the result set")
	func limitBounds() {
		var index = ClientPrefixIndex()
		for value in ["aa", "ab", "ac", "ad", "ae"] {
			index.insert(value)
			index.insert(value + "-x")
		}
		#expect(index.search(prefix: "a", limit: 3).count == 3)
		#expect(index.search(prefix: "a").count == 10)
	}

	@Test("the vertical answers from the built index")
	func verticalIndex() throws {
		ClientRuntime.bootSearch()
		#expect(!ClientRuntime.nameIndex.isEmpty)
		// "w" matches web (and the search row never matches).
		let names = ClientRuntime.nameIndex.search(prefix: "w")
		#expect(names.contains("web"))
		#expect(!names.contains("search"))
	}
}
