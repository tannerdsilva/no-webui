// MARK: - Attribute Injection
//
// the attribute model, its parsers and its merge rules live in
// `WebUISharedCore/Attributes.swift`, and the first-tag application itself now
// lives in `HTMLBuffer.settlePendingAttributes(from:)` — so the string path and
// the render path share ONE implementation rather than two that can drift.
// `injectAttributes` below is the html-string entry point over it, for callers
// that hold their content as a string (a consumer modifier's `apply`, `Raw`);
// the framework's own render path contributes through `addAttribute` instead.

/// inject `attributes` into the first html tag of `html`: the span fallback
/// when there is no tag, comments/doctypes/closing tags left alone, otherwise
/// the attribute merge. the exact rules live in
/// `HTMLBuffer.settlePendingAttributes(from:)`.
public func injectAttributes(into html: String, _ attributes: String) -> String {
	var buffer = HTMLBuffer()
	let mark = buffer.mark
	buffer.append(html)
	buffer.addAttribute(attributes)
	buffer.settlePendingAttributes(from: mark)
	return buffer.finish()
}

// MARK: - Markdown Rendering

// minimal safe markdown subset: atx headings, '-'/'*'/'+' bullet and "1."
// numbered lists, paragraphs, and the inline forms **bold**, *emphasis*,
// `code`, and [label](url). every byte of input is html-escaped before any
// token is recognized, so raw html in markdown never reaches the document and
// link targets pass through sanitizeURL. unpaired delimiters render literally.
public func markdownToHTML(_ markdown: String) -> String {
	// stdlib split keeps empty subsequences exactly like Foundation's
	// `components(separatedBy:)` (leading/trailing/adjacent separators).
	let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
	var html: [String] = []
	html.reserveCapacity(lines.count + 8)
	var listType: String?
	var listItems: [String] = []
	var codeFence: String?
	var codeLines: [String] = []
	var tableRows: [[String]] = []

	func flushList() {
		guard let type = listType else { return }
		html.append("<\(type)>\(listItems.map { "<li>\($0)</li>" }.joined())</\(type)>")
		listType = nil
		listItems = []
	}

	func flushCode() {
		guard let lang = codeFence else { codeLines = []; return }
		let attr = lang.isEmpty ? "" : " class=\"language-\(htmlEscape(lang))\""
		html.append("<pre><code\(attr)>\(highlightCode(codeLines.joined(separator: "\n"), language: lang))</code></pre>")
		codeFence = nil
		codeLines = []
	}

	func flushTable() {
		guard tableRows.count >= 2 else { tableRows = []; return }
		let header = tableRows[0]
		let body = tableRows.dropFirst(2)
		var t = "<table><thead><tr>"
		for c in header { t += "<th>\(renderInlineMarkdown(c))</th>" }
		t += "</tr></thead><tbody>"
		for row in body {
			t += "<tr>"
			for c in row { t += "<td>\(renderInlineMarkdown(c))</td>" }
			t += "</tr>"
		}
		t += "</tbody></table>"
		html.append(t)
		tableRows = []
	}

	func pushParagraph(_ text: String) {
		if listType != nil {
			listItems.append(renderInlineMarkdown(text))
		} else {
			html.append("<p>\(renderInlineMarkdown(text))</p>")
		}
	}

	// a table row is a pipe-delimited line with >= 2 cells (GitHub-style).
	func tableCells(_ trimmed: String) -> [String]? {
		let t = trimmingHTMLWhitespace(trimmed)
		guard t.hasPrefix("|") else { return nil }
		let cells = t.split(separator: "|", omittingEmptySubsequences: true)
			.map { trimmingHTMLWhitespace(String($0)) }
		return cells.count >= 2 ? cells : nil
	}

	for rawLine in lines {
		let trimmed = trimmingHTMLWhitespace(rawLine)

		if trimmed.hasPrefix("```") {
			if codeFence != nil {
				flushCode()
			} else {
				flushList()
				flushTable()
				codeFence = trimmingHTMLWhitespace(String(trimmed.dropFirst(3)))
				codeLines = []
			}
			continue
		}
		if codeFence != nil {
			codeLines.append(rawLine)
			continue
		}
		if trimmed.isEmpty {
			flushList()
			flushTable()
			continue
		}
		if let cells = tableCells(trimmed) {
			if tableRows.isEmpty { flushList() }
			tableRows.append(cells)
			continue
		}
		if !tableRows.isEmpty {
			flushTable()
		}
		if let heading = parseMarkdownHeading(trimmed) {
			flushList()
			flushTable()
			html.append(heading)
			continue
		}
		if let item = parseMarkdownListItem(trimmed) {
			if listType == nil { listType = item.type }
			listItems.append(renderInlineMarkdown(item.content))
			continue
		}
		flushList()
		flushTable()
		pushParagraph(trimmed)
	}
	flushList()
	flushCode()
	flushTable()
	return html.joined(separator: "\n")
}

