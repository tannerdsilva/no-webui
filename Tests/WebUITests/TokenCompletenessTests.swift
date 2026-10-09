import Testing
import WebUI
import WebUIDesignSystem

// MARK: - reading the shipped stylesheet independently

/// the declarations the shipped stylesheet puts inside a `:root` block,
/// parsed here in the test rather than by the generator.
///
/// this parser is deliberately a second implementation of the same scan the
/// asset tool performs — the whole point of the two-way check is that a
/// regression in the generator's own parse (a family of declarations it stops
/// seeing) shows up as a mismatch between the *file* and the *vocabulary*,
/// not as a vocabulary that silently agrees with itself. both directions run
/// against this independent read.
private struct RootTokenScanner {

	static func declaredNames(in css: String) -> [String] {
		scan(stripComments(css))
	}

	/// strips `/* … */` blocks — the sheet carries the designer's notes and
	/// a brace inside one must not open a false block.
	private static func stripComments(_ css: String) -> String {
		var out = ""
		out.reserveCapacity(css.utf8.count)
		var i = css.startIndex
		while i < css.endIndex {
			if css[i] == "/", css.index(after: i) != css.endIndex, css[css.index(after: i)] == "*" {
				var j = css.index(after: i)
				j = css.index(after: j)
				var closed = false
				while j != css.endIndex {
					if css[j] == "*", css.index(after: j) != css.endIndex, css[css.index(after: j)] == "/" {
						closed = true
						j = css.index(after: j)
						j = css.index(after: j)
						break
					}
					j = css.index(after: j)
				}
				i = j
				if closed { continue }
			}
			out.append(css[i])
			i = css.index(after: i)
		}
		return out
	}

	private static func scan(_ css: String) -> [String] {
		var names: [String] = []
		var seen: Set<String> = []
		var stack: [String] = []
		var pending = ""
		var i = css.startIndex
		while i < css.endIndex {
			let c = css[i]
			if c == "{" {
				stack.append(pending.trimmingCharacters(in: .whitespacesAndNewlines))
				pending = ""
				i = css.index(after: i)
			} else if c == "}" {
				if !stack.isEmpty { stack.removeLast() }
				pending = ""
				i = css.index(after: i)
			} else if c == ";" {
				pending = ""
				i = css.index(after: i)
			} else if c == "-", isDeclarationStart(css, at: i) {
				guard let (name, end) = parseCustomProperty(css, from: i) else {
					pending.append(c)
					i = css.index(after: i)
					continue
				}
				if stack.contains(":root"), seen.insert(name).inserted {
					names.append(name)
				}
				pending = ""
				i = end
			} else {
				pending.append(c)
				i = css.index(after: i)
			}
		}
		return names
	}

	/// true when `css[i]` begins a declaration (`--name:`) rather than a
	/// `var(--name)` reference.
	private static func isDeclarationStart(_ css: String, at i: String.Index) -> Bool {
		guard i != css.startIndex else { return true }
		let prev = css[css.index(before: i)]
		return !(prev.isLetter || prev.isNumber || prev == "-")
	}

	/// parses `--name` and the following whitespace + `:`. nil when the `--`
	/// is a `var(--…)` reference or other non-declaration.
	private static func parseCustomProperty(_ css: String, from i: String.Index) -> (name: String, end: String.Index)? {
		var j = css.index(after: i)
		j = css.index(after: j)
		var name = ""
		while j != css.endIndex, css[j].isLetter || css[j].isNumber || css[j] == "-" || css[j] == "_" {
			name.append(css[j])
			j = css.index(after: j)
		}
		guard !name.isEmpty else { return nil }
		var k = j
		while k != css.endIndex, css[k] == " " || css[k] == "\t" { k = css.index(after: k) }
		guard k != css.endIndex, css[k] == ":" else { return nil }
		return (name, css.index(after: k))
	}
}

// MARK: - the documented name contract, re-encoded for the cross-check

