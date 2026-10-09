// A11y.swift — a structural accessibility audit over rendered markup (w4.4).
//
// the framework's own pages (showcase, the block scaffolds, the smoke page)
// run through `A11yAudit.audit(:)` in `A11yTests`, and the browser gate
// `designer/a11y-audit.mjs` re-implements the same six rules over the served
// bytes. findings are flat and machine-consumable: rule, element, message.
//
// foundation-free by construction (WebUICore links no Foundation), so the
// audit runs anywhere the framework runs.

// MARK: - the finding

/// one audit finding: which rule fired, on which element (the element's
/// opening tag, compact), and why.
public struct A11yFinding: Sendable, Equatable {
	public let rule: String
	public let element: String
	public let message: String

	public init(rule: String, element: String, message: String) {
		self.rule = rule
		self.element = element
		self.message = message
	}
}

// MARK: - the audit

/// the structural checker. `audit(:)` parses the html into a tree and runs
/// the six starter rules over it; each finding names the rule that fired.
public struct A11yAudit {

	// the rule ids — stable, machine-consumed (the browser gate keys on them).
	public static let buttonNoName = "button-no-name"
	public static let imageNoAlt = "image-no-alt"
	public static let controlNoLabel = "control-no-label"
	public static let interactiveNoName = "interactive-no-name"
	public static let headingSkip = "heading-skip"
	public static let roleMissingAria = "role-missing-aria"

	public static func audit(_ html: String) -> [A11yFinding] {
		let roots = A11yParser.parse(html)
		var findings: [A11yFinding] = []

		let ids = indexByID(roots)
		let labelledIDs = labelForIDs(roots)

		// one document-order walk for every rule: heading levels track
		// through the same visit so the outline reads as a human would.
		var walker = Walker(ids: ids, labelledIDs: labelledIDs)
		for root in roots {
			walker.visit(root, hidden: false, inLabel: false, findings: &findings)
		}
		return findings
	}

	// MARK: rules

	/// the roles that carry required aria states/properties, and the
	/// name-required roles. mirrors axe-core's `aria-required-attr` (and its
	/// `aria-*-name` rules for dialog/img): a role in this table with the
	/// attribute absent is a finding.
	static func requiredAria(for role: String) -> [AriaRequirement] {
		switch role {
		case "checkbox", "radio", "switch", "menuitemcheckbox", "menuitemradio":
			return [.attribute("aria-checked")]
		case "tab", "option":
			return [.attribute("aria-selected")]
		case "slider", "scrollbar":
			return [.attribute("aria-valuenow")]
		case "dialog", "img":
			return [.accessibleName]
		default:
			return []
		}
	}

	enum AriaRequirement {
		case attribute(String)
		case accessibleName
	}

	// MARK: the walk

	private struct Walker {
		let ids: [String: A11yNode]
		let labelledIDs: Set<String>
		var lastHeadingLevel = 0

