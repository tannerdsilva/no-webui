import WebUI
import WebUIDesignSystem
import WebUIChart

// MARK: - The block set
//
// A block is a page *scaffold*: a composed arrangement of the existing
// framework + design-system surface, rendered standalone (its own document,
// no dependency on the showcase). Blocks are deliberately static; where a
// block needs application wiring the consumer supplies the handlers, which is
// what keeps a block a library view rather than an app.
//
// Everything here composes classes that already exist in the sheet, so the
// orphan-class ratchet is unaffected by this target.

/// The shipped blocks. The raw value is the name the blocks server takes
/// (`--block <name>`).
public enum Block: String, CaseIterable, Sendable {
	case dashboard
	case login
	case signup
	case sidebarDefault = "sidebar-default"
	case sidebarCollapsible = "sidebar-collapsible"
	case sidebarRail = "sidebar-rail"
	case sidebarInset = "sidebar-inset"
	case patterns

	/// Human title (document title + index page).
	public var title: String {
 switch self {
 case .dashboard: return "Dashboard"
 case .login: return "Login"
 case .signup: return "Sign up"
 case .sidebarDefault: return "Sidebar: default"
 case .sidebarCollapsible: return "Sidebar: collapsible"
 case .sidebarRail: return "Sidebar: rail"
 case .sidebarInset: return "Sidebar: inset"
		case .patterns: return "Patterns"
		}
	}

	/// One line describing what the block demonstrates.
	public var summary: String {
 switch self {
 case .dashboard: return "Stat row, a charted trend and a data table in a padded content column."
 case .login: return "A centered auth card: two fiddlesticks fields, a primary action and a secondary link."
 case .signup: return "Registration with validation states (error, success, requirements)."
 case .sidebarDefault: return "A fixed navigation sidebar beside the content column."
 case .sidebarCollapsible: return "The same shell with a header toggle for the collapsed state."
 case .sidebarRail: return "Icon-only rail (labels and section header hidden)."
 case .sidebarInset: return "Sidebar outside a padded, inset content surface."
		case .patterns: return "Carousel, menubar and a questionnaire: composition over the existing set."
		}
	}
}

// MARK: - Pages

public enum WebUIBlocks {

	/// Every shipped block, in presentation order.
	public static var all: [Block] { Block.allCases }

	/// A complete standalone document for one block (its own runtime boot, so
	/// the socket-backed status chip and the theme toggle behave like a page).
	public static func page(for block: Block, dir: String? = nil) -> String {
		WebUIDocument(title: "WebUI block - " + block.title,
 body: body(for: block),
 dir: dir,
 includeRuntime: true,
 checkClasses: true
).render()
	}

	/// The block's page body (no document chrome).
	public static func body(for block: Block) -> String {
 switch block {
 case .dashboard: return dashboardBody()
 case .login: return loginBody()
 case .signup: return signupBody()
 case .sidebarDefault: return sidebarBody(mode: .default)
 case .sidebarCollapsible: return sidebarBody(mode: .collapsible)
 case .sidebarRail: return sidebarBody(mode: .rail)
 case .sidebarInset: return sidebarBody(mode: .inset)
		case .patterns: return patternsBody()
		}
	}

	/// The blocks index: one card per block, linking to its standalone page.
	public static func indexPage(dir: String? = nil) -> String {
 let cards = all.map { block in
			WebUICard(variant: .outlined) {
				VStack(alignment: .leading, spacing: 8) {
					Heading(block.title, level: .h3)
					Paragraph(block.summary)
					Link("Open block", href: "/blocks/" + block.rawValue,
					     class: "button button--secondary button--sm")
				}
				.padding(16)
			}
		}
 return WebUIDocument(title: "WebUI blocks",
 body: VStack(spacing: 24) {
				Heading("Blocks", level: .h1)
				Paragraph("\(all.count) standalone page scaffolds, composed from the existing component set.")
				Div(class: "grid grid--4") {
 cards
				}
			}
			.padding(24)
			.render(),
 dir: dir,
 includeRuntime: true,
 checkClasses: true
).render()
	}

	// MARK: Shared chrome

	static let navItems: [WebUISidebarItem] = [
		WebUISidebarItem(id: "nav-overview", label: "Overview", icon: .home),
		WebUISidebarItem(id: "nav-analytics", label: "Analytics", icon: .chartBar, badge: "12"),
		WebUISidebarItem(id: "nav-deploys", label: "Deploys", icon: .zap),
		WebUISidebarItem(id: "nav-incidents", label: "Incidents", icon: .bell, badge: "3"),
		WebUISidebarItem(id: "nav-databases", label: "Databases", icon: .database),
		WebUISidebarItem(id: "nav-settings", label: "Settings", icon: .settings),
]

