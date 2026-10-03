import Foundation
#if canImport(FoundationNetworking)
// swift-corelibs-foundation keeps URLSession/URLRequest/HTTPURLResponse in a
// separate module; without this the test target does not compile on linux.
import FoundationNetworking
#endif
import Logging
import ServiceLifecycle
import Testing
import WebUI
import WebUIDesignSystem
@testable import WebUIServer

// MARK: - query parsing

@Suite("server query parsing")
struct ServerQueryParsingTests {

	@Test("decodes percent escapes and '+'")
	func decoding() {
		let parsed = parseQuery("a=1&b=hello%20world&c=x%2By&d=a+b")
		#expect(parsed["a"] == "1")
		#expect(parsed["b"] == "hello world")
		#expect(parsed["c"] == "x+y")
		#expect(parsed["d"] == "a b")
	}

	@Test("empty input yields no pairs; a bare key yields an empty value")
	func degenerate() {
		#expect(parseQuery("").isEmpty)
		#expect(parseQuery("solo")["solo"] == "")
	}

	@Test("a repeated key keeps its first value")
	func repeated() {
		#expect(parseQuery("k=first&k=second")["k"] == "first")
	}

	@Test("a malformed escape is preserved rather than dropped")
	func malformed() {
		#expect(parseQuery("bad=%zz")["bad"] == "%zz")
		#expect(parseQuery("bad=%e")["bad"] == "%e")
	}

	@Test("a multi-byte escape decodes to its character")
	func multiByte() {
		#expect(parseQuery("q=%E2%9C%93")["q"] == "\u{2713}")
	}
}

// MARK: - host assets, query stripping, request-aware render

@Suite("WebUIServer seams", .serialized)
struct WebUIServerSeamsTests {

	@Test("serves host text + binary assets and strips the query string")
	func hostAssetsAndQuery() async throws {
		let router = EventRouter()
		let binary: [UInt8] = [0x00, 0xFF, 0x10, 0x80, 0x77, 0x4F]
		let cssText = ".app{color:red}"

		try await withServer(
			requestRender: { request in
				// the request-aware render sees the decoded query.
				"<p>deep=\(request.value("s") ?? "none")</p>"
			},
			router: router,
			assets: [
				.text("/ui/app.css", cssText, contentType: "text/css; charset=utf-8", cacheSeconds: 60),
				.bytes("/ui/font.woff2", binary, contentType: "font/woff2", cacheSeconds: 31536000),
			]
		) { port in
			// the page route, bare and with a deep link.
			let (bare, bareStatus) = try await get("http://127.0.0.1:\(port)/")
			#expect(bareStatus == 200)
			#expect(bare.contains("deep=none"))

			let (linked, linkedStatus) = try await get("http://127.0.0.1:\(port)/?s=abc-123")
			#expect(linkedStatus == 200)
			#expect(linked.contains("deep=abc-123"))

			let (indexed, indexedStatus) = try await get("http://127.0.0.1:\(port)/index.html?s=deep%2Fx")
			#expect(indexedStatus == 200)
			#expect(indexed.contains("deep=deep/x"))

			// host text asset: served bare and with a cache-busting query.
			let (css, cssStatus) = try await get("http://127.0.0.1:\(port)/ui/app.css")
			#expect(cssStatus == 200)
			#expect(css == cssText)

			let (busted, bustedStatus) = try await get("http://127.0.0.1:\(port)/ui/app.css?v=41")
			#expect(bustedStatus == 200)
			#expect(busted == cssText)

			// host binary asset: byte-exact.
			let (bytes, fontStatus) = try await getData("http://127.0.0.1:\(port)/ui/font.woff2")
			#expect(fontStatus == 200)
			#expect(bytes == Data(binary))

			// the framework routes still win: the built-in sheet answers with a
			// query string attached, and 404s stay 404.
			let (sheet, sheetStatus) = try await get("http://127.0.0.1:\(port)/__assets/css?v=9")
			#expect(sheetStatus == 200)
			#expect(sheet.contains(".button"))

			let (_, missingStatus) = try await get("http://127.0.0.1:\(port)/nope")
			#expect(missingStatus == 404)

			// a page whose path is query-only-different is still the page.
			let (_, postStatus) = try await post("http://127.0.0.1:\(port)/")
			#expect(postStatus == 405)
		}
	}

