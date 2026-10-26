import Foundation
import ServiceLifecycle
import Synchronization
import WebUI
import WebUIDesignSystem
import WebUIServer

// MARK: - shared state
//
// the wave-3 acceptance demo state: everything a POST mutates lands here, so
// the dashboard re-render after the redirect proves what the previous action
// did. `Mutex`-backed and `Sendable`, matching the house lock discipline.

final class DemoState: Sendable {
	/// one persisted upload's receipt, rendered on the dashboard as proof.
	struct UploadReceipt: Sendable {
		let filename: String
		let bytes: Int
		let digest: String
		let path: String
	}

	private struct Values {
		var count = 0
		var signIn: String?
		var upload: UploadReceipt?
		var uploadError: String?
	}
	private let values = Mutex(Values())

	func increment() -> Int { values.withLock { $0.count += 1; return $0.count } }
	func decrement() -> Int { values.withLock { $0.count -= 1; return $0.count } }
	var count: Int { values.withLock { $0.count } }

	func signIn(_ name: String) { values.withLock { $0.signIn = name } }
	var signInName: String? { values.withLock { $0.signIn } }

	func recordUpload(_ receipt: UploadReceipt) {
		values.withLock { $0.upload = receipt; $0.uploadError = nil }
	}
	func recordUploadError(_ message: String) { values.withLock { $0.uploadError = message } }
	var uploadReceipt: UploadReceipt? { values.withLock { $0.upload } }
	var uploadError: String? { values.withLock { $0.uploadError } }
}

// MARK: - counter fragment

/// the live counter's display element, replaced in place by the click handler.
func countMarkup(_ n: Int) -> String {
	"<span id=\"dash-count\" class=\"demo-count\" role=\"status\">count: \(n)</span>"
}

// MARK: - upload persistence

/// persist one uploaded file under the system temp dir and return the receipt
/// that proves it: the exact byte count, the sha-256 of those bytes, and the
/// on-disk path. (plan w3.3 — the response reports what was stored.)
func persistUpload(_ file: UploadedFile) throws -> DemoState.UploadReceipt {
	let dir = FileManager.default.temporaryDirectory
		.appendingPathComponent("webui-acceptance-demo", isDirectory: true)
	try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
	let filename = sanitizedFilename(file.filename)
	let url = dir.appendingPathComponent(filename, isDirectory: false)
	try Data(file.bytes).write(to: url, options: .atomic)
	return DemoState.UploadReceipt(
		filename: filename,
		bytes: file.bytes.count,
		digest: SHA256.hex(file.bytes),
		path: url.path
	)
}

/// the client controls the filename; keep only path-safe characters so a
/// traversal or absolute path can never escape the demo's temp dir.
func sanitizedFilename(_ raw: String) -> String {
	let safe = raw.map { ch -> Character in
		if ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-" { return ch }
		return "_"
	}
	let trimmed = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: "."))
	return trimmed.isEmpty ? "upload.bin" : trimmed
}

// MARK: - the sse producer
//
/// three events, spaced so a client observes three distinct sse dispatch: two
/// `tick`s and a final `done`. the stream finishes itself after the third, so
/// the connection closes cleanly and the browser's EventSource ends.
func tickStream() -> AsyncStream<SSEEvent> {
	AsyncStream { continuation in
		let task = Task {
			let payloads = ["tick-1", "tick-2", "done-3"]
			for (index, data) in payloads.enumerated() {
				try? await Task.sleep(for: .milliseconds(150))
				continuation.yield(SSEEvent(
					event: index == payloads.count - 1 ? "done" : "tick",
					data: data
				))
			}
			continuation.finish()
		}
		continuation.onTermination = { _ in task.cancel() }
	}
}

// MARK: - route handlers

func handleLogin(request: HTTPRequest, state: DemoState) -> HTTPResponse {
	var name = ""
	if case .form(let values) = request.body {
		name = values.string("name") ?? ""
	}
	state.signIn(name.isEmpty ? "anonymous" : name)
	// 303 see-other: the browser re-GETs "/" and the dashboard renders the
	// proof (the parsed form values) on the fresh page.
	return HTTPResponse(body: .redirect(to: "/"))
}

func handleUpload(request: HTTPRequest, state: DemoState) -> HTTPResponse {
	if case .multipart(let form) = request.body {
		if let file = form.file("file") {
			do {
				state.recordUpload(try persistUpload(file))
			} catch {
				state.recordUploadError("persist failed: \(error)")
			}
		} else {
			state.recordUploadError("no file part under the name \"file\"")
		}
	} else {
		let contentType = request.headers.first(name: "Content-Type") ?? "?"
		state.recordUploadError("expected multipart/form-data, got \(contentType)")
	}
	return HTTPResponse(body: .redirect(to: "/"))
}

