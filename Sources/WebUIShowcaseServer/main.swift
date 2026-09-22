import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import WebUI
import WebUIDesignSystem
import WebUIShowcaseContent

// MARK: - Live showcase generation (re-rendered per request, never a frozen file)

/// Build the full showcase document from Swift views right now. Unlike the
/// static `designer/previews/showcase.html` artifact, every request reflects
/// the current source: change a component or the css and this server serves
/// it immediately. The runtime is enabled (and served a working `/ws` below),
/// so the client boots cleanly with no failed-handshake error.
func renderShowcasePage() -> String {
    let doc = WebUIDocument(
        title: "WebUI Showcase",
        body: ShowcasePage().render(),
        includeRuntime: true
    )
    return doc.render()
}

func intFlag(named name: String, default fallback: Int) -> Int {
    if let i = CommandLine.arguments.firstIndex(of: name),
       i + 1 < CommandLine.arguments.count,
       let v = Int(CommandLine.arguments[i + 1]), v > 0 {
        return v
    }
    return fallback
}

// MARK: - Upgrade result

enum ShowcaseUpgradeResult: Sendable {
    case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
    case http(NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>)
}

// converts the async channel's typed HTTP parts back into the pipeline's
// `HTTPServerResponsePart` outbound form (parity with the demo server).
final class HTTPByteBufferResponsePartHandler: ChannelOutboundHandler {
    typealias OutboundIn = HTTPPart<HTTPResponseHead, ByteBuffer>
    typealias OutboundOut = HTTPServerResponsePart

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let part = Self.unwrapOutboundIn(data)
        switch part {
        case .head(let head):
            context.write(Self.wrapOutboundOut(.head(head)), promise: promise)
        case .body(let buffer):
            context.write(Self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: promise)
        case .end(let trailers):
            context.write(Self.wrapOutboundOut(.end(trailers)), promise: promise)
        }
    }
}

// MARK: - WebSocket loop (the showcase registers no handlers, so this simply
// keeps the runtime alive: answer pings with pongs, hug the close frame).