/// a scoped markdown body: wraps ``markdownToHTML(:_:)`` output in the design
/// system's `.md` rich-text class so chat/message content inherits the
/// scoped typography (lists, code, tables, headings) without leaking styles.
public func markdownBody(_ markdown: String) -> String {
	"<div class=\"md\">\n" + markdownToHTML(markdown) + "\n</div>"
}

private func parseMarkdownHeading(_ trimmed: String) -> String? {
	var idx = trimmed.startIndex
	var level = 0
	while idx < trimmed.endIndex, trimmed[idx] == "#" {
		level += 1
		idx = trimmed.index(after: idx)
	}
	guard level > 0 else { return nil }
	let text = trimmingHTMLWhitespace(String(trimmed[idx...]))
	let h = min(level, 6)
	return "<h\(h)>\(renderInlineMarkdown(text))</h\(h)>"
}

private func parseMarkdownListItem(_ trimmed: String) -> (type: String, content: String)? {
	if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
		return ("ul", String(trimmed.dropFirst(2)))
	}
	var idx = trimmed.startIndex
	var digits = 0
	while idx < trimmed.endIndex, trimmed[idx].isNumber {
		digits += 1
		idx = trimmed.index(after: idx)
	}
	if digits > 0, idx < trimmed.endIndex, trimmed[idx] == "." || trimmed[idx] == ")" {
		return ("ol", trimmingHTMLWhitespace(String(trimmed[trimmed.index(after: idx)...])))
	}
	return nil
}

private func renderInlineMarkdown(_ text: String) -> String {
	let escaped = htmlEscape(text)
	var codeSpans: [String] = []
	var carved = ""
	var idx = escaped.startIndex
	var inCode = false
	var current = ""
	while idx < escaped.endIndex {
		if escaped[idx] == "`" {
			if inCode {
				codeSpans.append(current)
				carved += "\u{0}\(codeSpans.count - 1)\u{1}"
				current = ""
			}
			inCode.toggle()
		} else if inCode {
			current.append(escaped[idx])
		} else {
			carved.append(escaped[idx])
		}
		idx = escaped.index(after: idx)
	}
	if inCode { carved += "`" + current }

	var out = wrapMarkdownDelimited(carved, delimiter: "**", open: "<strong>", close: "</strong>")
	out = replacingAllOccurrences(out, of: "**", with: "\u{2}")
	out = wrapMarkdownDelimited(out, delimiter: "*", open: "<em>", close: "</em>")
	out = replacingAllOccurrences(out, of: "\u{2}", with: "**")
	out = renderMarkdownLinks(out)
	for (index, span) in codeSpans.enumerated() {
		out = replacingAllOccurrences(out, of: "\u{0}\(index)\u{1}", with: "<code>\(span)</code>")
	}
	return out
}

