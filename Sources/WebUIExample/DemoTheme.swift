// MARK: - the demo's theme catalog (DX-15a pipeline + DX-15b policy)
//
// the consumer-side surface for the theme axis: declare a `ThemeCatalog`, attach
// the framework's `WebUIThemePlugin`, and reference the emitted sheet. the plugin
// discovers `DemoCatalog` in this target and emits `DemoCatalogSheet` (a
// `WebUIShippedAsset` conformance) as a compilable source on every build — the
// framework path (mechanism (a)), with no consumer tool target and no shim.
//
// policy (DX-15b): tokens and typed rules in, shadowing out. every palette below
// states a FEW tokens of the framework's own vocabulary — no re-skinning of a
// design-system class under a colliding name.

import WebUIDesignSystem
import WebUIDesignSystemCore

/// the light palette — three tokens, all framework vocabulary.
@Theme
struct DemoLight {
	static let colorPrimary500 = "#7c3aed"
	static let colorPrimary50 = "#f5f3ff"
	static let colorBorder = "#ddd6fe"
}

/// the dark palette — overlays the light one through `@Theme(base:)`.
@Theme(base: DemoLight.self)
struct DemoDark {
	static let colorPrimary600 = "#6d28d9"
}

/// the HAND-WRITTEN twin (no `@Theme` macro): a provider composed by `overlaying`,
/// so the same emitter path carries a macro-free conformance.
struct DemoHandWritten: WebUIThemeProvider {
	static let theme = DemoLight.theme.overlaying(
		WebUITheme(tokens: [.colorDanger500: "#dc2626"])
	)
}

/// the catalog the plugin discovers and emits (`DemoCatalogSheet`). the server
/// serves those emitted bytes at the sheet's content address and the document
/// links that same address — the address is computed from the bytes, so the two
/// cannot disagree.
enum DemoCatalog: ThemeCatalog {
	static var all: [any WebUIThemeProvider.Type] {
		[DemoLight.self, DemoDark.self, DemoHandWritten.self]
	}
	static var defaultTheme: any WebUIThemeProvider.Type { DemoLight.self }
}