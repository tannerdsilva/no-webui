import Testing
import Foundation
import WebUI

// media primitives (W4.3; G10, E1). every url-bearing primitive in this file
// routes its src/poster through sanitizeURL exactly as Image and Link do, and
// Iframe's sandbox always defaults to the strict (empty) set.

@Suite("video")
struct VideoTests {

	@Test("renders a control-bearing video with a sanitized src and its tracks")
	func rendersControls() {
		let html = Video(src: "/movie.mp4") {
			Track(src: "/movie.vtt", kind: .subtitles, srclang: "en", label: "English")
		}.markup.html
		#expect(html.contains("<video src=\"/movie.mp4\" controls>"), "got \(html)")
		#expect(html.contains("<track src=\"/movie.vtt\" kind=\"subtitles\" srclang=\"en\" label=\"English\">"))
		#expect(html.contains("</video>"))
	}

	@Test("optional booleans map onto bare attributes when set")
	func optionalFlags() {
		let html = Video(src: "/m.mp4", autoplay: true, muted: true, loop: true, playsInline: true) {
			Track(src: "/m.vtt", kind: .captions, srclang: "fr", label: "French")
		}.markup.html
		#expect(html.contains("<video src=\"/m.mp4\" controls autoplay muted loop playsinline>"))
	}

	@Test("a javascript: src drops the whole element")
	func javascriptSrcDropsElement() {
		let html = Video(src: "javascript:alert(1)") {
			Track(src: "/m.vtt", kind: .subtitles, srclang: "en", label: "English")
		}.markup.html
		#expect(html.isEmpty)
		#expect(!html.lowercased().contains("javascript:"))
	}

	@Test("a data: src drops the whole element")
	func dataSrcDropsElement() {
		let html = Video(src: "data:text/html,<script>alert(1)</script>") {
			Track(src: "/m.vtt", kind: .subtitles, srclang: "en", label: "English")
		}.markup.html
		#expect(html.isEmpty)
		#expect(!html.lowercased().contains("data:text/html"))
	}

	@Test("a hostile poster is omitted while the video still renders")
	func hostilePosterOmitted() {
		let html = Video(src: "/movie.mp4", poster: "javascript:alert(1)") {
			Track(src: "/m.vtt", kind: .subtitles, srclang: "en", label: "English")
		}.markup.html
		#expect(html.contains("src=\"/movie.mp4\""))
		#expect(!html.lowercased().contains("poster="))
		#expect(!html.lowercased().contains("javascript:"))
	}
}

@Suite("audio")
struct AudioTests {

	@Test("renders a control-bearing audio with a sanitized src")
	func rendersControls() {
		let html = Audio(src: "/podcast.mp3") {
			Track(src: "/podcast.vtt", kind: .captions, srclang: "en", label: "Captions")
		}.markup.html
		#expect(html.contains("<audio src=\"/podcast.mp3\" controls>"), "got \(html)")
		#expect(html.contains("<track"))
		#expect(html.contains("</audio>"))
	}

	@Test("a javascript: src drops the whole element")
	func javascriptSrcDropsElement() {
		let html = Audio(src: "javascript:alert(1)") {
			Track(src: "/p.vtt", kind: .captions, srclang: "en", label: "c")
		}.markup.html
		#expect(html.isEmpty)
		#expect(!html.lowercased().contains("javascript:"))
	}

	@Test("a data: src drops the whole element")
	func dataSrcDropsElement() {
		let html = Audio(src: "data:audio/wav;base64,UklGRg==") {
			Track(src: "/p.vtt", kind: .captions, srclang: "en", label: "c")
		}.markup.html
		#expect(html.isEmpty)
		#expect(!html.lowercased().contains("data:audio"))
	}
}

@Suite("picture")
struct PictureTests {

	@Test("renders a picture wrapper around its source candidates and image fallback")
	func rendersWrapper() {
		let html = Picture {
			Source(src: "/hero.avif", type: "image/avif", media: "(min-width: 800px)")
			Image(src: "/hero.jpg", alt: "hero")
		}.markup.html
		#expect(html.hasPrefix("<picture>"), "got \(html)")
		#expect(html.hasSuffix("</picture>"))
		#expect(html.contains("<source src=\"/hero.avif\" type=\"image/avif\" media=\"(min-width: 800px)\">"))
		#expect(html.contains("<img src=\"/hero.jpg\""))
	}

