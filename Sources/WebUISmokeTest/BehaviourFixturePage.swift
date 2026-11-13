import Foundation
import Synchronization
import WebUI
import WebUIDesignSystem
import WebUIServer
import WebUISharedCore

// the behavior fixture page: one page that renders every attribute in
// `Documentation/BEHAVIOUR.md`'s register, plus the server handlers the
// client consequences need (a feed that grows, a form that answers with a
// fragment, and a two-layer dismiss stack). `designer/behaviour-probe.mjs`
// drives it in a real browser; the page never contains hand-written `data-*`
// literals — each attribute is spliced from the typed value that owns it
// (`Behavior.attributeText`), which is the same door §22.8 allows a string
// renderer to use.

// MARK: - state

/// the fixture's server-side state: how many times the feed has grown, and the
/// two echoes the form handlers answer with.
final class BehaviourFixtureState: Sendable {
	private struct Values {
		var feed = 0
		var saved = "(none)"
		var last = "(none)"
		var refreshes = 0
		var dialogOpen = false
		var dialog2Open = false
		var t26 = 0
		var uploads: [String: String] = [:]
		var templated: [String] = []
		var streamLines: [String] = []
	}
	private let values = Mutex(Values())

	/// one clock reading for the life of the fixture, NOT one per render.
	///
	/// the ticking labels are painted client-side from `data-reltime`, so the
	/// server's stamp only has to be stable: a per-render `now` would move six
	/// spans on every render, and a re-render (the refresh contract's whole
	/// point) would then change bytes outside every region — the residue — and
	/// escalate to a full page instead of a region patch.
	let stamp: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)

	/// what the upload route received for one drop zone, as the line the
	/// region renders: the destination header, the filename header and the
	/// counted byte total are the proof the transport travelled.
	func recordUpload(zone: String, path: String, name: String, bytes: String) {
		values.withLock { $0.uploads[zone] = "path=\(path) name=\(name) bytes=\(bytes)" }
	}

	func upload(zone: String) -> String {
		values.withLock { $0.uploads[zone] ?? "(none)" }
	}

	/// appends one templated-zone result, so the region can render both
	/// sequential uploads and the probe can read two composed paths from one
	/// zone without a second page load.
	func recordTemplatedUpload(path: String, name: String, bytes: String) {
		values.withLock { $0.templated.append("path=\(path) name=\(name) bytes=\(bytes)") }
	}

	func templatedUpload(_ index: Int) -> String {
		values.withLock { index < $0.templated.count ? $0.templated[index] : "(none)" }
	}

	var feed: Int {
		get { values.withLock { $0.feed } }
		set { values.withLock { $0.feed = newValue } }
	}
	var saved: String {
		get { values.withLock { $0.saved } }
		set { values.withLock { $0.saved = newValue } }
	}
	var last: String {
		get { values.withLock { $0.last } }
		set { values.withLock { $0.last = newValue } }
	}
	var refreshes: Int {
		get { values.withLock { $0.refreshes } }
		set { values.withLock { $0.refreshes = newValue } }
	}
	var dialogOpen: Bool {
		get { values.withLock { $0.dialogOpen } }
		set { values.withLock { $0.dialogOpen = newValue } }
	}

	var dialog2Open: Bool {
		get { values.withLock { $0.dialog2Open } }
		set { values.withLock { $0.dialog2Open = newValue } }
	}
	var t26: Int {
		get { values.withLock { $0.t26 } }
		set { values.withLock { $0.t26 = newValue } }
	}

	/// the streamed-delta fixture: `#stream` appends one line and the handler
	/// answers with a **single `text` fragment** carrying the accumulated text
	/// — the patch kind the follow pass has to survive without a replacement.
	func appendStreamLine() -> String {
		values.withLock {
			$0.streamLines.append("stream line \($0.streamLines.count + 1) (delta)")
			return $0.streamLines.joined(separator: "\n")
		}
	}

	var streamText: String {
		values.withLock { $0.streamLines.joined(separator: "\n") }
	}
}

// MARK: - fragments