// MARK: - the dashboard document (.page)

struct DashboardDocument: View {
	let state: DemoState
	/// the per-render token the server minted, echoed into the page's
	/// `RuntimeConfig` so the websocket frames bind back to this render's
	/// session (AGENTS.md security invariant 11).
	let renderToken: String

	init(state: DemoState, renderToken: String = "") {
		self.state = state
		self.renderToken = renderToken
	}

	func render(into buffer: inout HTMLBuffer) {
		let document = WebUIDocument(
			title: "Wave 3 · acceptance demo",
			body: .trusted(renderDashboardBody(state: state)),
			runtimeConfig: renderToken.isEmpty ? nil : RuntimeConfig(renderToken: renderToken),
			rawStyles: Self.demoStyles
		)
		buffer.append(document.markup.html)
	}

	/// the page-scoped shell styles: the shared sheet leaves the demo's
	/// classes unstyled, so give them token-based defaults here.
	static let demoStyles: [String] = [
		".demo-app { max-width: 1000px; margin: 0 auto; padding: var(--space-8); display: flex; flex-direction: column; gap: var(--space-5); }",
		".demo-app__header { padding-bottom: var(--space-2); border-bottom: 1px solid var(--color-border-subtle, #e5e7eb); }",
		".demo-app__header p { color: var(--color-text-muted); margin: 0; }",
		".demo-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: var(--space-4); }",
		".demo-form { display: flex; flex-direction: column; gap: var(--space-3); }",
		".demo-actions { display: flex; align-items: center; gap: var(--space-2); }",
		".demo-routes { display: grid; grid-template-columns: auto 1fr; gap: var(--space-2) var(--space-4); font-size: 14px; }",
		".demo-routes__label { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }",
		".demo-count { font-variant-numeric: tabular-nums; font-weight: 600; }",
		".demo-log { margin: 0; padding: var(--space-3); background: var(--color-surface-muted, #f3f4f6); border-radius: 8px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; min-height: 4em; white-space: pre-wrap; word-break: break-all; }",
	]
}

/// the dashboard body: header, route map, then the four live halves — counter
/// (click), sign-in (urlencoded POST), upload (multipart POST), and the SSE
/// feed the /events route streams.
func renderDashboardBody(state: DemoState) -> String {
	Div(class: "demo-app") {
		Header(class: "demo-app__header") {
			Heading("Wave 3 · acceptance demo", level: .h1)
			Paragraph("one server, four routes — click, submit a form, upload a file, receive an SSE stream.")
		}
		WebUICard(elevation: .flat) {
			Heading("The routes", level: .h3)
			Div(class: "demo-routes") {
				Span(class: "demo-routes__label") { Text("GET  /") }
				Span { Text("the dashboard you are reading") }
				Span(class: "demo-routes__label") { Text("POST /login") }
				Span { Text("a real form POST, parsed via FormValues, answered with a 303 redirect") }
				Span(class: "demo-routes__label") { Text("POST /upload") }
				Span { Text("multipart upload, persisted to the temp dir, answered with a byte + sha-256 proof") }
				Span(class: "demo-routes__label") { Text("GET  /events") }
				Span { Text("a server-sent-event feed of three events") }
			}
		}
		Div(class: "demo-grid") {
			WebUICard(elevation: .elevated) {
				Heading("Live counter", level: .h3)
				Paragraph("a click round-trips over the WebSocket and repaints this span.")
				Div(class: "demo-actions") {
					WebUIButton("−", appearance: .secondary, size: .sm, id: "btn-dec", onTap: { _ in
						[FragmentUpdate(id: "dash-count", html: countMarkup(state.decrement()))]
					})
					Raw(UnsafeMarkup.trusted(countMarkup(state.count)))
					WebUIButton("+", appearance: .primary, size: .sm, id: "btn-inc", onTap: { _ in
						[FragmentUpdate(id: "dash-count", html: countMarkup(state.increment()))]
					})
					WebUIButton("reset", appearance: .ghost, size: .sm, id: "btn-reset", onTap: { _ in
						return [FragmentUpdate(id: "dash-count", html: countMarkup(0))]
					})
				}
			}
			WebUICard(elevation: .elevated) {
				Heading("Sign in", level: .h3)
				Paragraph("a native urlencoded POST — no script intercepts the submit; the server parses it and redirects back here.")
				Form(action: "/login", method: .post) {
					Input(id: "login-name", name: "name", placeholder: "ada lovelace", type: .text)
					Div(class: "demo-actions") {
						WebUIButton("Sign in", appearance: .primary, size: .sm, id: "login-submit")
					}
				}
			}
			WebUICard(elevation: .elevated) {
				Heading("Upload a file", level: .h3)
				Paragraph("the file is persisted to the temp dir; the dashboard reports the exact bytes and their sha-256.")
				Form(action: "/upload", method: .post, enctype: "multipart/form-data") {
					Input(id: "upload-file", name: "file", type: .file, accept: "application/octet-stream,text/plain")
					Div(class: "demo-actions") {
						WebUIButton("Upload", appearance: .primary, size: .sm, id: "upload-submit")
					}
				}
			}
			WebUICard(elevation: .elevated) {
				Heading("Server-sent events", level: .h3)
				Paragraph("open /events against this page's origin and the feed delivers three events before closing.")
				Raw(UnsafeMarkup.trusted(sseLogMarkup(state)))
			}
		}
		WebUICard(elevation: .outlined) {
			Heading("What the server has done", level: .h3)
			Div(class: "demo-form") {
				Div {
					Text("sign-in: ")
					Raw(UnsafeMarkup.trusted(signInStatusMarkup(state)))
				}
				Div {
					Text("upload: ")
					Raw(UnsafeMarkup.trusted(uploadStatusMarkup(state)))
				}
			}
		}
		Footer {
			Paragraph("served by Sources/WebUIExample — the wave-3 acceptance surface (W3.7).")
		}
	}.markup.html
}

