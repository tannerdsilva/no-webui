import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import Synchronization
import WebUI
import WebUIChart
import WebUICore
import WebUIDesignSystem

// MARK: - WebUIBench
//
// the desktop-grade stress host (plan d0 t0.1/t0.3): one process, four
// deliberately naive fixture pages — feed, grid, dashboard, editor — each
// rendered with today's components and today's interaction semantics
// (`replace` only), so the wall is measured honestly. benches are fixtures,
// not products (plan §3).
//
// routes:
//   /bench/feed?items=N            feed (card rows) + append-100 (replace)
//   /bench/feed?windowed=1         t0.3 naive variant (one replace per scroll step)
//   /bench/feed?windowed=1&ops=1   t0.3 op variant (append + empty-fragment remove)
//   /bench/grid?rows=R&cols=C      WebUITable + sort
//   /bench/dashboard?series=S&points=P  WebUIChart wall + tick
//   /bench/editor                  TextArea + echo + commit
//   /__assets/css, /__assets/css.<sha>, /ui/webui-engine.js, /ui/bench-window.js
//
// port: `--port <n>` else `WEBUI_BENCH_PORT` else 9130 (plan t0.1). lane
// convention: measure on 9200–9219.
//
// the host is raw NIO (not `WebUIServer`) because the four bench routes need
// request-differentiated pages and `WebUIServer` serves a single `pagePath`;
// the skeleton is the repo's own pre-`WebUIServer` `WebUIExample`: websocket
// upgrade, admission gate, idle reaping, security headers, charset=utf-8 on
// every text response.

// MARK: - shared state

final class BenchState: Sendable {
	struct Values {
		var feedCount = 0
		var windowStart = 0
		var gridSortColumn = 0
		var gridAscending = true
		var tick = 0
		var editorText = ""
		var committed = ""
	}
	private let values = Mutex(Values())
	func withLock<Result: Sendable>(_ body: @Sendable (inout Values) -> sending Result) -> sending Result { values.withLock(body) }
}

// MARK: - row renderers (raw strings; the naive full-render model)

/// one feed card row; id-bearing so the t0.3 op variant can remove it.
func feedRowHTML(_ i: Int) -> String {
	"<div id=\"feed-item-\(i)\" class=\"feed-item\"><span class=\"feed-item__title\">item \(i)</span><span class=\"feed-item__meta\">row \(i)</span></div>"
}

func feedSliceHTML(from start: Int, count: Int) -> String {
	var html = ""
	for i in start..<(start + count) { html += feedRowHTML(i) }
	return html
}

func gridCellText(_ r: Int, _ c: Int) -> String { "r\(r)c\(c)" }

// MARK: - page assembly
//
// every page body renders under `RenderContext(router:)` so
// `controlAttributes`-wired controls register into the one router the socket
// dispatches against. fragment re-renders from inside a handler re-emit the
// same stable ids without re-registering (the documented contract), so
// routing survives every interaction.

func benchDocument(title: String, body: String) -> String {
	// the engine auto-boot needs the config meta and the engine script; the
	// sheet links content-addressed, cached a year.
	WebUIDocument(
		title: title,
		body: body,
		rawStyles: [
			".bench { max-width: 1100px; margin: 0 auto; padding: var(--space-8); }",
			".bench__toolbar { display: flex; gap: var(--space-3); margin: var(--space-4) 0; }",
			".feed-window { height: 70vh; overflow-y: auto; border: 1px solid var(--color-border); }",
			".feed-item { display: flex; justify-content: space-between; padding: var(--space-3); border-bottom: 1px solid var(--color-border); }",
			".dash-wall { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: var(--space-4); }",
			".echo-out { margin-top: var(--space-2); padding: var(--space-3); background: var(--color-surface-2); }",
		]
	).render()
}

extension RenderContext {
	func withValueBody<V: View>(_ build: () -> V) -> String {
		RenderContext.$current.withValue(self) { build().render() }
	}
}

// MARK: - the four bench pages

// ── feed ──────────────────────────────────────────────────────────────────