	@Test("a host asset cannot shadow a framework route")
	func hostAssetCannotShadowFramework() async throws {
		try await withServer(
			requestRender: { _ in "<p>page</p>" },
			router: EventRouter(),
			assets: [
				.text("/__assets/css", "SHADOWED", contentType: "text/css"),
				.text("/ui/webui-engine.js", "SHADOWED", contentType: "text/javascript"),
			]
		) { port in
			let (sheet, sheetStatus) = try await get("http://127.0.0.1:\(port)/__assets/css")
			#expect(sheetStatus == 200)
			#expect(!sheet.contains("SHADOWED"))

			let (engine, engineStatus) = try await get("http://127.0.0.1:\(port)/ui/webui-engine.js")
			#expect(engineStatus == 200)
			#expect(!engine.contains("SHADOWED"))
		}
	}

	@Test("hosts through a ServiceGroup and releases the port on shutdown")
	func serviceHostsAndStops() async throws {
		let port = try await freePort()
		let server = WebUIServer(
			requestRender: { _ in "<p>service-up</p>" },
			router: EventRouter(),
			config: WebUIServerConfig(host: "127.0.0.1", port: port)
		)
		let group = ServiceGroup(
			services: [WebUIServerService(server: server)],
			logger: Logger(label: "webui.service.test")
		)
		let running = Task { try await group.run() }

		// the service reaches "ready" only once the socket answers.
		let (page, status) = try await waitForServe(port: port)
		#expect(status == 200)
		#expect(page.contains("service-up"))

		// shutting the group down must actually stop the listener.
		running.cancel()
		try await assertClosed(port: port)
		_ = try? await running.value
	}

	@Test("pushes fragments to a connected page with no inbound event")
	func broadcastPush() async throws {
		#if os(Linux)
		// `URLSessionWebSocketTask` does not exist in swift-corelibs-foundation,
		// so the ws leg is apple-only here; the push path is covered on linux
		// out of band by the raw-socket bench against this same server.
		return
		#else
		let port = try await freePort()
		let target = "push-target"
		let server = WebUIServer(
			requestRender: { _ in "<span id=\"\(target)\">before</span>" },
			router: EventRouter(),
			config: WebUIServerConfig(host: "127.0.0.1", port: port)
		)
		let task = Task { try await server.start() }
		_ = try await waitForServe(port: port)

		let socket = URLSession(configuration: .ephemeral)
			.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
		socket.resume()
		defer { socket.cancel(with: .normalClosure, reason: nil) }

		// the accept side registers the sink on upgrade — wait for that rather
		// than racing the broadcast against the handshake.
		var registered = false
		for _ in 0..<120 {
			if await server.connectedPages == 1 {
				registered = true
				break
			}
			try await Task.sleep(for: .milliseconds(25))
		}
		#expect(registered, "the socket never registered as a push target")

		await server.broadcast([
			FragmentUpdate(id: target, html: "<span id=\"\(target)\">after</span>")
		])

		let message = try await socket.receive()
		let text: String
		switch message {
		case .string(let value): text = value
		case .data(let data): text = String(decoding: data, as: UTF8.self)
		@unknown default: text = ""
		}
		#expect(text.contains("\"update\""))
		#expect(text.contains("after"))

		// the connection is gone once the socket closes.
		socket.cancel(with: .normalClosure, reason: nil)
		for _ in 0..<120 {
			if await server.connectedPages == 0 { break }
			try await Task.sleep(for: .milliseconds(25))
		}
		#expect(await server.connectedPages == 0, "the sink was not released")

		await server.stop()
		task.cancel()
		try await assertClosed(port: port)
		#endif
	}

