import WebUIServer

// MARK: - SessionCookie

/// the http cookie type, spelled once for this module.
///
/// `WebUIAuth` still carries a deprecated `HTTPCookie` typealias (the shim that
/// kept pre-move hosts compiling), and `WebUIServer` re-exports the shared
/// `HTTPCookie` those aliases point at. a file that imports both — every file
/// here that names a cookie — therefore cannot say `HTTPCookie` unqualified:
/// two modules export the name, and the compiler is right to refuse to pick.
///
/// this alias is the single place that is resolved (this file imports only
/// `WebUIServer`), and it is the name the host's own surface uses. it is not a
/// new type: `SessionCookie` and `WebUISharedCore.HTTPCookie` are one type, so
/// `HTTPResponse.cookies` takes one without a conversion.
public typealias SessionCookie = HTTPCookie
