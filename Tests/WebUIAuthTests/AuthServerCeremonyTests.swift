import Foundation
import Testing
import WebUI

#if os(Linux)
import Glibc
#else
import Darwin
#endif

// MARK: - Auth server ceremony tests

// end-to-end ceremony tests for the `WebUIAuthExample` server. each test
// boots the real binary on an ephemeral port (via `--port`), then drives the
// login / websocket / logout ceremony over raw POSIX sockets — no scripts, no
// extra dependencies, and no shared state between tests (each test gets a
// fresh server).
//
// the binary must exist first: run `swift build` before `swift test`. the
// test locates it under `.build/` (any triple layout) and fails with a clear
// message when it is missing. the suite is `.serialized` so ephemeral ports
// cannot collide.

@Suite(.serialized)
struct AuthServerCeremonyTests {

	// MARK: ceremony

	@Test("login page carries the hardening headers and a csrf token")
	func loginPageHeaders() async throws {
		try await withServer { server in
			let page = try httpRequest(port: server.port, path: "/login")
			#expect(page.status == 200)
			#expect(page.header("cache-control") == "no-store")
			#expect(page.header("x-content-type-options") == "nosniff")
			#expect(page.header("x-frame-options") == "SAMEORIGIN")
			let token = page.csrfToken()
			#expect(token != nil)
			#expect(token?.isEmpty == false)
		}
	}

	@Test("a login csrf token is consumed on the first submit")
	func loginTokenIsSingleUse() async throws {
		try await withServer { server in
			let token = try #require(try httpRequest(port: server.port, path: "/login").csrfToken())
			let first = try postLoginAttempt(server: server, token: token, password: "wrong")
			#expect(first.status == 200)
			#expect(first.body.contains("invalid credentials"))
			// the same token, replayed, is rejected before any KDF work.
			let replay = try postLoginAttempt(server: server, token: token, password: "wrong")
			#expect(replay.status == 200)
			#expect(replay.body.contains("invalid or expired form token"))
		}
	}

	@Test("wrong-password floods are throttled to 429")
	func throttleReturns429() async throws {
		try await withServer { server in
			var sawLimit = false
			for _ in 0..<30 {
				let page = try httpRequest(port: server.port, path: "/login")
				guard let token = page.csrfToken() else { continue }
				let attempt = try postLoginAttempt(server: server, token: token, password: "wrong")
				if attempt.status == 429 {
					sawLimit = true
					#expect(attempt.header("retry-after") == "60")
					break
				}
			}
			#expect(sawLimit)
		}
	}

	@Test("login issues a session cookie and logout closes the live socket")
	func fullCeremony() async throws {
		try await withServer { server in
			// the ws upgrade is refused without a session, even with a bogus cookie.
			let noCookie = try wsUpgrade(port: server.port, cookie: nil)
			#expect(noCookie.code == 403)
			let bogus = try wsUpgrade(port: server.port, cookie: "auth=nonsense")
			#expect(bogus.code == 403)

			// login -> 303 + cookie.
			let cookie = try #require(try logIn(server: server))
			let cookieHeader = "auth=\(cookie)"

			// dashboard under the session carries no-store and a logout token.
			let dashboard = try httpRequest(port: server.port, path: "/", headers: [("cookie", cookieHeader)])
			#expect(dashboard.status == 200)
			#expect(dashboard.body.contains("Member Dashboard"))
			#expect(dashboard.header("cache-control") == "no-store")
			let logoutToken = try #require(dashboard.csrfToken())

			// a valid session upgrades to 101.
			let upgraded = try wsUpgrade(port: server.port, cookie: cookieHeader)
			#expect(upgraded.code == 101)
			let socket = try #require(upgraded.socket)

			// logout -> 303 to /login, and the live socket is closed by the server.
			let logout = try postLogout(server: server, token: logoutToken, cookie: cookieHeader)
			#expect(logout.status == 303)
			#expect(logout.header("location") == "/login")
			#expect(socket.waitForClose(timeout: 3))

			// the stale cookie can no longer upgrade.
			let stale = try wsUpgrade(port: server.port, cookie: cookieHeader)
			#expect(stale.code == 403)
		}
	}