/// mirrors `WebUIThemeMacro.themeAxis(forMember:)` — the camelCase partition
/// the macro applies to flat `@Theme` members. encoded here a second time on
/// purpose: `DesignToken.axis` (css-name families) and this (member-name
/// families) must agree for every generated case, so a drift in either
/// direction is a test failure, not a silent regroup.
private enum MacroContract {
	static func axis(forMemberName name: String) -> DesignTokenAxis {
		if name.hasPrefix("space") || name.hasPrefix("spacing") { return .spacing }
		if name.hasPrefix("radius") { return .radii }
		if name.hasPrefix("font") || name.hasPrefix("fs")
			|| name.hasPrefix("lineHeight") || name.hasPrefix("letterSpacing")
			|| name.hasPrefix("text") { return .typography }
		if name.hasPrefix("transition") || name.hasPrefix("ease") { return .motion }
		return .palette
	}
}

/// mirrors `WebUIAssetTool.camelCase(_:)`: `color-primary-solid` →
/// `colorPrimarySolid`.
private func camelCase(_ name: String) -> String {
	let parts = name.split(separator: "-", omittingEmptySubsequences: true)
	guard let first = parts.first else { return name }
	var result = String(first)
	for part in parts.dropFirst() {
		result += part.prefix(1).uppercased() + part.dropFirst()
	}
	return result
}

// MARK: - the two-way completeness check

@Suite("DesignToken completeness — stylesheet vs vocabulary")
struct TokenCompletenessTests {

	private static func stylesheet() throws -> String {
		let url = packageRootURL().appendingPathComponent("designer/assets/design-system.css")
		return try String(contentsOf: url, encoding: .utf8)
	}

	@Test("the generated count is the stylesheet's declared count, in both directions")
	func tokenCountMatchesStylesheet() throws {
		let declared = RootTokenScanner.declaredNames(in: try Self.stylesheet())
		#expect(DesignToken.tokenCount == declared.count)
		#expect(DesignToken.tokenCount == DesignToken.allCases.count)
		#expect(DesignToken.stylesheetTokenNames.count == declared.count)
	}

	@Test("(a) every token the stylesheet declares has a DesignToken reader")
	func everyDeclaredTokenHasAReader() throws {
		let declared = RootTokenScanner.declaredNames(in: try Self.stylesheet())
		let vocabulary = Set(DesignToken.allCases.map(\.rawValue))
		let holes = declared.filter { !vocabulary.contains($0) }
		#expect(holes.isEmpty, "the stylesheet declares tokens the vocabulary does not read: \(holes)")
	}

	@Test("(b) every vocabulary entry names a real token in the stylesheet")
	func everyReaderNamesARealToken() throws {
		let declared = Set(RootTokenScanner.declaredNames(in: try Self.stylesheet()))
		let phantoms = DesignToken.allCases.map(\.rawValue).filter { !declared.contains($0) }
		#expect(phantoms.isEmpty, "the vocabulary reads tokens the stylesheet does not declare: \(phantoms)")
	}

	@Test("the generated declaration list is exactly what the file declares")
	func generatedListMatchesStylesheet() throws {
		let declared = RootTokenScanner.declaredNames(in: try Self.stylesheet())
		#expect(Set(DesignToken.stylesheetTokenNames) == Set(declared))
		// and the generated parse found the same set with no duplicates.
		#expect(DesignToken.stylesheetTokenNames.count == Set(DesignToken.stylesheetTokenNames).count)
	}
}

// MARK: - axis partition cross-check

@Suite("DesignToken axis — name contract")
struct TokenAxisContractTests {

	@Test("every token's axis is derivable from its name by the documented contract")
	func everyAxisIsDerivable() {
		// the palette catch-all keeps the partition total, so nothing "fits no
		// axis". the finding this pins is the sharper one: a family token is
		// never read as palette, and the macro's camelCase rule never
		// disagrees with the css-name rule.
		for token in DesignToken.allCases {
			#expect(DesignTokenAxis.allCases.contains(token.axis))
			let memberName = camelCase(token.rawValue)
			#expect(
				token.axis == MacroContract.axis(forMemberName: memberName),
				"token \(token.rawValue): css-name axis \(token.axis) disagrees with the macro's member-name rule for \(memberName)"
			)
		}
	}

	@Test("every documented family has non-empty vocabulary — the contract is not vacuous")
	func everyFamilyHasTokens() {
		for axis in DesignTokenAxis.allCases {
			#expect(
				DesignToken.allCases.contains { $0.axis == axis },
				"no vocabulary entry maps to axis \(axis.rawValue) — the partition contract is vacuous for it"
			)
		}
		// and the families claim real members, not each other's.
		let spacing = DesignToken.allCases.filter { $0.axis == .spacing }
		let radii = DesignToken.allCases.filter { $0.axis == .radii }
		let typography = DesignToken.allCases.filter { $0.axis == .typography }
		let motion = DesignToken.allCases.filter { $0.axis == .motion }
		#expect(spacing.allSatisfy { $0.rawValue.hasPrefix("space") || $0.rawValue.hasPrefix("spacing") })
		#expect(radii.allSatisfy { $0.rawValue.hasPrefix("radius") })
		#expect(typography.allSatisfy { $0.rawValue.hasPrefix("font") || $0.rawValue.hasPrefix("fs")
			|| $0.rawValue.hasPrefix("line-height") || $0.rawValue.hasPrefix("letter-spacing")
			|| $0.rawValue.hasPrefix("text") })
		#expect(motion.allSatisfy { $0.rawValue.hasPrefix("transition") || $0.rawValue.hasPrefix("ease") })
	}
}