/// the rendered sign-in proof: the last name the /login POST parsed.
func signInStatusMarkup(_ state: DemoState) -> String {
	var text: String
	if let name = state.signInName {
		text = "signed in as <strong>" + htmlEscape(name) + "</strong>"
	} else {
		text = "not signed in yet — submit the form above"
	}
	return "<span id=\"signin-status\">\(text)</span>"
}

/// the rendered upload proof: byte count, sha-256 digest, and the persisted
/// path, each drawn from the real receipt the /upload POST produced.
func uploadStatusMarkup(_ state: DemoState) -> String {
	let inner: String
	if let receipt = state.uploadReceipt {
		inner = "stored \(htmlEscape(receipt.filename)) — "
			+ "\(receipt.bytes) bytes · sha-256 \(receipt.digest) · \(htmlEscape(receipt.path))"
	} else if let error = state.uploadError {
		inner = "error: \(htmlEscape(error))"
	} else {
		inner = "no upload yet — choose a file above"
	}
	return "<span id=\"upload-status\">\(inner)</span>"
}

/// the placeholder log the browser appends the received sse events to.
func sseLogMarkup(_ state: DemoState) -> String {
	"<pre class=\"demo-log\"><span id=\"sse-log\">waiting for /events…</span></pre>"
}

// MARK: - server entry

@main
struct WebUIExample {
	static func main() async throws {
		let state = DemoState()
		let router = Router {
			Route.page("/") { request in
				DashboardDocument(state: state, renderToken: request.renderToken.value)
			}
			Route.post("/login") { request in handleLogin(request: request, state: state) }
			Route.post("/upload") { request in handleUpload(request: request, state: state) }
			Route.get("/events") { _ in SSE.response(tickStream()) }
			// the W5.4 theming demo: the same body under three themes. the
			// default route is the control — a host that never themes — and
			// `/theme-light` + `/theme-dark` carry the three token overrides
			// and the host component's StyleSheet. driven by
			// designer/theme-default-probe.mjs.
			Route.page("/theme-default") { _ in ThemeDemo.document(mode: nil) }
			Route.page("/theme-light") { _ in ThemeDemo.document(mode: .light) }
			Route.page("/theme-dark") { _ in ThemeDemo.document(mode: .dark) }
		}
		let server = WebUIServer(
			router: router,
			config: WebUIServerConfig(port: intFlag(named: "--port", default: 9090))
		)
		// a long-lived process is launched by the group, not awaited in main.
		// the group's default signals are graceful: it invokes the service's
		// `withGracefulShutdownHandler`, which closes the listener, `start()`
		// unwinds, and `run()` returns.
		let group = ServiceGroup(
			services: [WebUIServerService(server: server)],
			gracefulShutdownSignals: [.sigterm, .sigint]
		)
		do {
			try await group.run()
		} catch is CancellationError {
			// the signal asked for exactly this: the listener is already down.
		}
	}

	/// parse a positive-integer flag (`--name N`) with a fallback.
	static func intFlag(named name: String, default fallback: Int) -> Int {
		if let i = CommandLine.arguments.firstIndex(of: name),
		   i + 1 < CommandLine.arguments.count,
		   let v = Int(CommandLine.arguments[i + 1]), v > 0 {
			return v
		}
		return fallback
	}
}