/// the feed: a scroll container that follows new content, a keyed inner
/// scroller whose id changes every render, a `<details>` whose open state is
/// user state, and a focus-return region. the whole element is replaced by the
/// `#patch` control, so every consequence above has to survive a replace.
func behaviourFeedHTML(_ state: BehaviourFixtureState) -> String {
	let n = state.feed
	var rows = ""
	for i in 0..<(6 + n * 4) {
		rows += "<li class=\"fx-item\">feed row \(i + 1) (render \(n))</li>"
	}
	var threadLines = ""
	for i in 0..<30 {
		threadLines += "<p>thread line \(i + 1)</p>"
	}
	return """
	<div id="feed"\(ScrollFollow().attributeText) class="fx-feed" aria-label="feed">
	<details id="feed-more"\(Disclosure().attributeText) class="fx-details"><summary>More about this feed</summary><p class="fx-muted">the open state is the reader's.</p></details>
	<div id="thread-\(n)"\(ScrollKey(key: "thread").attributeText) class="fx-thread" aria-label="thread">\(threadLines)</div>
	<div id="focus-region"\(FocusReturn(id: "panel-search").attributeText) class="fx-focus"><a id="feed-link" href="#feed-more">a link inside the replaced region</a><input id="panel-search" type="search" aria-label="search the feed" placeholder="search"></div>
	<ul class="fx-items">\(rows)</ul>
	<pre id="feed-tail" class="fx-tail">\(htmlEscape(state.streamText))</pre>
	</div>
	"""
}

/// layer a: the first dismiss layer, carrying its own close affordance. the
/// fragment keeps the `#layers` container, so a later layer can be appended
/// in front of it.
func behaviourLayerAHTML() -> String {
	"""
	<div id="layers" class="fx-layers"><div id="layer-a"\(DismissStack(layer: "a").attributeText) class="fx-layer"><p>Layer A — the first layer.</p><button id="open-b" type="button" data-component-id="fx-open-b" data-event="click">Open layer B</button><button id="close-a" type="button"\(DismissStack(layer: "a").attributeText) data-component-id="fx-close-a" data-event="click">Close A</button></div></div>
	"""
}

/// layer b: opened later, rendered first — so a document-order stack and a
/// LIFO stack disagree, and the probe can tell which one the engine built.
func behaviourLayerBHTML() -> String {
	"""
	<div id="layer-b"\(DismissStack(layer: "b").attributeText) class="fx-layer"><p>Layer B — opened later, first in the document.</p><button id="close-b" type="button"\(DismissStack(layer: "b").attributeText) data-component-id="fx-close-b" data-event="click">Close B</button></div>
	"""
}

/// the round-trip dialog: `#fx-dialog-open` is a button that names the dialog
/// it opens, and `#fx-dialog-close` names the opener focus must return to.
/// both handlers answer with a patch of `#fx-dialog-region`, so the dialog is
/// removed by a server round trip — never by Escape — which is the path the
/// opener memo and the removal pass exist for.
func behaviourDialogRegionHTML(_ state: BehaviourFixtureState) -> String {
	let dialog: String = state.dialogOpen ? """
	<div id="fx-dialog" class="fx-layer" role="dialog" aria-label="round trip dialog"><p class="fx-muted">opened by <code>#fx-dialog-open</code>; closed by a server patch.</p><input id="fx-dialog-field" type="text" aria-label="dialog field" value="focus me"><button id="fx-dialog-close" type="button"\(FocusReturn(id: "fx-dialog-open").attributeText) data-component-id="fx-dialog-close" data-event="click">Close the dialog</button></div>
	""" : ""
	return """
	<section id="fx-dialog-region" class="fx-sec"><h2>focus return by round trip</h2>
	<p class="fx-muted">the close is a server round trip: the patch removes the dialog, and focus returns to the opener by id.</p>
	<div class="fx-row"><button id="fx-dialog-open" type="button"\(FocusReturn(id: "fx-dialog").attributeText) data-component-id="fx-dialog-open" data-event="click">Open the dialog</button><p id="fx-dialog-state" class="fx-muted">dialog: \(state.dialogOpen ? "open" : "closed")</p></div>
	\(dialog)</section>
	"""
}