		mutating func visit(_ node: A11yNode, hidden: Bool, inLabel: Bool, findings: inout [A11yFinding]) {
			let nodeHidden = hidden || node.isHidden
			if node.tag.isEmpty {
				return // text run — nothing to audit
			}
			let presentation = node.role == "presentation" || node.role == "none"

			if !nodeHidden && !presentation {
				// heading-order: a level may only climb one rung.
				if let level = A11yAudit.headingLevel(node.tag) {
					if lastHeadingLevel != 0 && level > lastHeadingLevel + 1 {
						findings.append(A11yFinding(
							rule: A11yAudit.headingSkip,
							element: A11yAudit.describe(node),
							message: "heading level \(level) follows level \(lastHeadingLevel), skipping a level in the outline"
						))
					}
					lastHeadingLevel = level
				}

				let name = A11yAudit.accessibleName(of: node, ids: ids)

				// button without a name.
				if A11yAudit.isButton(node) {
					if name.isEmpty {
						findings.append(A11yFinding(
							rule: A11yAudit.buttonNoName,
							element: A11yAudit.describe(node),
							message: "a <\(node.tag)> renders no accessible name (no text, aria-label, or aria-labelledby)"
						))
					}
				} else if node.tag == "img" {
					// an image without an alt attribute at all.
					if node.attributes["alt"] == nil {
						findings.append(A11yFinding(
							rule: A11yAudit.imageNoAlt,
							element: A11yAudit.describe(node),
							message: "an <img> without an alt attribute is unlabeled — use alt=\"\" for a decorative image"
						))
					}
				} else if A11yAudit.isFormControl(node) {
					// a form control with no label association. a placeholder
					// is not a label (axe agrees): only a real <label>, an
					// aria-label/labelledby, or a title satisfies this rule.
					let id = node.attributes["id"] ?? ""
					let hasLabel = !A11yAudit.explicitName(of: node, ids: ids).isEmpty
						|| (!id.isEmpty && labelledIDs.contains(id))
						|| inLabel
					if !hasLabel {
						findings.append(A11yFinding(
							rule: A11yAudit.controlNoLabel,
							element: A11yAudit.describe(node),
							message: "a form control renders without a label (no <label>, aria-label, or aria-labelledby)"
						))
					}
				} else if A11yAudit.isOtherInteractive(node), name.isEmpty {
					// an interactive element (link, tab, checkbox role, a
					// focusable anything) without an accessible name.
					findings.append(A11yFinding(
						rule: A11yAudit.interactiveNoName,
						element: A11yAudit.describe(node),
						message: "an interactive element renders without an accessible name (no text, aria-label, or aria-labelledby)"
					))
				}

				// a role missing a required aria state/property or name.
				if let role = node.role {
					for requirement in A11yAudit.requiredAria(for: role) {
						switch requirement {
						case .attribute(let attribute):
							if node.attributes[attribute] == nil {
								findings.append(A11yFinding(
									rule: A11yAudit.roleMissingAria,
									element: A11yAudit.describe(node),
									message: "role=\"\(role)\" requires \(attribute), which is missing"
								))
							}
						case .accessibleName:
							if A11yAudit.explicitName(of: node, ids: ids).isEmpty {
								findings.append(A11yFinding(
									rule: A11yAudit.roleMissingAria,
									element: A11yAudit.describe(node),
									message: "role=\"\(role)\" requires an accessible name (aria-label or aria-labelledby)"
								))
							}
						}
					}
				}
			}

			let childInLabel = inLabel || node.tag == "label"
			if node.tag == "script" || node.tag == "style" {
				return // raw-text elements: nothing inside is audited
			}
			for child in node.children {
				visit(child, hidden: nodeHidden, inLabel: childInLabel, findings: &findings)
			}
		}
	}

	// MARK: classification

	static func isButton(_ node: A11yNode) -> Bool {
		node.tag == "button" || node.role == "button"
	}

	static func isFormControl(_ node: A11yNode) -> Bool {
		switch node.tag {
		case "select", "textarea":
			return true
		case "input":
			let type = node.attributes["type"] ?? "text"
			return !["hidden", "submit", "button", "reset", "image"].contains(type)
		default:
			return false
		}
	}

	/// interactive but not a button (its own rule) and not a form control
	/// (its own rule): links, role'd interactive widgets, focusable elements.
	static func isOtherInteractive(_ node: A11yNode) -> Bool {
		if node.tag == "a", node.attributes["href"] != nil { return true }
		if node.tag == "summary" { return true }
		if isButton(node) { return false }
		if isFormControl(node) { return false }
		if let tabindex = node.attributes["tabindex"], tabindex != "-1" { return true }
		switch node.role {
		case "link", "checkbox", "radio", "switch", "menuitem",
		     "menuitemcheckbox", "menuitemradio", "tab", "option", "treeitem":
			return true
		default:
			return false
		}
	}

	static func headingLevel(_ tag: String) -> Int? {
		switch tag {
		case "h1": return 1
		case "h2": return 2
		case "h3": return 3
		case "h4": return 4
		case "h5": return 5
		case "h6": return 6
		default: return nil
		}
	}

	// MARK: accessible name

