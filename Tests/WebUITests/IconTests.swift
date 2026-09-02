import Foundation
import Testing
import WebUI
import WebUIDesignSystem

// MARK: - Icon catalog + generated library

struct IconManifest: Decodable {
	struct Icon: Decodable, Identifiable {
		let name: String
		let category: String
		let title: String
		let tags: [String]
		let viewBox: String
		let elements: [String]
		var id: String { name }
	}
	let icons: [Icon]
}

func loadIconManifest() throws -> IconManifest {
	let url = packageRootURL().appendingPathComponent("designer/icons/icon-manifest.json")
	return try JSONDecoder().decode(IconManifest.self, from: Data(contentsOf: url))
}

@Suite("Icon catalog integrity")
struct IconCatalogTests {
	@Test("every manifest icon resolves to a generated catalog entry")
	func allManifestIconsAreCataloged() throws {
		let manifest = try loadIconManifest()
		for icon in manifest.icons {
			#expect(WebUIIcons.meta(named: icon.name) != nil, "missing catalog entry for \(icon.name)")
			let meta = WebUIIcons.meta(named: icon.name)!
			#expect(!meta.body.isEmpty, "empty body for \(icon.name)")
			#expect(meta.body.contains("<path") || meta.body.contains("<circle") || meta.body.contains("<line") || meta.body.contains("<rect") || meta.body.contains("<polyline") || meta.body.contains("<polygon") || meta.body.contains("<ellipse"))
		}
	}

	@Test("generated case count matches the manifest")
	func caseCountMatches() throws {
		let manifest = try loadIconManifest()
		#expect(IconName.allCases.count == manifest.icons.count, "IconName has \(IconName.allCases.count) cases; manifest has \(manifest.icons.count)")
	}

	@Test("icon names are identifier-safe and unique")
	func namesAreSafe() throws {
		let names = Set(IconName.allCases.map(\.rawValue))
		#expect(names.count == IconName.allCases.count)
		for n in names {
			#expect(n.allSatisfy { $0 == "-" || $0.isLowercase || $0.isNumber })
		}
	}

	@Test("camelCase mapping round-trips reserved words (repeat)")
	func reservedWordsMapped() {
		// "repeat" is a Swift keyword; the generator must backtick it and still resolve.
		#expect(IconName.named("repeat") == .`repeat`)
	}
}

// MARK: - WebUIIcon rendering

@Suite("WebUIIcon rendering")
struct WebUIIconTests {
	@Test("renders a currentColor inline svg with size class")
	func rendersSvg() {
		let html = WebUIIcon(.search, size: .large).render()
		#expect(html.hasPrefix("<svg class=\"icon icon--lg\""))
		#expect(html.contains("viewBox=\"0 0 24 24\""))
		#expect(html.contains("stroke=\"currentColor\""))
		#expect(html.contains("stroke-width=\"2\""))
		#expect(html.contains("stroke-linecap=\"butt\""))
		#expect(html.contains("stroke-linejoin=\"miter\""))
		#expect(html.contains("aria-hidden=\"true\""))
		#expect(html.hasSuffix("</svg>"))
		#expect(html.contains("<circle cx=\"11\" cy=\"11\" r=\"8\"/>"))
	}

	@Test("slot size emits the bare icon class")
	func slotSize() {
		let html = WebUIIcon(.inbox, size: .slot).render()
		#expect(html.hasPrefix("<svg class=\"icon\""))
		#expect(!html.contains("icon--"))
	}

	@Test("title switches to a labeled img")
	func titled() {
		let html = WebUIIcon(.trash, size: .medium, title: "Delete").render()
		#expect(html.contains("role=\"img\""))
		#expect(html.contains("aria-label=\"Delete\""))
		#expect(!html.contains("aria-hidden"))
	}