func renderFeedPage(state: BenchState, router: EventRouter, items: Int, windowed: Bool, opsVariant: Bool) -> String {
	let ctx = RenderContext(router: router)
	state.withLock { $0.feedCount = max($0.feedCount, items) }
	let windowStart = state.withLock { $0.windowStart }

	let body = ctx.withValueBody {
		Div(class: "bench") {
			Heading("Feed bench", level: .h1)
			if windowed {
				Div(class: "bench__toolbar") {
					Text("windowed (" + (opsVariant ? "ops" : "replace") + ")")
				}
			} else {
				Div(class: "bench__toolbar") {
					WebUIButton("Append 100", variant: .primary, size: .md, id: "feed-append", onTap: { _ in
						let n = state.withLock { v in
							v.feedCount += 100
							return v.feedCount
						}
						// today's model: one whole-region replace of the list,
						// re-emitting the container so the id anchor survives.
						return [FragmentUpdate(id: "feed-list", html: rowsRegionHTML(count: n))]
					})
					WebUIButton("Append 100 (op)", variant: .secondary, size: .md, id: "feed-append-op", onTap: { _ in
						// the op-shaped interaction: emit 100 single-row
						// `append` fragments instead of one big region replace.
						let base = state.withLock { v in
							let b = v.feedCount
							v.feedCount += 100
							return b
						}
						return (base..<(base + 100)).map { i in
							FragmentUpdate.append(id: "feed-list", html: feedRowHTML(i))
						}
					})
				}
			}
			if windowed {
				// fixed 60-row sliding window in a scroll container. the
				// scroll affordance is `/ui/bench-window.js` (external,
				// same-origin → allowed by script-src 'self'): it observes
				// scroll on `#feed-window` and dispatches a routed click on
				// the hidden next-window control. today's engine has NO
				// scroll delivery (EVENT_TYPES lacks `scroll`, no `onScroll`
				// modifier), so this page-side observer + routed click IS the
				// d0 scroll-delivery mechanism; see t0.3 findings.
				Div(id: "feed-window", class: "feed-window") {
					Raw(feedSliceHTML(from: windowStart, count: 60))
				}
				Raw(routedNextWindowControl(state: state, opsVariant: opsVariant))
			} else {
				Div(id: "feed-list", class: "feed-list") {
					Raw(rowsHTML(count: state.withLock { $0.feedCount }))
				}
			}
		}
	}

	// the bench scroll observer maps scroll steps to the routed next-window
	// click; it is a page-authored fixture, never a runtime patch.
	var scrollScript = ""
	if windowed {
		scrollScript = "<script src=\"/ui/bench-window.js\"></script>"
	}

	let html = benchDocument(title: "Feed bench", body: body)
	return injectHead(html, scrollScript)
}

/// the routed next-window control the scroll observer clicks, registered into
/// the router at render time (the stable-id contract). handler differs by
/// variant:
///   replace (naive): one whole-region replace of `#feed-window` per step —
///     the wall demonstration.
///   ops (op variant): keep the container stable; `append` the entering rows
///     and remove the leaving rows via an empty-fragment replace (the pinned
///     remove branch today — the `remove` op lands with t1.1).
func routedNextWindowControl(state: BenchState, opsVariant: Bool) -> String {
	let handler: @Sendable (EventData) async -> [FragmentUpdate] = { _ in
		if opsVariant {
			let (start, count) = state.withLock { v -> (Int, Int) in
				let s = v.windowStart
				v.windowStart = min(s + 10, max(0, v.feedCount))
				return (s, v.windowStart)
			}
			let advanced = count != start
			guard advanced else { return [] }
			let leaving = start..<min(start + 10, count)
			let entering = max(start, count - 10)..<count
			var updates = leaving.map { i in FragmentUpdate(id: "feed-item-\(i)", html: "") }
			updates.append(contentsOf: entering.map { i in FragmentUpdate.append(id: "feed-window", html: feedRowHTML(i)) })
			return updates
		} else {
			let start = state.withLock { v -> Int in
				let s = v.windowStart
				v.windowStart = s + 10
				return v.windowStart
			}
			// one whole-region replace of the window, re-emitting the
			// container so scroll position (saved by id across patches)
			// survives the swap.
			let html = "<div id=\"feed-window\" class=\"feed-window\">\(feedSliceHTML(from: start, count: 60))</div>"
			return [FragmentUpdate(id: "feed-window", html: html)]
		}
	}
	let attrs = controlAttributes(id: "feed-window-next", event: .click, handler: handler)
	return "<button id=\"feed-window-next\" style=\"display:none\"\(attrs)></button>"
}

