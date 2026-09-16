import Foundation

// p5-t3: a compact case-insensitive prefix trie over client-resident
// datasets. built once at boot (single-threaded), then read-only on the hot
// path — every local-search keystroke in wasm answers from this structure,
// zero server round trips. the node graph is immutable-after-build; queries
// never mutate it.

public struct ClientPrefixIndex: Sendable {
	private final class Node: @unchecked Sendable {
		var children: [Character: Node] = [:]
		var terminal = false
		init() {}
	}

	private let root = Node()
	private let nodeBudget: Int

	/// - Parameter nodeBudget: per-insert cap on allocated nodes (bounds a
	///   single adversarial insert's memory; return early past the cap).
	public init(nodeBudget: Int = 1 << 20) {
		self.nodeBudget = nodeBudget
	}

	/// insert a value (lowercased internally) into the trie.
	public func insert(_ value: String) {
		var node = root
		var allocated = 0
		for char in value.lowercased() {
			if let next = node.children[char] {
				node = next
			} else {
				guard allocated < nodeBudget else { return }
				let next = Node()
				node.children[char] = next
				node = next
				allocated += 1
			}
		}
		node.terminal = true
	}

	/// every terminal under `prefix`, in lexicographic order, up to `limit`.
	/// an empty prefix returns all terminals.
	public func search(prefix: String, limit: Int = 50) -> [String] {
		var node = root
		for char in prefix.lowercased() {
			guard let next = node.children[char] else { return [] }
			node = next
		}
		var results: [String] = []
		collect(from: node, path: Array(prefix.lowercased()), into: &results, limit: limit)
		return results
	}

	public var isEmpty: Bool {
		root.children.isEmpty
	}

	private func collect(from node: Node, path: [Character], into results: inout [String], limit: Int) {
		guard results.count < limit else { return }
		if node.terminal {
			results.append(String(path))
		}
		for (char, next) in node.children.sorted(by: { $0.key < $1.key }) {
			guard results.count < limit else { return }
			collect(from: next, path: path + [char], into: &results, limit: limit)
		}
	}
}