	private static func statCards() -> [any View] {
		[
			WebUIStat(label: "Requests", value: "12.4M", size: .lg, trend: "+8.1%", trendDirection: .up,
 compare: "vs last week", spark: [3, 5, 4, 8, 7, 10, 12]),
			WebUIStat(label: "p95 latency", value: "42ms", size: .lg, trend: "-6.4%", trendDirection: .down,
 compare: "vs last week", spark: [12, 11, 9, 10, 8, 7, 7]),
			WebUIStat(label: "Error rate", value: "0.21%", size: .lg, trend: "+0.03%", trendDirection: .up,
 compare: "vs last week", spark: [2, 2, 3, 2, 4, 3, 5]),
			WebUIStat(label: "Uptime", value: "99.98%", size: .lg, trend: "+0.01%", trendDirection: .up,
 compare: "30 days", spark: [9, 9, 10, 9, 10, 10, 10]),
]
	}

	private static func trendChart() -> some View {
		Chart {
			ForEach(Array([12.0, 18.0, 15.0, 24.0, 31.0, 27.0, 38.0, 42.0].enumerated().map { (x: Double($0.offset + 1), y: $0.element) })) { p in
				Group {
					AreaMark(x: .value("Week", p.x), y: .value("Requests", p.y))
						.foregroundStyle(by: "requests")
						.areaGradient(.fade(.explicit("var(--color-chart-1)")))
					LineMark(x: .value("Week", p.x), y: .value("Requests", p.y))
						.foregroundStyle(by: "requests")
						.interpolation(.catmullRom)
				}
			}
		}
		.chartTitle("Requests per week")
		.chartHeight(260)
		.chartLegend(position: .hidden)
	}

	private static func deployTable() -> some View {
		WebUITable(headers: ["Service", "Region", "p95", "Status"],
 rows: [
				[Text("web"), Text("us-east-1"), Text("42 ms"), Text("healthy")],
				[Text("api"), Text("eu-west-2"), Text("18 ms"), Text("healthy")],
				[Text("search"), Text("us-west-2"), Text("61 ms"), Text("degraded")],
				[Text("worker"), Text("ap-south-1"), Text("27 ms"), Text("healthy")],
],
 wrapped: true,
 alignments: [.leading, .leading, .trailing, .leading]
)
	}

	// MARK: Dashboard

	private static func dashboardBody() -> String {
		VStack(alignment: .leading, spacing: 24) {
			Div(class: "grid grid--2") {
				VStack(alignment: .leading, spacing: 4) {
					Heading("Overview", level: .h1)
					Paragraph("Production, last 7 days")
				}
				WebUIEngineStatus()
				WebUIThemeToggle()
			}
			Div(class: "grid grid--4") {
 statCards()
			}
			WebUICard(variant: .outlined) {
				VStack(alignment: .leading, spacing: 12) {
					Heading("Traffic", level: .h3)
 trendChart()
				}
				.padding(16)
			}
			WebUICard(variant: .outlined) {
				VStack(alignment: .leading, spacing: 12) {
					Heading("Deploys", level: .h3)
 deployTable()
				}
				.padding(16)
			}
		}
		.padding(24)
		.render()
	}

	// MARK: Auth

	private static func authCard(title: String, subtitle: String, fields: [any View],
 action: String, footer: String, footerHref: String) -> some View {
		WebUICard(variant: .elevated) {
			VStack(alignment: .leading, spacing: 16) {
				VStack(alignment: .leading, spacing: 4) {
					Heading(title, level: .h2)
					Paragraph(subtitle)
				}
				VStack(alignment: .leading, spacing: 12) {
 fields
				}
				Button(action, class: "button button--primary button--md", type: .submit)
				Link(footer, href: footerHref, class: "link")
			}
			 .padding(24)
		}
		.maxWidth("26rem")
	}

	private static func loginBody() -> String {
		VStack(alignment: .center, spacing: 24) {
 authCard(title: "Sign in",
 subtitle: "Use your workspace account to continue.",
 fields: [
					WebUIField(label: "Email", controlID: "block-login-email", required: true) {
						Input(id: "block-login-email", name: "email", placeholder: "you@example.com", type: .email)
					},
					WebUIField(label: "Password", controlID: "block-login-password", required: true) {
						Input(id: "block-login-password", name: "password", type: .password)
					},
],
 action: "Sign in",
 footer: "Forgot your password?",
 footerHref: "/blocks/login"
)
		}
		.padding(24)
		.render()
	}

	private static func signupBody() -> String {
		VStack(alignment: .center, spacing: 24) {
 authCard(title: "Create your account",
 subtitle: "Two minutes, no credit card.",
 fields: [
					WebUIField(label: "Full name", controlID: "block-signup-name", required: true) {
						Input(id: "block-signup-name", name: "name", placeholder: "Ada Lovelace", type: .text)
					},
					WebUIField(label: "Work email", controlID: "block-signup-email", required: true,
 note: "Already registered", noteKind: .error,
 helper: "That address already has an account; sign in instead.",
 helperIsError: true) {
						Input(id: "block-signup-email", name: "email", type: .email, value: "ada@example.com")
					},
					WebUIField(label: "Workspace slug", controlID: "block-signup-slug", required: true,
 note: "Available", noteKind: .success, count: "2 / 32") {
						Input(id: "block-signup-slug", name: "slug", type: .text, value: "acme")
					},
					WebUIField(label: "Password", controlID: "block-signup-password", required: true,
 helper: "At least 12 characters, with a number and a symbol.") {
						Input(id: "block-signup-password", name: "password", type: .password)
					},
],
 action: "Create account",
 footer: "Already have an account?",
 footerHref: "/blocks/login"
)
		}
		.padding(24)
		.render()
	}

// MARK: Patterns (p7 long tail)



