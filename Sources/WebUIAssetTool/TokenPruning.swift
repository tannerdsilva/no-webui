import Foundation

// MARK: - TokenPruning
//
// T9 (per-sku token pruning). the shared sheet declares every `:root` token — 174 of
// them — but an app resolves only the ones its themes and its own css name. dropping the
// rest is a **build-time** step, not a request-time one: the sheet is content-addressed and
// cached immutably, so its bytes have to be right before they are embedded.
//
// the keep-set is the *oracle's* output — `ThemeReachability.usedTokens(in:extraCSS:)` in the
// consuming app, written out as names (`used.map(\.rawValue)`). it is deliberately the whole
// contract: a component class used without its tokens in the set renders wrong, which is why
// a name the sheet does not declare is a build failure rather than a silent no-op.
//
// `guard-css` is the belt to the oracle's suspenders. the set is computed in Swift and can go
// stale between the computation and the build; any `var(--name)` in the consumer's own
// stylesheet is kept regardless, so a stale set cannot drop a colour that css still resolves.
//
// the soundness direction, restated: over-keeping costs bytes, under-keeping costs a colour.
enum TokenPruning {

	/// what a pruning pass did, and to what.
	struct Outcome {
		/// the css with unreachable `:root` token declarations removed.
		let css: String
		/// token names removed, in first-declaration order, deduplicated.
		let dropped: [String]
		/// token names kept, in first-declaration order, deduplicated.
		let kept: [String]
		/// how many `:root` token declarations the sheet carried (both blocks of a
		/// light/dark pair count, so this is occurrences, not distinct names).
		let declarations: Int

		/// distinct tokens the pruned sheet ships.
		var emittedTokens: Int { kept.count }
	}

	/// remove every `:root`-scoped token declaration whose name is not in `keep`.
	///
	/// only declarations are removed: values, comments, selectors, component-scoped custom
	/// properties (`.btn { --btn-bg: … }` is not a design token and not in the vocabulary) and
	/// every rule are copied through verbatim. a `:root` block whose declarations are all
	/// pruned is left as an empty shell — it is a handful of bytes, and rewriting block
	/// structure is a risk this step does not need to take.
	static func prune(_ css: String, keeping keep: Set<String>) -> Outcome {
		var out = ""
		out.reserveCapacity(css.utf8.count)

		var stack: [String] = []
		var pending = ""
		var kept: [String] = []
		var dropped: [String] = []
		var keptSeen = Set<String>()
		var droppedSeen = Set<String>()
		var declarations = 0

		var i = css.startIndex
		while i != css.endIndex {
			let c = css[i]

			// comments copy through verbatim, and their content is not read: a `--x:` or a
			// `var(--x)` inside css comments is neither a declaration nor a reference.
			if c == "/", css.index(after: i) != css.endIndex, css[css.index(after: i)] == "*" {
				var j = css.index(after: css.index(after: i))
				var closed = false
				while j != css.endIndex {
					if css[j] == "*", css.index(after: j) != css.endIndex, css[css.index(after: j)] == "/" {
						j = css.index(after: css.index(after: j))
						closed = true
						break
					}
					j = css.index(after: j)
				}
				out += css[i..<j]
				i = j
				if !closed { break }
				continue
			}

			if c == "{" {
				stack.append(pending.trimmingCharacters(in: .whitespacesAndNewlines))
				pending = ""
				out.append(c)
				i = css.index(after: i)
				continue
			}

			if c == "}" {
				if !stack.isEmpty { stack.removeLast() }
				pending = ""
				out.append(c)
				i = css.index(after: i)
				continue
			}

			if c == ";" {
				pending = ""
				out.append(c)
				i = css.index(after: i)
				continue
			}

			// a declaration only where a `:root` block is open (at any nesting, so the
			// dark `@media { :root { … } }` pass counts) and only when a `:` follows the
			// name — which is what separates a declaration from a `var(--x)` reference.
			if c == "-", stack.contains(":root"), WebUIAssetTool.isStartOfTokenDecl(css, at: i),
			   let (name, afterColon) = WebUIAssetTool.parseTokenName(css, from: i) {
				declarations += 1
				if keep.contains(name) {
					if keptSeen.insert(name).inserted { kept.append(name) }
					out += css[i..<afterColon]
					i = afterColon
					continue
				}
				if droppedSeen.insert(name).inserted { dropped.append(name) }
				i = endOfValue(css, from: afterColon)
				continue
			}

			pending.append(c)
			out.append(c)
			i = css.index(after: i)
		}

		return Outcome(css: out, dropped: dropped, kept: kept, declarations: declarations)
	}