	/// the accessible-name computation for the rules: aria-label wins, then
	/// aria-labelledby (resolved through the document's id table), then
	/// title/alt/placeholder, then the element's own text.
	static func accessibleName(of node: A11yNode, ids: [String: A11yNode]) -> String {
		if let label = node.attributes["aria-label"] {
			let decoded = A11yParser.decodeHTMLEntities(label).whitespaceTrimmed
			if !decoded.isEmpty { return decoded }
		}
		if let refs = node.attributes["aria-labelledby"] {
			var collected = ""
			for part in refs.split(whereSeparator: { $0.isWhitespace }) {
				if let target = ids[String(part)] {
					collected += subtreeText(of: target) + " "
				}
			}
			let trimmed = collected.whitespaceTrimmed
			if !trimmed.isEmpty { return trimmed }
		}
		if let title = node.attributes["title"], !title.isEmpty {
			return title.whitespaceTrimmed
		}
		if node.tag == "img", let alt = node.attributes["alt"] {
			return A11yParser.decodeHTMLEntities(alt).whitespaceTrimmed
		}
		if node.tag == "input", node.attributes["type"] == "image",
		   let alt = node.attributes["alt"], !alt.isEmpty {
			return alt.whitespaceTrimmed
		}
		if let placeholder = node.attributes["placeholder"], !placeholder.isEmpty {
			return A11yParser.decodeHTMLEntities(placeholder).whitespaceTrimmed
		}
		return subtreeText(of: node).whitespaceTrimmed
	}

	/// concatenated descendant text with aria-hidden subtrees and
	/// raw-text elements (script/style) excluded.
	static func subtreeText(of node: A11yNode) -> String {
		var out = ""
		func visit(_ n: A11yNode) {
			if n.tag.isEmpty {
				out += A11yParser.decodeHTMLEntities(n.text)
				return
			}
			if n.tag == "script" || n.tag == "style" { return }
			if n.isHidden { return }
			for child in n.children { visit(child) }
		}
		visit(node)
		return out
	}

	/// the name a landmark role (`dialog`, `img`) can carry: aria-label,
	/// aria-labelledby, or title — never its text content. a dialog is not
	/// named by the paragraph it contains, so the fallbacks stop here.
	static func explicitName(of node: A11yNode, ids: [String: A11yNode]) -> String {
		if let label = node.attributes["aria-label"] {
			let decoded = A11yParser.decodeHTMLEntities(label).whitespaceTrimmed
			if !decoded.isEmpty { return decoded }
		}
		if let refs = node.attributes["aria-labelledby"] {
			var collected = ""
			for part in refs.split(whereSeparator: { $0.isWhitespace }) {
				if let target = ids[String(part)] {
					collected += subtreeText(of: target) + " "
				}
			}
			let trimmed = collected.whitespaceTrimmed
			if !trimmed.isEmpty { return trimmed }
		}
		if let title = node.attributes["title"], !title.isEmpty {
			return title.whitespaceTrimmed
		}
		return ""
	}

	// MARK: document tables

	static func indexByID(_ roots: [A11yNode]) -> [String: A11yNode] {
		var map: [String: A11yNode] = [:]
		func visit(_ node: A11yNode) {
			if let id = node.attributes["id"], !id.isEmpty { map[id] = node }
			for child in node.children { visit(child) }
		}
		for root in roots { visit(root) }
		return map
	}

	/// the ids targeted by `<label for="...">`.
	static func labelForIDs(_ roots: [A11yNode]) -> Set<String> {
		var set: Set<String> = []
		func visit(_ node: A11yNode) {
			if node.tag == "label", let forID = node.attributes["for"], !forID.isEmpty {
				set.insert(forID)
			}
			for child in node.children { visit(child) }
		}
		for root in roots { visit(root) }
		return set
	}

	/// a compact, deterministic description of an element's opening tag.
	static func describe(_ node: A11yNode) -> String {
		var out = "<\(node.tag)"
		let shown = node.attributes.sorted { $0.key < $1.key }.prefix(3)
		for (key, value) in shown {
			out += " \(key)=\"\(value)\""
		}
		out += ">"
		if out.count > 90 {
			out = String(out.prefix(87)) + "..."
		}
		return out
	}
}

// MARK: - the audit modifier