private func handleWebsocket(_ channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>) async throws {
    try await channel.executeThenClose { inbound, outbound in
        for try await frame in inbound {
            switch frame.opcode {
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
}

// MARK: - Server

@main
struct WebUIShowcaseServer {
    static func main() async throws {
        let logger = Logger(label: "webui.showcase-server")
        let port = intFlag(named: "--port", default: 9092)

        // prewarm the hoisted minified sheet so the one-time minify never
        // lands inside the first request handler.
        DesignSystemAssets.prewarm()

        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 128)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        let channel: NIOAsyncChannel<EventLoopFuture<ShowcaseUpgradeResult>, Never> = try await bootstrap.bind(
            host: "0.0.0.0", port: port
        ) { channel in
            channel.eventLoop.makeCompletedFuture { () -> EventLoopFuture<ShowcaseUpgradeResult> in
                let upgrader = NIOTypedWebSocketServerUpgrader<ShowcaseUpgradeResult>(
                    shouldUpgrade: { channel, head in
                        let ok = head.method == .GET && head.uri == "/ws"
                        return channel.eventLoop.makeSucceededFuture(ok ? HTTPHeaders() : nil)
                    },
                    upgradePipelineHandler: { channel, _ in
                        channel.eventLoop.makeCompletedFuture {
                            let ws = try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(wrappingChannelSynchronously: channel)
                            return ShowcaseUpgradeResult.websocket(ws)
                        }
                    }
                )
                let config = NIOTypedHTTPServerUpgradeConfiguration(
                    upgraders: [upgrader],
                    notUpgradingCompletionHandler: { channel in
                        channel.eventLoop.makeCompletedFuture {
                            try channel.pipeline.syncOperations.addHandler(HTTPByteBufferResponsePartHandler())
                            let http = try NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>(wrappingChannelSynchronously: channel)
                            return ShowcaseUpgradeResult.http(http)
                        }
                    }
                )
                let pipelineConfig = NIOUpgradableHTTPServerPipelineConfiguration(upgradeConfiguration: config)
                return try channel.pipeline.syncOperations.configureUpgradableHTTPServerPipeline(configuration: pipelineConfig)
            }
        }

        logger.info("live showcase on http://localhost:\(port) (generated from Swift per request)")

        try await withThrowingDiscardingTaskGroup { group in
            try await channel.executeThenClose { inbound in
                for try await negotiationFuture in inbound {
                    group.addTask {
                        await handle(negotiationFuture, logger: logger)
                    }
                }
            }
        }

        try await group.shutdownGracefully()
    }

    private static func handle(_ negotiationFuture: EventLoopFuture<ShowcaseUpgradeResult>, logger: Logger) async {
        do {
            switch try await negotiationFuture.get() {
            case .websocket(let ws):
                try await handleWebsocket(ws)
            case .http(let http):
                try await handleHTTP(http)
            }
        } catch {
            // connection error or a refused upgrade; ignore.
        }
    }

    private static func handleHTTP(_ channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>) async throws {
        try await channel.executeThenClose { inbound, _ in
            for try await part in inbound {
                guard case .head(let head) = part else { continue }
                guard head.method == .GET else {
                    try await respond(channel: channel.channel, body: "method not allowed", contentType: "text/plain; charset=utf-8", status: .methodNotAllowed)
                    return
                }
                let uri = head.uri
                if uri == "/" || uri == "/index.html" {
                    try await respond(channel: channel.channel, body: renderShowcasePage(), contentType: "text/html; charset=utf-8", status: .ok)
                } else if uri == "/__assets/css" {
                    try await respond(channel: channel.channel, body: DesignSystemAssets.minifiedCss, contentType: "text/css; charset=utf-8", status: .ok)
                } else if uri == "/ui/webui-client.js" {
                    try await respond(channel: channel.channel, body: WebUIAssets.client, contentType: "text/javascript; charset=utf-8", status: .ok)
                } else if uri == "/ui/webui-app-boot.js" {
                    try await respond(channel: channel.channel, body: WebUIAssets.clientBoot, contentType: "text/javascript; charset=utf-8", status: .ok)
                } else if uri == "/ui/webui-engine.js" {
                    try await respond(channel: channel.channel, body: WebUIAssets.engine, contentType: "text/javascript; charset=utf-8", status: .ok)
                } else if uri.hasPrefix("/__assets/webui-client."), uri.hasSuffix(".wasm") {
                    try await respondWasm(channel: channel.channel)
                } else {
                    try await respond(channel: channel.channel, body: "not found", contentType: "text/plain; charset=utf-8", status: .notFound)
                    return
                }
            }
        }
    }

    private static func respondWasm(channel: Channel) async throws {
        guard let url = WebUIBoot.wasmProductURL(productName: "WebUIClient"),
              let data = try? Data(contentsOf: url) else {
            try await respond(channel: channel, body: "not found", contentType: "text/plain; charset=utf-8", status: .notFound)
            return
        }
        var head = HTTPResponseHead(version: .http1_1, status: .ok)
        head.headers.replaceOrAdd(name: "Content-Type", value: "application/wasm")
        head.headers.replaceOrAdd(name: "Content-Length", value: "\(data.count)")
        head.headers.replaceOrAdd(name: "Connection", value: "close")
        head.headers.replaceOrAdd(name: "Cache-Control", value: "public, max-age=31536000, immutable")
        var buf = ByteBuffer()
        buf.writeBytes(data)
        _ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head))
        _ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.body(buf))
        try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil)).get()
    }

    private static func respond(channel: Channel, body: String, contentType: String, status: HTTPResponseStatus) async throws {
        var head = HTTPResponseHead(version: .http1_1, status: status)
        head.headers.replaceOrAdd(name: "Content-Type", value: contentType)
        head.headers.replaceOrAdd(name: "Content-Length", value: "\(body.utf8.count)")
        head.headers.replaceOrAdd(name: "Connection", value: "close")
        // parity with the demo/auth servers.
        head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
        head.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        head.headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
        var buf = ByteBuffer()
        buf.writeString(body)
        _ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head))
        _ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.body(buf))
        try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil)).get()
    }
}
