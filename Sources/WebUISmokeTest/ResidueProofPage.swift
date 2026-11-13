import Foundation
import Synchronization
import WebUI
import WebUIDesignSystem
import WebUIServer
import WebUISharedCore

// the residue proof page: every §20 row expressed with zero consumer
// JavaScript — server fragments, typed behavior attributes, native HTML
// semantics (`<details>`), and typed render-time handlers. the proof is the
// page itself plus `designer/behaviour-probe.mjs`'s residue group, which
// asserts the served page carries no consumer script and that each row's
// interaction works in a real browser.
//
// the rows (and the expression each one proves):
//   transcript          server-rendered fragments
//   outline             server-rendered anchors + `data-scroll-to` (flash)
//   conversation rename `data-inline-edit` + native form submit + `.refresh`
//   kanban card rename  same shape, a second region
//   session menus       two `data-dismiss` layers, LIFO Escape ordering
//   context chip        `<details data-preserve-open>` (WebUIDisclosure)
//   session group       `<details data-preserve-open>`
//   skill category      `<details data-preserve-open>`
//   chat-row menus      `data-dismiss` layer + disclosure
//   copy halves         `data-copy` (clipboard + engine toast)

// MARK: - state

/// the residue page's server-side state: the two renamed values.
final class ResidueState: Sendable {
	private struct Values {
		var name = "quarterly plan"
		var card = "ship the slice"
	}
	private let values = Mutex(Values())

	var name: String {
		get { values.withLock { $0.name } }
		set { values.withLock { $0.name = newValue } }
	}
	var card: String {
		get { values.withLock { $0.card } }
		set { values.withLock { $0.card = newValue } }
	}
}

// MARK: - fragments

/// the first dismiss layer: a server-rendered menu with its own close control.
func residueMenuAHTML() -> String {
	"""
	<div id="res-layers" class="res-layers"><div id="res-menu-a"\(DismissStack(layer: "a").attributeText) class="res-menu"><p>session menu — pinned, rename, delete</p><button id="res-open-b" type="button" data-component-id="res-open-b" data-event="click">Open workspace menu</button><button id="res-menu-a-close" type="button"\(DismissStack(layer: "a").attributeText) data-component-id="res-menu-a-close" data-event="click">Close menu</button></div></div>
	"""
}

/// the second layer: opened later, rendered first, so document order and LIFO
/// disagree and the probe can tell which ordering the engine built.
func residueMenuBHTML() -> String {
	"""
	<div id="res-menu-b"\(DismissStack(layer: "b").attributeText) class="res-menu"><p>workspace menu — settings, members</p><button id="res-menu-b-close" type="button"\(DismissStack(layer: "b").attributeText) data-component-id="res-menu-b-close" data-event="click">Close workspace menu</button></div>
	"""
}

// MARK: - page

/// the page's own layout: enough height for the outline to scroll, and no
/// dependency on the framework sheet's cascade.
let residueStyle: String = """
	<style>
	body { margin: 0; font-family: system-ui, sans-serif; }
	.res { max-width: 56rem; margin: 0 auto; padding: 16px; }
	.res h1 { font-size: 1.4rem; margin: 0 0 8px; }
	.res h2 { font-size: 1rem; margin: 24px 0 8px; }
	.res nav a { margin-right: 12px; }
	.res-sec { min-height: 320px; }
	.res-menu { border: 1px solid #888; padding: 8px; margin: 8px 0; }
	.res-layers { display: block; }
	.res-inline { display: flex; gap: 8px; align-items: center; }
	</style>
	"""

