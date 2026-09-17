import Foundation

// MARK: - HTML Escaping
public func htmlEscape(_ string: String) -> String {
    guard string.unicodeScalars.contains(where: { c in
        c == "&" || c == "<" || c == ">" || c == "\"" || c == "'"
    }) else { return string }

    var result = ""
    result.reserveCapacity(string.utf8.count + 8)
    for c in string.unicodeScalars {
        switch c {
        case "&":  result += "&amp;"
        case "<":  result += "&lt;"
        case ">":  result += "&gt;"
        case "\"": result += "&quot;"
        case "'":  result += "&#39;"
        default:   result.unicodeScalars.append(c)
        }
    }
    return result
}

// MARK: - Attribute Injection

/// One attribute parsed from an opening tag. `value` is the raw text as
/// written in the source (for quoted values: the text between the quotes,
/// character references and all — it is re-emitted verbatim, never
/// re-escaped, so a value the emitter already escaped cannot double-escape).
/// `hadValue` records whether the source had a `=` at all (boolean attrs).
/// `sourceQuote` is the quote char the source used, or nil for unquoted.
private struct ParsedAttr {
	let key: String
	let keyLower: String
	var value: String
	let hadValue: Bool
	let sourceQuote: Character?
}

/// Scans an opening tag (without its terminating `>` / `/>`) into its tag
/// name and attribute occurrences. Quoted values are respected, so `=` and
/// `>` inside an attribute value never terminate a token. Returns nil when
/// the tag name is not recognizable (the caller falls back to the legacy
/// append behaviour).
private func parseOpeningTag(_ tag: String) -> (name: String, attrs: [ParsedAttr])? {
	var i = tag.index(after: tag.startIndex)
	let nameStart = i
	guard i < tag.endIndex else { return nil }
	while i < tag.endIndex {
		let c = tag[i]
		if c.isLetter || c.isNumber || c == "-" || c == "_" || c == ":" || c == "." {
			i = tag.index(after: i)
		} else {
			break
		}
	}
	let nameEnd = i
	guard nameEnd > nameStart else { return nil }
	let name = String(tag[nameStart..<nameEnd])

	var attrs: [ParsedAttr] = []
	while i < tag.endIndex {
		while i < tag.endIndex, tag[i].isWhitespace { i = tag.index(after: i) }
		if i >= tag.endIndex { break }
		if tag[i] == ">" { break }
		let attrStart = i
		while i < tag.endIndex, !tag[i].isWhitespace, tag[i] != "=", tag[i] != ">" {
			i = tag.index(after: i)
		}
		guard i > attrStart else {
			// stray character (defensive — never emitted by this framework)
			i = tag.index(after: i)
			continue
		}
		let key = String(tag[attrStart..<i])
		if i < tag.endIndex, tag[i] == "=" {
			let eq = i
			i = tag.index(after: i)
			if i < tag.endIndex, tag[i] == "\"" || tag[i] == "'" {
				let quote = tag[i]
				i = tag.index(after: i)
				let vStart = i
				while i < tag.endIndex, tag[i] != quote {
					i = tag.index(after: i)
				}
				let vEnd = i
				if i < tag.endIndex { i = tag.index(after: i) } // closing quote
				attrs.append(ParsedAttr(key: key, keyLower: key.lowercased(), value: String(tag[vStart..<vEnd]), hadValue: true, sourceQuote: quote))
				_ = eq
			} else if i < tag.endIndex, !tag[i].isWhitespace {
				let vStart = i
				while i < tag.endIndex, !tag[i].isWhitespace, tag[i] != ">" {
					i = tag.index(after: i)
				}
				attrs.append(ParsedAttr(key: key, keyLower: key.lowercased(), value: String(tag[vStart..<i]), hadValue: true, sourceQuote: nil))
			} else {
				// `key=` with an empty value — keep as a quoted empty
				attrs.append(ParsedAttr(key: key, keyLower: key.lowercased(), value: "", hadValue: true, sourceQuote: "\""))
			}
		} else {
			attrs.append(ParsedAttr(key: key, keyLower: key.lowercased(), value: "", hadValue: false, sourceQuote: nil))
		}
	}
	return (name, attrs)
}

/// Serializes one attribute. Quote choice never re-escapes: a value that
/// already carries a literal `"` (possible only when the source used single
/// quotes) either keeps single quotes or is `&quot;`-escaped into double
/// quotes — both semantically identical in the DOM.
private func serializeAttr(_ a: ParsedAttr) -> String {
	guard a.hadValue else { return " \(a.key)" }
	let v = a.value
	if v.contains("\"") {
		if !v.contains("'") {
			return " \(a.key)='\(v)'"
		}
		return " \(a.key)=\"\(v.replacingOccurrences(of: "\"", with: "&quot;"))\""
	}
	if v.contains("'") {
		return " \(a.key)=\"\(v)\""
	}
	if a.sourceQuote == "'" {
		return " \(a.key)='\(v)'"
	}
	return " \(a.key)=\"\(v)\""
}

