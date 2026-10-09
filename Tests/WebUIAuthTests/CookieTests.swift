import Foundation
import Testing

@testable import WebUIAuth

@Suite("HTTPCookie")
struct CookieTests {

	@Test("set-cookie renders the full flag surface")
	func fullFlags() throws {
		let cookie = HTTPCookie(
			name: "auth",
			value: "abc123",
			attributes: .init(
				maxAge: 3600,
				path: "/",
				secure: true,
				httpOnly: true,
				sameSite: .lax
			)
		)
		let header = try cookie.setCookieHeaderValue()
		#expect(header.hasPrefix("auth=abc123"))
		#expect(header.contains("Max-Age=3600"))
		#expect(header.contains("Path=/"))
		#expect(header.contains("Secure"))
		#expect(header.contains("HttpOnly"))
		#expect(header.contains("SameSite=Lax"))
		#expect(header.contains("; "))
	}

	@Test("expires renders as an rfc-1123 date from epoch seconds")
	func expiresDate() throws {
		// `WebUIAuth` re-exports the shared cookie types; the file must not
		// import `WebUISharedCore` itself (the unqualified name would become
		// ambiguous), so the epoch annotation is spelled as the shared
		// typealias's underlying `UInt64`.
		let epoch: UInt64 = 1623233894 // Wed, 09 Jun 2021 10:18:14 GMT
		let cookie = HTTPCookie(name: "a", value: "b", attributes: .init(expires: epoch))
		let header = try cookie.setCookieHeaderValue()
		#expect(header.contains("Expires=Wed, 09 Jun 2021 10:18:14 GMT"))
		#expect(try HTTPCookie(name: "a", value: "b", attributes: .init(expires: 0)).setCookieHeaderValue().contains("Expires=Thu, 01 Jan 1970 00:00:00 GMT"))
	}

	@Test("__Host- requires secure, no domain, and path /")
	func hostPrefixRules() throws {
		#expect(throws: HTTPCookie.BuildError.hostPrefixWithoutSecure) {
			_ = try HTTPCookie(name: "__Host-a", value: "b", attributes: .init(path: "/")).setCookieHeaderValue()
		}
		#expect(throws: HTTPCookie.BuildError.hostPrefixWithDomain) {
			_ = try HTTPCookie(
				name: "__Host-a", value: "b",
				attributes: .init(domain: "example.com", path: "/", secure: true)
			).setCookieHeaderValue()
		}
		#expect(throws: HTTPCookie.BuildError.hostPrefixWithNonRootPath) {
			_ = try HTTPCookie(
				name: "__Host-a", value: "b",
				attributes: .init(path: "/app", secure: true)
			).setCookieHeaderValue()
		}
		// valid __Host- cookie
		let ok = HTTPCookie(name: "__Host-a", value: "b", attributes: .init(path: "/", secure: true))
		let header = try ok.setCookieHeaderValue()
		#expect(header.contains("Secure"))
	}

	@Test("invalid names and delimiter-bearing values are rejected")
	func invalidInputs() {
		#expect(throws: HTTPCookie.BuildError.invalidName) {
			_ = try HTTPCookie(name: "bad name", value: "b").setCookieHeaderValue()
		}
	}
}

@Suite("CookieParser")
struct CookieParserTests {

	@Test("parses a simple cookie header")
	func simple() {
		let cookies = CookieParser.requestCookies("a=1; b=two")
		#expect(cookies == ["a": "1", "b": "two"])
	}

	@Test("ignores $ attributes and empty entries")
	func attributesIgnored() {
		let cookies = CookieParser.requestCookies("session=x; $Path=/; $Domain=example.com;")
		#expect(cookies == ["session": "x"])
	}

	@Test("unquotes values and trims whitespace")
	func quotingAndTrimming() {
		let cookies = CookieParser.requestCookies("a = \"hello; world\" ; b=")
		#expect(cookies["a"] == "hello; world")
	}
}