	// MARK: harness plumbing

	private func withServer(_ body: (AuthServer) async throws -> Void) async throws {
		let server = try AuthServer.launch()
		defer { server.stop() }
		try await server.waitUntilReady()
		try await body(server)
	}

	private func logIn(server: AuthServer) throws -> String? {
		let page = try httpRequest(port: server.port, path: "/login")
		guard let token = page.csrfToken() else { return nil }
		let response = try postForm(
			port: server.port, path: "/login",
			fields: ["username": "admin", "password": "password"], token: token)
		guard response.status == 303, response.header("location") == "/" else { return nil }
		guard let setCookie = response.header("set-cookie") else { return nil }
		// `auth=<value>; Max-Age=...; Path=/; HttpOnly; SameSite=Lax`
		let first = setCookie.split(separator: ";").first.map(String.init) ?? setCookie
		let parts = first.split(separator: "=", maxSplits: 1).map(String.init)
		guard parts.count == 2, parts[0] == "auth" else { return nil }
		return parts[1]
	}

	private func postLoginAttempt(server: AuthServer, token: String, password: String) throws -> HTTPResponse {
		try postForm(
			port: server.port, path: "/login",
			fields: ["username": "admin", "password": password], token: token)
	}

	private func postLogout(server: AuthServer, token: String, cookie: String) throws -> HTTPResponse {
		try postForm(
			port: server.port, path: "/logout",
			fields: [:], token: token, headers: [("cookie", cookie)])
	}
}

// MARK: - Response model

struct HTTPResponse {
	let status: Int
	let headers: [String: String]
	let body: String

	func header(_ name: String) -> String? {
		headers[name.lowercased()]
	}

	/// the login/logout form's synchronizer token, when rendered.
	func csrfToken() -> String? {
		let pattern = /name="_csrf" value="([^"]+)"/
		guard let match = body.firstMatch(of: pattern) else { return nil }
		return String(match.1)
	}
}

// MARK: - Minimal HTTP over a raw socket

private func httpRequest(
	port: Int,
	method: String = "GET",
	path: String,
	headers: [(String, String)] = [],
	body: String? = nil
) throws -> HTTPResponse {
	var head = "\(method) \(path) HTTP/1.1\r\n"
	head += "Host: 127.0.0.1:\(port)\r\n"
	head += "Connection: close\r\n"
	var allHeaders = headers
	if let body {
		allHeaders.append(("Content-Length", "\(body.utf8.count)"))
	}
	for (name, value) in allHeaders {
		head += "\(name): \(value)\r\n"
	}
	head += "\r\n"

	let socket = try RawSocket(host: "127.0.0.1", port: port)
	defer { socket.closeSocket() }
	try socket.write(head + (body ?? ""))

	guard let statusLine = try socket.readLine() else {
		throw CeremonyError.badResponse("no status line for \(method) \(path)")
	}
	// `HTTP/1.1 200 OK`
	let statusParts = statusLine.split(separator: " ")
	let statusCode = Int(statusParts.count > 1 ? statusParts[1] : "") ?? 0

	var headers: [String: String] = [:]
	while let line = try socket.readLine(), !line.isEmpty {
		if let colon = line.firstIndex(of: ":") {
			let key = String(line[..<colon]).lowercased()
			let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
			headers[key] = value
		}
	}

	let bodyText: String
	if let contentLength = headers["content-length"].flatMap(Int.init) {
		let data = try socket.readExactly(contentLength)
		bodyText = String(decoding: data, as: UTF8.self)
	} else {
		// no content-length (never the case for this server) — read to close.
		bodyText = String(decoding: try socket.readToEnd(), as: UTF8.self)
	}
	return HTTPResponse(status: statusCode, headers: headers, body: bodyText)
}

