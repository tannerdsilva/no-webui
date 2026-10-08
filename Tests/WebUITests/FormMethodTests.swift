import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import WebUI
import WebUIServer

// the form method
// (`.hermes/plans/2026-10-08_151549_GENERAL_WEB_CAPABILITY.md`, W0.4; defect C5).
//
// `Form`'s default was `method: "post"` and `WebUIServer` answers every non-GET
// with 405 — an empty-bodied one until this task. so the default form a welder
// writes is broken against the framework's own server, and the failure is a bare
// status code with nothing anywhere to explain it.
//
// the default stays (changing it would break the rendered bytes of every page
// that relies on it); the method becomes typed, and the mismatch announces
// itself once, at render time, where the welder can act.

@Suite("form method")
struct FormMethodTests {

    @Test("the three html methods keep their raw spellings")
    func rawValues() {
        #expect(FormMethod.get.rawValue == "get")
        #expect(FormMethod.post.rawValue == "post")
        #expect(FormMethod.dialog.rawValue == "dialog")
        #expect(FormMethod.allCases.count == 3)
    }

    @Test("the typed default is .post and emits exactly what the string default did")
    func typedDefaultMatchesLegacyBytes() {
        let typed = Form(action: "/go") { Text("x") }.render()
        let legacy = Form(action: "/go", method: "post") { Text("x") }.render()
        #expect(typed == legacy)
        #expect(typed.contains(" method=\"post\""))
    }

    @Test("every typed case emits its raw value")
    func everyCaseEmits() {
        for method in FormMethod.allCases {
            let html = Form(action: "/go", method: method) { Text("x") }.render()
            #expect(html.contains(" method=\"\(method.rawValue)\""), "got \(html)")
        }
    }

    @Test("the raw-string spelling still emits verbatim, escaped")
    func legacyStringIsVerbatim() {
        // an unknown method is not silently rewritten to post: the legacy
        // initializer's contract is byte fidelity.
        let html = Form(action: "/go", method: "put") { Text("x") }.render()
        #expect(html.contains(" method=\"put\""), "got \(html)")
    }

    @Test("a hostile method string is escaped, never emitted raw")
    func hostileMethodIsEscaped() {
        let html = Form(method: "post\" onsubmit=\"alert(1)") { Text("x") }.render()
        #expect(!html.contains(" onsubmit=\"alert(1)\""), "attribute injection: \(html)")
        #expect(html.contains("&quot;"), "got \(html)")
    }

    @Test("the action still routes through sanitizeURL")
    func actionSanitized() {
        #expect(Form(action: "javascript:alert(1)") { Text("x") }.render().contains("action=\"\""))
        #expect(Form(action: "/go") { Text("x") }.render().contains("action=\"/go\""))
    }
}

#if !os(Linux)

/// the server half: the 405 must say what happened.
@Suite("method-not-allowed honesty", .serialized)
struct MethodNotAllowedTests {

    @Test("a POST gets 405, an Allow header, and a body naming the cause")
    func postSaysWhy() async throws {
        try await withServer(
            requestRender: { _ in "<!DOCTYPE html><html><body>x</body></html>" },
            router: EventRouter(),
            assets: [],
            portBase: 29_000
        ) { port in
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
            request.httpMethod = "POST"
            request.httpBody = Data("field=value".utf8)

            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            let http = try #require(response as? HTTPURLResponse)

            #expect(http.statusCode == 405)
            // RFC 9110 requires Allow on a 405; the reference servers omitted it.
            #expect(http.value(forHTTPHeaderField: "Allow") == "GET")

            let body = String(decoding: data, as: UTF8.self)
            #expect(body.contains("accepts GET only"), "got \(body)")
            #expect(body.contains("no JS interception"), "got \(body)")
            #expect(body.contains("Documentation/API.md#forms"), "got \(body)")
            // the status line and the cause must not disagree about the length.
            #expect(http.value(forHTTPHeaderField: "Content-Length") == "\(data.count)")
        }
    }
}

#endif