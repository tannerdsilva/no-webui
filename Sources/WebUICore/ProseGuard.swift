// MARK: - ProseGuard
//
// the first law's enforcement, in the core so the asset tool, the tests and any
// future gate can share one definition: prose never reaches a client.
//
// the payloads a client can receive are the minified sheet and the three js
// assets. the *working* sheet is allowed designer notes — they are stripped by
// `minifyCSS` before embedding — but the js assets have no strip step, so their
// source must be clean. a prose guard run over the payloads turns "the client
// never sees a comment" from a hope into a build-time fact.
//
// why a scanner and not `grep -c '//'`: a `//` inside a string is not a comment
// (the engine carries `'ws://'`), and a `/*` inside a css string is not a comment
// either. a naive count reports prose where there is none — and a gate that
// cries wolf is a gate people learn to ignore. this scanner reads comments only
// where the language says one can start.
//
// known limit, stated rather than hidden: javascript regex literals are
// disambiguated from division by the previous significant character. a regex
// whose *body* contains `//` (e.g. `/a\/\//`) is therefore read as a line
// comment and reported; build the pattern from a string when that comes up.
// false positives are otherwise structurally impossible, and every comment that
// opens in code position is reported.
package enum ProseGuard {

	/// which comment syntax to read.
	package enum Language: Sendable {
		/// block comments only — `//` is not a css comment.
		case css
		case javaScript
	}

	/// one comment found where a client could receive it.
	package struct Finding: Sendable, CustomStringConvertible {
		/// 1-based line number of the comment's opening delimiter.
		package let line: Int
		/// the comment's opening line, trimmed — enough to recognize the prose.
		package let text: String

		package var description: String { "line \(line): \(text)" }
	}

	/// every comment in `text`, in document order.
	package static func findings(in text: String, language: Language) -> [Finding] {
		var scanner = Scanner(language: language)
		return scanner.run(text)
	}

	/// the guard, as one pass. an explicit mode stack rather than an index into a
	/// split: the languages interleave strings, template literals and two comment
	/// forms, and the whole point is to get each case exactly right.
	private struct Scanner {
		let language: Language
		var findings: [Finding] = []

		private enum Mode { case code, singleQuote, doubleQuote, template, lineComment, blockComment }

		/// characters that cannot end an expression, so a following `/` opens a
		/// regex literal rather than a division (`= /re/`, `return /re/`).
		private static let regexPreceders: Set<Character> = [
			"(", ",", "=", ":", "[", "!", "&", "|", "?", "{", "}", ";", "+", "-", "*", "%", "^", "<", ">", "~",
		]

		mutating func run(_ text: String) -> [Finding] {
			let chars = Array(text)
			var modes: [Mode] = [.code]
			/// brace depth of each open `${ … }` hole; parallel to the open holes,
			/// in order. only meaningful while the top mode is `.code`.
			var holes: [Int] = []
			var i = 0
			var line = 1

			func previousSignificant(_ at: Int) -> Character? {
				var j = at - 1
				while j >= 0, chars[j].isWhitespace { j -= 1 }
				return j >= 0 ? chars[j] : nil
			}

			while i < chars.count {
				let c = chars[i]
				switch modes[modes.count - 1] {
				case .code:
					if c == "\n" { line += 1; i += 1; continue }
					if language == .javaScript, c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
						record(chars, from: i, line: line, block: false)
						modes.append(.lineComment)
						i += 2
						continue
					}
					if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
						record(chars, from: i, line: line, block: true)
						modes.append(.blockComment)
						i += 2
						continue
					}
					if language == .javaScript, c == "/", let prev = previousSignificant(i),
					   Scanner.regexPreceders.contains(prev) {
						i += 1
						var inClass = false
						while i < chars.count {
							let r = chars[i]
							if r == "\\" { i += 2; continue }
							if r == "\n" { line += 1; break }
							if r == "[" { inClass = true }
							else if r == "]" { inClass = false }
							else if r == "/", !inClass { i += 1; break }
							i += 1
						}
						continue
					}
					if c == "\"" { modes.append(.doubleQuote); i += 1; continue }
					if c == "'" { modes.append(.singleQuote); i += 1; continue }
					if c == "`", language == .javaScript { modes.append(.template); i += 1; continue }
					if c == "{", !holes.isEmpty { holes[holes.count - 1] += 1; i += 1; continue }
					if c == "}", !holes.isEmpty {
						holes[holes.count - 1] -= 1
						if holes[holes.count - 1] == 0 {
							holes.removeLast()
							modes.removeLast()
						}
						i += 1
						continue
					}
					i += 1
				case .singleQuote, .doubleQuote:
					let quote: Character = modes[modes.count - 1] == .doubleQuote ? "\"" : "'"
					if c == "\\" { i += 2; continue }
					if c == "\n" { line += 1 }
					if c == quote { modes.removeLast() }
					i += 1
				case .template:
					if c == "\\" { i += 2; continue }
					if c == "\n" { line += 1; i += 1; continue }
					if c == "`" { modes.removeLast(); i += 1; continue }
					if c == "$", i + 1 < chars.count, chars[i + 1] == "{" {
						holes.append(1)
						modes.append(.code)
						i += 2
						continue
					}
					i += 1
				case .lineComment:
					if c == "\n" { modes.removeLast() }
					i += 1
				case .blockComment:
					if c == "*", i + 1 < chars.count, chars[i + 1] == "/" {
						modes.removeLast()
						i += 2
						continue
					}
					if c == "\n" { line += 1 }
					i += 1
				}
			}
			return findings
		}

		private mutating func record(_ chars: [Character], from: Int, line: Int, block: Bool) {
			let start = from + 2
			let end = min(chars.count, start + 96)
			let body = String(chars[start..<end])
			let firstLine = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)[0]
			var trimmed = Substring(firstLine)
			while let f = trimmed.first, f == " " || f == "\t" { trimmed = trimmed.dropFirst() }
			while let l = trimmed.last, l == " " || l == "\t" { trimmed = trimmed.dropLast() }
			findings.append(Finding(line: line, text: (block ? "/* " : "// ") + trimmed))
		}
	}
}