import Foundation
import WebUI
import WebUIDesignSystem
import WebUIChart
import WebUIChartSpec
import WebUIIslandFixtures
import WebUISharedCore
import Synchronization

// the smoke page itself: state, the interactive surfaces, and the page
// assembly. split out of `main.swift` so the host there is only the route
// table and the launch — this file is the page, byte for byte, as it was
// when `main.swift` also carried its own NIO bootstrap.

// MARK: - Shared state

final class SmokeState: Sendable {
	private struct Values {
		var count = 0
		var progress = 0.25
		var echo = ""
		// interactive table demo (server is the source of truth)
		var tableSortColumn = 0
		var tableSortAsc = true
		var tableSelected: Set<String> = []
		var tableExpanded: Set<String> = []
		// interactive chart demo (chart selection: click a bar → server re-renders)
		var hiddenColumns: Set<Int> = []
		var chartSelected: String? = nil
	}
	private let values = Mutex(Values())

	var count: Int {
		get { values.withLock { $0.count } }
		set { values.withLock { $0.count = newValue } }
	}
	var progress: Double {
		get { values.withLock { $0.progress } }
		set { values.withLock { $0.progress = newValue } }
	}
	var echo: String {
		get { values.withLock { $0.echo } }
		set { values.withLock { $0.echo = newValue } }
	}
	var tableSortColumn: Int {
		get { values.withLock { $0.tableSortColumn } }
		set { values.withLock { $0.tableSortColumn = newValue } }
	}
	var tableSortAsc: Bool {
		get { values.withLock { $0.tableSortAsc } }
		set { values.withLock { $0.tableSortAsc = newValue } }
	}
	var tableSelected: Set<String> {
		get { values.withLock { $0.tableSelected } }
		set { values.withLock { $0.tableSelected = newValue } }
	}
	var tableExpanded: Set<String> {
		get { values.withLock { $0.tableExpanded } }
		set { values.withLock { $0.tableExpanded = newValue } }
	}
	var hiddenColumns: Set<Int> {
		get { values.withLock { $0.hiddenColumns } }
		set { values.withLock { $0.hiddenColumns = newValue } }
	}
	var chartSelected: String? {
		get { values.withLock { $0.chartSelected } }
		set { values.withLock { $0.chartSelected = newValue } }
	}
}

// MARK: - Interactive table demo data

/// the base direction for the page: `WEBUI_DIR=rtl` renders every surface
/// mirrored, which is how the interactive page gets an rtl pass.
let smokeDir = ProcessInfo.processInfo.environment["WEBUI_DIR"]

let smokeTableRecords: [(id: String, name: String, region: String, ms: Int, detail: String)] = [
	("web", "web", "us-east-1", 42, "8 instances · 99.98% SLA · canary 10% to v2.14"),
	("api", "api", "eu-west-2", 18, "4 instances · 99.95% SLA · zero-downtime deploys"),
	("search", "search", "us-west-2", 61, "12 shards · 99.9% SLA · 3 warm nodes"),
	("auth", "auth", "ap-south-1", 9, "3 instances · 100% SLA · hardware-backed keys"),
]

/// the column-visibility control for the smoke table: a plain `WebUIMenu`
/// dispatched by `targetId` (the container-handler pattern), whose effect is
/// host state. the handler re-emits the menu (check marks) and the table
/// (which stops emitting the hidden column) - the p4 surface, on the page the
/// full-stack gate drives.
func smokeColumnMenuHTML(state: SmokeState) -> String {
	let columns = ["Name", "Region", "p95"]
	return WebUIMenu(
		items: columns.enumerated().map { index, name in
			WebUIMenu.Item(
				name,
				icon: state.hiddenColumns.contains(index) ? .xCircle : .checkCircle
			)
		},
		id: "smoke-column-menu",
		onSelect: { event in
			guard let raw = event.targetID,
			      let last = raw.split(separator: "-").last,
			      let index = Int(last) else { return [] }
			if state.hiddenColumns.contains(index) {
				state.hiddenColumns.remove(index)
			} else {
				state.hiddenColumns.insert(index)
			}
			return [
				FragmentUpdate(id: "smoke-column-menu", html: smokeColumnMenuHTML(state: state)),
				FragmentUpdate(id: "interactive-table", html: interactiveTableHTML(state: state)),
			]
		},
		header: "Columns",
		panel: true
	).markup.html
}