/// the full detached-list html (naive append-100: one region replace). the
/// payload re-emits the container div — `replaceElement` swaps the element
/// WHOLESALE (parentNode.replaceChild), so a bare-rows payload would delete
/// the region's own id anchor and kill every subsequent patch on it.
func rowsRegionHTML(count: Int) -> String {
	"<div id=\"feed-list\" class=\"feed-list\">\(rowsHTML(count: count))</div>"
}

/// the bare rows (used under the ops path, where the container is stable and
/// rows are appended into it).
func rowsHTML(count: Int) -> String {
	var html = ""
	for i in 0..<count { html += feedRowHTML(i) }
	return html
}

func injectHead(_ html: String, _ slot: String) -> String {
	guard !slot.isEmpty else { return html }
	// insert before </head> so external bench scripts ride under the page csp.
	return html.replacingOccurrences(of: "</head>", with: slot + "</head>")
}

// ── grid ──────────────────────────────────────────────────────────────────

func renderGridPage(state: BenchState, router: EventRouter, rows: Int, cols: Int) -> String {
	let ctx = RenderContext(router: router)
	let (sortCol, asc) = state.withLock { ($0.gridSortColumn, $0.gridAscending) }
	let sortedRows = sortedGridRows(rows: rows, cols: cols, sortCol: sortCol, ascending: asc)

	let body = ctx.withValueBody {
		Div(class: "bench") {
			Heading("Grid bench", level: .h1)
			WebUITable(
				headers: (0..<cols).map { "Col \($0)" },
				rows: sortedRows,
				id: "bench-grid",
				sortableColumns: (0..<cols).map { $0 }.reduce(into: Set<Int>()) { $0.insert($1) },
				sort: (column: sortCol, direction: asc ? .ascending : .descending)
			)
			.onSort { me, col in
				// today's model: server applies the sort and re-emits the
				// WHOLE table region as one fragment.
				let (c, a) = state.withLock { v -> (Int, Bool) in
					if v.gridSortColumn == col { v.gridAscending.toggle() }
					else { v.gridSortColumn = col; v.gridAscending = true }
					return (v.gridSortColumn, v.gridAscending)
				}
				let reRendered = renderGridFragment(rows: rows, cols: cols, sortCol: c, ascending: a)
				return [me.replace(with: reRendered)]
			}
		}
	}
	return benchDocument(title: "Grid bench", body: body)
}

/// build the rows array in the requested sort order (a stable sort by the
/// cell-text of `sortCol`, the data-grid's server-side contract).
func sortedGridRows(rows: Int, cols: Int, sortCol: Int, ascending: Bool) -> [[any View]] {
	let effectiveCol = max(0, min(sortCol, cols - 1))
	let order = (0..<rows).sorted { a, b in
		let ea = gridCellText(a, effectiveCol)
		let eb = gridCellText(b, effectiveCol)
		return ascending ? ea < eb : ea > eb
	}
	return order.map { r in (0..<cols).map { c in Text(gridCellText(r, c)) } }
}

/// the fragment re-render for a sort interaction (no render context → the
/// table's stable control ids are re-emitted without re-registering, keeping
/// routing alive — the documented `controlAttributes` contract).
func renderGridFragment(rows: Int, cols: Int, sortCol: Int, ascending: Bool) -> String {
	let sortedRows = sortedGridRows(rows: rows, cols: cols, sortCol: sortCol, ascending: ascending)
	return WebUITable(
		headers: (0..<cols).map { "Col \($0)" },
		rows: sortedRows,
		id: "bench-grid",
		sortableColumns: (0..<cols).map { $0 }.reduce(into: Set<Int>()) { $0.insert($1) },
		sort: (column: sortCol, direction: ascending ? .ascending : .descending)
	).render()
}

// ── dashboard ─────────────────────────────────────────────────────────────