/// the whole page, built from typed values — no hand-written `data-*` literal.
func renderResiduePage(_ state: ResidueState, renderToken: String) -> String {
	var sections = ""
	for i in 1...3 {
		var paragraphs = ""
		for p in 1...10 { paragraphs += "<p>section \(i), paragraph \(p)</p>" }
		sections += "<section id=\"res-sec-\(i)\" class=\"res-sec\"><h2>Section \(i)</h2>\(paragraphs)</section>"
	}

	var transcript = ""
	for (who, text) in [("reader", "the transcript is server-rendered."), ("assistant", "every message is a fragment."), ("reader", "no client script builds these.")] {
		transcript += "<div class=\"res-msg\"><strong>\(who)</strong> — \(text)</div>"
	}

	let chip = WebUIDisclosure("Context chip", id: "res-chip") { Text("the chip's content is native details content") }.markup.html
	let group = WebUIDisclosure("Session group", id: "res-group") { Text("three sessions, one summary") }.markup.html
	let skills = WebUIDisclosure("Skill category", id: "res-skills") { Text("collapsed categories stay collapsed across a patch") }.markup.html
	let chatRow = WebUIDisclosure("Chat row menu", id: "res-chat-row") { Text("rename · copy link · archive") }.markup.html

	let body = """
	<main class="res">
	<h1>Residue proof — zero consumer JavaScript</h1>

	<section id="res-transcript"><h2>transcript · server fragments</h2>\(transcript)</section>

	<nav id="res-outline" aria-label="outline">
	<h2>outline · data-scroll-to</h2>
	<a href="#res-sec-1"\(ScrollTo(id: "res-sec-1").attributeText)>Section 1</a>
	<a href="#res-sec-2"\(ScrollTo(id: "res-sec-2").attributeText)>Section 2</a>
	<a href="#res-sec-3"\(ScrollTo(id: "res-sec-3").attributeText)>Section 3</a>
	</nav>

	\(sections)

	<section id="res-rename"><h2>conversation rename · inline edit + refresh</h2>
	<form id="res-rename-form" data-component-id="res-rename" data-event="submit" data-prevent-enter="false">
	<div id="res-inline"\(InlineEdit().attributeText) class="res-inline">
	<span id="res-rename-value">\(htmlEscape(state.name))</span>
	<input id="res-name-input" name="res-name" type="text" value="\(htmlEscape(state.name))" aria-label="conversation name">
	<button id="res-rename-save" type="submit">Save name</button>
	</div>
	</form>
	</section>

	<section id="res-card"><h2>kanban card rename · inline edit + refresh</h2>
	<form id="res-card-form" data-component-id="res-card" data-event="submit" data-prevent-enter="false">
	<div id="res-card-inline"\(InlineEdit().attributeText) class="res-inline">
	<span id="res-card-value">\(htmlEscape(state.card))</span>
	<input id="res-card-input" name="res-card-title" type="text" value="\(htmlEscape(state.card))" aria-label="card title">
	<button id="res-card-save" type="submit">Save card</button>
	</div>
	</form>
	</section>

	<section id="res-menus"><h2>session menus · dismiss stack (LIFO)</h2>
	<button id="res-open-a" type="button" data-component-id="res-open-a" data-event="click">Open session menu</button>
	<div id="res-layers" class="res-layers"></div>
	</section>

	<section id="res-disclosures"><h2>disclosures · native details</h2>
	\(chip)
	\(group)
	\(skills)
	\(chatRow)
	</section>

	<section id="res-copy"><h2>copy halves · data-copy + engine toast</h2>
	<pre><code id="res-code">echo hello</code></pre>
	<button id="res-copy-btn" type="button"\(Clipboard(text: "echo hello").attributeText)>Copy code</button>
	</section>
	</main>
	"""

	return WebUIDocument(
		title: "Residue proof",
		body: .trusted(body),
		head: residueStyle,
		clientMode: ClientBoot(config: RuntimeConfig(renderToken: renderToken))
	).markup.html
}

// MARK: - responder

/// `/residue`: renders the proof page and registers the handlers its controls
/// name. every interaction is a server fragment or a `.refresh`; nothing in
/// the page is wired by consumer JavaScript.
struct ResiduePageResponder: Responder {
	let state: ResidueState
	let router: EventRouter

	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		let session = RenderSessionID(request.renderToken.value)
		router.begin(session)
		let state = self.state
		router.register(outcome: { event in
			state.name = event.string("res-name") ?? state.name
			return .refresh
		}, for: ComponentID("res-rename"), in: session)
		router.register(outcome: { event in
			state.card = event.string("res-card-title") ?? state.card
			return .refresh
		}, for: ComponentID("res-card"), in: session)
		router.register(outcome: { _ in
			.fragments([FragmentUpdate(id: "res-layers", html: residueMenuAHTML())])
		}, for: ComponentID("res-open-a"), in: session)
		router.register(outcome: { _ in
			.fragments([FragmentUpdate.append(id: "res-layers", html: residueMenuBHTML(), before: "res-menu-a")])
		}, for: ComponentID("res-open-b"), in: session)
		router.register(outcome: { _ in
			.fragments([FragmentUpdate(id: "res-menu-a", html: "")])
		}, for: ComponentID("res-menu-a-close"), in: session)
		router.register(outcome: { _ in
			.fragments([FragmentUpdate(id: "res-menu-b", html: "")])
		}, for: ComponentID("res-menu-b-close"), in: session)
		let html = renderResiduePage(state, renderToken: request.renderToken.value)
		return HTTPResponse(headers: smokeHeaders(), body: .html(UnsafeMarkup.trusted(html)))
	}
}