	@Test("a javascript: source inside is neutralized")
	func javascriptSourceNeutralized() {
		let html = Picture {
			Source(src: "javascript:alert(1)", type: "image/webp")
			Image(src: "/hero.jpg", alt: "hero")
		}.markup.html
		#expect(!html.lowercased().contains("javascript:"), "got \(html)")
		#expect(!html.contains("<source"), "the hostile source must not render")
	}

	@Test("a data: source inside is neutralized")
	func dataSourceNeutralized() {
		let html = Picture {
			Source(src: "data:image/svg+xml,<svg onload=alert(1)>", type: "image/svg+xml")
			Image(src: "/hero.jpg", alt: "hero")
		}.markup.html
		#expect(!html.contains("<source"), "the hostile source must not render")
		#expect(!html.lowercased().contains("onload"), "got \(html)")
	}
}

@Suite("source")
struct SourceTests {

	@Test("renders a source with src, type and media")
	func renders() {
		let html = Source(src: "/clip.mp4", type: "video/mp4", media: "(min-width: 640px)").markup.html
		#expect(html == "<source src=\"/clip.mp4\" type=\"video/mp4\" media=\"(min-width: 640px)\">")
	}

	@Test("a javascript: src drops the element")
	func javascriptSrcDrops() {
		#expect(Source(src: "javascript:alert(1)", type: "video/mp4").markup.html.isEmpty)
	}

	@Test("a data: src drops the element")
	func dataSrcDrops() {
		#expect(Source(src: "data:video/mp4;base64,AAAA", type: "video/mp4").markup.html.isEmpty)
	}
}

@Suite("track")
struct TrackTests {

	@Test("renders a track with kind, srclang, label and default")
	func renders() {
		let html = Track(src: "/c.vtt", kind: .captions, srclang: "en", label: "English", default: true).markup.html
		#expect(html == "<track src=\"/c.vtt\" kind=\"captions\" srclang=\"en\" label=\"English\" default>")
	}

	@Test("a javascript: src drops the element")
	func javascriptSrcDrops() {
		#expect(Track(src: "javascript:alert(1)", kind: .metadata, srclang: "en", label: "m").markup.html.isEmpty)
	}

	@Test("a data: src drops the element")
	func dataSrcDrops() {
		#expect(Track(src: "data:text/vtt,WEBVTT", kind: .subtitles, srclang: "en", label: "s").markup.html.isEmpty)
	}
}

@Suite("iframe")
struct IframeTests {

	@Test("defaults to the strict sandbox set")
	func defaultsToStrictSandbox() {
		let html = Iframe(src: "/embed", title: "embedded").markup.html
		#expect(html.contains("src=\"/embed\""), "got \(html)")
		#expect(html.contains("title=\"embedded\""))
		#expect(html.contains("sandbox=\"\""), "the default sandbox must be the strict empty set, got \(html)")
		#expect(!html.contains("allow-scripts"), "the strict sandbox never grants scripts")
		#expect(html.contains("loading=\"lazy\""))
	}

	@Test("a widened sandbox set emits sorted tokens")
	func widenedSandboxEmitsSorted() {
		let html = Iframe(src: "/embed", title: "e", sandbox: [.allowScripts, .allowSameOrigin, .allowForms]).markup.html
		#expect(html.contains("sandbox=\"allow-forms allow-same-origin allow-scripts\""), "got \(html)")
	}

	@Test("allow policies render in the permissions-policy attribute")
	func allowPoliciesRender() {
		let html = Iframe(src: "/embed", title: "e", allow: ["microphone", "camera"]).markup.html
		#expect(html.contains("allow=\"camera; microphone\""), "got \(html)")
	}

	@Test("a javascript: src drops the frame")
	func javascriptSrcDrops() {
		#expect(Iframe(src: "javascript:alert(1)", title: "e").markup.html.isEmpty)
	}

	@Test("a data: src drops the frame")
	func dataSrcDrops() {
		#expect(Iframe(src: "data:text/html,<script>alert(1)</script>", title: "e").markup.html.isEmpty)
	}
}

@Suite("canvas")
struct CanvasTests {

	@Test("renders a canvas with id, width and height")
	func renders() {
		let html = Canvas(id: "game", width: 640, height: 480).markup.html
		#expect(html == "<canvas id=\"game\" width=\"640\" height=\"480\">")
	}

	@Test("escapes a hostile id")
	func escapesId() {
		let html = Canvas(id: "a\" onload=\"x", width: 1, height: 1).markup.html
		// the quote is escaped, so the injected ` onload="x"` stays inside the
		// attribute value and never becomes a second attribute.
		#expect(!html.contains(" onload=\""), "got \(html)")
		#expect(html.contains("id=\"a&quot; onload=&quot;x\""))
	}
}