public extension View {
	/// run the structural a11y audit over this view's rendered markup —
	/// the preflight a test or a build check calls before shipping a page.
	func a11yAudit() -> [A11yFinding] {
		A11yAudit.audit(renderThroughBuffer())
	}
}

// MARK: - html parsing (foundation-free)

/// one node of the audited tree: an element (empty `tag` for a text run).
final class A11yNode {
	var tag = ""
	var text = ""
	var attributes: [String: String] = [:]
	var children: [A11yNode] = []

	var role: String? { attributes["role"] }
	var isHidden: Bool {
		attributes["aria-hidden"] == "true" || attributes["hidden"] != nil
	}
}

/// a tolerant tag scanner: comments, doctypes, quoted attribute values,
/// self-closing and void tags, raw-text script/style bodies. enough fidelity
/// for the six rules; never re-emits a byte.
enum A11yParser {

	static let voidTags: Set<String> = [
		"area", "base", "br", "col", "embed", "hr", "img", "input",
		"link", "meta", "param", "source", "track", "wbr",
	]

	static func parse(_ html: String) -> [A11yNode] {
		let chars = Array(html)
		let n = chars.count
		var roots: [A11yNode] = []
		var stack: [A11yNode] = []
		var pendingText = ""
		var i = 0

		func flushText() {
			if pendingText.isEmpty { return }
			let node = A11yNode()
			node.text = pendingText
			append(node)
			pendingText = ""
		}
		func append(_ node: A11yNode) {
			if let top = stack.last { top.children.append(node) } else { roots.append(node) }
		}

		while i < n {
			let c = chars[i]
			if c != "<" {
				pendingText.append(c)
				i += 1
				continue
			}
			guard i + 1 < n else { pendingText.append(c); i += 1; continue }
			let next = chars[i + 1]

			if next == "!" {
				// comment or doctype: skip the construct wholesale.
				if i + 3 < n, chars[i + 2] == "-", chars[i + 3] == "-" {
					var j = i + 4
					while j + 2 < n, !(chars[j] == "-" && chars[j + 1] == "-" && chars[j + 2] == ">") { j += 1 }
					i = min(j + 3, n)
				} else {
					var j = i + 2
					while j < n, chars[j] != ">" { j += 1 }
					i = min(j + 1, n)
				}
				continue
			}

			if next == "/" {
				// closing tag — pop the matching element.
				flushText()
				var j = i + 2
				while j < n, chars[j] != ">" { j += 1 }
				if !stack.isEmpty { stack.removeLast() }
				i = min(j + 1, n)
				continue
			}

			// start tag
			flushText()
			var j = i + 1
			while j < n, isTagNameChar(chars[j]) { j += 1 }
			let node = A11yNode()
			node.tag = String(chars[(i + 1)..<j]).lowercased()

			var selfClosing = false
			while j < n {
				while j < n, chars[j].isWhitespace { j += 1 }
				if j >= n { break }
				if chars[j] == ">" { j += 1; break }
				if chars[j] == "/" {
					if j + 1 < n, chars[j + 1] == ">" { selfClosing = true; j += 2; break }
					j += 1
					continue
				}
				let attrStart = j
				while j < n, !isAttrNameEnd(chars[j]) { j += 1 }
				let attrName = String(chars[attrStart..<j]).lowercased()
				while j < n, chars[j].isWhitespace { j += 1 }
				var value = ""
				if j < n, chars[j] == "=" {
					j += 1
					while j < n, chars[j].isWhitespace { j += 1 }
					if j < n, chars[j] == "\"" || chars[j] == "'" {
						let quote = chars[j]
						j += 1
						let vStart = j
						while j < n, chars[j] != quote { j += 1 }
						value = String(chars[vStart..<j])
						if j < n { j += 1 }
					} else {
						let vStart = j
						while j < n, !chars[j].isWhitespace, chars[j] != ">" { j += 1 }
						value = String(chars[vStart..<j])
					}
				}
				if !attrName.isEmpty { node.attributes[attrName] = value }
			}

			if voidTags.contains(node.tag) || selfClosing || node.tag == "script" || node.tag == "style" {
				// void/self-closing: no element to pop. script/style are
				// raw-text elements: swallow everything up to the matching
				// close tag (their bodies may contain "<" and ">").
				append(node)
				if node.tag == "script" || node.tag == "style" {
					i = rawTextEnd(chars, from: j, tag: node.tag, fallback: j)
				} else {
					i = j
				}
			} else {
				append(node)
				stack.append(node)
				i = j
			}
		}
		flushText()
		return roots
	}