func renderDashboardPage(state: BenchState, router: EventRouter, series: Int, points: Int) -> String {
	let ctx = RenderContext(router: router)
	let tick = state.withLock { $0.tick }
	let body = ctx.withValueBody {
		Div(class: "bench") {
			Heading("Dashboard bench", level: .h1)
			Div(class: "bench__toolbar") {
				WebUIButton("Tick", variant: .primary, size: .md, id: "dash-tick", onTap: { _ in
					// today's model: one whole-region replace of the chart wall
					// (re-emitting the container so the id anchor survives).
					let t = state.withLock { v in
						v.tick += 1
						return v.tick
					}
					return [FragmentUpdate(id: "dash-wall", html: chartWallRegionHTML(series: series, points: points, tick: t))]
				})
			}
			Div(id: "dash-wall", class: "dash-wall") {
				Raw(chartWallHTML(series: series, points: points, tick: tick))
			}
		}
	}
	return benchDocument(title: "Dashboard bench", body: body)
}

/// `series` charts × `points` marks; a pure function of the tick (the naive
/// live-chart model: re-render everything, replace the wall).
func chartWallHTML(series: Int, points: Int, tick: Int) -> String {
	var html = ""
	for s in 0..<max(0, series) {
		let marks = (0..<max(0, points)).map { p -> ChartMark in
			BarMark(x: .value("p", p), y: .value("v", Double((p * 37 + s * 101 + tick) % 97 + 1))).makeMark()
		}
		html += Chart(marks, config: ChartConfig(), ariaLabel: "series \(s)").render()
	}
	return html
}

/// the chart wall wrapped in its container (the replace path re-emits the
/// region's own div — replaceElement swaps the element wholesale, so a bare
/// payload would delete the `dash-wall` id anchor).
func chartWallRegionHTML(series: Int, points: Int, tick: Int) -> String {
	"<div id=\"dash-wall\" class=\"dash-wall\">\(chartWallHTML(series: series, points: points, tick: tick))</div>"
}

// ── editor ────────────────────────────────────────────────────────────────

func renderEditorPage(state: BenchState, router: EventRouter) -> String {
	let ctx = RenderContext(router: router)
	let echo = state.withLock { $0.editorText }
	let committed = state.withLock { $0.committed }
	let body = ctx.withValueBody {
		Div(class: "bench") {
			Heading("Editor bench", level: .h1)
			Div(class: "bench__toolbar") {
				WebUIButton("Commit", variant: .primary, size: .md, id: "editor-commit", onTap: { _ in
					// today's model: commit echoes the current text via one
					// region replace.
					let t = state.withLock { v in
						v.committed = v.editorText
						return v.committed
					}
					return [FragmentUpdate(id: "editor-echo", html: "<div id=\"echo-out\" class=\"echo-out\"><span>committed: \(htmlEscape(t))</span></div>")]
				})
			}
			TextArea(id: "editor-text", name: "text", placeholder: "type to echo…", value: echo, rows: 12)
				.onInput { event in
					// the naive echo path: an `input` event round-trips to the
					// server (debounced) and comes back as a region replace.
					// echoLatency measures exactly this wire, from outside.
					let text = event.string("value") ?? ""
					state.withLock { $0.editorText = text }
					return [FragmentUpdate(id: "echo-out", html: "<div id=\"echo-out\" class=\"echo-out\"><span class=\"echo-out__text\">\(htmlEscape(text))</span></div>")]
				}
			Raw("<div id=\"echo-out\" class=\"echo-out\"><span class=\"echo-out__text\">\(htmlEscape(echo))</span></div>")
			if !committed.isEmpty {
				Raw("<p class=\"echo-out\">last commit: \(htmlEscape(committed))</p>")
			}
		}
	}
	return benchDocument(title: "Editor bench", body: body)
}

// MARK: - the raw NIO host

final class BenchGate: Sendable {
	private let state = Mutex<Int>(0)
	private let maximum: Int
	init(maximum: Int) { self.maximum = maximum }
	func tryAcquire() -> Bool {
		state.withLock { v in
			if v >= maximum { return false }
			v += 1
			return true
		}
	}
	func release() { state.withLock { $0 -= 1 } }
}

enum BenchUpgradeResult: Sendable {
	case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
	case http(NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>)
}