/// Parses an injected attribute string (whitespace-separated `key=value`
/// tokens; values quoted or unquoted). Values are returned verbatim — the
/// emitters escape them, and re-escaping would double-escape entities.
private func parseAttributeString(_ attributes: String) -> [ParsedAttr] {
	var attrs: [ParsedAttr] = []
	var i = attributes.startIndex
	while i < attributes.endIndex {
		while i < attributes.endIndex, attributes[i].isWhitespace { i = attributes.index(after: i) }
		if i >= attributes.endIndex { break }
		let keyStart = i
		while i < attributes.endIndex, !attributes[i].isWhitespace, attributes[i] != "=" {
			i = attributes.index(after: i)
		}
		let keyEnd = i
		guard keyEnd > keyStart else {
			i = attributes.index(after: i)
			continue
		}
		let key = String(attributes[keyStart..<keyEnd])
		if i < attributes.endIndex, attributes[i] == "=" {
			i = attributes.index(after: i)
			if i < attributes.endIndex, attributes[i] == "\"" || attributes[i] == "'" {
				let quote = attributes[i]
				i = attributes.index(after: i)
				let vStart = i
				while i < attributes.endIndex, attributes[i] != quote { i = attributes.index(after: i) }
				let vEnd = i
				if i < attributes.endIndex { i = attributes.index(after: i) }
				attrs.append(ParsedAttr(key: key, keyLower: key.lowercased(), value: String(attributes[vStart..<vEnd]), hadValue: true, sourceQuote: quote))
			} else if i < attributes.endIndex, !attributes[i].isWhitespace {
				let vStart = i
				while i < attributes.endIndex, !attributes[i].isWhitespace { i = attributes.index(after: i) }
				attrs.append(ParsedAttr(key: key, keyLower: key.lowercased(), value: String(attributes[vStart..<i]), hadValue: true, sourceQuote: nil))
			} else {
				attrs.append(ParsedAttr(key: key, keyLower: key.lowercased(), value: "", hadValue: true, sourceQuote: "\""))
			}
		} else {
			attrs.append(ParsedAttr(key: key, keyLower: key.lowercased(), value: "", hadValue: false, sourceQuote: nil))
		}
	}
	return attrs
}

/// Joins a new style declaration onto an existing style value, inserting the
/// `; ` separator when the existing value is non-empty and lacks one.
/// (CSS drops a declaration when two run together without a separator, so
/// the join is what keeps both halves of a merged style alive.)
private func appendStyleDeclaration(existing: String, declaration: String) -> String {
	let e = existing.trimmingCharacters(in: .whitespaces)
	let d = declaration.trimmingCharacters(in: .whitespaces)
	if d.isEmpty { return existing }
	if e.isEmpty { return d }
	if e.hasSuffix(";") { return e + " " + d }
	return e + "; " + d
}

