import Testing
import WebUISharedCore

@testable import WebUIAuth

// MARK: - Cookie shim identity
//
// `WebUIAuth` now carries deprecated typealias shims for the cookie types
// that moved up to `WebUISharedCore` (plan w3.1). i keep this suite in its
// own file because the unqualified name `HTTPCookie` is ambiguous in a file
// that imports both modules — every reference here is module-qualified, so
// the two candidates never collide (and never shadow foundation's own).

@Suite("Cookie shims")
struct CookieShimTests {

	@Test("the deprecated webuiauth shims are the moved shared types")
	func shimsResolveToSharedTypes() {
		// the aliases must not be copies: the server's `HTTPResponse.cookies`
		// and `WebUIAuth`'s cookie building have to be the same type.
		#expect(WebUIAuth.HTTPCookie.self == WebUISharedCore.HTTPCookie.self)
		#expect(WebUIAuth.CookieParser.self == WebUISharedCore.CookieParser.self)
	}

	@Test("the shims still build and parse through the webuiauth module")
	func shimsBehave() throws {
		// full flag surface from the alias, through the shared implementation.
		let cookie = try WebUIAuth.HTTPCookie(
			name: "auth",
			value: "abc123",
			attributes: .init(maxAge: 3600, httpOnly: true, sameSite: .lax)
		).setCookieHeaderValue()
		#expect(cookie.hasPrefix("auth=abc123"))
		#expect(cookie.contains("HttpOnly"))
		#expect(WebUIAuth.CookieParser.requestCookies("a=1; b=two") == ["a": "1", "b": "two"])
		#expect(WebUIAuth.CookieParser.setCookie("s=x; SameSite=Strict")?.attributes.sameSite == .strict)
	}
}
