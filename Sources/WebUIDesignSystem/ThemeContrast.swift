import Foundation

// MARK: - ThemeContrast

/// WCAG contrast arithmetic over a ``WebUITheme``'s palettes.
///
/// This is the payoff of theming being typed rather than stringly-built: a consumer with
/// 27 schemes can assert every palette × mode pair clears AA in a loop, instead of
/// hand-writing (and eventually rotting) one expectation per pair. The shipped sheet has
/// its own contrast guardrail in `DeploymentIntegrityTests`; this is the same property,
/// applied to a consumer's own themes.
public enum ThemeContrast {

	/// The WCAG 2.1 contrast ratio, `1.0 … 21.0`. `nil` when either colour is not a hex
	/// literal — a `var(--token)` reference, `rgba(…)`, or a named colour cannot be
	/// resolved without the cascade, and guessing would be worse than reporting nothing.
	public static func ratio(_ a: String, _ b: String) -> Double? {
		guard let la = relativeLuminance(a), let lb = relativeLuminance(b) else { return nil }
		let lighter = max(la, lb)
		let darker = min(la, lb)
		return (lighter + 0.05) / (darker + 0.05)
	}

	/// Relative luminance of `#rgb` or `#rrggbb`.
	public static func relativeLuminance(_ hex: String) -> Double? {
		guard let channels = rgb(hex) else { return nil }
		func linear(_ c: Double) -> Double {
			c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
		}
		return 0.2126 * linear(channels.0) + 0.7152 * linear(channels.1) + 0.0722 * linear(channels.2)
	}

	/// The pairs a theme is expected to clear, in the "ink on surface" direction.
	///
	/// Not exhaustive — it is the set where getting it wrong is a legibility bug rather
	/// than a preference: body and muted text on each surface, the label on a solid accent,
	/// and the three status colours against the page.
	public static let defaultPairs: [(foreground: DesignToken, background: DesignToken)] = [
		(.colorText, .colorBg),
		(.colorText, .colorBgRaised),
		(.colorText, .colorBgInset),
		(.colorText, .colorBgSubtle),
		(.colorTextMuted, .colorBg),
		(.colorTextMuted, .colorBgRaised),
		(.colorOnPrimarySolid, .colorPrimarySolid),
		(.colorDanger, .colorBg),
		(.colorSuccess, .colorBg),
		(.colorWarning, .colorBg),
	]

	/// Every AA failure in a theme, as readable lines. **Empty means it clears AA.**
	///
	/// A pair is checked only when the theme sets *both* tokens: a partial theme that
	/// overrides one accent cannot be judged on text-on-surface, and silently substituting
	/// the shipped sheet's values for the tokens it does not set would report failures the
	/// theme is not responsible for. A theme that sets both and gets it wrong is the case
	/// this catches — which is the case that ships a bug.
	public static func audit(
		_ theme: WebUITheme,
		minimum: Double = 4.5,
		pairs: [(foreground: DesignToken, background: DesignToken)] = defaultPairs
	) -> [String] {
		var failures: [String] = []
		for (mode, palette) in [("light", theme.palette), ("dark", theme.dark)] where !palette.isEmpty {
			for pair in pairs {
				guard let ink = palette.tokens[pair.foreground],
					  let surface = palette.tokens[pair.background],
					  let ratio = ratio(ink, surface)
				else { continue }
				if ratio < minimum {
					failures.append(
						"\(mode): \(pair.foreground.rawValue) on \(pair.background.rawValue) "
						+ "= \(String(format: "%.2f", ratio)) (needs \(minimum))"
					)
				}
			}
		}
		return failures
	}

	/// `#rgb` / `#rrggbb` → linear sRGB channels in `0…1`.
	private static func rgb(_ hex: String) -> (Double, Double, Double)? {
		var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
		guard text.hasPrefix("#") else { return nil }
		text.removeFirst()
		guard text.count == 3 || text.count == 6 else { return nil }
		let expanded = text.count == 3 ? text.map { "\($0)\($0)" }.joined() : text
		guard let value = UInt32(expanded, radix: 16) else { return nil }
		return (
			Double((value >> 16) & 0xFF) / 255.0,
			Double((value >> 8) & 0xFF) / 255.0,
			Double(value & 0xFF) / 255.0
		)
	}
}