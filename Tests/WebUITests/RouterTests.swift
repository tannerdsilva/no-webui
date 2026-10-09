import Testing
import WebUIServer

// MARK: - RouterTests
//
// plan w3.2: the typed router. pinned here are the matching rules a page
// server lives on — most-specific-first precedence (literal segment count,
// then capture count), `:param` extraction, 404/405 semantics with an
// `Allow` header, trailing-slash tolerance, percent-decoded params, and the
// pattern-injection guard that must never let a decoded `..` escape the
// router's own structure.

/// read the plain-text payload of a response for assertion.
private extension HTTPResponse {
	var bodyText: String {
		switch body {
		case .html(let html): html
		case .text(let text): text
		case .bytes(let bytes, _): String(decoding: bytes, as: UTF8.self)
		case .empty: ""
		case .redirect(let to, _): "redirect:\(to)"
		case .stream(_, _): "<stream>"
		}
	}
}

// MARK: - PathPattern

@Suite("router: PathPattern")
struct PathPatternTests {

	@Test("a literal pattern matches only itself and yields no params")
	func literal() {
		let pattern: PathPattern = "/users"
		#expect(pattern.match("/users") != nil)
		#expect(pattern.match("/users")?.isEmpty == true)
		#expect(pattern.match("/users/1") == nil)
		#expect(pattern.match("/other") == nil)
	}

	@Test("a capture pattern extracts one segment")
	func capture() {
		let pattern: PathPattern = "/users/:id"
		#expect(pattern.match("/users/42")?["id"] == "42")
		#expect(pattern.match("/users/42/posts") == nil)
		#expect(pattern.match("/users") == nil)
	}

	@Test("a trailing wildcard captures the remainder without breaking on slashes")
	func wildcard() {
		let pattern: PathPattern = "/files/*rest"
		#expect(pattern.match("/files/a")?["rest"] == "a")
		#expect(pattern.match("/files/a/b/c")?["rest"] == "a/b/c")
		// a wildcard still needs at least one remaining segment, so a bare
		// "/files" falls through to a more specific literal if one exists.
		#expect(pattern.match("/files") == nil)
	}

	@Test("specificity ranks literal above capture above wildcard")
	func specificityOrder() {
		let literal: PathPattern = "/a/b"
		let capture: PathPattern = "/a/:x"
		let wildcard: PathPattern = "/a/*rest"
		#expect(literal.specificity > capture.specificity)
		#expect(capture.specificity > wildcard.specificity)
		#expect(literal.specificity > wildcard.specificity)
		// a deeper literal-prefixed path outranks a shallower capture: the
		// primary key is the literal segment count.
		let deeper: PathPattern = "/a/b/*rest"
		#expect(deeper.specificity > capture.specificity)
	}

	@Test("captured segments are percent-decoded and a %2f does not split them")
	func percentDecoding() {
		let pattern: PathPattern = "/users/:id"
		#expect(pattern.match("/users/a%20b")?["id"] == "a b")
		#expect(pattern.match("/users/%E2%9C%93")?["id"] == "\u{2713}")
		// "%2F" decodes to a slash INSIDE the captured value; it must never
		// re-split the path into extra segments.
		#expect(pattern.match("/users/x%2Fy")?["id"] == "x/y")
	}

	@Test("a trailing slash is insignificant")
	func trailingSlash() {
		let pattern: PathPattern = "/users/:id"
		#expect(pattern.match("/users/42/")?["id"] == "42")
		#expect(pattern.match("/users/") == nil)
		#expect((PathPattern(stringLiteral: "/")).match("/") != nil)
	}

	@Test("a pattern-injection attempt decodes inside one segment and cannot escape")
	func injection() {
		// "/..%2fadmin" decodes to "/../admin", but the split happens on the
		// raw path BEFORE decoding, so "..%2fadmin" is ONE segment — it can
		// never be read as the traversal ".." plus a second "admin" segment,
		// and it can never match a literal route sitting above it.
		let pattern: PathPattern = "/:name"
		#expect(pattern.match("/..%2fadmin")?["name"] == "../admin")
		#expect(pattern.match("/..%2fadmin")?.count == 1)

		let literal: PathPattern = "/admin"
		#expect(literal.match("/..%2fadmin") == nil)
		#expect(literal.match("/admin") != nil)
	}
}