/// the empty-fragment close: the patch targets `#fx-dialog2` itself with empty
/// html, so `applyFragments` sees no changed node — the removal pass has to run
/// anyway, which is the branch its removed-element flag exists for.
func behaviourDialog2RegionHTML(_ state: BehaviourFixtureState) -> String {
	let dialog: String = state.dialog2Open ? """
	<div id="fx-dialog2" class="fx-layer" role="dialog" aria-label="empty fragment dialog"><p class="fx-muted">closed by an empty fragment, not a region re-render.</p><input id="fx-dialog2-field" type="text" aria-label="dialog2 field" value="focus me"><button id="fx-dialog2-close" type="button"\(FocusReturn(id: "fx-dialog2-open").attributeText) data-component-id="fx-dialog2-close" data-event="click">Close by empty fragment</button></div>
	""" : ""
	return """
	<section id="fx-dialog2-host" class="fx-sec"><h2>focus return by empty-fragment close</h2>
	<div class="fx-row"><button id="fx-dialog2-open" type="button"\(FocusReturn(id: "fx-dialog2").attributeText) data-component-id="fx-dialog2-open" data-event="click">Open the empty-fragment dialog</button></div>
	\(dialog)</section>
	"""
}

/// T26: a focused button whose own click returns a fragment replacing the
/// region it lives in. the button is not an input, so it records `focus:<id>`
/// and the replacement's new `#fx-t26` gets the focus back by id.
func behaviourT26HTML(_ state: BehaviourFixtureState) -> String {
	"""
	<div id="t26-region" class="fx-sec"><h2>a focused button, replaced</h2>
	<p class="fx-muted">the button returns a fragment that replaces this whole region; focus has to come back to <code>#fx-t26</code>.</p>
	<div class="fx-row"><button id="fx-t26" type="button" data-component-id="fx-t26" data-event="click">Replace me (render \(state.t26))</button><p id="t26-out" class="fx-muted">t26: \(state.t26)</p></div></div>
	"""
}

// MARK: - page

/// the fixture's own layout: enough height to scroll, a real overflow on each
/// scroller, and nothing that depends on the framework sheet's cascade.
let behaviourFixtureStyle: String = """
	<style>
	body { margin: 0; font-family: system-ui, sans-serif; }
	.fx { max-width: 60rem; margin: 0 auto; padding: 16px; }
	.fx h1 { font-size: 1.4rem; margin: 0 0 8px; }
	.fx h2 { font-size: 1rem; margin: 0 0 6px; }
	.fx-muted { color: #666; font-size: 0.85rem; }
	.fx-sec { min-height: 320px; border-top: 1px solid #ddd; padding: 12px 0; }
	.fx-feed { height: 160px; overflow-y: auto; border: 1px solid #ccc; padding: 6px; }
	.fx-thread { height: 70px; overflow-y: auto; border: 1px dashed #bbb; }
	.fx-thread p { margin: 0; }
	.fx-focus { margin-top: 6px; }
	.fx-items { margin: 6px 0 0; padding-left: 18px; }
	.fx-item { padding: 2px 0; }
	.fx-layer { border: 1px solid #444; background: #f7f7f7; padding: 10px; margin: 8px 0; }
	.fx-list { list-style: none; margin: 0; padding: 0; }
	.fx-list li { border: 1px solid #ccc; padding: 4px 8px; margin: 2px 0; }
	.fx-row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin: 6px 0; }
	.fx-table { border-collapse: collapse; margin-top: 6px; }
	.fx-table th, .fx-table td { border: 1px solid #ccc; padding: 4px 10px; text-align: left; }
	.fx-nav a { margin-right: 10px; }
	.fx-nav a[aria-current="true"] { font-weight: 700; text-decoration: none; }
	.fx-inline { border: 1px solid #ccc; padding: 6px; }
	.fx-inline[data-editing] { border-color: #06c; }
	.fx-roving button { margin-right: 4px; }
	.fx-tail { margin: 6px 0 0; }
	.fx-reader { height: 120px; overflow-y: auto; border: 1px solid #ccc; padding: 6px; }
	.fx-upload-zone { width: 22rem; max-width: 100%; }
	</style>
	"""