private func postForm(
	port: Int,
	path: String,
	fields: [String: String],
	token: String,
	headers: [(String, String)] = []
) throws -> HTTPResponse {
	var merged = fields
	merged["_csrf"] = token
	let body = merged
		.map { "\($0.key)=\(urlEncoded($0.value))" }
		.joined(separator: "&")
	return try httpRequest(
		port: port, method: "POST", path: path,
		headers: headers + [("content-type", "application/x-www-form-urlencoded")],
		body: body)
}

private func urlEncoded(_ string: String) -> String {
	// the demo values (credentials, csrf tokens) are all url-safe already;
	// encode defensively for arbitrary inputs.
	string.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? string
}

// MARK: - WebSocket upgrade probe

private struct UpgradeResult {
	let code: Int
	/// the live socket for a successful 101 (used by the teardown check).
	let socket: RawSocket?
}

/// a raw websocket handshake (no framing) — just enough to verify the
/// upgrade gate: 403 for refusals, 101 + a live socket for accepted upgrades.
private func wsUpgrade(port: Int, cookie: String?) throws -> UpgradeResult {
	let key = Base64.encode((0..<16).map { _ in UInt8.random(in: 0...255) })
	var request = "GET /ws HTTP/1.1\r\n"
	request += "Host: 127.0.0.1:\(port)\r\n"
	request += "Connection: Upgrade\r\n"
	request += "Upgrade: websocket\r\n"
	request += "Sec-WebSocket-Version: 13\r\n"
	request += "Sec-WebSocket-Key: \(key)\r\n"
	request += "Origin: http://127.0.0.1:\(port)\r\n"
	if let cookie {
		request += "Cookie: \(cookie)\r\n"
	}
	request += "\r\n"

	let socket = try RawSocket(host: "127.0.0.1", port: port)
	try socket.write(request)
	guard let statusLine = try socket.readLine() else {
		throw CeremonyError.badResponse("no status line for ws upgrade")
	}
	let parts = statusLine.split(separator: " ")
	let code = Int(parts.count > 1 ? parts[1] : "") ?? 0
	// drain the handshake response headers to the blank line.
	var line = try socket.readLine()
	while let current = line, !current.isEmpty {
		line = try socket.readLine()
	}
	if code == 101 {
		return UpgradeResult(code: code, socket: socket)
	}
	socket.closeSocket()
	return UpgradeResult(code: code, socket: nil)
}

// MARK: - Raw POSIX socket

enum CeremonyError: Error, CustomStringConvertible {
	case badResponse(String)
	var description: String {
		switch self {
		case .badResponse(let message): "ceremony probe: \(message)"
		}
	}
}

struct ErrnoError: Error, CustomStringConvertible {
	let code: Int32
	let op: String
	init(_ code: Int32, _ op: String) {
		self.code = code
		self.op = op
	}
	var description: String { "\(op): errno \(code)" }
}

/// a buffered blocking POSIX client socket with short read timeouts — plenty
/// for the ceremony probes' bounded exchanges. foundation/FoundationNetworking
/// would smuggle in redirect handling and cookie jars we want to observe
/// manually, so the probes speak tcp directly.
final class RawSocket {
	private var fd: Int32
	private var buffer: [UInt8] = []
	private var consumed = 0
	private let readTimeout: TimeInterval

	/// ignore SIGPIPE once — a raw `send` to a peer that just closed would
	/// otherwise kill the whole test runner with the default disposition.
	private static let ignoreSIGPIPE: () = {
		_ = signal(SIGPIPE, SIG_IGN)
	}()