// MARK: - matching order

@Suite("router: matching order")
struct RouterMatchingOrderTests {

	@Test("a literal route beats a capture route for the same path")
	func literalBeatsCapture() async {
		let router = Router {
			Route.get("/users/:id") { _ in HTTPResponse(body: .text("capture")) }
			Route.get("/users/me") { _ in HTTPResponse(body: .text("literal")) }
		}
		let response = await router.respond(to: HTTPRequest(path: "/users/me"))
		#expect(response.bodyText == "literal")
		#expect(response.status.code == 200)
	}

	@Test("a capture route beats a wildcard route")
	func captureBeatsWildcard() async {
		let router = Router {
			Route.get("/files/*rest") { _ in HTTPResponse(body: .text("wildcard")) }
			Route.get("/files/:name") { req in
				let name = req.params["name"] ?? "?"
				return HTTPResponse(body: .text("capture:\(name)"))
			}
		}
		let response = await router.respond(to: HTTPRequest(path: "/files/a.png"))
		#expect(response.bodyText == "capture:a.png")
	}

	@Test("literal segment count outranks capture count")
	func literalCountFirst() async {
		// "/a/b/*rest" (two literals) and "/a/:x" (one literal) both match
		// "/a/b/c"; the deeper literal prefix must win.
		let router = Router {
			Route.get("/a/:x") { _ in HTTPResponse(body: .text("short")) }
			Route.get("/a/b/*rest") { req in
				let rest = req.params["rest"] ?? "?"
				return HTTPResponse(body: .text("long:\(rest)"))
			}
		}
		let response = await router.respond(to: HTTPRequest(path: "/a/b/c"))
		#expect(response.bodyText == "long:c")
	}

	@Test("precedence never depends on declaration order")
	func notDeclarationOrder() async {
		// the capture is declared FIRST and still loses to the literal: the
		// router sorts by specificity, it does not consult registration order.
		// (registration order is only the tie-break between two patterns with
		// identical counts.)
		let router = Router {
			Route.get("/users/:id") { _ in HTTPResponse(body: .text("capture")) }
			Route.get("/users/me") { _ in HTTPResponse(body: .text("literal")) }
		}
		#expect((await router.respond(to: HTTPRequest(path: "/users/me"))).bodyText == "literal")
		#expect((await router.respond(to: HTTPRequest(path: "/users/other"))).bodyText == "capture")
	}
}

// MARK: - params and status

@Suite("router: params and status")
struct RouterSemanticsTests {

	@Test("path parameters fill the routed request")
	func paramsFillRequest() async {
		let router = Router {
			Route.get("/users/:id/posts/:postId") { req in
				let id = req.params["id"] ?? "?"
				let postId = req.params["postId"] ?? "?"
				return HTTPResponse(body: .text("u\(id)/p\(postId)"))
			}
		}
		let response = await router.respond(to: HTTPRequest(path: "/users/7/posts/hello"))
		#expect(response.status.code == 200)
		#expect(response.bodyText == "u7/phello")
	}

	@Test("no matching pattern is a 404")
	func notFound() async {
		let router = Router {
			Route.get("/users/:id") { _ in HTTPResponse(body: .text("user")) }
		}
		let response = await router.respond(to: HTTPRequest(path: "/nope"))
		#expect(response.status.code == 404)
		#expect(response.headers["Allow"] == nil)
	}

	@Test("a matched pattern with an unmatched method is a 405 with an Allow header")
	func methodNotAllowed() async {
		let router = Router {
			Route.get("/users/:id") { _ in HTTPResponse(body: .text("get")) }
			Route.post("/users/:id") { _ in HTTPResponse(body: .text("post")) }
		}
		let response = await router.respond(to: HTTPRequest(method: .patch, path: "/users/7"))
		#expect(response.status.code == 405)
		#expect(response.headers["Allow"] == "GET, POST")
	}