func interactiveTableHTML(state: SmokeState) -> String {
	let col = state.tableSortColumn
	let asc = state.tableSortAsc
	let sorted = smokeTableRecords.sorted { a, b in
		let less: Bool
		switch col {
		case 1: less = a.region.localizedCaseInsensitiveCompare(b.region) == .orderedAscending
		case 2: less = a.ms < b.ms
		default: less = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
		}
		return asc ? less : !less
	}
	let rows = sorted.map { (rec: (id: String, name: String, region: String, ms: Int, detail: String)) in
		[Text(rec.name), Text(rec.region), Text("\(rec.ms) ms")]
	}
	let details = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, Text($0.detail)) })

	// Typed handlers: the table self-wires each control as a routed component
	// under its stable id ({id}-sort-{col} / -select-all / -select-{rowId} /
	// -expand-{rowId}). `me` references the table root, so the handler can
	// re-render the table in place with zero id strings. The fullstack driver
	// drives these same controls over the WS by their component ids.
	return WebUITable(
		headers: ["Name", "Region", "p95"],
		rows: rows,
		alignments: [.leading, .leading, .trailing],
		id: "interactive-table",
		sortableColumns: [0, 1, 2],
		hiddenColumns: state.hiddenColumns,
		sort: (col, asc ? .ascending : .descending),
		selectable: true,
		rowIds: sorted.map { $0.id },
		selectedRows: state.tableSelected,
		expandedRows: state.tableExpanded,
		rowDetails: details
	)
	.onSort { me, column in
		if state.tableSortColumn == column { state.tableSortAsc.toggle() }
		else { state.tableSortColumn = column; state.tableSortAsc = true }
		return [me.replace(with: interactiveTableHTML(state: state))]
	}
	.onSelectAll { me in
		if state.tableSelected.count == smokeTableRecords.count { state.tableSelected = [] }
		else { state.tableSelected = Set(smokeTableRecords.map { $0.id }) }
		return [me.replace(with: interactiveTableHTML(state: state))]
	}
	.onSelect { me, rowID in
		if state.tableSelected.contains(rowID) { state.tableSelected.remove(rowID) }
		else { state.tableSelected.insert(rowID) }
		return [me.replace(with: interactiveTableHTML(state: state))]
	}
	.onToggleExpand { me, rowID in
		if state.tableExpanded.contains(rowID) { state.tableExpanded.remove(rowID) }
		else { state.tableExpanded.insert(rowID) }
		return [me.replace(with: interactiveTableHTML(state: state))]
	}
	.markup.html
}

// MARK: - Display-element renderers (stable ids, no event handlers)

func counterValueHTML(_ n: Int) -> String {
	"<div id=\"counter-value\" class=\"counter-value\" role=\"status\"><span>\(n)</span></div>"
}

func progressValueHTML(_ value: Double) -> String {
	let bar = WebUIProgress(value: value, variant: .primary, showLabel: true, size: .md).markup.html
	return "<div id=\"progress-value\">\(bar)</div>"
}

func echoOutHTML(_ text: String) -> String {
	let safe = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
	return "<div id=\"echo-out\" class=\"echo-out\" role=\"status\"><span class=\"echo-out__text\">\(safe)</span></div>"
}

// MARK: - Interactive chart demo data

let smokeChartData: [(month: String, product: String, sales: Double)] = [
	("Jan", "Atlas", 12), ("Jan", "Boreas", 8),
	("Feb", "Atlas", 20), ("Feb", "Boreas", 15),
	("Mar", "Atlas", 16), ("Mar", "Boreas", 24),
]

func smokeChartHTML(state: SmokeState) -> String {
	var marks: [ChartMark] = []
	for d in smokeChartData {
		marks.append(BarMark(x: .value("Month", d.month), y: .value("Sales", d.sales))
			.foregroundStyle(by: d.product)
			.stacking(.unstacked)
			.makeMark())
	}
	return Chart(marks)
		.chartID("smoke-chart")
		.chartTitle("Quarterly sales by product")
		.chartAccessibilityLabel("Bar chart of quarterly sales by product")
		.chartYScale(.linear(domain: 0...28))
		.chartSelection(axis: .x, value: .category(state.chartSelected ?? ""))
		.onSelectMark { me, category in
			state.chartSelected = (state.chartSelected == category) ? nil : category
			return [me.replace(with: smokeChartHTML(state: state))]
		}
		.markup.html
}

