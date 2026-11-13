import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import NIOHTTP1
import WebUI
import WebUIBlocks
import WebUIServer
import WebUISharedCore

// MARK: - the smoke host's routes and assets
//
// everything the hand-rolled NIO host used to answer by hand is now a row in
// this table plus a `WebUIServerAsset`; `WebUIServer` owns the render, the
// framework assets, `/ws`, dispatch, ping/pong, idle reaping and the cap.

/// the gate's identity, when a gate spawned this process: every response
/// carries it so a gate can never mistake a stale/foreign process for its own
/// child (the readiness probe checks it before running any check).
let smokeNonce = ProcessInfo.processInfo.environment["WEBUI_SMOKE_NONCE"]

func smokeHeaders() -> [String: String] {
	guard let smokeNonce else { return [:] }
	return ["X-WebUI-Smoke-Nonce": smokeNonce]
}

/// read a release wasm product (built separately with the wasm sdk) so the
/// smoke server can serve it as a first-class static asset. an absent
/// artifact yields empty bytes, and the route is never registered — the 404
/// is the engine's documented degrade path (gates build it first).
func readWasmArtifact(_ product: String) -> [UInt8] {
	let url = URL(fileURLWithPath: ".build/out/Products/Release-webassembly-wasm32/\(product).wasm")
	guard FileManager.default.fileExists(atPath: url.path) else { return [] }
	let path = url.path
	let fd = open(path, O_RDONLY | O_CLOEXEC)
	guard fd >= 0 else { return [] }
	defer { close(fd) }
	var st = stat()
	guard fstat(fd, &st) == 0, st.st_size > 0 else { return [] }
	let size = Int(st.st_size)
	var bytes = [UInt8](repeating: 0, count: size)
	let n = bytes.withUnsafeMutableBytes { buf in
		read(fd, buf.baseAddress, size)
	}
	guard n == size else { return [] }
	return bytes
}

// MARK: - responders

/// the page route: render the smoke page for THIS request.
///
/// the render lands in the router's shared default session, and the redirect
/// probe is a handler on the router (not a branch in a dispatch loop), so a
/// `redirect-test` event answers the same `{type:redirect,…}` frame it always
/// did. `begin(.default)` restarts the mint counters per request, which is
/// what makes a re-render idempotent: same ids, same registrations, no growth.
struct SmokePageResponder: Responder {
	let state: SmokeState
	let router: EventRouter

	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		// the render's session is named by its token, which is what
		// `boundSession` resolves an inbound frame back to. beginning `.default`
		// here would register the page's handlers somewhere no token points at,
		// and a token-bound server would refuse every frame.
		let session = RenderSessionID(request.renderToken.value)
		router.begin(session)
		router.register(
			outcome: { _ in .redirect(to: "/", replace: true) },
			for: ComponentID("redirect-test"),
			in: session
		)
		let html = renderSmokePage(
			state: state,
			router: router,
			renderToken: request.renderToken.value
		)
		return HTTPResponse(headers: smokeHeaders(), body: .html(UnsafeMarkup.trusted(html)))
	}
}

/// the real multipart POST the page's form submits natively: echo the exact
/// uploaded bytes back, with the headers the fullstack gate compares.
struct UploadResponder: Responder {
	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		guard case .multipart(let form) = request.body, let file = form.file("file") else {
			return HTTPResponse(
				status: HTTPStatus(400),
				headers: smokeHeaders(),
				body: .text("no file part under 'file'")
			)
		}
		var headers = smokeHeaders()
		headers["X-Upload-Field"] = file.field
		headers["X-Upload-Name"] = file.filename
		headers["X-Upload-Type"] = file.contentType
		headers["X-Upload-Caption"] = form.values.string("caption") ?? ""
		headers["X-Upload-Bytes"] = "\(file.size)"
		headers["X-Upload-Sha256"] = SHA256.hex(file.bytes)
		return HTTPResponse(headers: headers, body: .bytes(file.bytes, contentType: file.contentType))
	}
}

/// the blocks surface, served by this same preview process: `/blocks` is the
/// index, `/blocks/<name>` one standalone scaffold.
func blocksPage(_ path: String) -> String {
	let name = String(path.dropFirst("/blocks".count))
		.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
	if name.isEmpty { return WebUIBlocks.indexPage(dir: smokeDir) }
	if let block = Block(rawValue: name) { return WebUIBlocks.page(for: block, dir: smokeDir) }
	return "<!DOCTYPE html><html><body><h1>unknown block</h1>"
		+ "<p><a href=\"/blocks\">all blocks</a></p></body></html>"
}

// MARK: - the upload contract route

/// the byte budget the contract route pins. small on purpose: the probe's
/// limit case is one file over it, and the framework's own counted refusal —
/// 413 plus the server's text — is what answers, so this route never
/// re-implements a limit of its own (plan §22.3: limits stay server-owned).
let uploadContractLimit = 65_536

