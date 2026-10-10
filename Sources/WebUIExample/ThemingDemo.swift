import WebUI
import WebUIDesignSystem

// W5.4 — the theming demo. three design tokens overridden through the typed
// path (`.overriding([...])`, W5.1), one host-defined component with its own
// `StyleSheet` in the `host` layer (W5.3), and the same demo page shipped in
// both themes. the whole demo is this file plus three routes in main.swift:
// zero edits to `designer/assets/design-system.css`, zero `!important`.
//
// the browser gate (designer/theme-default-probe.mjs) proves all of it on
// computed style, against `/theme-default` as the control.

// MARK: - the three typed token overrides (a)

/// the demo's theme: exactly THREE design tokens, moved through the typed
/// `.overriding([...])` path — never by hand-written css. light and dark
/// override the SAME three token names to different values, so "three
/// tokens" stays true while the demo ships both themes. every other token
/// keeps the framework's value (the gate's control asserts that).
enum ThemeDemoTokens {
	/// a teal accent replaces the framework's indigo; a warm paper canvas;
	/// hairline borders warmed to match.
	static let light = DefaultDesignTheme.overriding([
		.colorPrimarySolid: "#0d9488",
		.colorBg: "#faf9f7",
		.colorBorder: "#e7e2da",
	], mode: .light)

	/// the same three names, tuned for a dark canvas.
	static let dark = DefaultDesignTheme.overriding([
		.colorPrimarySolid: "#2dd4bf",
		.colorBg: "#0b1120",
		.colorBorder: "#334155",
	], mode: .dark)
}

// MARK: - the host component (b)

/// the demo's one custom component: a callout banner. a plain `View` on the
/// markup side; its look comes entirely from ``ThemeDemoStyle/sheet`` — a
/// host-layer ``StyleSheet`` using the W5.3 public artifact — and it reads
/// the theme through the SAME `var(--...)` tokens the framework components
/// read, so the three overrides restyle it for free, in both themes.
struct ThemeDemoCallout: View {
	let title: String
	let text: String

	func render(into buffer: inout HTMLBuffer) {
		buffer.append(
			"<aside class=\"theme-callout\" id=\"theme-callout\" role=\"note\">"
				+ "<h2 class=\"theme-callout__title\">" + htmlEscape(title) + "</h2>"
				+ "<p class=\"theme-callout__body\">" + htmlEscape(text) + "</p>"
				+ "</aside>"
		)
	}
}

// MARK: - the host StyleSheet (b)

/// the callout's own sheet: `.host` layer, so it wins the cascade over the
/// framework by origin — equal-or-lower specificity, zero `!important` —
/// exactly the guarantee a framework component gets. geometry is owned here
/// (the 3px border, the radius); anything that should follow the theme is a
/// `var(--...)` reference.
enum ThemeDemoStyle {
	static let sheet = StyleSheet(name: "theme-demo-callout", layer: .host) {
		CSSRule(".theme-callout", [
			CSSDeclaration("background", "var(--color-bg-raised, #ffffff)"),
			CSSDeclaration("border", "3px solid var(--color-primary-solid)"),
			CSSDeclaration("border-radius", "var(--radius-xl)"),
			CSSDeclaration("padding", "var(--space-4)"),
		])
		CSSRule(".theme-callout__title", [
			CSSDeclaration("color", "var(--color-primary-solid)"),
			CSSDeclaration("font-size", "var(--font-size-lg)"),
			CSSDeclaration("margin", "0 0 var(--space-2)"),
		])
		CSSRule(".theme-callout__body", [
			CSSDeclaration("margin", "0"),
			CSSDeclaration("color", "var(--color-text-secondary)"),
		])
	}
}

// MARK: - the demo pages (c)

/// the theming demo page: the same body served under three themes, so the
/// only variable between routes is the `WebUIDocument`'s `theme`.
enum ThemeDemo {
	/// the demo's own shell styles — token-referencing, like every other
	/// demo byte, and `!important`-free like every other demo byte.
	static let shellStyles: [String] = [
		".theme-demo { max-width: 960px; margin: 0 auto; padding: var(--space-8); display: flex; flex-direction: column; gap: var(--space-5); }",
		".theme-demo__header p { color: var(--color-text-muted); margin: 0; }",
		".theme-demo__tokens { font-family: var(--font-mono); font-size: var(--font-size-sm); color: var(--color-text-secondary); }",
		".theme-demo__row { display: flex; align-items: center; gap: var(--space-3); }",
	]

	/// the label each route renders so the gate can tell which theme is
	/// which — the ids it measures (`theme-callout`, `theme-button`,
	/// `theme-card`) are identical on every route.
	static func body(label: String) -> String {
		Div(class: "theme-demo") {
			Header(class: "theme-demo__header") {
				Heading("The theming demo", level: .h1)
				Paragraph("three tokens overridden via .overriding([...]) and one host component with its own StyleSheet — the same page in both themes, plus the unthemed default.")
			}
			ThemeDemoCallout(
				title: "a host component, styled by its own StyleSheet",
				text: "this callout is a View with no inline styles: the border, radius, padding and title colour all come from the host layer — and the border and title read --color-primary-solid, so the theme overrides restyle it for free."
			)
			WebUICard(elevation: .outlined, id: "theme-card", title: "what the theme moved") {
				Div(class: "theme-demo__tokens") {
					Text("--color-primary-solid · --color-bg · --color-border — nothing else changed.")
				}
			}
			Div(class: "theme-demo__row") {
				WebUIButton("primary button", appearance: .primary, id: "theme-button")
				Span { Text("this page ships theme: ") }
				Span { Raw(UnsafeMarkup.trusted("<strong id=\"theme-mode\">" + htmlEscape(label) + "</strong>")) }
			}
		}.renderThroughBuffer()
	}

	/// one demo page under one theme. `nil` is `.standard` — a host that
	/// never themes gets exactly the framework's own look (the gate's
	/// control), because an empty theme renders nothing.
	static func document(mode: ThemeMode?) -> WebUIDocument {
		let theme: WebUITheme
		let label: String
		switch mode {
			case .light?:
				theme = ThemeDemoTokens.light.webUITheme()
				label = "light"
			case .dark?:
				theme = ThemeDemoTokens.dark.webUITheme()
				label = "dark"
			default:
				theme = .standard
				label = "default (never themed)"
		}
		return WebUIDocument(
			title: "Theming demo · " + label,
			body: body(label: label),
			theme: theme,
			rawStyles: shellStyles,
			styleSheets: [ThemeDemoStyle.sheet]
		)
	}
}