	init(host: String, port: Int, readTimeout: TimeInterval = 5) throws {
		_ = Self.ignoreSIGPIPE
		let descriptor = socket(AF_INET, SOCK_STREAM, 0)
		guard descriptor >= 0 else { throw ErrnoError(errno, "socket") }
		fd = descriptor
		self.readTimeout = readTimeout

		var addr = sockaddr_in()
		addr.sin_family = sa_family_t(AF_INET)
		addr.sin_port = in_port_t(port).bigEndian
		#if !os(Linux)
		addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
		#endif
		guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
			close(descriptor)
			throw ErrnoError(EINVAL, "inet_pton")
		}
		do {
			// SO_RCVTIMEO requires tv_usec < 1_000_000 (EDOM otherwise, and the
			// timeout then silently never applies — a blocking recv hangs).
			var timeval = timeval()
			let secondsPart = Int(readTimeout)
			timeval.tv_sec = secondsPart
			let microsPart = Int((readTimeout - Double(secondsPart)) * 1_000_000)
			#if os(Linux)
			timeval.tv_usec = microsPart
			#else
			timeval.tv_usec = Int32(microsPart)
			#endif
			_ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeval, socklen_t(MemoryLayout<timeval>.size))
		}
		let status = withUnsafePointer(to: &addr) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		guard status == 0 else {
			let error = errno
			close(descriptor)
			throw ErrnoError(error, "connect")
		}
	}

	deinit {
		closeSocket()
	}

	func closeSocket() {
		if fd >= 0 {
			close(fd)
			fd = -1
		}
	}

	func write(_ string: String) throws {
		// send takes a pointer into the array's contiguous storage —
		// `&bytes[offset]` would pass a one-element copy and put garbage on
		// the wire (verified: the first byte followed by stack noise → the
		// server replies 400).
		let bytes = Array(string.utf8)
		var offset = 0
		while offset < bytes.count {
			let written = bytes.withUnsafeBytes { raw -> Int in
				send(fd, raw.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
			}
			if written < 0 {
				if errno == EINTR { continue }
				throw ErrnoError(errno, "send")
			}
			offset += written
		}
	}

	/// one `\n`-terminated line (trailing `\r` stripped), or nil on EOF.
	func readLine() throws -> String? {
		while true {
			if let newline = buffer[consumed...].firstIndex(of: 0x0A) {
				let line = String(decoding: buffer[consumed..<newline], as: UTF8.self)
				consumed = newline + 1
				return line.hasSuffix("\r") ? String(line.dropLast()) : line
			}
			guard try fillBuffer() else { return nil }
		}
	}

	func readExactly(_ count: Int) throws -> [UInt8] {
		var out: [UInt8] = []
		out.reserveCapacity(count)
		while out.count < count {
			if consumed < buffer.count {
				let take = min(count - out.count, buffer.count - consumed)
				out.append(contentsOf: buffer[consumed..<(consumed + take)])
				consumed += take
			} else if !(try fillBuffer()) {
				break
			}
		}
		return out
	}

	func readToEnd() throws -> [UInt8] {
		var out: [UInt8] = []
		while true {
			if consumed < buffer.count {
				out.append(contentsOf: buffer[consumed...])
				consumed = buffer.count
			} else if !(try fillBuffer()) {
				return out
			}
		}
	}

	/// true when the peer closes the connection (FIN or RST) within `timeout`.
	func waitForClose(timeout: TimeInterval) -> Bool {
		var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
		var remainingMs = Int(timeout * 1000)
		var scratch = [UInt8](repeating: 0, count: 256)
		while remainingMs > 0 {
			let result = poll(&pfd, 1, Int32(min(remainingMs, 250)))
			if result < 0 {
				if errno == EINTR { continue }
				return false
			}
			if result == 0 {
				remainingMs -= 250
				continue
			}
			let received = scratch.withUnsafeMutableBytes { recv(fd, $0.baseAddress, 256, 0) }
			if received == 0 { return true }
			if received < 0 {
				let error = errno
				if error == ECONNRESET { return true }
				if error == EAGAIN || error == EWOULDBLOCK { continue }
				return false
			}
			// payload drained; keep polling for the FIN.
		}
		return false
	}

	// MARK: buffered reads

	static func canConnect(host: String, port: Int) -> Bool {
		(try? RawSocket(host: host, port: port)) != nil
	}

	private func fillBuffer() throws -> Bool {
		if consumed > 0 {
			if consumed >= buffer.count {
				buffer.removeAll(keepingCapacity: true)
				consumed = 0
			} else {
				buffer.removeFirst(consumed)
				consumed = 0
			}
		}
		var chunk = [UInt8](repeating: 0, count: 2048)
		let received = chunk.withUnsafeMutableBytes { recv(fd, $0.baseAddress, 2048, 0) }
		if received == 0 { return false }
		if received < 0 {
			if errno == EINTR { return try fillBuffer() }
			throw ErrnoError(errno, "recv")
		}
		buffer.append(contentsOf: chunk[0..<received])
		return true
	}
}