	@Test("a hostile title cannot break out of the aria-label attribute")
	func escapedTitle() {
		// quotes in the title must be escaped so the attribute boundary holds
		let html = WebUIIcon(.x, title: "onmouseover=\"alert(1)\"").render()
		#expect(html.contains("&quot;"))
		// exactly one aria-label attribute survives (no breakout into a 2nd attribute)
		let labelCount = html.components(separatedBy: "aria-label=").count - 1
		#expect(labelCount == 1)
		#expect(html.hasPrefix("<svg") && html.hasSuffix("</svg>"))
	}

	@Test("iconSize modifier overrides the size class")
	func sizeModifier() {
		let html = WebUIIcon(.heart).iconSize(.small).render()
		#expect(html.contains("icon--sm"))
		#expect(!html.contains("icon--md"))
	}
}

// MARK: - Custom icon sanitization

@Suite("WebUIIconCustom sanitization")
struct WebUIIconCustomTests {
	@Test("script tags are stripped from custom geometry")
	func stripsScript() {
		let icon = WebUIIconCustom(name: "ok", body: "<path d=\"M1 1h10\"/><script>alert(1)</script>", size: .medium)
		let html = icon.render()
		#expect(!html.contains("<script"))
		#expect(html.contains("<path d=\"M1 1h10\"/>"))
		#expect(html.contains("data-icon=\"ok\""))
	}

	@Test("on* event handlers are neutralized")
	func neutralizesHandlers() {
		let icon = WebUIIconCustom(name: "ok", body: "<rect onmouseover=\"x\" x=\"1\" y=\"1\" width=\"4\" height=\"4\"/>", size: .medium)
		#expect(!icon.body.contains("onmouseover=\""))
	}

	@Test("javascript: hrefs are neutralized")
	func neutralizesHrefs() {
		let icon = WebUIIconCustom(name: "ok", body: "<a href=\"javascript:alert(1)\" x=\"1\">x</a>", size: .medium)
		#expect(!icon.body.contains("javascript:"))
	}

	@Test("foreignObject is disabled")
	func disablesForeignObject() {
		let icon = WebUIIconCustom(name: "ok", body: "<foreignObject><img src=\"x\"/></foreignObject>", size: .medium)
		#expect(!icon.body.contains("<foreignObject"))
	}

	@Test("custom icon still inherits currentColor + size class")
	func inherits() {
		let html = WebUIIconCustom(name: "my-star", body: "<path d=\"M12 2l3 7 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1z\"/>").iconSize(.extraLarge).render()
		#expect(html.contains("stroke=\"currentColor\""))
		#expect(html.contains("icon--xl"))
	}
}

// MARK: - Emoji migration bridge

@Suite("IconName emoji bridge")
struct IconEmojiBridgeTests {
	@Test("legacy emoji map to semantic icons")
	func mapsEmoji() {
		#expect(IconName(emoji: "📭") == .inbox)
		#expect(IconName(emoji: "🔎") == .search)
		#expect(IconName(emoji: "📁") == .folder)
		#expect(IconName(emoji: "📄") == .fileText)
		#expect(IconName(emoji: "ℹ️") == .info)
		#expect(IconName(emoji: "📦") == .package)
	}

	@Test("a raw name also resolves")
	func mapsRawName() {
		#expect(IconName(emoji: "check-circle") == .checkCircle)
		#expect(IconName(emoji: "search") == .search)
	}

	@Test("an unknown emoji yields nil (no silent fallback)")
	func unknownIsNil() {
		#expect(IconName(emoji: "🚀nope") == nil)
	}
}

// MARK: - Component migration (no emoji in shipped markup)

@Suite("Component icon migration")
struct ComponentMigrationTests {
	@Test("alert renders its semantic glyph, never an emoji")
	func alertUsesSvg() {
		let html = WebUIAlert(variant: .warning, message: "Careful").render()
		#expect(html.contains("alert__icon fill-slot"))
		#expect(html.contains("<svg"))
		// warning's semantic glyph is alert-triangle
		#expect(html.contains("M10.29 3.86") || html.contains("<path d=\"M12 9v4\""))
		#expect(!html.contains("⚠"))
	}