@main
struct WebUIBench {
	let state: BenchState
	let router: EventRouter
	let gate: BenchGate
	let port: Int
	let logger: Logger

	static func main() async throws {
		let port = resolvePort()
		let app = WebUIBench(
			state: BenchState(),
			router: EventRouter(),
			gate: BenchGate(maximum: 256),
			port: port,
			logger: Logger(label: "webui.bench")
		)
		DesignSystemAssets.prewarm()
		app.logger.info("[WebUIBench] listening on http://127.0.0.1:\(port) — benches at /bench/feed /bench/grid /bench/dashboard /bench/editor")

		let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
		let bootstrap = ServerBootstrap(group: group)
			.serverChannelOption(ChannelOptions.backlog, value: 128)
			.serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
			.childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)

		let channel: NIOAsyncChannel<EventLoopFuture<BenchUpgradeResult>, Never> = try await bootstrap.bind(
			host: "0.0.0.0", port: port
		) { channel in
			channel.eventLoop.makeCompletedFuture { () -> EventLoopFuture<BenchUpgradeResult> in
				guard app.gate.tryAcquire() else {
					channel.close(promise: nil)
					return channel.eventLoop.makeFailedFuture(BenchGateError.atCapacity)
				}
				try channel.pipeline.syncOperations.addHandler(IdleStateHandler(readTimeout: .seconds(120)))
				try channel.pipeline.syncOperations.addHandler(BenchIdleCloseHandler())
				try channel.pipeline.syncOperations.addHandler(BenchGateReleaser(gate: app.gate))
				let upgrader = NIOTypedWebSocketServerUpgrader<BenchUpgradeResult>(
					shouldUpgrade: { channel, head in
						let ok = head.method == .GET && head.uri == "/ws"
						return channel.eventLoop.makeSucceededFuture(ok ? HTTPHeaders() : nil)
					},
					upgradePipelineHandler: { channel, _ in
						channel.eventLoop.makeCompletedFuture {
							let ws = try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(wrappingChannelSynchronously: channel)
							return BenchUpgradeResult.websocket(ws)
						}
					}
				)
				let config = NIOTypedHTTPServerUpgradeConfiguration(
					upgraders: [upgrader],
					notUpgradingCompletionHandler: { channel in
						channel.eventLoop.makeCompletedFuture {
							try channel.pipeline.syncOperations.addHandler(BenchHTTPResponsePartHandler())
							let http = try NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>(wrappingChannelSynchronously: channel)
							return BenchUpgradeResult.http(http)
						}
					}
				)
				let pipelineConfig = NIOUpgradableHTTPServerPipelineConfiguration(
					upgradeConfiguration: config
				)
				return try channel.pipeline.syncOperations.configureUpgradableHTTPServerPipeline(configuration: pipelineConfig)
			}
		}