	@Test("Allow names only the methods of patterns that actually matched")
	func allowOnlyMatchedMethods() async {
		let router = Router {
			Route.get("/users/:id") { _ in HTTPResponse(body: .text("get")) }
			// a pattern that does not match the path must not leak into Allow.
			Route.post("/elsewhere") { _ in HTTPResponse(body: .text("post")) }
		}
		let response = await router.respond(to: HTTPRequest(method: .delete, path: "/users/7"))
		#expect(response.status.code == 405)
		#expect(response.headers["Allow"] == "GET")
	}

	@Test("a matched method still serves after an earlier 405 candidate")
	func matchedMethodWinsOver405() async {
		let router = Router {
			Route.get("/users/:id") { _ in HTTPResponse(body: .text("user")) }
			Route.get("/users/:id") { _ in HTTPResponse(body: .text("never")) }
			Route.post("/other") { _ in HTTPResponse(body: .text("post")) }
		}
		let response = await router.respond(to: HTTPRequest(method: .get, path: "/users/7"))
		#expect(response.status.code == 200)
		#expect(response.bodyText == "user")
	}

	@Test("a wildcard route serves a whole subtree including params")
	func wildcardDelivery() async {
		let router = Router {
			Route.get("/docs/*rest") { req in
				let rest = req.params["rest"] ?? "?"
				return HTTPResponse(body: .text("doc:\(rest)"))
			}
		}
		let response = await router.respond(to: HTTPRequest(path: "/docs/guides/getting-started"))
		#expect(response.bodyText == "doc:guides/getting-started")
	}

	@Test("routes is a plain introspection list")
	func introspection() {
		let router = Router {
			Route.get("/a") { _ in HTTPResponse() }
			Route.post("/b") { _ in HTTPResponse() }
		}
		#expect(router.routes.count == 2)
		#expect(router.routes[0].method == .get)
		#expect(router.routes[1].method == .post)
	}
}

// MARK: - live server (the new router-driven init)

@Suite("router: WebUIServer integration", .serialized)
struct WebUIServerRouterIntegrationTests {

	@Test("a router-driven server answers paths and params over the wire")
	func servesRoutes() async throws {
		let pageRouter = Router {
			Route.get("/") { _ in HTTPResponse(body: .text("root")) }
			Route.get("/hello") { _ in HTTPResponse(body: .text("hi")) }
			Route.get("/users/:id") { req in
				let id = req.params["id"] ?? "?"
				return HTTPResponse(body: .text("user:\(id)"))
			}
			Route.get("/files/*rest") { req in
				let rest = req.params["rest"] ?? "?"
				return HTTPResponse(body: .text("rest:\(rest)"))
			}
		}
		try await withRouterServer(pageRouter) { port in
			let (root, rootStatus) = try await get("http://127.0.0.1:\(port)/")
			#expect(rootStatus == 200)
			#expect(root == "root")

			let (hello, helloStatus) = try await get("http://127.0.0.1:\(port)/hello")
			#expect(helloStatus == 200)
			#expect(hello == "hi")

			// percent-decoded on the wire, as the unit tests pin.
			let (user, userStatus) = try await get("http://127.0.0.1:\(port)/users/a%20b")
			#expect(userStatus == 200)
			#expect(user == "user:a b")

			let (file, fileStatus) = try await get("http://127.0.0.1:\(port)/files/one/two")
			#expect(fileStatus == 200)
			#expect(file == "rest:one/two")

			let (missing, missingStatus) = try await get("http://127.0.0.1:\(port)/nope")
			#expect(missingStatus == 404)

			// a POST into a GET-only pattern keeps the router's 405 + Allow.
			let (postData, postStatus) = try await post("http://127.0.0.1:\(port)/users/7")
			#expect(postStatus == 405)
			let postBody = String(decoding: postData, as: UTF8.self)
			#expect(postBody.contains("GET"))
		}
	}
}
