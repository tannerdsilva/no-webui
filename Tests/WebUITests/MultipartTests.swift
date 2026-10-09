import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import WebUIServer

// MARK: - MultipartTests
//
// plan w3.3: the multipart/form-data decoder — a real boundary, binary file
// content, CRLF-bearing content, repeated fields, the part cap, and the
// malformed-boundary rejections. the wire round-trip at the end proves the
// server decodes a genuine browser-style body to the EXACT uploaded bytes.

/// build a multipart/form-data body for `parts` under `boundary`. a part is
/// (name, content, filename?) — a filename marks it as a file part.
private func multipartBody(
	boundary: String,
	parts: [(String, [UInt8], String?)]
) -> [UInt8] {
	var body: [UInt8] = []
	for (name, content, filename) in parts {
		body.append(contentsOf: Array("--\(boundary)\r\n".utf8))
		if let filename {
			body.append(contentsOf: Array("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
			body.append(contentsOf: Array("Content-Type: application/octet-stream\r\n".utf8))
		} else {
			body.append(contentsOf: Array("Content-Disposition: form-data; name=\"\(name)\"\r\n".utf8))
		}
		body.append(contentsOf: Array("\r\n".utf8))
		body.append(contentsOf: content)
		body.append(contentsOf: Array("\r\n".utf8))
	}
	body.append(contentsOf: Array("--\(boundary)--\r\n".utf8))
	return body
}

@Suite("multipart decoding")
struct MultipartTests {

	private let boundary = "----WebKitFormBoundaryX7y9"
	private let reader = BodyReader()

	@Test("a text field and a binary file with CRLF-bearing content decode exactly")
	func fieldAndBinaryFile() throws {
		// the file content carries CRLF and non-utf8 bytes: the CRLF must not
		// be mistaken for a boundary or eaten by header parsing.
		let binary: [UInt8] = [0x00, 0x01, 0xff, 0x0d, 0x0a, 0x0a, 0x0d, 0x41]
		let body = multipartBody(boundary: boundary, parts: [
			("title", Array("hello world".utf8), nil),
			("file", binary, "probe.bin"),
		])
		let form = try reader.multipart(body, contentType: "multipart/form-data; boundary=\(boundary)")
		#expect(form.values.string("title") == "hello world")
		let file = try #require(form.file("file"))
		#expect(file.field == "file")
		#expect(file.filename == "probe.bin")
		#expect(file.contentType == "application/octet-stream")
		#expect(file.bytes == binary)
		#expect(file.size == binary.count)
		#expect(form.files("file").count == 1)
	}

	@Test("repeated file parts under one field are all kept in order")
	func multipleFiles() throws {
		let a: [UInt8] = Array("aaa".utf8)
		let b: [UInt8] = Array("bbb".utf8)
		let body = multipartBody(boundary: boundary, parts: [
			("photo", a, "a.png"),
			("photo", b, "b.png"),
		])
		let form = try reader.multipart(body, contentType: "multipart/form-data; boundary=\(boundary)")
		let files = form.files("photo")
		#expect(files.count == 2)
		#expect(files[0].filename == "a.png")
		#expect(files[0].bytes == a)
		#expect(files[1].filename == "b.png")
		#expect(files[1].bytes == b)
		// a file field is not readable as a text value.
		#expect(form.file("missing") == nil)
	}

	@Test("a quoted boundary and extra content-type parameters still parse")
	func quotedBoundary() throws {
		let body = multipartBody(boundary: "abc123", parts: [("k", Array("v".utf8), nil)])
		let form = try reader.multipart(
			body,
			contentType: "multipart/form-data; charset=utf-8; boundary=\"abc123\""
		)
		#expect(form.values.string("k") == "v")
	}

	@Test("CRLF-bearing text field content survives verbatim")
	func fieldContentPreservesCRLF() throws {
		let content = Array("line one\r\nline two\r\n\r\nline four".utf8)
		let body = multipartBody(boundary: boundary, parts: [("note", content, nil)])
		let form = try reader.multipart(body, contentType: "multipart/form-data; boundary=\(boundary)")
		#expect(form.values.string("note") == "line one\r\nline two\r\n\r\nline four")
	}

	@Test("multipart field values are literal — never url-decoded")
	func multipartValuesAreLiteral() throws {
		let body = multipartBody(boundary: boundary, parts: [("k", Array("a+b%20c".utf8), nil)])
		let form = try reader.multipart(body, contentType: "multipart/form-data; boundary=\(boundary)")
		#expect(form.values.string("k") == "a+b%20c")
	}

	@Test("an empty file part still decodes to a zero-byte file")
	func emptyFile() throws {
		let body = multipartBody(boundary: boundary, parts: [("file", [], "empty.bin")])
		let form = try reader.multipart(body, contentType: "multipart/form-data; boundary=\(boundary)")
		let file = try #require(form.file("file"))
		#expect(file.size == 0)
		#expect(file.bytes.isEmpty)
	}

	@Test("more parts than maxMultipartParts throws tooManyParts naming the cap")
	func partCap() {
		let reader = BodyReader(maxMultipartParts: 2)
		let body = multipartBody(boundary: boundary, parts: [
			("a", Array("1".utf8), nil),
			("b", Array("2".utf8), nil),
			("c", Array("3".utf8), nil),
		])
		#expect(throws: BodyParseError.tooManyParts(limit: 2, actual: 3)) {
			_ = try reader.multipart(body, contentType: "multipart/form-data; boundary=\(boundary)")
		}
	}

	@Test("a multipart body without a boundary parameter is malformed")
	func noBoundaryParameter() {
		let body = multipartBody(boundary: boundary, parts: [("a", Array("1".utf8), nil)])
		expectMalformed {
			try reader.multipart(body, contentType: "multipart/form-data")
		}
	}

	@Test("a body with no boundary marker at all is malformed")
	func noBoundaryMarker() {
		let body = Array("this is not multipart at all".utf8)
		expectMalformed {
			try reader.multipart(body, contentType: "multipart/form-data; boundary=\(boundary)")
		}
	}

	@Test("a boundary not followed by CRLF or -- is malformed")
	func bareBoundary() {
		let body = Array("--\(boundary)NOTACRLF".utf8)
		expectMalformed {
			try reader.multipart(body, contentType: "multipart/form-data; boundary=\(boundary)")
		}
	}

	@Test("a part whose headers never end is malformed")
	func unterminatedHeaders() {
		var body = Array("--\(boundary)\r\nContent-Disposition: form-data; name=\"a\"\r\n".utf8)
		body.append(contentsOf: Array("--\(boundary)--\r\n".utf8))
		expectMalformed {
			try reader.multipart(body, contentType: "multipart/form-data; boundary=\(boundary)")
		}
	}

	@Test("a part whose content never reaches a boundary is malformed")
	func unterminatedContent() {
		var body = Array("--\(boundary)\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\ndata with no end".utf8)
		body.append(contentsOf: Array("--\(boundary)\r\n".utf8)) // next boundary, but the CLOSING one is missing
		expectMalformed {
			try reader.multipart(body, contentType: "multipart/form-data; boundary=\(boundary)")
		}
	}

	/// assert a multipart parse fails as malformed, whatever the reason text.
	private func expectMalformed(_ parse: () throws -> MultipartForm) {
		do {
			_ = try parse()
			Issue.record("expected a malformed multipart body")
		} catch let BodyParseError.malformedMultipart(reason) {
			#expect(!reason.isEmpty)
		} catch {
			Issue.record("expected .malformedMultipart, got \(error)")
		}
	}
}

#if !os(Linux)

@Suite("multipart over the wire", .serialized)
struct MultipartWireTests {

	@Test("a browser-style multipart POST delivers the exact uploaded bytes")
	func exactBytesRoundTrip() async throws {
		// binary + CRLF-bearing content, as a real file upload would carry.
		let payload: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0xff]
		let boundary = "----WebKitTestBoundaryAbC"
		let body = multipartBody(boundary: boundary, parts: [
			("caption", Array("a caption\r\nwith crlf".utf8), nil),
			("file", payload, "image.png"),
		])

		let pageRouter = Router {
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.post("/upload") { request in
				guard case .multipart(let form) = request.body,
				      let file = form.file("file") else {
					return HTTPResponse(status: 400, body: .text("no file"))
				}
				// the caption field parsed alongside the file: its CRLF content
				// is asserted off the wire (a header cannot carry CRLF).
				guard form.values.string("caption") == "a caption\r\nwith crlf" else {
					return HTTPResponse(status: 400, body: .text("caption lost"))
				}
				return HTTPResponse(
					status: .ok,
					headers: [
						"X-Upload-Field": file.field,
						"X-Upload-Name": file.filename,
						"X-Upload-Type": file.contentType,
					],
					body: .bytes(file.bytes, contentType: "application/octet-stream")
				)
			}
		}
		try await withRouterServer(pageRouter, portBase: 33200) { port in
			var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/upload")!)
			request.httpMethod = "POST"
			request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
			request.httpBody = Data(body)
			let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
			let http = try #require(response as? HTTPURLResponse)
			#expect(http.statusCode == 200, "got \(String(decoding: data, as: UTF8.self))")
			// the response body IS the uploaded file's bytes — exact match.
			#expect(Array(data) == payload)
			#expect(http.value(forHTTPHeaderField: "X-Upload-Field") == "file")
			#expect(http.value(forHTTPHeaderField: "X-Upload-Name") == "image.png")
			#expect(http.value(forHTTPHeaderField: "X-Upload-Type") == "application/octet-stream")
		}
	}

	@Test("more parts than the configured cap is 422 naming the part limit")
	func partCapGets422() async throws {
		let boundary = "boundary-1"
		let body = multipartBody(boundary: boundary, parts: [
			("a", Array("1".utf8), nil),
			("b", Array("2".utf8), nil),
			("c", Array("3".utf8), nil),
		])
		let pageRouter = Router {
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.post("/upload") { _ in HTTPResponse(body: .text("ok")) }
		}
		let config = WebUIServerConfig(host: "127.0.0.1", port: 0, maxBodyBytes: 1 << 20, maxMultipartParts: 2)
		try await withRouterServer(pageRouter, portBase: 33250, config: config) { port in
			var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/upload")!)
			request.httpMethod = "POST"
			request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
			request.httpBody = Data(body)
			let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
			let http = try #require(response as? HTTPURLResponse)
			#expect(http.statusCode == 422)
			let text = String(decoding: data, as: UTF8.self)
			#expect(text.contains("maxMultipartParts"), "got \(text)")
		}
	}
}

#endif