/// one page with every behavior the register names. the order is the probe's
/// order, so a failure names the attribute and the section it lives in.
func renderBehaviourPage(
	state: BehaviourFixtureState,
	renderToken: String,
	bareReader: Bool = false,
	drawer: Bool = false
) -> String {
	let now = state.stamp
	let followOff = ScrollFollow(mode: .off).attributeText
	let table = TableEnhance(mode: .sortAndFilter).attributeText
	// the refresh control is a `.control`, and it is the ONE owner of its
	// handler: this page is rendered inside the server's render pass, so the
	// modifier registers here and emits the routing pair. the handler moves the
	// only state the region renders, then answers `.refresh` — the server
	// re-renders this page in the same session, diffs it against that session's
	// baseline and ships the section whose bytes moved.
	let refreshButton = Button("Refresh this page", id: "refresh", type: .button)
		.control(id: "fx-refresh") { _ in
			state.refreshes += 1
			return .refresh
		}
		.markup.html
	// the upload fixture: three typed destinations against one contract route,
	// so the probe can prove the destination travelled (the server echoes the
	// composed path it received) and that one engine transport serves every
	// zone. the third zone carries a name template and is uploaded to twice,
	// so the region can show two composed paths from the same zone.
	let zoneA = WebUIDropZone(
		"Drop a file here", hint: "attachments", destination: .attachments,
		route: "/upload/contract", id: "fx-upload-a"
	).markup.html
	let zoneB = WebUIDropZone(
		"Drop a file here", hint: "docs", destination: .folder(path: "docs"),
		route: "/upload/contract", id: "fx-upload-b"
	).markup.html
	let zoneC = WebUIDropZone(
		"Drop a file here", hint: "docs, templated {name}-{seq}-{ts}.{ext}",
		destination: .folder(path: "docs"),
		route: "/upload/contract", id: "fx-upload-c",
		nameTemplate: UploadNameTemplate(template: "{name}-{seq}-{ts}.{ext}")
	).markup.html
	var refreshLines = ""
	for i in 0..<30 {
		refreshLines += "<p>refresh line \(i + 1)</p>"
	}
	var readerLines = ""
	for i in 0..<24 {
		readerLines += "<p>reader line \(i + 1)</p>"
	}
	let drawerSection = drawer ? """
	<section class="fx-sec" id="fx-drawer-host"><h2>drawer open state</h2>
	<p class="fx-muted">below 860px the drawer is an off-canvas layer: the host button opens it, and the scrim, <code>Escape</code> or its own close control shuts it, with focus moving into the panel and back to the toggle. above 860px it is the static rail and the toggle changes nothing.</p>
	<div class="fx-row"><button id="fx-drawer-open" type="button" data-drawer-toggle="fx-drawer">Open the drawer</button></div>
	\(WebUIDrawer(title: "fx drawer", id: "fx-drawer") { Text("drawer body") }.markup.html)
	</section>
	""" : ""
	let body = bareReader ? """
	<main class="fx">
	<h1>Reading keys, bare</h1>
	<p class="fx-muted">the same reader on a page that renders no layer at all: with no layer open, Escape returns it to the live tail.</p>
	<div id="reader" class="fx-reader" tabindex="0" aria-label="reader"\(ReadingKeys().attributeText)>\(readerLines)</div>
	</main>
	""" : """
	<main class="fx">
	<h1>Behavior fixture</h1>
	<p class="fx-muted">Every attribute in the register, on one page, driven by <code>designer/behaviour-probe.mjs</code>.</p>

	<nav id="spy-nav" class="fx-nav" aria-label="Sections"><a id="spy-link-a" href="#sec-a">Section A</a><a id="spy-link-b" href="#sec-b">Section B</a><a id="spy-link-c" href="#sec-c">Section C</a></nav>

	<div id="spy"\(Scrollspy().attributeText) class="fx-spy">
	<section id="sec-a" class="fx-sec"><h2>Section A</h2><p class="fx-muted">scrollspy marks this link while A is in view</p></section>
	<section id="sec-b" class="fx-sec"><h2>Section B</h2><p class="fx-muted">scrollspy marks this link while B is in view</p></section>
	<section id="sec-c" class="fx-sec"><h2>Section C</h2><p class="fx-muted">scrollspy marks this link while C is in view</p></section>
	</div>

	<section class="fx-sec"><h2>scroll follow · scroll key · disclosure · focus return</h2>
	<div class="fx-row"><button id="patch" type="button" data-component-id="fx-patch" data-event="click">Grow feed</button><button id="stream" type="button" data-component-id="fx-stream" data-event="click">Stream a line</button><button id="to-target" type="button"\(ScrollTo(id: "scroll-target").attributeText)>Jump to the marker</button><button id="to-top" type="button"\(ScrollTo(id: "").attributeText)>Back to the document top</button></div>
	\(behaviourFeedHTML(state))
	<div class="fx-row"><button id="to-feed" type="button"\(ScrollTo(id: "feed").attributeText)>Jump to the feed</button></div>
	<div id="follow-off"\(followOff) class="fx-thread" aria-label="not followed"><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p></div>
	<input id="draft" type="text" aria-label="draft" placeholder="draft"\(DraftIdentity(key: "note").attributeText)>
	</section>

	<section class="fx-sec"><h2>reading keys</h2>
	<p class="fx-muted">focus the reader, then use ArrowUp/PageUp/Home/End; Escape returns to the live tail unless a layer is open.</p>
	<div id="reader" class="fx-reader" tabindex="0" aria-label="reader"\(ReadingKeys().attributeText)>\(readerLines)</div>
	</section>

	<section class="fx-sec" id="fx-refresh-region" data-component-id="fx-refresh-region"><h2>refresh contract</h2>
	<p class="fx-muted">the button below is a <code>.control</code> whose handler returns <code>.refresh</code>: the server re-renders this page and patches only this region, then the engine's afterPatch funnel restores focus, scroll and draft inside it.</p>
	<div class="fx-row">\(refreshButton)</div>
	<div id="refresh-focus"\(FocusReturn(id: "refresh-search").attributeText) class="fx-focus"><a id="refresh-link" href="#fx-refresh-region">a link inside the refreshed region</a><input id="refresh-search" type="search" aria-label="search the refreshed region" placeholder="search"></div>
	<div id="refresh-thread"\(ScrollKey(key: "refresh-thread").attributeText) class="fx-thread" aria-label="refresh thread">\(refreshLines)</div>
	<form id="refresh-draft-form" class="fx-row" data-component-id="fx-refresh-draft" data-event="submit"><input id="refresh-draft" type="text" aria-label="refresh draft" placeholder="draft"\(DraftIdentity(key: "refresh-draft").attributeText)></form>
	<p id="refresh-count" class="fx-muted">refreshes: \(state.refreshes)</p>
	</section>

	<section class="fx-sec"><h2>dismiss stack</h2>
	<div class="fx-row"><button id="open-a" type="button" data-component-id="fx-open-a" data-event="click">Open layer A</button><div id="outside" class="fx-muted">click here to close the top layer</div></div>
	<div id="layers" class="fx-layers"></div>
	</section>

	\(behaviourDialogRegionHTML(state))

	\(behaviourDialog2RegionHTML(state))

	\(behaviourT26HTML(state))

	<section class="fx-sec"><h2>reorder</h2>
	<ul id="reorder" class="fx-list"\(Reorder(inputID: "order-input").attributeText)><li id="item-a">item a</li><li id="item-b">item b</li><li id="item-c">item c</li></ul>
	<input id="order-input" type="hidden" name="order" value="">
	<p id="order-out" class="fx-muted">order: (none)</p>
	</section>

	<section class="fx-sec"><h2>clipboard</h2>
	<div class="fx-row"><button id="copy-text" type="button"\(Clipboard(text: "pinned text").attributeText)>Copy the pinned text</button><button id="copy-empty" type="button"\(Clipboard().attributeText)>Copy me</button></div>
	</section>

	<section class="fx-sec"><h2>table enhance</h2>
	<div id="table-region" class="fx-table-region"\(table)>
	<input id="table-filter" type="search" aria-label="filter rows" placeholder="filter" data-table-filter>
	<table id="fx-table" class="fx-table"><thead><tr><th id="th-name" scope="col">Name</th><th id="th-size" scope="col">Size</th></tr></thead>
	<tbody><tr id="row-b"><td>beta</td><td>20</td></tr><tr id="row-a"><td>alpha</td><td>3</td></tr><tr id="row-c"><td>gamma</td><td>100</td></tr></tbody></table>
	</div>
	</section>

	<section class="fx-sec"><h2>skip target</h2>
	<div class="fx-row"><a id="skip" href="#skip-target"\(SkipTarget(id: "skip-target").attributeText)>Skip to the content</a></div>
	<div id="skip-target" class="fx-muted">the skip target: focus lands here, and the engine adds tabindex when it is absent.</div>
	</section>

	<section class="fx-sec"><h2>ticking labels</h2>
	<p><span id="rel-1"\(TickingLabel(epochMilliseconds: now - 30_000).attributeText)>-</span>
	<span id="rel-2"\(TickingLabel(epochMilliseconds: now - 300_000).attributeText)>-</span>
	<span id="rel-3"\(TickingLabel(epochMilliseconds: now - 10_800_000).attributeText)>-</span>
	<span id="rel-4"\(TickingLabel(epochMilliseconds: now - 172_800_000).attributeText)>-</span>
	<span id="rel-5"\(TickingLabel(epochMilliseconds: 1_577_880_000_000).attributeText)>-</span></p>
	<p><span id="elapsed"\(ElapsedClock(startedMilliseconds: now - 125_000).attributeText)>-</span></p>
	</section>

	<section class="fx-sec"><h2>inline edit</h2>
	<form id="inline-form" class="fx-inline" data-component-id="fx-inline" data-event="submit" data-prevent-enter="false">
	<div id="inline"\(InlineEdit().attributeText)><span id="inline-label" class="fx-muted">title: </span><input id="inline-input" name="title" type="text" value="untitled"><button id="inline-save" type="submit">Save</button></div>
	<p id="inline-saved" class="fx-muted">saved: \(htmlEscape(state.saved))</p>
	</form>
	</section>

	<section class="fx-sec"><h2>roving</h2>
	<div id="roving"\(Roving().attributeText) class="fx-roving" role="toolbar" aria-label="Letters"><button id="rov-1" type="button">1</button><button id="rov-2" type="button">2</button><button id="rov-3" type="button">3</button></div>
	</section>

	<section class="fx-sec" id="fx-filter"><h2>filter list</h2>
	<p class="fx-muted">the combo below is the real component: its region carries the marker, its panel carries the dismiss layer and the roving group.</p>
	\(WebUIComboBox(placeholder: "filter the options", options: [.init("alpha"), .init("beta"), .init("gamma")], emptyMessage: "nothing matches").markup.html)
	</section>

	<section class="fx-sec" id="fx-filter-source"><h2>filter list · external source · write-back</h2>
	<p class="fx-muted">the query lives in the composer, outside the list. typing filters the items; a click, or <code>Enter</code> on a focused item, writes the item back at the composer's caret and strips the typed token first.</p>
	<textarea id="fx-composer" rows="2" aria-label="composer"></textarea>
	<div id="fx-palette"\(FilterList(source: "#fx-composer").attributeText)\(FilterInsert(target: "fx-composer").attributeText)\(FilterTemplate(text: "{value} ").attributeText)\(FilterClear().attributeText) role="menu" aria-label="palette">
	<div id="fx-item-hello" class="fx-item" role="menuitem" tabindex="-1">hello</div>
	<div id="fx-item-help" class="fx-item" role="menuitem" tabindex="-1">help</div>
	<div id="fx-item-world" class="fx-item" role="menuitem" tabindex="-1">world</div>
	</div>
	</section>

	\(drawerSection)

	<section class="fx-sec"><h2>form semantics</h2>
	<form id="submit-form" class="fx-form" data-component-id="fx-submit" data-event="submit">
	<p><input id="submit-input" name="q" type="text" aria-label="query" placeholder="type and press enter"\(SubmitOnEnter().attributeText)\(ClearOnSubmit().attributeText)></p>
	<p><textarea id="submit-area" name="body" rows="2" aria-label="body"\(SubmitOnEnter().attributeText)></textarea></p>
	<p><input id="submit-exempt" name="x" type="text" aria-label="exempt" placeholder="enter stays here"\(SubmitOnEnter().attributeText) data-prevent-enter="false"></p>
	<p id="submit-out" class="fx-muted">last: \(htmlEscape(state.last))</p>
	</form>
	<textarea id="grow" rows="1" aria-label="grow"\(Autogrow().attributeText)></textarea>
	<p><input id="clamp" type="number" value="5" aria-label="clamp"\(NumberClamp(min: 1, max: 10).attributeText)></p>
	</section>

	<section class="fx-sec" id="fx-upload" data-component-id="fx-upload"><h2>upload contract</h2>
	<p class="fx-muted">each zone posts to <code>/upload/contract</code> through the engine's XHR transport; the engine composes <code>&lt;destination&gt;/&lt;name&gt;</code> into <code>X-Upload-Path</code>, and the route echoes the path it received. the handler answers <code>.refresh</code>.</p>
	<div class="fx-upload-zone">\(zoneA)</div>
	<div class="fx-upload-zone">\(zoneB)</div>
	<div class="fx-upload-zone">\(zoneC)</div>
	<p id="upload-out-a" class="fx-muted">attachments: \(htmlEscape(state.upload(zone: "a")))</p>
	<p id="upload-out-b" class="fx-muted">docs: \(htmlEscape(state.upload(zone: "b")))</p>
	<p id="upload-out-c1" class="fx-muted">templated 1: \(htmlEscape(state.templatedUpload(0)))</p>
	<p id="upload-out-c2" class="fx-muted">templated 2: \(htmlEscape(state.templatedUpload(1)))</p>
	</section>

	<section class="fx-sec"><h2>theme choice</h2>
	<div class="fx-row"><button id="theme-dark" type="button"\(ThemeChoice(mode: .dark).attributeText)>Dark</button><button id="theme-light" type="button"\(ThemeChoice(mode: .light).attributeText)>Light</button></div>
	</section>

	<div id="scroll-target" class="fx-sec"><h2>The scroll marker</h2><p class="fx-muted">data-scroll-to lands here.</p></div>

	<section class="fx-sec"><h2>island inertness</h2>
	<p class="fx-muted">the region below is island-mounted; a behavior inside it must stay inert.</p>
	<div id="fx-island" data-webui-island="behaviour-island" data-webui-args='{}'>
	<div id="island-follow"\(ScrollFollow().attributeText) class="fx-thread" aria-label="island scroller"><p>island 1</p><p>island 2</p><p>island 3</p><p>island 4</p><p>island 5</p><p>island 6</p><p>island 7</p><p>island 8</p><p>island 9</p><p>island 10</p><p>island 11</p><p>island 12</p></div>
	</div>
	</section>
	</main>
	"""
	return WebUIDocument(
		title: "Behavior fixture",
		body: .trusted(body),
		head: behaviourFixtureStyle,
		clientMode: ClientBoot(config: RuntimeConfig(
			renderToken: renderToken,
			capabilities: ["behaviour-island"]
		))
	).markup.html
}

