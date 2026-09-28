// MARK: - Foundation-free string helpers
//
// stdlib stand-ins for the Foundation APIs these renderers used
// (`CharacterSet`-based trimming, `replacingOccurrences(of:with:)`) so the
// rendering core never links Foundation/ICU. Behaviour matches the Foundation
// equivalents exactly for the inputs these renderers produce.

/// trims leading/trailing space + tab (U+0020/U+0009) — the same set
/// `CharacterSet.whitespaces` covers (NOT newlines, matching Foundation).
package func trimmingHTMLWhitespace(_ string: String) -> String {
	var start = string.startIndex
	var end = string.endIndex
	while start < end {
		let c = string[start]
		if c == " " || c == "\t" { start = string.index(after: start) } else { break }
	}
	while end > start {
		let prev = string.index(before: end)
		let c = string[prev]
		if c == " " || c == "\t" { end = prev } else { break }
	}
	return String(string[start..<end])
}

/// non-overlapping replace-all, matching `String.replacingOccurrences(of:with:)`.
package func replacingAllOccurrences(_ string: String, of target: String, with replacement: String) -> String {
	guard !target.isEmpty else { return string }
	var result = ""
	var index = string.startIndex
	while index < string.endIndex {
		guard let found = string[index...].firstRange(of: target) else {
			result += string[index...]
			break
		}
		result += string[index..<found.lowerBound]
		result += replacement
		index = found.upperBound
	}
	return result
}

// MARK: - Attribute Model
//
// the attribute model shared by the html-string path (`injectAttributes`, which
// lives in WebUICore) and the render buffer (`HTMLBuffer`). it sits in this leaf
// so both can use it without widening the public surface — everything here is
// `package`.
//
// the framework emits one attribute per key, but a modifier chain applies
// attributes to *already rendered* html, which may carry the same key already —
// and may be caller-supplied (`Raw`). the merge rules below are what keep a
// chained `style` alive, stop a dead duplicate attribute from shipping, and
// reproduce browser semantics exactly; they are pinned by
// `Tests/WebUITests/AttributeMergeTests.swift`.

/// One attribute parsed from an opening tag. `value` is the raw text as
/// written in the source (for quoted values: the text between the quotes,
/// character references and all — it is re-emitted verbatim, never
/// re-escaped, so a value the emitter already escaped cannot double-escape).
/// `hadValue` records whether the source had a `=` at all (boolean attrs).
/// `sourceQuote` is the quote char the source used, or nil for unquoted.
package struct ParsedAttr {
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
package func parseOpeningTag(_ tag: String) -> (name: String, attrs: [ParsedAttr])? {
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
package func serializeAttr(_ a: ParsedAttr) -> String {
	guard a.hadValue else { return " \(a.key)" }
	let v = a.value
	if v.contains("\"") {
		if !v.contains("'") {
			return " \(a.key)='\(v)'"
		}
		return " \(a.key)=\"\(replacingAllOccurrences(v, of: "\"", with: "&quot;"))\""
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
package func parseAttributeString(_ attributes: String) -> [ParsedAttr] {
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
package func appendStyleDeclaration(existing: String, declaration: String) -> String {
	let e = trimmingHTMLWhitespace(existing)
	let d = trimmingHTMLWhitespace(declaration)
	if d.isEmpty { return existing }
	if e.isEmpty { return d }
	if e.hasSuffix(";") { return e + " " + d }
	return e + "; " + d
}

/// Merge `incoming` attribute occurrences into `base`, by the rules html and
/// the browser agree on:
///
/// - a key that already exists keeps its first source position;
/// - a *duplicated* `style` appends its declarations to the first occurrence,
///   and any other duplicated key keeps the first value (the browser drops the
///   rest, so shipping them would be a dead attribute);
/// - an incoming `style` appends its declarations (the chained-style case);
/// - any other incoming key REPLACES the first occurrence — a later value is
///   the newer intent;
/// - a key that does not exist yet is appended.
package func mergeAttributes(base: [ParsedAttr], incoming: [ParsedAttr]) -> [ParsedAttr] {
	var merged = base
	var firstIndex: [String: Int] = [:]
	for (idx, a) in base.enumerated() where firstIndex[a.keyLower] == nil {
		firstIndex[a.keyLower] = idx
	}

	// fold pre-existing duplicate occurrences into their first sibling
	for (idx, a) in base.enumerated() {
		guard let first = firstIndex[a.keyLower], first != idx else { continue }
		if a.hadValue, !a.value.isEmpty, a.keyLower == "style" {
			merged[first].value = appendStyleDeclaration(existing: merged[first].value, declaration: a.value)
		}
		merged[idx] = ParsedAttr(key: "\0", keyLower: a.keyLower, value: "", hadValue: false, sourceQuote: nil) // tombstone
	}
	merged = merged.filter { $0.key != "\0" }

	// rebuild the index before using it: it above holds positions in the
	// PRE-filter array, and compaction shifts every position after the first
	// dropped duplicate — which is what made a target key whose first
	// occurrence followed a tombstone index past the end (the regression fixed
	// in commit 91a21d9). after filtering, each key occurs exactly once.
	firstIndex.removeAll(keepingCapacity: true)
	for (idx, a) in merged.enumerated() {
		firstIndex[a.keyLower] = idx
	}

	// apply incoming attributes: merge into an existing first-occurrence or append
	for inc in incoming {
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
		} else {
			firstIndex[inc.keyLower] = merged.count
			merged.append(inc)
		}
	}
	return merged
}

/// Merge `incoming` attribute text into a tag's own `base` attribute text, and
/// serialize the result. every attribute is preceded by a space, so a caller
/// writes `"<div" + mergedAttributeText(base: existing, incoming: added) + ">"`.
///
/// this is the whole reason the machinery lives in the shared leaf: the render
/// buffer merges at open-tag time instead of re-parsing rendered html.
package func mergedAttributeText(base: String, incoming: String) -> String {
	var out = ""
	for a in mergeAttributes(base: parseAttributeString(base), incoming: parseAttributeString(incoming)) {
		out += serializeAttr(a)
	}
	return out
}