	/// the index just past a declaration's terminating `;`, or the index of the `}` that
	/// ends the block when the declaration carries no semicolon (a malformed last entry —
	/// the brace is left for the main loop so the block stays balanced).
	///
	/// depth-aware and quote-aware: a value may legitimately contain `;` inside a
	/// `data:` uri, a quoted string, or a function call like `color-mix(…)`.
	private static func endOfValue(_ css: String, from: String.Index) -> String.Index {
		var i = from
		var depth = 0
		var quote: Character?
		while i != css.endIndex {
			let c = css[i]
			if let open = quote {
				if c == open { quote = nil }
			} else if c == "\"" || c == "'" {
				quote = c
			} else if c == "(" {
				depth += 1
			} else if c == ")" {
				depth = max(0, depth - 1)
			} else if depth == 0, c == ";" {
				return css.index(after: i)
			} else if depth == 0, c == "}" {
				return i
			}
			i = css.index(after: i)
		}
		return i
	}

	/// token names named as `var(--name)` in a stylesheet, with the leading `--` stripped.
	///
	/// a name that is not a design token (`var(--chat-bubble)`) is returned too: this scans
	/// text, not the vocabulary, and the caller unions the result into a keep-set where an
	/// unknown name simply matches no declaration. same scan as
	/// `ThemeReachability.referencedTokens`, deliberately — one definition of "referenced".
	static func referencedNames(in css: String) -> Set<String> {
		var found: Set<String> = []
		var rest = Substring(css)
		let marker = "var(--"
		while let range = rest.range(of: marker) {
			rest = rest[range.upperBound...]
			let name = rest.prefix { !$0.isWhitespace && $0 != ")" && $0 != "," }
			if !name.isEmpty { found.insert(String(name)) }
		}
		return found
	}

	/// parse a used-token listing: one or more names per line, comma or whitespace
	/// separated, `#` ignores the rest of its line, and the leading `--` is optional on
	/// every name.
	///
	/// written this loosely on purpose — the file is produced by
	/// `used.map(\.rawValue).joined(separator: "\n")`, and a name that does not exist in the
	/// sheet is rejected by the caller, so lenience in *format* costs nothing while
	/// lenience in *names* would cost a colour.
	static func names(inListing text: String) -> Set<String> {
		var names: Set<String> = []
		for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
			var line = rawLine[...]
			if let hash = line.firstIndex(of: "#") { line = line[..<hash] }
			for part in line.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
				let name = String(part).drop { $0 == "-" }
				if !name.isEmpty { names.insert(String(name)) }
			}
		}
		return names
	}

	/// the CLI's pruning step: read the oracle's listing, reject names the sheet does not
	/// declare, fold in the guard stylesheets, and prune.
	///
	/// the rejection is the point of the interface. a name that reaches here and matches no
	/// declaration is a token this build will not ship — a typo, or a token the framework
	/// removed — and silently dropping it means a missing colour that shows up in one rule,
	/// in the mode where that rule applies. so it fails the build and names itself.
	static func performing(
		css: String,
		usedTokensPath: String,
		guardPaths: [String]
	) throws -> Outcome {
		let listing = try String(contentsOfFile: usedTokensPath, encoding: .utf8)
		let used = names(inListing: listing)
		let vocabulary = Set(try WebUIAssetTool.rootTokens(in: css))
		let unknown = used.subtracting(vocabulary).sorted()
		guard unknown.isEmpty else {
			throw TokenPruningError.unknownTokens(unknown)
		}
		var keep = used
		for path in guardPaths {
			let guardCSS = try String(contentsOfFile: path, encoding: .utf8)
			keep.formUnion(referencedNames(in: guardCSS))
		}
		return prune(css, keeping: keep)
	}
}

enum TokenPruningError: Error, CustomStringConvertible {
	/// names the oracle asked to keep that the sheet does not declare.
	case unknownTokens([String])

	var description: String {
		switch self {
		case .unknownTokens(let names):
			let rendered = names.map { "--\($0)" }.joined(separator: ", ")
			return "used-tokens lists \(names.count) token(s) the sheet does not declare: \(rendered) — fix the listing, or the token was removed from the sheet"
		}
	}
}