/// one json answer for `/upload/contract`: the shape `Documentation/UPLOAD.md`
/// fixes is `{ok, path, name, bytes}` or `{ok, error}`, serialized through the
/// framework's own `JSONValue` so a header value can never break the document.
func uploadContractJSON(_ fields: [String: JSONValue], status: HTTPStatus = .ok) -> HTTPResponse {
	HTTPResponse(
		status: status,
		headers: smokeHeaders(),
		body: .bytes(
			Array(JSONValue.object(fields).serialize().utf8),
			contentType: "application/json"
		)
	)
}

/// the contract route's handler: echo the two headers the engine travelled
/// with, and count the body as it streams past. the destination and the
/// filename are the proof — a route that received neither cannot answer.
func uploadContract(
	head: UploadHead,
	body: consuming UploadBody
) async throws -> HTTPResponse {
	// the browser owns `Origin` on a same-origin POST; the engine never sets
	// it. when it is present it must name this host, so a cross-origin page
	// cannot drive the route.
	if let origin = head.headers.first(name: "Origin"), !origin.isEmpty {
		let host = head.headers.first(name: "Host") ?? ""
		let stripped = origin.hasPrefix("https://") ? String(origin.dropFirst("https://".count))
			: origin.hasPrefix("http://") ? String(origin.dropFirst("http://".count)) : origin
		guard stripped == host else {
			return uploadContractJSON(
				["ok": .bool(false), "error": .string("cross-origin upload refused")],
				status: HTTPStatus(403)
			)
		}
	}
	let name = head.headers.first(name: "X-Upload-Name") ?? ""
	guard !name.isEmpty else {
		return uploadContractJSON(
			["ok": .bool(false), "error": .string("missing X-Upload-Name header")],
			status: HTTPStatus(400)
		)
	}
	var received = 0
	for try await chunk in body { received += chunk.count }
	return uploadContractJSON([
		"ok": .bool(true),
		"path": .string(head.headers.first(name: "X-Upload-Path") ?? ""),
		"name": .string(name),
		"bytes": .number(Double(received)),
	])
}

// MARK: - assets

/// the host assets: the embed plugin's dogfood plus the three capability
/// islands. an island rides `.bytes` at the exact url the engine fetches
/// (`/__assets/webui-<name>.wasm`); an absent artifact registers nothing, so
/// the request is the router's 404 — the documented degrade path.
func smokeAssets() -> [WebUIServerAsset] {
	var assets: [WebUIServerAsset] = [
		.bytes(
			"/ui/probe.css", ProbeAsset.body,
			contentType: ProbeAsset.contentType, cacheSeconds: 31536000, immutable: true
		),
	]
	let islands = [
		"/__assets/webui-validate.wasm": readWasmArtifact("WebUIValidateIsland"),
		"/__assets/webui-width-probe.wasm": readWasmArtifact("WebUIWidthProbeIsland"),
		"/__assets/webui-chart-probe.wasm": readWasmArtifact("WebUIChartIsland"),
	]
	for (path, bytes) in islands where !bytes.isEmpty {
		assets.append(
			.bytes(path, bytes, contentType: "application/wasm", cacheSeconds: 31536000, immutable: true)
		)
	}
	return assets
}

// MARK: - routes

/// the whole request surface, in one table: the page (both the historic
/// `/` and `/index.html` aliases), the blocks preview, and the upload POST.
func smokeRoutes(state: SmokeState, router: EventRouter) -> Router {
	let page = SmokePageResponder(state: state, router: router)
	// the behavior fixture is its own page with its own state: the `/` page's
	// 27-component pin is a smoke-gate contract, so a fixture that adds controls
	// must not live there.
	let behaviourState = BehaviourFixtureState()
	let behaviourPage = BehaviourPageResponder(state: behaviourState, router: router)
	// the residue proof page: §20's zero-JS re-expressions, one page.
	let residueState = ResidueState()
	let residuePage = ResiduePageResponder(state: residueState, router: router)
	return Router {
		Route(method: .get, pattern: "/", responder: page)
		Route(method: .get, pattern: "/index.html", responder: page)
		Route(method: .get, pattern: "/behaviour", responder: behaviourPage)
		Route(method: .get, pattern: "/residue", responder: residuePage)
		Route.get("/blocks") { _ in
			HTTPResponse(headers: smokeHeaders(), body: .html(UnsafeMarkup.trusted(blocksPage("/blocks"))))
		}
		Route.get("/blocks/*name") { request in
			HTTPResponse(
				headers: smokeHeaders(),
				body: .html(UnsafeMarkup.trusted(blocksPage("/blocks/" + (request.params["name"] ?? ""))))
			)
		}
		Route(method: .post, pattern: "/upload", responder: UploadResponder())
		// the engine's XHR transport posts here: a streamed body, a JSON
		// answer, and the two headers that name the destination and the file.
		Route.upload("/upload/contract", limit: uploadContractLimit, handler: uploadContract)
	}
}
