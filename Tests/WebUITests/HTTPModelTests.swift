import Testing
import NIOHTTP1
import WebUIServer
import WebUISharedCore

// MARK: - HTTPModelTests
//
// the typed request/response model (plan w3.1): the wire shapes the server
// builds on without poking at nio's part types. pinned here are the two
// lookups the router will live on — method and case-insensitive header —
// and the cookie parsing/building round-trip that moved up to the shared
// leaf with the model's `HTTPResponse.cookies`.

@Suite("HTTP model")
struct HTTPModelTests {

	@Test("http method carries lowercase wire names")
	func methods() {
		#expect(HTTPMethod.allCases.count == 7)
		#expect(HTTPMethod.get.rawValue == "get")
		#expect(HTTPMethod.post.rawValue == "post")
		#expect(HTTPMethod.delete.rawValue == "delete")
	}

	@Test("http status literal ergonomics")
	func statusLiterals() {
		#expect(HTTPStatus.ok.code == 200)
		#expect(HTTPStatus.created.code == 201)
		#expect(HTTPStatus.noContent.code == 204)
		#expect(HTTPStatus.redirect.code == 303)
		#expect(HTTPStatus.notFound.code == 404)
		#expect(HTTPStatus.unprocessable.code == 422)
		let custom: HTTPStatus = 418
		#expect(custom.code == 418)
		#expect(HTTPStatus(599).code == 599)
		#expect(HTTPStatus.ok == 200)
		#expect(HTTPStatus.notFound != .ok)
	}

	@Test("header lookup is case-insensitive")
	func caseInsensitiveHeaders() {
		var headers = HTTPHeaders()
		headers.add(name: "Content-Type", value: "text/html")
		headers.add(name: "x-custom-prop", value: "42")
		let request = HTTPRequest(headers: headers)
		#expect(request.headers.first(name: "content-type") == "text/html")
		#expect(request.headers.first(name: "CONTENT-TYPE") == "text/html")
		#expect(request.headers["X-Custom-Prop"] == ["42"])
		#expect(request.headers.first(name: "missing") == nil)
	}

	@Test("request model carries the fields the router fills")
	func requestModel() {
		var request = HTTPRequest(method: .post, path: "/api/login")
		request.query["next"] = "/home"
		request.cookies["sid"] = "1"
		request.isSecure = true
		request.body = .bytes([0x01, 0x02])
		request.params["id"] = "7"
		#expect(request.method == .post)
		#expect(request.path == "/api/login")
		#expect(request.query["next"] == "/home")
		#expect(request.cookies["sid"] == "1")
		#expect(request.isSecure)
		#expect(request.params["id"] == "7")
		guard case .bytes(let bytes) = request.body else {
			Issue.record("expected a bytes body")
			return
		}
		#expect(bytes == [0x01, 0x02])
	}

	@Test("response model carries status, headers, and cookies")
	func responseModel() throws {
		var response = HTTPResponse()
		response.status = .created
		response.headers["Location"] = "/next"
		response.cookies.append(HTTPCookie(name: "sid", value: "1"))
		response.body = .html("<p>hi</p>")
		#expect(response.status.code == 201)
		#expect(response.headers["Location"] == "/next")
		#expect(response.cookies.count == 1)
		guard case .html(let html) = response.body else {
			Issue.record("expected an html body")
			return
		}
		#expect(html == "<p>hi</p>")
	}

	@Test("redirect response defaults to 303")
	func redirectDefault() {
		let body: HTTPResponse.Body = .redirect(to: "/login")
		guard case .redirect(let to, let status) = body else {
			Issue.record("expected a redirect body")
			return
		}
		#expect(to == "/login")
		#expect(status.code == 303)
	}

	@Test("cookie parser round-trips a set-cookie header")
	func setCookieRoundTrip() throws {
		let epoch: Epoch = 1623233894 // Wed, 09 Jun 2021 10:18:14 GMT
		let cookie = HTTPCookie(
			name: "session",
			value: "abc123",
			attributes: .init(
				expires: epoch,
				maxAge: 3600,
				domain: "example.com",
				path: "/",
				secure: true,
				httpOnly: true,
				sameSite: .lax
			)
		)
		let header = try cookie.setCookieHeaderValue()
		#expect(header.hasPrefix("session=abc123"))
		#expect(header.contains("Expires=Wed, 09 Jun 2021 10:18:14 GMT"))
		#expect(header.contains("SameSite=Lax"))

		let parsed = CookieParser.setCookie(header)
		#expect(parsed != nil)
		#expect(parsed?.name == "session")
		#expect(parsed?.value == "abc123")
		#expect(parsed?.attributes.expires == epoch)
		#expect(parsed?.attributes.maxAge == 3600)
		#expect(parsed?.attributes.domain == "example.com")
		#expect(parsed?.attributes.path == "/")
		#expect(parsed?.attributes.secure == true)
		#expect(parsed?.attributes.httpOnly == true)
		#expect(parsed?.attributes.sameSite == .lax)
	}

	@Test("expires round-trips at epoch zero")
	func epochZero() throws {
		let cookie = HTTPCookie(name: "a", value: "b", attributes: .init(expires: 0))
		let header = try cookie.setCookieHeaderValue()
		#expect(header.contains("Expires=Thu, 01 Jan 1970 00:00:00 GMT"))
		#expect(CookieParser.setCookie(header)?.attributes.expires == 0)
	}

	@Test("a cookie with an invalid epoch does not crash")
	func invalidEpoch() {
		let garbage = CookieParser.setCookie("session=x; Expires=not-a-date; SameSite=Strict")
		#expect(garbage?.attributes.expires == nil)
		#expect(garbage?.attributes.sameSite == .strict)

		let numeric = CookieParser.setCookie("session=x; Expires=0; Max-Age=0")
		#expect(numeric?.attributes.expires == nil)
		#expect(numeric?.attributes.maxAge == 0)

		let empty = CookieParser.setCookie("session=x; Expires=")
		#expect(empty?.attributes.expires == nil)
	}
}