		@Test("serves a content-addressed theme sheet, and only at its own address")
	func themeSheetRoute() async throws {
		let sheet = ThemeSheet(css: ":root[data-scheme=\"x\"]{--color-bg:#fff;}")
		try await withServer(
			requestRender: { _ in "<p>page</p>" },
			router: EventRouter(),
			assets: [],
			themeSheet: sheet
		) { port in
			let (body, status) = try await get("http://127.0.0.1:\(port)\(sheet.url)")
			#expect(status == 200)
			#expect(body.contains("--color-bg:#fff;"))
			// the address IS the content: a wrong address must not serve the right sheet, or a
			// cache would hold bytes under a url they do not belong to.
			let (_, missing) = try await get("http://127.0.0.1:\(port)/__assets/theme.deadbeef")
			#expect(missing == 404)
			// and the page route still works with a sheet configured.
			let (page, pageStatus) = try await get("http://127.0.0.1:\(port)/")
			#expect(pageStatus == 200)
			#expect(page.contains("page"))
		}
	}

	@Test("serves a host asset's pre-compressed variant, and `Vary` either way")
	func hostAssetGzipVariant() async throws {
		let plain = probePlain
		let gzipped = probeGzip
		try await withServer(
			requestRender: { _ in "<p>page</p>" },
			router: EventRouter(),
			assets: [
				WebUIServerAsset(
					path: "/ui/probe.css",
					body: .text(plain),
					contentType: "text/css; charset=utf-8",
					cacheSeconds: 60,
					gzip: gzipped
				)
			]
		) { port in
			let url = "http://127.0.0.1:\(port)/ui/probe.css"

			// a client that accepts gzip gets the host's compressed bytes.
			let (gzipHeaders, gzipBody) = try await rawGET(url, acceptEncoding: "gzip, deflate")
			#expect(gzipHeaders.contains("Content-Encoding: gzip"))
			#expect(gzipHeaders.contains("Vary: Accept-Encoding"))
			#expect(gzipBody == Data(gzipped))

			// one that does not gets the plain bytes — and STILL sees `Vary`, or a shared
			// cache would hand it the compressed variant.
			let (plainHeaders, plainBody) = try await rawGET(url, acceptEncoding: "identity")
			#expect(!plainHeaders.contains("Content-Encoding:"))
			#expect(plainHeaders.contains("Vary: Accept-Encoding"))
			#expect(String(decoding: plainBody, as: UTF8.self) == plain)

			// an asset with no variant advertises none: no `Vary`, no `Content-Encoding`.
			let (bareHeaders, _) = try await rawGET("http://127.0.0.1:\(port)/", acceptEncoding: "gzip")
			#expect(!bareHeaders.contains("Vary: Accept-Encoding"))
		}
	}

