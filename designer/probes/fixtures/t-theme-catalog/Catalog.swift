// lane T fixture: a consumer theme catalog (the committed, reproducible input
// for the t-emission probe). mirrors the demo catalog shape: two @Theme
// providers (a few tokens each) + a hand-written WebUIThemeProvider twin with
// overlaying composition — the twin must emit through the same path.
import WebUIDesignSystem
import WebUIDesignSystemCore

@Theme
struct ProbeLight {
	static let colorPrimary500 = "#f97316"
	static let colorPrimary50 = "#fff7ed"
}

@Theme(base: ProbeLight.self)
struct ProbeDark {
	static let colorPrimary600 = "#ea580c"
}

struct ProbeTwin: WebUIThemeProvider {
	static let theme = ProbeLight.theme.overlaying(
		WebUITheme(tokens: [.colorDanger500: "#dc2626"])
	)
}

enum ProbeCatalog: ThemeCatalog {
	static var all: [any WebUIThemeProvider.Type] {
		[ProbeLight.self, ProbeDark.self, ProbeTwin.self]
	}
	static var defaultTheme: any WebUIThemeProvider.Type { ProbeLight.self }
}
