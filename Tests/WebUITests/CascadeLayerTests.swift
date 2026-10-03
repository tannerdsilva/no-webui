import Testing
import WebUI
import WebUIDesignSystem

// MARK: - cascade layers
//
// the shipped sheet is layered — `webui` first, then `webui.utilities` — so
// unlayered css outranks every framework rule by *intent* rather than by
// specificity. two things can silently break that promise, and only these two:
// a rule escaping into the unlayered origin (it would beat consumers again), and
// the order statement going missing (layer order is set by first mention, so a
// lost statement *reorders* the layers instead of failing loudly).

@Suite("cascade layers")
struct CascadeLayerTests {

	/// the served composition: the order statement, the utility layer, then the sheet.
	private var composed: String { DesignSystemAssets.minifiedCss }

	@Test("the order statement opens the sheet, before any rule")
	func orderStatementFirst() {
		#expect(composed.hasPrefix("@layer webui, webui.utilities;"))
		// the working payload carries the file verbatim and the file opens with
		// blank lines; what matters is that the statement precedes the block that
		// *creates* the layers, since order is set by first mention.
		let working = WebUIAssets.css
		let statement = working.range(of: "@layer webui, webui.utilities;")
		let block = working.range(of: "@layer webui {")
		#expect(statement != nil, "the working payload declares the layer order")
		#expect(block != nil, "the working payload wraps the sheet in the framework layer")
		if let statement, let block {
			#expect(statement.lowerBound < block.lowerBound)
		}
	}

	@Test("the utility layer sits between the order statement and the sheet")
	func utilityLayerOrder() throws {
		let order = try #require(composed.range(of: "@layer webui, webui.utilities;"))
		let utilities = try #require(composed.range(of: "@layer webui.utilities {"))
		let framework = try #require(composed.range(of: "@layer webui {"))
		#expect(order.lowerBound < utilities.lowerBound)
		#expect(utilities.lowerBound < framework.lowerBound)
		// the layout primitives ride the utility layer, not the framework layer
		let spacing = try #require(composed.range(of: ".spacing-8"))
		#expect(utilities.lowerBound < spacing.lowerBound && spacing.lowerBound < framework.lowerBound)
	}

	@Test("no style rule escapes into the unlayered origin")
	func everyRuleIsLayered() {
		// depth-0 scan over the *served* bytes: at the top level only `@layer`
		// blocks may open. anything else — a component rule, an @media block of
		// component rules — would be unlayered and beat consumer css again.
		var depth = 0
		var header = ""
		var offenders: [String] = []
		for character in composed {
			switch character {
			case "{":
				let selector = header.trimmingCharacters(in: .whitespacesAndNewlines)
				if depth == 0, !selector.hasPrefix("@layer") {
					offenders.append(String(selector.suffix(80)))
				}
				depth += 1
				header = ""
			case "}":
				depth -= 1
				header = ""
			case ";":
				if depth == 0 { header = "" }
			default:
				if depth == 0 { header.append(character) }
			}
		}
		#expect(depth == 0, "the served sheet is brace-balanced")
		#expect(offenders.isEmpty, "unlayered rules found: \(offenders)")
	}

	@Test("the framework layer holds the sheet's rules, the utility layer holds layout")
	func layerContents() {
		let utilities = composed.range(of: "@layer webui.utilities {")
		let framework = composed.range(of: "@layer webui {")
		guard let utilities, let framework else {
			Issue.record("layer blocks missing")
			return
		}
		let utilitiesBody = composed[utilities.upperBound..<framework.lowerBound]
		#expect(utilitiesBody.contains(".vstack"))
		#expect(utilitiesBody.contains(".align-flex-start"))
		#expect(!utilitiesBody.contains(".button {"), "component rules never ride the utility layer")

		let frameworkBody = composed[framework.upperBound...]
		#expect(frameworkBody.contains(".button {"))
		#expect(frameworkBody.contains("--color-primary-500"))
	}

	@Test("the theme sheet stays unlayered, so a theme outranks the base sheet")
	func themeSheetIsUnlayered() {
		// layering the base is what lets *unlayered* css win, and the theme sheet
		// rides that same origin. if a theme ever grew a layer wrapper it would fall
		// below the base sheet's tokens and a scheme switch would stop painting —
		// the failure is silent, so it is pinned here.
		let theme = WebUITheme(palette: ThemePalette(tokens: [.colorBg: "#FFFFFF"]))
		let scoped = theme.stylesheet(scope: .attribute(id: "probe"))
		#expect(!scoped.contains("@layer"))
		#expect(scoped.contains(":root[data-scheme=\"probe\"]"))
		#expect(!theme.stylesheet().contains("@layer"))
	}
}