		try await withThrowingDiscardingTaskGroup { group in
			try await channel.executeThenClose { inbound in
				for try await negotiationFuture in inbound {
					group.addTask { await app.handle(negotiationFuture) }
				}
			}
		}
		try await group.shutdownGracefully()
	}

	static func resolvePort() -> Int {
		if let i = CommandLine.arguments.firstIndex(of: "--port"), i + 1 < CommandLine.arguments.count,
		   let v = Int(CommandLine.arguments[i + 1]), v > 0 {
			return v
		}
		if let raw = ProcessInfo.processInfo.environment["WEBUI_BENCH_PORT"], let v = Int(raw), v > 0 {
			return v
		}
		return 9130
	}

	func handle(_ negotiationFuture: EventLoopFuture<BenchUpgradeResult>) async {
		do {
			switch try await negotiationFuture.get() {
			case .websocket(let ws): try await handleWebsocket(ws)
			case .http(let http): try await handleHTTP(http)
			}
		} catch {
			// connection error or a refused admission; ignore.
		}
	}

	// MARK: websocket

	private func handleWebsocket(_ channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>) async throws {
		try await channel.executeThenClose { inbound, outbound in
			try await withThrowingTaskGroup(of: Void.self) { tg in
				tg.addTask {
					for try await frame in inbound {
						switch frame.opcode {
						case .text:
							let payload = String(buffer: frame.unmaskedData)
							await self.dispatch(eventText: payload, outbound: outbound)
						case .ping:
							try await outbound.write(WebSocketFrame(fin: true, opcode: .pong, data: ByteBuffer()))
						case .connectionClose:
							var data = frame.unmaskedData
							let code = data.readSlice(length: 2) ?? ByteBuffer()
							try await outbound.write(WebSocketFrame(fin: true, opcode: .connectionClose, data: code))
							return
						default:
							break
						}
					}
				}
				try await tg.next()
				tg.cancelAll()
			}
		}
	}

	private func dispatch(eventText payload: String, outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async {
		do {
			let msg = try WSIncoming(jsonText: payload)
			switch msg {
			case .event(let component, let event, let data, _):
				let eventData = EventData(component: ComponentID(component), event: event, data: data)
				let updates = await self.router.handle(eventData)
				guard !updates.isEmpty else { return }
				try await writeJSON(WSOutgoing.update(fragments: updates), outbound: outbound)
			case .ping(_):
				try await writeJSON(WSOutgoing.pong, outbound: outbound)
			case .navigate:
				break
			}
		} catch {
			let err = WSOutgoing.error(code: "decode", message: "bad event: \(error)")
			try? await writeJSON(err, outbound: outbound)
		}
	}

	private func writeJSON(_ msg: WSOutgoing, outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async throws {
		var buf = ByteBuffer()
		buf.writeBytes(msg.jsonBytes)
		try await outbound.write(WebSocketFrame(fin: true, opcode: .text, data: buf))
	}

	// MARK: http

	/// the windowed-feed page script: observes scroll on `#feed-window` and,
	/// per step boundary, dispatches a routed click on `#feed-window-next`.
	/// this is the d0 scroll-delivery mechanism (plan t0.3 option (a), page
	/// side) — the engine itself has no scroll event today. the script is an
	/// external same-origin asset (`script-src 'self'`), so it rides the page
	/// csp without a nonce.
	static let windowObserverScript = """
	(function () {
	  // capture-phase scroll listener on document: the naive variant REPLACES
	  // `#feed-window` per step (whole-region swap), so a listener attached to
	  // the element dies with it. a document-level capture listener survives
	  // every replace and forwards the real scroll path (mouse.wheel →
	  // scrollTop) into a routed click on the hidden next-window control.
	  function arm() {
	    var armed = true;
	    document.addEventListener('scroll', function (e) {
	      var t = e.target;
	      if (!t || t.nodeType !== 1) return;
	      if (!t.id || t.id !== 'feed-window') return;
	      if (!armed) return;
	      armed = false;
	      var next = document.getElementById('feed-window-next');
	      if (next) next.click();
	      setTimeout(function () { armed = true; }, 150);
	    }, { capture: true, passive: true });
	  }
	  if (document.readyState === 'loading') {
	    document.addEventListener('DOMContentLoaded', arm);
	  } else {
	    arm();
	  }
	})();
	"""

	private func handleHTTP(_ channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>) async throws {
		try await channel.executeThenClose { inbound, outbound in
			for try await part in inbound {
				guard case .head(let head) = part else { continue }
				guard head.method == .GET else {
					try await respond405(channel: channel.channel)
					return
				}
				let uri = head.uri
				let path = String(uri.prefix(while: { $0 != "?" }))
				let query = parseBenchQuery(String(uri.dropFirst(path.count).dropFirst()))

				if path == "/__assets/css" || path.hasPrefix("/__assets/css.") {
					try await respond(channel: channel.channel, body: DesignSystemAssets.minifiedCss, contentType: "text/css; charset=utf-8", cacheControl: "public, max-age=3600")
				} else if path == "/ui/webui-engine.js" {
					try await respond(channel: channel.channel, body: WebUIAssets.engine, contentType: "text/javascript; charset=utf-8", cacheControl: "public, max-age=3600")
				} else if path == "/ui/bench-window.js" {
					try await respond(channel: channel.channel, body: Self.windowObserverScript, contentType: "text/javascript; charset=utf-8", cacheControl: "no-store")
				} else if path == "/bench/feed" {
					let items = Int(query["items"] ?? "0") ?? 0
					let windowed = query["windowed"] == "1"
					let ops = query["ops"] == "1"
					if windowed {
						state.withLock { $0.windowStart = 0 }
					}
					let page = renderFeedPage(state: state, router: router, items: items, windowed: windowed, opsVariant: ops)
					try await respond(channel: channel.channel, body: page, contentType: "text/html; charset=utf-8")
				} else if path == "/bench/grid" {
					let rows = Int(query["rows"] ?? "0") ?? 0
					let cols = Int(query["cols"] ?? "0") ?? 0
					try await respond(channel: channel.channel, body: renderGridPage(state: state, router: router, rows: rows, cols: cols), contentType: "text/html; charset=utf-8")
				} else if path == "/bench/dashboard" {
					let series = Int(query["series"] ?? "0") ?? 0
					let points = Int(query["points"] ?? "0") ?? 0
					try await respond(channel: channel.channel, body: renderDashboardPage(state: state, router: router, series: series, points: points), contentType: "text/html; charset=utf-8")
				} else if path == "/bench/editor" {
					try await respond(channel: channel.channel, body: renderEditorPage(state: state, router: router), contentType: "text/html; charset=utf-8")
				} else {
					try await respond404(channel: channel.channel)
					return
				}
			}
		}
	}

	private func respond(channel: Channel, body: String, contentType: String, status: HTTPResponseStatus = .ok, cacheControl: String = "no-store") async throws {
		var head = HTTPResponseHead(version: .http1_1, status: status)
		head.headers.replaceOrAdd(name: "Content-Type", value: contentType)
		head.headers.replaceOrAdd(name: "Content-Length", value: "\(body.utf8.count)")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
		head.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
		head.headers.replaceOrAdd(name: "Service-Worker-Allowed", value: "/")
		head.headers.replaceOrAdd(name: "Cache-Control", value: cacheControl)
		var buf = ByteBuffer()
		buf.writeString(body)
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head))
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.body(buf))
		try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil)).get()
	}

	private func respond404(channel: Channel) async throws {
		try await respond(channel: channel, body: "not found", contentType: "text/plain; charset=utf-8", status: .notFound)
	}

	private func respond405(channel: Channel) async throws {
		var head = HTTPResponseHead(version: .http1_1, status: .methodNotAllowed)
		head.headers.replaceOrAdd(name: "Content-Length", value: "0")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
		head.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
		head.headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head))
		try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil)).get()
	}
}

