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
	}
	private let values = Mutex(Values())

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
	</style>
	"""

/// one page with every behavior the register names. the order is the probe's
/// order, so a failure names the attribute and the section it lives in.
func renderBehaviourPage(
	state: BehaviourFixtureState,
	renderToken: String
) -> String {
	let now = UInt64(Date().timeIntervalSince1970 * 1000)
	let followOff = ScrollFollow(mode: .off).attributeText
	let table = TableEnhance(mode: .sortAndFilter).attributeText
	let body = """
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
	<div class="fx-row"><button id="patch" type="button" data-component-id="fx-patch" data-event="click">Grow feed</button><button id="to-target" type="button"\(ScrollTo(id: "scroll-target").attributeText)>Jump to the marker</button></div>
	\(behaviourFeedHTML(state))
	<div class="fx-row"><button id="to-feed" type="button"\(ScrollTo(id: "feed").attributeText)>Jump to the feed</button></div>
	<div id="follow-off"\(followOff) class="fx-thread" aria-label="not followed"><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p><p>off</p></div>
	<input id="draft" type="text" aria-label="draft" placeholder="draft"\(DraftIdentity(key: "note").attributeText)>
	</section>

	<section class="fx-sec"><h2>dismiss stack</h2>
	<div class="fx-row"><button id="open-a" type="button" data-component-id="fx-open-a" data-event="click">Open layer A</button><div id="outside" class="fx-muted">click here to close the top layer</div></div>
	<div id="layers" class="fx-layers"></div>
	</section>

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
		let html = renderBehaviourPage(state: state, renderToken: request.renderToken.value)
		return HTTPResponse(headers: smokeHeaders(), body: .html(UnsafeMarkup.trusted(html)))
	}
}