private func wrapMarkdownDelimited(_ text: String, delimiter: String, open: String, close: String) -> String {
	// stdlib split keeps empty parts exactly like `components(separatedBy:)`;
	// an odd part count means an even number of delimiters (balanced pairs);
	// anything else is an unpaired stray and stays literal so the output
	// never carries an unclosed tag.
	let parts = text.split(separator: delimiter, omittingEmptySubsequences: false).map(String.init)
	guard parts.count >= 3, parts.count % 2 == 1 else { return text }
	var result = parts[0]
	var closing = false
	for part in parts.dropFirst() {
		result += (closing ? close : open) + part
		closing.toggle()
	}
	return result
}

private func renderMarkdownLinks(_ text: String) -> String {
	var result = ""
	var idx = text.startIndex
	while idx < text.endIndex {
		if text[idx] == "[",
		   let labelEnd = text[idx...].firstIndex(of: "]"),
		   labelEnd < text.index(before: text.endIndex),
		   text[text.index(after: labelEnd)] == "(",
		   let urlEnd = text[text.index(labelEnd, offsetBy: 2)...].firstIndex(of: ")") {
			let label = String(text[text.index(after: idx)..<labelEnd])
			let url = String(text[text.index(labelEnd, offsetBy: 2)..<urlEnd])
			if let safeURL = sanitizeURL(url), !label.isEmpty {
				result += "<a href=\"\(htmlEscape(safeURL))\">\(label)</a>"
			} else {
				result += "[\(label)](\(url))"
			}
			idx = text.index(after: urlEnd)
		} else {
			result.append(text[idx])
			idx = text.index(after: idx)
		}
	}
	return result
}

// MARK: - Syntax Highlighting (Stub)
public func highlightCode(_ code: String, language: String) -> String {
    htmlEscape(code)
}

// MARK: - SVG Inline Helpers
public func inlineSVG(viewBox: String = "0 0 24 24", width: Int = 24, height: Int = 24, _ content: String) -> String {
    """
    <svg viewBox="\(viewBox)" width="\(width)" height="\(height)" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="butt" stroke-linejoin="miter">
    \(content)
    </svg>
    """
}

// MARK: - URL Sanitization
private let unsafeURLProtocols: Set<String> = ["javascript", "data", "vbscript"]
private let urlForbiddenControlScalars: Set<UnicodeScalar> = {
    var set = Set<UnicodeScalar>()
    for value in 0x00...0x1F {
        if let scalar = UnicodeScalar(value) { set.insert(scalar) }
    }
    if let del = UnicodeScalar(0x7F) { set.insert(del) }
    return set
}()
private let urlWhitespaceScalars: Set<UnicodeScalar> = ["\t", "\n", "\u{0B}", "\u{0C}", "\r", " "]

// the browser strips ASCII whitespace and C0 control characters from a URL
// before parsing the scheme, so " javascript:" and "java\tscript:" both
// execute as javascript. strip the same set here so the scheme check sees
// what the browser would see.
private func normalizedURLString(_ url: String) -> String {
    let forbidden = urlForbiddenControlScalars.union(urlWhitespaceScalars)
    let filtered = url.unicodeScalars.filter { !forbidden.contains($0) }
    return String(String.UnicodeScalarView(filtered))
}

public func sanitizeURL(_ url: String) -> String? {
    let normalized = normalizedURLString(url)
    guard let colonIndex = normalized.firstIndex(of: ":") else { return normalized }
    let scheme = String(normalized[normalized.startIndex..<colonIndex]).lowercased()
    guard !unsafeURLProtocols.contains(scheme) else { return nil }
    return normalized
}

// MARK: - Conditional Attribute Helper
public func attrIf(_ name: String, _ value: String, _ condition: Bool) -> String {
    condition ? " \(name)=\"\(value)\"" : ""
}
public func classIf(_ className: String, _ condition: Bool) -> String {
    condition ? " \(className)" : ""
}