// MARK: - Page shell

// Page-level layout for the smoke page only (injected via the document's
// `head:` slot, mirroring how the showcase scopes its own shell). The
// design system owns component styling; the page owns its gutter,
// header, and card rhythm. tokens come from the design system :root.
let smokePageStyle: String = """
	<style>
	.smoke { max-width: 56rem; margin: 0 auto; padding: var(--space-8) var(--space-6) var(--space-10); }
	.smoke__header { margin-bottom: var(--space-6); }
	.smoke__header h1 { font-size: var(--font-size-2xl); font-weight: 700; letter-spacing: -0.02em; line-height: 1.15; }
	.smoke__subtitle { margin-top: var(--space-2); color: var(--color-text-muted); font-size: var(--font-size-sm); }
	.smoke__content { display: grid; gap: var(--space-5); }
	.smoke__content > .card { padding: var(--space-5); }
	.smoke__content > .card > h3 { font-size: var(--font-size-sm); font-weight: 600; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: var(--space-4); }
	.smoke__actions { display: flex; gap: var(--space-2); margin-top: var(--space-4); }
	.smoke .counter-value { font-size: var(--font-size-3xl); font-weight: 700; font-variant-numeric: tabular-nums; line-height: 1.1; margin-bottom: var(--space-1); }
	.smoke .echo-out { margin-top: var(--space-3); font-size: var(--font-size-sm); color: var(--color-text-muted); min-height: 1.4em; }
	.smoke .echo-out__text { color: var(--color-text); font-family: var(--font-mono); }
	.smoke .table-wrap { margin-top: var(--space-2); }
	.smoke__chart { margin-top: var(--space-1); }
	.smoke__chart-hint { margin-top: var(--space-3); font-size: var(--font-size-xs); color: var(--color-text-faint); }
	@media (max-width: 720px) { .smoke { padding: var(--space-6) var(--space-4) var(--space-8); } }
	</style>
"""

// MARK: - Typed capability islands (W3.6)

/// the typed surface behind `island-typed`: declares the `validate`
/// capability (the existing artifact), so `WebUIDocument` grants it from the
/// declaration alone and the raw region above shares the same single fetch.
/// its `{"input":…}` mount envelope carries no validation rules, so the
/// mounted chip is the vacuous `valid` — the rule-bearing envelope stays with
/// the hand-rolled region. the server-rendered fallback below is byte-identical
/// to what the artifact composes for that envelope (same swift, both sides).
enum SmokeValidateIsland: Island {
	static let name = "validate"
	static func render(_ input: String) -> String {
		"<div class=\"island island--validate island--ok\" role=\"status\"><span class=\"island__dot\"></span><span class=\"island__msg\">valid</span></div>"
	}
}

/// the typed surface behind `island-greet`: a capability with no artifact, so
/// the engine attempts the lazy fetch once, fails cleanly, and the region
/// keeps its server-rendered fallback — the same swift a wasm build of this
/// island would have shipped.
enum SmokeGreetIsland: Island {
	static let name = "typed-greet"
	static func render(_ input: String) -> String {
		"<span class=\"island__msg\">hello, \(htmlEscape(input))</span>"
	}
}

/// the resizable capability: the same `WidthProbeIsland` logic its wasm
/// product ships, so the server fallback (width nil) and the mounted region
/// agree by construction.
enum SmokeWidthProbeIsland: ResizableIsland {
	static let name = "width-probe"
	static func render(_ input: String) -> String {
		WidthProbeIsland.render(input, width: nil)
	}
	static func render(_ input: String, width: Int?) -> String {
		WidthProbeIsland.render(input, width: width)
	}
}