	static func isTagNameChar(_ c: Character) -> Bool {
		c.isLetter || c.isNumber || c == "-" || c == ":" || c == "_" || c == "."
	}

	/// the index just past `</tag ...>` starting the search at `start` — the
	/// raw-text element's end. returns `fallback` when the close tag is
	/// missing (malformed input: tolerate it as text to the end).
	static func rawTextEnd(_ chars: [Character], from start: Int, tag: String, fallback: Int) -> Int {
		let n = chars.count
		let needle = "</" + tag
		let first = needle[needle.startIndex]
		var k = start
		while k < n {
			guard chars[k] == "<" else { k += 1; continue }
			if n - k <= needle.count || chars[k + 1] != "/" {
				k += 1
				continue
			}
			// cheap prefilter on the first char before the per-char compare.
			if String(chars[k + 2].lowercased()) != String(first) {
				k += 1
				continue
			}
			var match = true
			for offset in needle.indices {
				let wanted = String(needle[offset])
				let haveIdx = k + needle.distance(from: needle.startIndex, to: offset)
				if haveIdx >= n || String(chars[haveIdx].lowercased()) != wanted {
					match = false
					break
				}
			}
			if match {
				var m = k + needle.count
				while m < n, chars[m] != ">" { m += 1 }
				return min(m + 1, n)
			}
			k += 1
		}
		return fallback
	}

	static func isAttrNameEnd(_ c: Character) -> Bool {
		c.isWhitespace || c == "=" || c == ">" || c == "/"
	}

	// MARK: entity decoding

	static func decodeHTMLEntities(_ input: String) -> String {
		guard input.contains("&") else { return input }
		let chars = Array(input)
		var out = ""
		var i = 0
		let n = chars.count
		while i < n {
			if chars[i] == "&", let semi = chars[i...].firstIndex(of: ";") {
				let entity = String(chars[(i + 1)..<semi])
				guard let scalar = namedScalar(entity) ?? numericScalar(entity) else {
					out.append("&")
					i += 1
					continue
				}
				out.unicodeScalars.append(scalar)
				i = semi + 1
			} else {
				out.append(chars[i])
				i += 1
			}
		}
		return out
	}

	private static func namedScalar(_ entity: String) -> UnicodeScalar? {
		switch entity {
		case "amp": return "&"
		case "lt": return "<"
		case "gt": return ">"
		case "quot": return "\""
		case "apos": return "'"
		case "nbsp": return "\u{00A0}"
		case "times": return "\u{00D7}"
		case "minus": return "\u{2212}"
		case "copy": return "\u{00A9}"
		case "hellip": return "\u{2026}"
		case "mdash": return "\u{2014}"
		case "ndash": return "\u{2013}"
		case "laquo": return "\u{00AB}"
		case "raquo": return "\u{00BB}"
		case "lsaquo": return "\u{2039}"
		case "rsaquo": return "\u{203A}"
		default: return nil
		}
	}

	private static func numericScalar(_ entity: String) -> UnicodeScalar? {
		if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
			guard let value = Int(entity.dropFirst(2), radix: 16) else { return nil }
			return UnicodeScalar(value)
		}
		if entity.hasPrefix("#") {
			guard let value = Int(entity.dropFirst()) else { return nil }
			return UnicodeScalar(value)
		}
		return nil
	}
}

// MARK: - foundation-free whitespace trim

extension String {
	/// strip leading/trailing whitespace without Foundation.
	var whitespaceTrimmed: String {
		var start = startIndex
		var end = endIndex
		while start < end, self[start].isWhitespace { start = index(after: start) }
		while end > start, self[index(before: end)].isWhitespace { end = index(before: end) }
		return String(self[start..<end])
	}
}
