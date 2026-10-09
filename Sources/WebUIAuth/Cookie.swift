import WebUISharedCore

// MARK: - deprecated re-export shims
//
// `HTTPCookie` and `CookieParser` moved up to `WebUISharedCore` (plan w3.1)
// so the web server can set a cookie it can parse without depending on
// `WebUIAuth`. the shared types are what everything builds on now; these
// aliases only keep existing hosts and tests compiling.
//
// the deprecated `HTTPCookie.SameSite` rides along with the alias — the
// nested enum is reached through the (shared) `HTTPCookie` type.

/// deprecated — `HTTPCookie` now lives in `WebUISharedCore`, where the
/// server can reach it.
@available(*, deprecated, renamed: "WebUISharedCore.HTTPCookie")
public typealias HTTPCookie = WebUISharedCore.HTTPCookie

/// deprecated — `CookieParser` moved up with `HTTPCookie`.
@available(*, deprecated, renamed: "WebUISharedCore.CookieParser")
public typealias CookieParser = WebUISharedCore.CookieParser