enum BenchGateError: Error {
	case atCapacity
}

/// close the channel when the read-idle window elapses.
final class BenchIdleCloseHandler: ChannelInboundHandler {
	typealias InboundIn = IOData
	func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
		if event is IdleStateHandler.IdleStateEvent {
			context.close(promise: nil)
		} else {
			context.fireUserInboundEventTriggered(event)
		}
	}
}

/// release a gate slot when the channel closes.
final class BenchGateReleaser: ChannelInboundHandler {
	typealias InboundIn = IOData
	private let gate: BenchGate
	init(gate: BenchGate) { self.gate = gate }
	func channelInactive(context: ChannelHandlerContext) {
		gate.release()
		context.fireChannelInactive()
	}
}

final class BenchHTTPResponsePartHandler: ChannelOutboundHandler {
	typealias OutboundIn = HTTPPart<HTTPResponseHead, ByteBuffer>
	typealias OutboundOut = HTTPServerResponsePart
	func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
		let part = Self.unwrapOutboundIn(data)
		switch part {
		case .head(let head): context.write(Self.wrapOutboundOut(.head(head)), promise: promise)
		case .body(let buffer): context.write(Self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: promise)
		case .end(let trailers): context.write(Self.wrapOutboundOut(.end(trailers)), promise: promise)
		}
	}
}

// MARK: - query parsing (same contract as WebUIServerRequest)

func parseBenchQuery(_ text: String) -> [String: String] {
	guard !text.isEmpty else { return [:] }
	var out: [String: String] = [:]
	for pair in text.split(separator: "&", omittingEmptySubsequences: true) {
		let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
		let name = String(parts[0])
		guard !name.isEmpty, out[name] == nil else { continue }
		out[name] = parts.count == 2 ? String(parts[1]) : ""
	}
	return out
}