// MARK: - Auth server harness

/// locates the built `WebUIAuthExample` binary and boots one instance on an
/// ephemeral port for each test.
final class AuthServer {
	let process: Process?
	let port: Int

	private init(process: Process?, port: Int) {
		self.process = process
		self.port = port
	}

	static func launch() throws -> AuthServer {
		let binary = try locateBinary()
		let port = try selectFreePort()
		let process = Process()
		process.executableURL = binary
		process.arguments = ["--port", "\(port)"]
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		try process.run()
		return AuthServer(process: process, port: port)
	}

	func stop() {
		if let process {
			process.terminate()
		}
	}

	func waitUntilReady(timeout: Duration = .seconds(8)) async throws {
		let deadline = ContinuousClock.now + timeout
		while ContinuousClock.now < deadline {
			if RawSocket.canConnect(host: "127.0.0.1", port: port) {
				return
			}
			try await Task.sleep(for: .milliseconds(100))
		}
		throw AuthServerError.notReady(port: port)
	}

	// MARK: discovery
	private static func packageRoot() -> URL {
		var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		url.deleteLastPathComponent() // Tests
		url.deleteLastPathComponent() // package root
		return url
	}

	private static func locateBinary() throws -> URL {
		let build = packageRoot().appendingPathComponent(".build")
		let fileManager = FileManager.default
		let fast = build.appendingPathComponent("debug/WebUIAuthExample")
		if fileManager.isExecutableFile(atPath: fast.path) {
			return fast
		}
		let subdirs = (try? fileManager.contentsOfDirectory(at: build, includingPropertiesForKeys: nil)) ?? []
		for sub in subdirs where sub.hasDirectoryPath {
			let candidate = sub.appendingPathComponent("debug/WebUIAuthExample")
			if fileManager.isExecutableFile(atPath: candidate.path) {
				return candidate
			}
		}
		throw AuthServerError.binaryMissing
	}

	/// ask the OS for a free ephemeral port, then release it — the suite is
	/// serialized so the race window is effectively ours.
	private static func selectFreePort() throws -> Int {
		let descriptor = socket(AF_INET, SOCK_STREAM, 0)
		guard descriptor >= 0 else { throw ErrnoError(errno, "socket") }
		defer { close(descriptor) }
		var addr = sockaddr_in()
		addr.sin_family = sa_family_t(AF_INET)
		addr.sin_port = 0 // ephemeral
		#if !os(Linux)
		addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
		#endif
		let status = withUnsafePointer(to: &addr) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		guard status == 0 else { throw ErrnoError(errno, "bind(ephemeral)") }
		var assigned = sockaddr_in()
		var assignedLen = socklen_t(MemoryLayout<sockaddr_in>.size)
		let nameStatus = withUnsafeMutablePointer(to: &assigned) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
				getsockname(descriptor, sockaddrPointer, &assignedLen)
			}
		}
		guard nameStatus == 0 else {
			throw ErrnoError(errno, "getsockname(ephemeral)")
		}
		return Int(assigned.sin_port.bigEndian)
	}
}

enum AuthServerError: Error, CustomStringConvertible {
	case binaryMissing
	case notReady(port: Int)

	var description: String {
		switch self {
		case .binaryMissing:
			"WebUIAuthExample binary not found under .build/ — run `swift build` first"
		case .notReady(let port):
			"auth server did not become ready on port \(port)"
		}
	}
}
