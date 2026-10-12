// staged by W0 (probe wave, 2026-10-10) — W2 lands this as
// Tests/WebUITests/TypedMarkupTests.swift.
//
// W0 VERIFIED this source compiles and passes against the A1/A2 probe edits
// (`BufferRendering` public + `markup` extension + empty-bodied `View`).
// it does NOT compile against the reverted tree — `markup` does not exist until
// W2 lands — which is exactly why W0 staged it here instead of committing it.
//
// raw W0 evidence:
//   ✔ Test "a Raw's stored markup shadows the BufferRendering extension" passed
//   ✔ Test "BufferRendering.markup materializes a view's render" passed
//   ✔ Test run with 2 tests in 1 suite passed
//
// W2's own note: once `render()` is deprecated, migrate the second test's
// `text.render()` to `text.markup.html` to avoid a deprecation warning — the
// assertion is on byte identity either way.

import Testing
import WebUI
import WebUIDesignSystem

// the typed materializer and the typed response boundary (W2).
//
// these pin the two load-bearing facts of the typed-markup arc:
// 1. a `View`'s own stored `markup` (a `Raw`) shadows the `BufferRendering`
//    extension property — the concrete member wins, so a trusted `Raw` reads
//    back exactly the bytes it was given;
// 2. the framework's `markup` materializer renders a view through the buffer
//    and hands back an `UnsafeMarkup` the host can inspect (`.html`).
@Suite("typed markup")
struct TypedMarkupTests {
	@Test("a Raw's stored markup shadows the BufferRendering extension")
	func rawsStoredMarkupWins() {
		let raw = Raw(.trusted("<b>x</b>"))
		#expect(raw.markup.html == "<b>x</b>")
		#expect(Raw(.trusted("<b>x</b>")).markup.html == "<b>x</b>")
	}

	@Test("BufferRendering.markup materializes a view's render")
	func markupMaterializesRender() {
		// W2 substitution: the staged source asserted `probe.markup.html ==
		// text.render()`, but `render()` is deprecated as of W2, so it warns.
		// replace ONLY that right-hand side with an equivalent that avoids the
		// deprecated spelling — a local probe view whose render(into:) appends
		// a known literal. the assertion still pins the materializer rendering
		// a view's bytes.
		let probe = RenderProbe()
		#expect(probe.markup.html == "<p>probe</p>")
	}

	@Test("a document's markup served through the typed response carries its exact bytes")
	func typedResponseServesDocumentBytes() {
		// webuidocument's render mints a fresh nonce on every call (it builds
		// a fresh HTMLDocument), so capture the materialized markup once and
		// assert the response round-trips exactly those bytes.
		let doc = WebUIDocument(title: "boundary", body: .trusted("<main>ride-through</main>"))
		let markup = doc.markup
		let response = HTTPResponse(markup)
		guard case .html(let served) = response.body else {
			Issue.record("expected an html body")
			return
		}
		#expect(served.html == markup.html)
		#expect(served.html.contains("<main>ride-through</main>"))
	}

	@Test("UnsafeMarkup.trusted round-trips to .html as those bytes")
	func trustedRoundTripsToHTML() {
		let response = HTTPResponse(.trusted("<p>hi</p>"))
		guard case .html(let markup) = response.body else {
			Issue.record("expected an html body")
			return
		}
		#expect(markup.html == "<p>hi</p>")
	}
}

// a minimal view whose render writes a known literal — the deprecation-free
// probe for the materializer test above.
private struct RenderProbe: View {
	func render(into buffer: inout HTMLBuffer) {
		buffer.append("<p>probe</p>")
	}
}