public func injectAttributes(into html: String, _ attributes: String) -> String {
	guard let firstLessThan = html.firstIndex(of: "<") else {
		return "<span \(attributes)>\(html)</span>"
	}

	let afterLT = html.index(after: firstLessThan)
	guard afterLT < html.endIndex else {
		return "<span \(attributes)>\(html)</span>"
	}

	let peek = html[afterLT]
	guard peek != "/" && peek != "!" && peek != "?" else {
		return html
	}

	var inQuote = false
	var quoteChar: Character = "\""
	var tagEnd: String.Index?

	var i = html.index(after: firstLessThan)
	while i < html.endIndex {
		let c = html[i]
		if inQuote {
			if c == quoteChar {
				inQuote = false
			}
		} else if c == "\"" || c == "'" {
			inQuote = true
			quoteChar = c
		} else if c == ">" {
			tagEnd = i
			break
		}
		i = html.index(after: i)
	}

	guard let end = tagEnd else {
		return "<span \(attributes)>\(html)</span>"
	}

	// the opening tag is everything up to `>` (or up to the `/` of `/>`)
	let beforeEnd = html.index(before: end)
	let tagRangeEnd: String.Index = (html[beforeEnd] == "/" ? beforeEnd : end)
	let tag = String(html[..<tagRangeEnd])

	guard let parsed = parseOpeningTag(tag) else {
		// unparseable tag — preserve the legacy append behaviour byte-for-byte
		if html[beforeEnd] == "/" {
			return String(html[..<beforeEnd]) + " " + attributes + String(html[beforeEnd...])
		}
		return String(html[..<end]) + " " + attributes + String(html[end...])
	}

	// HTML honors only the FIRST occurrence of a duplicated attribute — a
	// second `style`/`class`/`data-*` is silently dropped by every browser.
	// So a naive append of a key that already exists ships a dead attribute
	// (the chained-style bug: `style="a" style="b"` rendered `a` only,
	// losing every later modifier). Merge instead:
	// - `style` — duplicate/incoming values APPEND their declarations to
	//   the first occurrence (CSS cascade: last declaration wins), so
	//   every chain survives;
	// - any other key — the LATER value wins (an incoming value is the
	//   newer intent; among source duplicates the first is kept, the
	//   rest dropped as the browser already did).
	var merged = parsed.attrs
	var firstIndex: [String: Int] = [:]
	for (idx, a) in parsed.attrs.enumerated() where firstIndex[a.keyLower] == nil {
		firstIndex[a.keyLower] = idx
	}

	// fold pre-existing duplicate occurrences into their first sibling
	for (idx, a) in parsed.attrs.enumerated() {
		guard let first = firstIndex[a.keyLower], first != idx else { continue }
		if a.hadValue, !a.value.isEmpty {
			if a.keyLower == "style" {
				merged[first].value = appendStyleDeclaration(existing: merged[first].value, declaration: a.value)
			}
			// non-style: keep the first value (document-order HTML semantics)
		}
		merged[idx] = ParsedAttr(key: "\0", keyLower: a.keyLower, value: "", hadValue: false, sourceQuote: nil) // tombstone
	}
	merged = merged.filter { $0.key != "\0" }

	// apply incoming attributes: merge into an existing first-occurrence or append
	for inc in parseAttributeString(attributes) {
		if let first = firstIndex[inc.keyLower] {
			if inc.hadValue, !inc.value.isEmpty {
				if inc.keyLower == "style" {
					merged[first].value = appendStyleDeclaration(existing: merged[first].value, declaration: inc.value)
				} else {
					merged[first] = inc // the newer value replaces the older
				}
			} else if inc.keyLower == "style" {
				// empty incoming style: leave the existing value untouched
			} else {
				merged[first] = inc // explicit empty / boolean intent
			}
			_ = first
		} else {
			firstIndex[inc.keyLower] = merged.count
			merged.append(inc)
		}
	}

	var out = "<" + parsed.name
	for a in merged {
		out += serializeAttr(a)
	}
	return out + String(html[tagRangeEnd...])
}

// MARK: - Markdown Rendering

// minimal safe markdown subset: atx headings, '-'/'*'/'+' bullet and "1."
// numbered lists, paragraphs, and the inline forms **bold**, *emphasis*,
// `code`, and [label](url). every byte of input is html-escaped before any
// token is recognized, so raw html in markdown never reaches the document and
// link targets pass through sanitizeURL. unpaired delimiters render literally.
public func markdownToHTML(_ markdown: String) -> String {
	let lines = markdown.components(separatedBy: "\n")
	var html: [String] = []
	html.reserveCapacity(lines.count + 8)
	var listType: String?
	var listItems: [String] = []

	func flushList() {
		guard let type = listType else { return }
		html.append("<\(type)>\(listItems.map { "<li>\($0)</li>" }.joined())</\(type)>")
		listType = nil
		listItems = []
	}

	func pushParagraph(_ text: String) {
		if listType != nil {
			listItems.append(renderInlineMarkdown(text))
		} else {
			html.append("<p>\(renderInlineMarkdown(text))</p>")
		}
	}

	for rawLine in lines {
		let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
		if trimmed.isEmpty {
			flushList()
			continue
		}
		if let heading = parseMarkdownHeading(trimmed) {
			flushList()
			html.append(heading)
			continue
		}
		if let item = parseMarkdownListItem(trimmed) {
			if listType == nil { listType = item.type }
			listItems.append(renderInlineMarkdown(item.content))
			continue
		}
		flushList()
		pushParagraph(trimmed)
	}
	flushList()
	return html.joined(separator: "\n")
}

private func parseMarkdownHeading(_ trimmed: String) -> String? {
	var idx = trimmed.startIndex
	var level = 0
	while idx < trimmed.endIndex, trimmed[idx] == "#" {
		level += 1
		idx = trimmed.index(after: idx)
	}
	guard level > 0 else { return nil }
	let text = String(trimmed[idx...]).trimmingCharacters(in: .whitespaces)
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
		return ("ol", String(trimmed[trimmed.index(after: idx)...]).trimmingCharacters(in: .whitespaces))
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
	out = out.replacingOccurrences(of: "**", with: "\u{2}")
	out = wrapMarkdownDelimited(out, delimiter: "*", open: "<em>", close: "</em>")
	out = out.replacingOccurrences(of: "\u{2}", with: "**")
	out = renderMarkdownLinks(out)
	for (index, span) in codeSpans.enumerated() {
		out = out.replacingOccurrences(of: "\u{0}\(index)\u{1}", with: "<code>\(span)</code>")
	}
	return out
}

private func wrapMarkdownDelimited(_ text: String, delimiter: String, open: String, close: String) -> String {
	let parts = text.components(separatedBy: delimiter)
	// an odd part count means an even number of delimiters (balanced pairs);
	// anything else is an unpaired stray and stays literal so the output
	// never carries an unclosed tag.
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
