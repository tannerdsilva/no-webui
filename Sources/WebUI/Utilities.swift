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

    let beforeEnd = html.index(before: end)
    if html[beforeEnd] == "/" {
        return String(html[..<beforeEnd]) + " " + attributes + String(html[beforeEnd...])
    } else {
        return String(html[..<end]) + " " + attributes + String(html[end...])
    }
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

// MARK: - CSRF Protection
public enum CSRFError: Error, Equatable, Sendable {
    /// the os entropy source failed — no fallback was attempted. the signing
    /// key must fail loudly rather than degrade to a prng (mirrors
    /// `SessionToken.generate`).
    case entropyUnavailable
    /// hmac failure while signing a token.
    case signingFailed
}

public enum CSRFProtection {
    public static let defaultMaxAge: TimeInterval = 1800
    public static func generateSecret() throws -> String {
        guard let bytes = SecureRandom.bytes(32) else {
            throw CSRFError.entropyUnavailable
        }
        return Base64.encode(bytes)
    }
    public static func token(for formID: String, secret: String, maxAge: TimeInterval = defaultMaxAge) throws -> String {
        let expires = Date().timeIntervalSince1970 + maxAge
        // a per-token random nonce is required: the embedded expiry is
        // second-quantized (`Int` truncation), so without a nonce two tokens
        // minted in the same wall-clock second would be byte-identical —
        // harmless for stateless validation, but fatal for the single-use
        // login-token store, which would reject the second one as consumed.
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let payload = "\(formID):\(Int(expires)):\(nonce)"
        let signature = try hmacSHA256(key: secret, message: payload)
        return Base64.encode([UInt8]("\(payload):\(signature)".utf8))
    }
    public static func validate(_ token: String, for formID: String, secret: String) -> Bool {
        guard let tokenBytes = Base64.decode(token) else {
            return false
        }
        let tokenStr = String(decoding: tokenBytes, as: UTF8.self)
        let parts = tokenStr.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let payloadFormID = String(parts[0])
        let expiresStr = String(parts[1])
        let nonce = String(parts[2])
        let signature = String(parts[3])

        guard payloadFormID == formID,
              let expires = TimeInterval(expiresStr),
              Date().timeIntervalSince1970 < expires else {
            return false
        }

        let expectedSignature: String
        do {
            expectedSignature = try hmacSHA256(key: secret, message: "\(formID):\(expiresStr):\(nonce)")
        } catch {
            // an hmac failure must reject, never accept. the old `try?` + ""
            // fallback compared attacker-supplied "" against expected "" when
            // the hmac threw — an empty-signature token would validate.
            return false
        }
        // constant-time compare — the caller's signature is attacker-controlled,
        // and a short-circuiting == would leak prefix bytes of the MAC.
        return constantTimeEquals(Array(signature.utf8), Array(expectedSignature.utf8))
    }
    /// the embedded expiry (seconds since 1970) of a well-formed token, or
    /// `nil` when the token does not decode to `formID:expiry:nonce:signature`.
    /// callers should only pass tokens that have already passed `validate`.
    public static func expiry(of token: String) -> TimeInterval? {
        guard let tokenBytes = Base64.decode(token) else {
            return nil
        }
        let tokenStr = String(decoding: tokenBytes, as: UTF8.self)
        let parts = tokenStr.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return TimeInterval(parts[1])
    }
    private static func hmacSHA256(key: String, message: String) throws -> String {
        try HMACSHA256.hex(message: [UInt8](message.utf8), key: [UInt8](key.utf8))
    }
}

// MARK: - Conditional Attribute Helper
public func attrIf(_ name: String, _ value: String, _ condition: Bool) -> String {
    condition ? " \(name)=\"\(value)\"" : ""
}
public func classIf(_ className: String, _ condition: Bool) -> String {
    condition ? " \(className)" : ""
}