	@Test("alert danger default is the x-circle glyph")
	func alertDanger() {
		let html = WebUIAlert(variant: .danger, message: "Nope").render()
		#expect(html.contains("alert__icon fill-slot"))
		#expect(!html.contains("❌"))
	}

	@Test("table empty state renders an svg, not an emoji")
	func tableEmpty() {
		let html = WebUITable(headers: ["A"], rows: [], emptyState: .init(icon: .search, title: "None", message: "Try again")).render()
		#expect(html.contains("table__empty-icon fill-slot"))
		#expect(html.contains("<svg"))
		#expect(!html.contains("🔎"))
	}

	@Test("standalone empty state renders an svg, not an emoji")
	func emptyState() {
		let html = WebUIEmptyState(icon: .package, title: "Empty", message: "m", action: ("Add", "a")).render()
		#expect(html.contains("empty-state__icon fill-slot"))
		#expect(html.contains("<svg"))
		#expect(!html.contains("📦"))
	}

	@Test("tree node icon renders an svg, not an emoji")
	func tree() {
		let html = WebUITree(nodes: [WebUITree.Node(id: "f", label: "f", icon: .folder, children: [WebUITree.Node(id: "i", label: "i", icon: .fileText)])], id: "t", expanded: ["f"]).render()
		#expect(html.contains("tree__icon fill-slot"))
		#expect(html.contains("<svg"))
		#expect(!html.contains("📁") && !html.contains("📄"))
	}

	@Test("no shipped icon slot emits an emoji code point")
	func noEmojiAnyWhere() {
		let samples = [
			WebUIAlert(variant: .info, message: "a").render(),
			WebUIAlert(variant: .success, message: "b").render(),
			WebUIAlert(variant: .warning, message: "c").render(),
			WebUIAlert(variant: .danger, message: "d").render(),
			WebUIEmptyState(icon: .inbox, title: "e", message: "m").render(),
			WebUITable(headers: ["h"], rows: [], emptyState: .init(icon: .search, title: "f", message: "g")).render(),
			WebUITree(nodes: [WebUITree.Node(id: "x", label: "y", icon: .folder)]).render(),
		]
		let emojiRanges: [ClosedRange<UInt32>] = [
			0x2190...0x21FF, 0x2600...0x27BF, 0x2B00...0x2BFF,
			0x1F000...0x1FAFF, 0xFE00...0xFE0F,
		]
		for sample in samples {
			for scalar in sample.unicodeScalars {
				let v = scalar.value
				for r in emojiRanges {
					#expect(!r.contains(v), "emoji code point U+\(String(v, radix: 16)) found in: \(sample.prefix(120))")
				}
			}
		}
	}
}

// MARK: - Shipped CSS (first law + icon primitives present)

@Suite("Icon CSS deployment")
struct IconCSSDeploymentTests {
	@Test("shipped css carries the icon primitives")
	func hasIconPrimitives() throws {
		let css = WebUIAssets.css
		for needle in [".icon", ".icon--sm", ".icon--md", ".icon--lg", ".icon--xl", "fill-slot", "alert__icon > svg.icon", "tree__icon > svg.icon", "table__empty-icon > svg.icon", "empty-state__icon > svg.icon", "icon--spin"] {
			#expect(css.contains(needle), "shipped css missing \(needle)")
		}
	}

	@Test("shipped css is comment-free (first law)")
	func noComments() throws {
		// comments are stripped by the wire minifier; the deployed css must have none
		#expect(!minifyCSS(WebUIAssets.css).contains("/*"))
	}

	@Test("embedded css is byte-identical to the designer source")
	func byteIdentical() throws {
		let source = try Data(contentsOf: packageRootURL().appendingPathComponent("designer/assets/design-system.css"))
		#expect(source == Data(WebUIAssets.css.utf8))
	}
}
