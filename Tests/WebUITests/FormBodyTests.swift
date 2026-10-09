import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import NIOHTTP1
@testable import WebUIServer

// MARK: - FormBodyTests
//
// plan w3.3: the typed request-body model. pinned here are the urlencoded
// decoder (`+`, percent-escapes, repeated keys), the typed getters, and the
// MANDATORY typed limits (`maxBodyBytes`, `maxMultipartParts`) with their
// named-limit errors — the bounded-parsing discipline an upload endpoint
// without a cap would otherwise throw away.

@Suite("form values")
struct FormValuesTests {

	@Test("the typed getters read a decoded urlencoded body")
	func typedGetters() {
		let reader = BodyReader()
		let values = reader.urlencoded(Array("n=42&flag=on&off=0&bad=2x".utf8))
		#expect(values["n"] == "42")
		#expect(values.string("n") == "42")
		#expect(values.int("n") == 42)
		#expect(values.bool("flag") == true)
		#expect(values.bool("off") == false)
		#expect(values.int("bad") == nil)
		#expect(values.bool("bad") == nil)
		#expect(values.int("off") == 0)
		#expect(values.bool("n") == nil)
		#expect(values.string("missing") == nil)
		#expect(values["missing"] == nil)
	}

	@Test("'+' decodes to a space and percent-escapes to their bytes")
	func plusAndEscapes() {
		let reader = BodyReader()
		let values = reader.urlencoded(Array("q=hello+world&tag=a%2Bb&name=J%C3%BCrgen".utf8))
		#expect(values.string("q") == "hello world")
		#expect(values.string("tag") == "a+b")
		#expect(values.string("name") == "Jürgen")
	}

	@Test("a repeated key keeps its first value and all() returns every one")
	func repeatedKeys() {
		let reader = BodyReader()
		let values = reader.urlencoded(Array("tag=a&tag=b&tag=c".utf8))
		#expect(values["tag"] == "a")
		#expect(values.string("tag") == "a")
		#expect(values.all("tag") == ["a", "b", "c"])
	}

	@Test("a field without '=' decodes as an empty value")
	func bareName() {
		let reader = BodyReader()
		let values = reader.urlencoded(Array("a&b=1".utf8))
		#expect(values.string("a") == "")
		#expect(values.string("b") == "1")
	}

	@Test("an empty body decodes to no fields")
	func emptyBody() {
		let reader = BodyReader()
		#expect(reader.urlencoded([]).isEmpty)
	}
}

@Suite("body limits (mandatory and typed)")
struct BodyLimitsTests {

	@Test("the default body cap is 1 << 20 bytes and the part cap is 64")
	func defaultLimits() {
		let reader = BodyReader()
		#expect(reader.maxBodyBytes == 1 << 20)
		#expect(reader.maxMultipartParts == 64)
	}

	@Test("over the body cap throws tooLarge naming the limit")
	func overBodyCap() throws {
		let reader = BodyReader(maxBodyBytes: 1024)
		#expect(throws: BodyParseError.tooLarge(limit: 1024, actual: 2048)) {
			_ = try reader.multipart([UInt8](repeating: 0x30, count: 2048), contentType: "multipart/form-data; boundary=x")
		}
	}

	@Test("a declared Content-Length over the cap is refused before any buffering")
	func declaredOverCap() {
		let reader = BodyReader(maxBodyBytes: 100)
		#expect(throws: BodyParseError.tooLarge(limit: 100, actual: 101)) {
			try reader.validateContentLength(101)
		}
		#expect(throws: Never.self) { try reader.validateContentLength(100) }
	}

	@Test("a Content-Length that lies is refused as a mismatch (smuggling guard)")
	func lyingContentLength() {
		let reader = BodyReader()
		#expect(throws: BodyParseError.lengthMismatch(declared: 99, actual: 3)) {
			try reader.validateLength(declared: 99, actual: 3)
		}
		#expect(throws: Never.self) { try reader.validateLength(declared: 12, actual: 12) }
		// chunked: no declared length to contradict the received bytes.
		#expect(throws: Never.self) { try reader.validateLength(declared: nil, actual: 12) }
	}

	@Test("the content-length header parses to an int, absent stays nil")
	func contentLengthHeader() {
		var headers = HTTPHeaders()
		headers.add(name: "Content-Length", value: "512")
		#expect(BodyReader.contentLength(headers) == 512)
		#expect(BodyReader.contentLength(HTTPHeaders()) == nil)
	}
}

// MARK: - over the wire

#if !os(Linux)

@Suite("form bodies over the wire", .serialized)
struct FormBodyWireTests {

	@Test("a urlencoded POST reaches the route as typed FormValues")
	func urlencodedRoundTrip() async throws {
		let pageRouter = Router {
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.post("/submit") { request in
				guard case .form(let values) = request.body else {
					return HTTPResponse(status: 400, body: .text("no form"))
				}
				let q = values.string("q") ?? "?"
				let tags = values.all("tag").joined(separator: ",")
				return HTTPResponse(body: .text("q=\(q)&tags=\(tags)"))
			}
		}
		try await withRouterServer(pageRouter, portBase: 33000) { port in
			var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/submit")!)
			request.httpMethod = "POST"
			request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
			request.httpBody = Data("q=hello+world&tag=a%2Bb&tag=c".utf8)
			let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
			let http = try #require(response as? HTTPURLResponse)
			#expect(http.statusCode == 200)
			#expect(String(decoding: data, as: UTF8.self) == "q=hello world&tags=a+b,c")
		}
	}

	@Test("a body over maxBodyBytes is 413 with a body naming the byte limit")
	func bodyTooLargeGets413() async throws {
		let pageRouter = Router {
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.post("/submit") { _ in HTTPResponse(body: .text("ok")) }
		}
		let config = WebUIServerConfig(host: "127.0.0.1", port: 0, maxBodyBytes: 512, maxMultipartParts: 64)
		try await withRouterServer(pageRouter, portBase: 33050, config: config) { port in
			var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/submit")!)
			request.httpMethod = "POST"
			request.httpBody = Data([UInt8](repeating: 0x61, count: 1024))
			let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
			let http = try #require(response as? HTTPURLResponse)
			#expect(http.statusCode == 413)
			let body = String(decoding: data, as: UTF8.self)
			#expect(body.contains("maxBodyBytes"), "got \(body)")
		}
	}

	@Test("a declared Content-Length over the cap is refused before buffering")
	func declaredOverCapGets413() async throws {
		let pageRouter = Router {
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.post("/submit") { _ in HTTPResponse(body: .text("ok")) }
		}
		let config = WebUIServerConfig(host: "127.0.0.1", port: 0, maxBodyBytes: 256, maxMultipartParts: 64)
		try await withRouterServer(pageRouter, portBase: 33100, config: config) { port in
			var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/submit")!)
			request.httpMethod = "POST"
			request.httpBody = Data([UInt8](repeating: 0x61, count: 512))
			let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
			let http = try #require(response as? HTTPURLResponse)
			#expect(http.statusCode == 413)
			#expect(String(decoding: data, as: UTF8.self).contains("maxBodyBytes"))
		}
	}
}

#endif