/// arc b's typed capability: a `ChartSpec` crosses the wasm boundary as a
/// versioned binary frame — base64 inside the same `data-webui-args`
/// attribute — so the module decodes typed values instead of parsing json,
/// and re-renders at the measured container width like any resizable region.
enum SmokeChartProbeIsland: TypedResizableIsland {
	static let name = "chart-probe"
	static func render(_ input: ChartSpec) -> String {
		ChartSpecIsland.render(input, width: nil)
	}
	static func render(_ input: ChartSpec, width: Int?) -> String {
		ChartSpecIsland.render(input, width: width)
	}
}

// MARK: - Page assembly (renders interactive views, registers handlers)

func renderSmokePage(state: SmokeState, router: EventRouter, renderToken: String) -> String {
	// the session is named by the token: the server resolves an inbound frame's
	// token to `RenderSessionID(token)`, so the ids and handlers this pass mints
	// must land in exactly that session.
	let ctx = RenderContext(router: router, session: RenderSessionID(renderToken))
	let body = ctx.withValueBody {
		Div(class: "smoke") {
			Header(class: "smoke__header") {
				Heading("Design System — Full-Stack Smoke Test", level: .h1)
				Div(class: "smoke__subtitle") {
					Text("Live event routing: click / type → WebSocket → Swift EventRouter → fragment patch → DOM.")
				}
			}
			Main(class: "smoke__content") {
				// Counter card
				WebUICard(variant: .elevated) {
					Heading("Counter", level: .h3)
					Raw(counterValueHTML(state.count))
					Div(class: "smoke__actions") {
						WebUIButton("−", variant: .secondary, size: .md, id: "btn-dec")
							.onClick { _ in
								state.count -= 1
								return [FragmentUpdate(id: "counter-value", html: counterValueHTML(state.count))]
							}
						WebUIButton("+", variant: .primary, size: .md, id: "btn-inc")
							.onClick { _ in
								state.count += 1
								return [FragmentUpdate(id: "counter-value", html: counterValueHTML(state.count))]
							}
						WebUIButton("Reset", variant: .ghost, size: .sm, id: "btn-reset")
							.onOptimisticClick(
								predict: { [FragmentUpdate(id: "counter-value", html: counterValueHTML(0))] },
								perform: { _ in
									state.count = 0
									return [FragmentUpdate(id: "counter-value", html: counterValueHTML(0))]
								}
							)
					}
				}
				// Progress card
				WebUICard(variant: .outlined) {
					Heading("Progress", level: .h3)
					Raw(progressValueHTML(state.progress))
					Div(class: "smoke__actions") {
						WebUIButton("−10%", variant: .secondary, size: .sm, id: "btn-pdec")
							.onClick { _ in
								state.progress = max(0, state.progress - 0.1)
								return [FragmentUpdate(id: "progress-value", html: progressValueHTML(state.progress))]
							}
						WebUIButton("+10%", variant: .primary, size: .sm, id: "btn-pinc")
							.onClick { _ in
								state.progress = min(1, state.progress + 0.1)
								return [FragmentUpdate(id: "progress-value", html: progressValueHTML(state.progress))]
							}
					}
				}
				// Echo card
				WebUICard(variant: .flat) {
					Heading("Echo (input → server → DOM)", level: .h3)
					WebUIInput(placeholder: "Type something…", id: "echo-input", label: "Input", helpText: "Round-trips over the WebSocket.")
						.onInput { event in
							state.echo = event.value ?? ""
							return [FragmentUpdate(id: "echo-out", html: echoOutHTML(state.echo))]
						}
					Raw(echoOutHTML(state.echo))
				}
				// Interactive table card — sortable · selectable · expandable.
				// The persistent .table-wrap div carries the STABLE routing anchor
				// (data-component-id="interactive-table"); the inner element is
				// re-patched wholesale on every state change. One container handler
				// dispatches on event.data.targetId — the server is the source of
				// truth for sort, selection and expansion.
				WebUICard(variant: .outlined) {
					Heading("Table (sort · select · expand)", level: .h3)
					Div(class: "smoke__columns") {
						Raw(smokeColumnMenuHTML(state: state))
						Div(class: "smoke__chart-hint") {
							Text("Use the Columns menu to hide one - the server owns the state.")
						}
					}
					Div(id: "interactive-table-anchor", class: "table-wrap") {
						Raw(interactiveTableHTML(state: state))
					}
				}
				// Interactive chart card — WebUIChart bar chart; clicking a
				// bar routes through the runtime (SVG-safe parentNode walk)
				// to the container handler, which toggles the x-selection
				// and re-renders the figure (server is the source of truth).
				// The stable #smoke-chart-anchor div carries the routing
				// anchor (data-component-id="smoke-chart") and is NEVER
				// patched; the inner figure is re-patched in place by its own
				// id (the runtime replaces the element the fragment names).
				WebUICard(variant: .elevated) {
					Heading("Chart (bars · selection)", level: .h3)
					Div(id: "smoke-chart-anchor", class: "smoke__chart") {
						Raw(smokeChartHTML(state: state))
					}
					Div(class: "smoke__chart-hint") {
						Text("Click a bar to toggle its selection.")
					}
				}
				// p5 surface: the polar marks and the gradient fill, shown so the
				// preview reflects the whole chart library. static — no handlers,
				// so no data-component-id and the interactive-count pin is
				// unaffected by this card (the routed chart is the one above).
				WebUICard(variant: .elevated) {
					Heading("Charts (radar · radial · gradient)", level: .h3)
					Div(class: "grid grid--2") {
						Chart {
							RadarMark([("speed", 8), ("reliability", 6), ("cost", 4), ("support", 7), ("reach", 5)], series: "eu")
								.foregroundStyle(by: "eu")
							RadarMark([("speed", 5), ("reliability", 9), ("cost", 7), ("support", 3), ("reach", 8)], series: "us")
								.foregroundStyle(by: "us")
						}
						.chartTitle("Radar")
						.chartHeight(260)
						.chartAspectRatio(1)
						Chart {
							RadialMark(value: 72, of: 100, series: "cpu")
								.foregroundStyle(by: "cpu")
						}
						.chartTitle("Radial gauge")
						.chartHeight(260)
						.chartAspectRatio(1)
						.chartLegend(position: .hidden)
					}
					Chart {
						ForEach(Array([12.0, 18.0, 15.0, 24.0, 31.0, 27.0, 38.0].enumerated().map { (x: Double($0.offset + 1), y: $0.element) })) { p in
							Group {
								AreaMark(x: .value("Week", p.x), y: .value("Requests", p.y))
									.foregroundStyle(by: "requests")
									.areaGradient(.fade(.explicit("var(--color-chart-3)")))
								LineMark(x: .value("Week", p.x), y: .value("Requests", p.y))
									.foregroundStyle(by: "requests")
									.interpolation(.catmullRom)
							}
						}
					}
					.chartTitle("Area with a gradient fill")
					.chartHeight(240)
					.chartLegend(position: .hidden)
				}
				// p7 surface: the zero-js long tail. the entries carry no href, so
				// they render as plain rows — nothing interactive, nothing to wire.
				WebUICard(variant: .elevated) {
					Heading("Carousel · Menubar (no client script)", level: .h3)
					WebUIMenubar(items: [
						WebUIMenubar.Item("File", entries: [.init("New"), .init("Open"), .init("Export")]),
						WebUIMenubar.Item("View", entries: [.init("Zoom in"), .init("Zoom out"), .init("Reset")]),
						WebUIMenubar.Item("Help", entries: [.init("Shortcuts")]),
					], id: "smoke-menubar")
					WebUICarousel(id: "smoke-carousel", label: "Smoke slides", slides: [
						VStack(alignment: .leading, spacing: 8) {
							Heading("Scroll-snap", level: .h3)
							Paragraph("Focus the track and press the arrow keys — it scrolls natively, with no script.")
						}
						.padding(16),
						VStack(alignment: .leading, spacing: 8) {
							Heading("Dots are anchors", level: .h3)
							Paragraph("They jump to a slide; tracking the current one would need script, so it is not claimed.")
						}
						.padding(16),
						])
				}
				WebUICard(variant: .elevated) {
					Heading("Island validation (same Swift in wasm)", level: .h3)
					Div(class: "smoke__island-row") {
						Text("Type a value: ")
						Raw("<input id=\"island-input\" data-island-input=\"island-validate\" class=\"input\" type=\"text\" value=\"a\">")
					}
					Raw("<div id=\"island-validate\" data-webui-island=\"validate\" data-webui-args='{\"value\":\"a\",\"rules\":[{\"rule\":\"required\"},{\"rule\":\"minLength\",\"arg\":4}]}'></div>")
					Raw("<div id=\"island-never\" data-webui-island=\"never-built\" data-webui-args='{}'></div>")
				// W3.6 — the typed capability surface: these two regions are
				// declared, not hand-wired. `WebUIDocument` collects their
				// names out of the body and folds them into the emitted
				// config, so the engine grants + fetches + mounts with no
				// manual `capabilities` entry. `island-typed` shares the
				// existing `validate` artifact with the raw region above
				// (one fetch serves both — the smoke gate counts); its
				// `{"input":…}` mount envelope carries no validation rules,
				// so the mounted chip is the vacuous `valid`, while the
				// rule-bearing envelope stays with the raw region.
				Div(id: "island-typed") {
					IslandRegion<SmokeValidateIsland>("a")
				}
				// `typed-greet` has no artifact: the engine attempts the lazy
				// fetch once, fails, and the region keeps its server-rendered
				// fallback — the same swift a wasm build would have shipped.
				Div(id: "island-greet") {
					IslandRegion<SmokeGreetIsland>("world")
				}
				// the resizable region: `data-webui-island-resize` makes the
				// engine re-render it at the measured container width on
				// mount and on every resize. the wrapper carries the id the
				// patch-harness control below replaces.
				Div(id: "island-width") {
					ResizableIslandRegion<SmokeWidthProbeIsland>("width probe")
				}
				// the typed region: the args attribute carries a base64 rawdog
				// frame instead of json, which the engine passes through
				// untouched — the resize loop re-invokes it exactly like any
				// other resizable region. `data-chart-width` is the browser
				// gate's witness that the marker followed the measurement.
				Div(id: "island-chart") {
					TypedResizableIslandRegion<SmokeChartProbeIsland>(
						ChartSpec(title: "quarterly", values: [3, 7, 2, 9, 5])
					)
				}
				Div(class: "smoke__actions") {
					WebUIButton("Re-render island", variant: .secondary, size: .sm, id: "btn-island-rerender")
						.onClick { _ in
							let region = ResizableIslandRegion<SmokeWidthProbeIsland>("width probe").markup.html
							return [FragmentUpdate(id: "island-width", html: "<div id=\"island-width\">" + region + "</div>")]
						}
				}
					Div(class: "smoke__chart-hint") {
						Text("The chip above is composed by a lazily loaded wasm island (no round trip).")
					}
				}
				// File upload card — the post with a real action ships NATIVELY
				// (the browser's own multipart encoder, exact bytes, no JS),
				// even though the form is a wired component: the engine's
				// submit guard lets a real-action + method=post form with a
				// file input through (plan w3.3, G5). the fullstack gate
				// drives it with playwright setInputFiles and asserts the
				// server received exactly what it uploaded.
				WebUICard(variant: .outlined) {
					Heading("File upload (real POST)", level: .h3)
					Div(class: "smoke__chart-hint") {
						Text("A file input inside a wired component submits natively; the server echoes the exact bytes back.")
					}
					Form(action: "/upload", method: .post, enctype: "multipart/form-data") {
						Input(name: "file", type: .file, accept: "application/octet-stream")
						Div(class: "smoke__actions") {
							Input(type: .submit, value: "Upload")
						}
					}
					.onSubmit { _ in [] }
				}
			}
		}
	}
		return WebUIDocument(
			title: "Design System Full-Stack Smoke Test",
			body: .trusted(body),
			head: smokePageStyle,
			clientMode: ClientBoot(config: RuntimeConfig(
				// the socket is token-bound: the engine echoes this on every
				// frame, and the server routes it only into the render that
				// minted it.
				renderToken: renderToken,
				capabilities: ["validate", "never-built", "offline"]
			)),
			dir: smokeDir,
		).markup.html
	}

// small helper to run a builder under a RenderContext value
extension RenderContext {
	func withValueBody<V: View>(_ build: () -> V) -> String {
		RenderContext.$current.withValue(self) { build().markup.html }
	}
}