// MARK: - DesignToken.verify(_:)

@Suite("DesignToken.verify(_:)")
struct TokenVerifyTests {

	@Test("an empty theme and a correctly-partitioned theme pass with no findings")
	func healthyThemesPass() {
		#expect(DesignToken.verify(DefaultDesignTheme.self).isEmpty)
		#expect(DesignToken.verify(AccentTheme.self).isEmpty)
	}

	@Test("a token read on the wrong axis is a MissingToken that names it")
	func misplacedAxisIsReported() {
		struct WrongAxis: DesignTheme {
			static var palette: ThemePalette { ThemePalette(tokens: [.space4: "1rem"]) }
			static var spacing: TokenOverrides { .empty }
			static var radii: TokenOverrides { .empty }
			static var typography: TokenOverrides { .empty }
			static var motion: TokenOverrides { TokenOverrides([.radiusLg: "1rem"]) }
		}
		let findings = DesignToken.verify(WrongAxis.self)
		#expect(findings.count == 2)
		#expect(findings.contains { $0.name == "space-4" && $0.kind == .misplacedAxis })
		#expect(findings.contains { $0.name == "radius-lg" && $0.kind == .misplacedAxis })
	}

	@Test("a palette token read through a family axis is a MissingToken that names it")
	func paletteTokenOnFamilyAxisIsReported() {
		struct WrongAxis: DesignTheme {
			static var palette: ThemePalette { .empty }
			static var spacing: TokenOverrides { TokenOverrides([.colorBg: "#ffffff"]) }
			static var radii: TokenOverrides { .empty }
			static var typography: TokenOverrides { .empty }
			static var motion: TokenOverrides { .empty }
		}
		let findings = DesignToken.verify(WrongAxis.self)
		#expect(findings.count == 1)
		#expect(findings.first?.name == "color-bg")
		#expect(findings.first?.kind == .misplacedAxis)
	}

	@Test("the full vocabulary, each token on its own axis, passes — the completeness promise, exercised")
	func fullVocabularyPasses() {
		struct FullTheme: DesignTheme {
			static var palette: ThemePalette {
				ThemePalette(tokens: Dictionary(uniqueKeysWithValues:
					DesignToken.allCases.filter { $0.axis == .palette }.map { ($0, "initial") }))
			}
			static var spacing: TokenOverrides {
				TokenOverrides(Dictionary(uniqueKeysWithValues:
					DesignToken.allCases.filter { $0.axis == .spacing }.map { ($0, "1px") }))
			}
			static var radii: TokenOverrides {
				TokenOverrides(Dictionary(uniqueKeysWithValues:
					DesignToken.allCases.filter { $0.axis == .radii }.map { ($0, "1px") }))
			}
			static var typography: TokenOverrides {
				TokenOverrides(Dictionary(uniqueKeysWithValues:
					DesignToken.allCases.filter { $0.axis == .typography }.map { ($0, "1px") }))
			}
			static var motion: TokenOverrides {
				TokenOverrides(Dictionary(uniqueKeysWithValues:
					DesignToken.allCases.filter { $0.axis == .motion }.map { ($0, "1px") }))
			}
		}
		#expect(DesignToken.verify(FullTheme.self).isEmpty)
		// the whole vocabulary is read, so the fold is complete too.
		#expect(FullTheme.resolvedPalette.tokens.count == DesignToken.allCases.count)
	}
}