// MARK: - responder

/// `/behaviour`: renders the fixture and registers the handlers its controls
/// name. every handler answers with a fragment, so the client consequences
/// that need a round trip (a dismiss close, a save, a submit) are driven by the
/// same wire path a real page uses — nothing is faked client-side.
struct BehaviourPageResponder: Responder {
	let state: BehaviourFixtureState
	let router: EventRouter

	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		let session = RenderSessionID(request.renderToken.value)
		router.begin(session)
		let state = self.state
		router.register(outcome: { _ in
			state.feed += 1
			return .fragments([FragmentUpdate(id: "feed", html: behaviourFeedHTML(state))])
		}, for: ComponentID("fx-patch"), in: session)
		// the streamed-delta fixture: one text op per click, never a replace —
		// the patch kind `capture()`'s follow loop has to see.
		router.register(outcome: { _ in
			.fragments([FragmentUpdate.text(id: "feed-tail", value: state.appendStreamLine())])
		}, for: ComponentID("fx-stream"), in: session)
		router.register(outcome: { _ in
			.fragments([FragmentUpdate(id: "layers", html: behaviourLayerAHTML())])
		}, for: ComponentID("fx-open-a"), in: session)
		router.register(outcome: { _ in
			.fragments([FragmentUpdate.append(id: "layers", html: behaviourLayerBHTML(), before: "layer-a")])
		}, for: ComponentID("fx-open-b"), in: session)
		router.register(outcome: { _ in
			.fragments([FragmentUpdate(id: "layer-a", html: "")])
		}, for: ComponentID("fx-close-a"), in: session)
		router.register(outcome: { _ in
			.fragments([FragmentUpdate(id: "layer-b", html: "")])
		}, for: ComponentID("fx-close-b"), in: session)
		// the round-trip dialog: open and close are both patches of the region
		// holding it, so the removal path — not Escape — returns focus to the
		// opener the close control names.
		router.register(outcome: { _ in
			state.dialogOpen = true
			return .fragments([FragmentUpdate(id: "fx-dialog-region", html: behaviourDialogRegionHTML(state))])
		}, for: ComponentID("fx-dialog-open"), in: session)
		router.register(outcome: { _ in
			state.dialogOpen = false
			return .fragments([FragmentUpdate(id: "fx-dialog-region", html: behaviourDialogRegionHTML(state))])
		}, for: ComponentID("fx-dialog-close"), in: session)
		// the empty-fragment dialog: open re-renders its host, close removes the
		// dialog element itself — a patch with no changed node.
		router.register(outcome: { _ in
			state.dialog2Open = true
			return .fragments([FragmentUpdate(id: "fx-dialog2-host", html: behaviourDialog2RegionHTML(state))])
		}, for: ComponentID("fx-dialog2-open"), in: session)
		router.register(outcome: { _ in
			state.dialog2Open = false
			return .fragments([FragmentUpdate(id: "fx-dialog2", html: "")])
		}, for: ComponentID("fx-dialog2-close"), in: session)
		// T26: the clicked button's own answer replaces the region holding it.
		router.register(outcome: { _ in
			state.t26 += 1
			return .fragments([FragmentUpdate(id: "t26-region", html: behaviourT26HTML(state))])
		}, for: ComponentID("fx-t26"), in: session)
		router.register(outcome: { event in
			state.saved = event.string("title") ?? "(none)"
			return .fragments([
				FragmentUpdate(id: "inline-saved", html: "<p id=\"inline-saved\" class=\"fx-muted\">saved: \(htmlEscape(state.saved))</p>"),
			])
		}, for: ComponentID("fx-inline"), in: session)
		router.register(outcome: { event in
			state.last = event.string("q") ?? "(none)"
			return .fragments([
				FragmentUpdate(id: "submit-out", html: "<p id=\"submit-out\" class=\"fx-muted\">last: \(htmlEscape(state.last))</p>"),
			])
		}, for: ComponentID("fx-submit"), in: session)
		// one handler per destination: the engine's `upload-complete` event
		// carries the route's echo, the region renders it, and `.refresh` ships
		// the patch — no consumer JavaScript in the loop.
		router.register(outcome: { event in
			state.recordUpload(
				zone: "a",
				path: event.string("path") ?? "",
				name: event.string("name") ?? "",
				bytes: event.string("bytes") ?? ""
			)
			return .refresh
		}, for: ComponentID("fx-upload-a"), in: session)
		router.register(outcome: { event in
			state.recordUpload(
				zone: "b",
				path: event.string("path") ?? "",
				name: event.string("name") ?? "",
				bytes: event.string("bytes") ?? ""
			)
			return .refresh
		}, for: ComponentID("fx-upload-b"), in: session)
		// the templated zone: two uploads, two composed paths. the region keeps
		// both lines so the probe can read them without a reload, and the
		// handler answers `.refresh` exactly like the untemplated zones — the
		// template is a transport detail, not a second contract.
		router.register(outcome: { event in
			state.recordTemplatedUpload(
				path: event.string("path") ?? "",
				name: event.string("name") ?? "",
				bytes: event.string("bytes") ?? ""
			)
			return .refresh
		}, for: ComponentID("fx-upload-c"), in: session)
		let html = renderBehaviourPage(
			state: state,
			renderToken: request.renderToken.value,
			bareReader: request.query["bare"] == "reader",
			drawer: request.query["drawer"] == "1"
		)
		return HTTPResponse(headers: smokeHeaders(), body: .html(UnsafeMarkup.trusted(html)))
	}
}
