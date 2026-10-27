import Foundation
import Testing
import NIOCore
import NIOEmbedded
import NIOHTTP1
import WebUI
import WebUIServer
import WebUIHost

// MARK: - HTTPLab
//
// a real NIO `EmbeddedChannel` carrying the real http codecs: a request goes in
// as wire bytes, comes out of `HTTPRequestDecoder` as typed parts, is handed to
// whatever responder the test names, and the answer is written back through
// `HTTPResponseEncoder` so the assertions read *bytes* — status line, headers,
// body — rather than a value the test could have fabricated.
//
// what it deliberately does not do: route. the framework's own router is not
// under test here (the host is a `Responder`, so it drops into one), and a lab
// that reused the server's private request builder would be testing that code a
// second time instead of the host.

struct HTTPLab {
	private let channel: EmbeddedChannel

	init() {
		channel = EmbeddedChannel(handlers: [
			ByteToMessageHandler(HTTPRequestDecoder()),
			HTTPResponseEncoder(),
		])
	}

	/// one request/response exchange over the channel.
	///
	/// `cookie` is planted as the `Cookie:` header — the wire form, so the
	/// resolver's header fallback and the parsed map are both exercised by the
	/// same test.
	func exchange(
		_ path: String,
		cookie: String? = nil,
		method: String = "GET",
		body: String = "",
		through responder: some Responder
	) async throws -> Wire {
		// keep-alive, not close: the lab reuses one channel for several
		// exchanges, and nio's decoder refuses further inbound bytes after a
		// `Connection: close`.
		var raw = "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\n"
		if let cookie {
			raw += "Cookie: \(CookieSessionResolver.defaultCookieName)=\(cookie)\r\n"
		}
		if !body.isEmpty {
			raw += "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: \(body.utf8.count)\r\n"
		}
		raw += "\r\n\(body)"

		var inbound = channel.allocator.buffer(capacity: raw.utf8.count)
		inbound.writeString(raw)
		try channel.writeInbound(inbound)

		var head: HTTPRequestHead?
		var bodyBytes: [UInt8] = []
		while let part = try channel.readInbound(as: HTTPServerRequestPart.self) {
			switch part {
			case .head(let value): head = value
			case .body(var buffer): bodyBytes.append(contentsOf: buffer.readBytes(length: buffer.readableBytes) ?? [])
			case .end: break
			}
		}
		let parsed = try #require(head)

		let response = try await responder.respond(to: request(from: parsed, body: bodyBytes))
		try write(response)

		return try parse(readOutboundBytes())
	}

	/// close the channel. the lab owns no threads, so this is all the cleanup
	/// there is.
	func finish() {
		_ = try? channel.finish()
	}

	// MARK: the two conversions

	private func request(from head: HTTPRequestHead, body: [UInt8]) -> HTTPRequest {
		let path: String
		var query: [String: String] = [:]
		if let mark = head.uri.firstIndex(of: "?") {
			path = String(head.uri[..<mark])
			for pair in head.uri[head.uri.index(after: mark)...].split(separator: "&") {
				let halves = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
				if halves.count == 2 {
					query[String(halves[0])] = String(halves[1])
				}
			}
		} else {
			path = head.uri
		}

		let cookies: [String: String]
		if let header = head.headers.first(name: "cookie") {
			cookies = CookieParser.requestCookies(header)
		} else {
			cookies = [:]
		}

		return HTTPRequest(
			// `.POST` is nio's, `.post` is the framework's: the ternary's
			// branches are inferred from the parameter type, so no name is
			// needed for either module and the two never collide.
			method: head.method == .POST ? .post : .get,
			path: path,
			query: query,
			headers: head.headers,
			cookies: cookies,
			body: body.isEmpty ? .none : .bytes(body)
		)
	}

	private func write(_ response: HTTPResponse) throws {
		var headers = HTTPHeaders()
		for (name, value) in response.headers {
			headers.add(name: name, value: value)
		}
		var payload: [UInt8] = []
		var contentType = "text/html; charset=utf-8"
		// the redirect body case carries the target, exactly as the server's own
		// encoder reads it: `Location` plus the body case's status.
		if case .redirect(let to, let status) = response.body {
			headers.add(name: "Location", value: to)
			_ = status
		}
		switch response.body {
		case .html(let markup):
			payload = Array(markup.html.utf8)
		case .text(let text):
			payload = Array(text.utf8)
			contentType = "text/plain; charset=utf-8"
		case .bytes(let bytes, let type):
			payload = bytes
			contentType = type
		case .empty, .redirect, .stream:
			break
		}
		if !payload.isEmpty {
			headers.add(name: "Content-Type", value: contentType)
			headers.add(name: "Content-Length", value: "\(payload.count)")
		}
		for cookie in response.cookies {
			if let value = try? cookie.setCookieHeaderValue() {
				headers.add(name: "Set-Cookie", value: value)
			}
		}
		let head = HTTPResponseHead(
			version: .http1_1,
			status: HTTPResponseStatus(statusCode: response.status.code),
			headers: headers
		)
		try channel.writeOutbound(HTTPServerResponsePart.head(head))
		if !payload.isEmpty {
			var buffer = channel.allocator.buffer(capacity: payload.count)
			buffer.writeBytes(payload)
			try channel.writeOutbound(HTTPServerResponsePart.body(.byteBuffer(buffer)))
		}
		try channel.writeOutbound(HTTPServerResponsePart.end(nil))
	}

	private func readOutboundBytes() -> [UInt8] {
		var bytes: [UInt8] = []
		while let next = try? channel.readOutbound(as: ByteBuffer.self) {
			var buffer = next
			bytes.append(contentsOf: buffer.readBytes(length: buffer.readableBytes) ?? [])
		}
		return bytes
	}

	// MARK: wire parsing

	/// the raw response, split into the three things a test asserts on.
	struct Wire {
		let status: Int
		/// the head, headers included, as it went on the wire.
		let head: String
		let body: String

		func header(_ name: String) -> String? {
			for line in head.split(separator: "\r\n") {
				let halves = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
				guard halves.count == 2, halves[0].lowercased() == name.lowercased() else { continue }
				return String(halves[1].drop(while: { $0 == " " }))
			}
			return nil
		}
	}

	private func parse(_ bytes: [UInt8]) throws -> Wire {
		let text = String(decoding: bytes, as: UTF8.self)
		let parts = text.components(separatedBy: "\r\n\r\n")
		let head = parts.first ?? ""
		let body = parts.count > 1 ? parts.dropFirst().joined(separator: "\r\n\r\n") : ""
		let statusLine = head.split(separator: "\r\n").first.map(String.init) ?? ""
		let fields = statusLine.split(separator: " ")
		let status = fields.count > 1 ? Int(fields[1]) ?? 0 : 0
		return Wire(status: status, head: head, body: body)
	}
}