	@Test("a `WebUIAsset` owns its url, registration and variant — and the stamped path 404s")
	func webUIAssetOwnsItsAddress() async throws {
		let asset = WebUIAsset(
			path: "/ui/pair.css", text: probePlain, gzip: probeGzip, contentType: "text/css; charset=utf-8"
		)
		// the pairing is derived from one value, never hand-declared: the url carries the
		// stamp, the registration is the *bare* path. matching happens after the query is
		// stripped, so a registration carrying its stamp (the P3 bug) can never match.
		#expect(asset.registration.path == "/ui/pair.css")
		#expect(asset.url == "/ui/pair.css?v=\(asset.stamp)")
		#expect(asset.stamp.count == 12)

		try await withServer(
			requestRender: { _ in "<p>page</p>" },
			router: EventRouter(),
			assets: [
				asset.registration,
				// a host asset with a plain policy: no stamp, no immutable.
				.text("/ui/plain.css", probePlain, contentType: "text/css; charset=utf-8", cacheSeconds: 60),
				// the bug, pinned: a registration that carries its stamp matches nothing.
				.text("/x.css?v=deadbeef", "wrong", contentType: "text/css; charset=utf-8"),
			]
		) { port in
			// (a) the linked url answers, bare registration + immutable cache, `Vary`
			// present because a variant exists.
			let (headers, body) = try await rawGET(
				"http://127.0.0.1:\(port)\(asset.url)", acceptEncoding: "identity"
			)
			#expect(headers.contains("200 OK"))
			#expect(headers.contains("Cache-Control: public, max-age=31536000, immutable"))
			#expect(headers.contains("Vary: Accept-Encoding"))
			#expect(!headers.contains("Content-Encoding:"))
			#expect(String(decoding: body, as: UTF8.self) == probePlain)

			// (b) the compressed variant negotiates to the bytes the build produced.
			let (gzHeaders, gzBody) = try await rawGET(
				"http://127.0.0.1:\(port)\(asset.url)", acceptEncoding: "gzip, deflate"
			)
			#expect(gzHeaders.contains("Content-Encoding: gzip"))
			#expect(gzHeaders.contains("Vary: Accept-Encoding"))
			#expect(gzBody == Data(probeGzip))

			// (c) a plain host policy is untouched: max-age without immutable.
			let (plainHeaders, _) = try await rawGET(
				"http://127.0.0.1:\(port)/ui/plain.css", acceptEncoding: "identity"
			)
			#expect(plainHeaders.contains("Cache-Control: public, max-age=60"))
			#expect(!plainHeaders.contains("immutable"))

			// (d) the P3 bug, pinned both ways: the stamped registration matches nothing —
			// not the stamped request, and not the bare path it was never registered at.
			let (_, stamped) = try await get("http://127.0.0.1:\(port)/x.css?v=deadbeef")
			#expect(stamped == 404)
			let (_, bare) = try await get("http://127.0.0.1:\(port)/x.css")
			#expect(bare == 404)
		}
	}

	@Test("the theme sheet negotiates compression, and a sheet without a variant advertises none")
	func themeSheetNegotiates() async throws {
		// the sheet's bytes are the shared fixture pair, so the compressed leg can be
		// asserted byte-for-byte the way the host-asset leg is.
		let sheet = ThemeSheet(css: probePlain, gzip: probeGzip)
		let bare = ThemeSheet(css: probePlain)

		try await withServer(
			requestRender: { _ in "<p>page</p>" },
			router: EventRouter(),
			assets: [],
			themeSheet: sheet
		) { port in
			let (plainHeaders, plainBody) = try await rawGET(
				"http://127.0.0.1:\(port)\(sheet.url)", acceptEncoding: "identity"
			)
			#expect(plainHeaders.contains("200 OK"))
			#expect(plainHeaders.contains("Cache-Control: public, max-age=31536000, immutable"))
			#expect(plainHeaders.contains("Vary: Accept-Encoding"), "a variant exists, so caches must be told")
			#expect(!plainHeaders.contains("Content-Encoding:"))
			#expect(String(decoding: plainBody, as: UTF8.self) == probePlain)

			let (gzHeaders, gzBody) = try await rawGET(
				"http://127.0.0.1:\(port)\(sheet.url)", acceptEncoding: "gzip"
			)
			#expect(gzHeaders.contains("Content-Encoding: gzip"))
			#expect(gzHeaders.contains("Vary: Accept-Encoding"))
			#expect(gzBody == Data(probeGzip))
		}

		// no variant: bytes and headers exactly as they were before the seam existed.
		try await withServer(
			requestRender: { _ in "<p>page</p>" },
			router: EventRouter(),
			assets: [],
			themeSheet: bare,
			portBase: 22000
		) { port in
			let (headers, body) = try await rawGET(
				"http://127.0.0.1:\(port)\(bare.url)", acceptEncoding: "gzip"
			)
			#expect(headers.contains("200 OK"))
			#expect(!headers.contains("Content-Encoding:"))
			#expect(!headers.contains("Vary: Accept-Encoding"))
			#expect(String(decoding: body, as: UTF8.self) == probePlain)
		}
	}
}
