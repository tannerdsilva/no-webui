// MARK: - CSS Miniification

// conservative minifier for css destined for the wire: strips `/* */`
// comments, trims every line, and drops blank lines. it deliberately does
// not touch whitespace inside rules, so selectors and declarations survive
// intact. the goals are comment-free shipped css (the first law) and a
// meaningful payload reduction, not maximal compression.
// Foundation-free: `trimmingHTMLWhitespace` (U+0020/U+0009 only, matching
// `CharacterSet.whitespaces`) lives in Utilities.swift — newlines are NOT
// trimmed, so a stray `\r` on a CRLF line survives exactly as Foundation did.
public func minifyCSS(_ css: String) -> String {
	let chars = Array(css)
	var out = ""
	out.reserveCapacity(chars.count)
	var i = 0
	var inComment = false
	while i < chars.count {
		let c = chars[i]
		if inComment {
			if c == "*", i + 1 < chars.count, chars[i + 1] == "/" {
				inComment = false
				i += 2
				continue
			}
			i += 1
			continue
		}
		if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
			inComment = true
			i += 2
			continue
		}
		out.append(c)
		i += 1
	}

	let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
	let trimmed = lines.map { trimmingHTMLWhitespace(String($0)) }.filter { !$0.isEmpty }
	return trimmed.joined(separator: "\n")
}