	private static func patternsBody() -> String {
		let slides: [any View] = [
			WebUICard(variant: .elevated) {
				VStack(alignment: .leading, spacing: 8) {
					Heading("Ship faster", level: .h3)
					Paragraph("Server-owned state means every interaction is a round trip you can log and test.")
				}
				.padding(16)
			},
			WebUICard(variant: .elevated) {
				VStack(alignment: .leading, spacing: 8) {
					Heading("No client script", level: .h3)
					Paragraph("Scroll-snap, focus-visible and anchor dots: this carousel needs no javascript.")
				}
				.padding(16)
			},
			WebUICard(variant: .elevated) {
				VStack(alignment: .leading, spacing: 8) {
					Heading("Divergences are documented", level: .h3)
					Paragraph("Where fidelity would need script, the trade is written down instead of hidden.")
				}
				.padding(16)
			},
		]

		let menu: [WebUIMenubar.Item] = [
			WebUIMenubar.Item("File", entries: [.init("New"), .init("Open"), .init("Export")]),
			WebUIMenubar.Item("View", entries: [.init("Zoom in"), .init("Zoom out"), .init("Reset")]),
			WebUIMenubar.Item("Help", entries: [.init("Blocks index", href: "/blocks"), .init("Shortcuts")]),
		]

		return VStack(alignment: .leading, spacing: 24) {
			Heading("Patterns", level: .h1)
			Paragraph("Three long-tail patterns, composed from the surface that already exists.")

			VStack(alignment: .leading, spacing: 8) {
				Heading("Carousel", level: .h3)
				Paragraph("Focus the track and use the arrow keys; the dots are anchors, so they jump but cannot track state.")
				WebUICarousel(id: "blk-carousel", label: "Release highlights", slides: slides)
			}

			VStack(alignment: .leading, spacing: 8) {
				Heading("Menubar", level: .h3)
				Paragraph("Hover or tab onto a trigger to open its panel; escape-to-close is the documented divergence.")
				WebUIMenubar(items: menu, id: "blk-menubar")
			}

			VStack(alignment: .leading, spacing: 8) {
				Heading("Questionnaire", level: .h3)
				WebUICard(variant: .outlined) {
					VStack(alignment: .leading, spacing: 16) {
						WebUIField(label: "How was the setup?", controlID: "blk-q1", required: true,
						           helper: "Pick the closest answer.") {
							WebUIRadioGroup(options: [
								.init("Effortless"), .init("Fine"), .init("Painful"),
							], selected: "Fine")
						}
						WebUIField(label: "Which surfaces do you use?", controlID: "blk-q2") {
							WebUICheckboxGroup(options: [
								.init("Dashboard", checked: true), .init("Blocks"), .init("Charts", checked: true),
							])
						}
						WebUIField(label: "Anything else?", controlID: "blk-q3", count: "0 / 200") {
							Input(id: "blk-q3", name: "notes", placeholder: "Optional", type: .text)
						}
						Button("Submit answers", class: "button button--primary button--md", type: .submit)
					}
					.padding(16)
				}
			}
		}
		.padding(24)
		.render()
	}

	// MARK: Sidebar family

	enum SidebarMode {
 case `default`
 case collapsible
 case rail
 case inset
	}

	private static func sidebarBody(mode: SidebarMode) -> String {
 let rail = mode == .rail
 let sidebar = WebUISidebar(items: navItems,
 activeID: "nav-overview",
 id: "block-sidebar",
 style: rail ? .rail : .full,
 header: "Acme"
)
 let content = VStack(alignment: .leading, spacing: 16) {
			Div(class: "grid grid--2") {
				Heading("Overview", level: .h1)
				WebUIEngineStatus()
				WebUIThemeToggle()
			}
			Div(class: "grid grid--4") {
 statCards()
			}
			WebUICard(variant: .outlined) {
				VStack(alignment: .leading, spacing: 12) {
					Heading("Deploys", level: .h3)
 deployTable()
				}
				.padding(16)
			}
		}
		.padding(24)

 let shell = HStack(alignment: .top, spacing: 0) {
 sidebar
			Main {
 content
			}
		}

		// inset: the page margin goes on the shell itself, so the content column
		// reads as a surface inset from the window edge. an extra wrapper is not
		// safe here: a bare .grid track sizes to max-content, which pushed the
		// shell past a 320px viewport (the measured track was 543px). the shell
		// stays a direct child, like the variants that already pass the sweep.
		if mode == .inset {
			return HStack(alignment: .top, spacing: 0) {
				sidebar
				Main {
					content
				}
			}
			.padding(16)
			.render()
		}
		return shell.render()
	}
}