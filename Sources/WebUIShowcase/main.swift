import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import WebUI
import WebUIDesignSystem

let logger = Logger(label: "webui.showcase")

// Parse arguments
if let generateIndex = CommandLine.arguments.firstIndex(of: "--generate"),
   generateIndex + 1 < CommandLine.arguments.count {
    // Generate mode: render to file and exit
    let outputPath = CommandLine.arguments[generateIndex + 1]
    let pageHTML = renderShowcase()
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try pageHTML.write(to: outputURL, atomically: true, encoding: .utf8)
    logger.info("showcase page written to \(outputPath) (\(pageHTML.utf8.count) bytes)")
} else {
    // Server mode: start HTTP server
    var port = 9091
    if let portIndex = CommandLine.arguments.firstIndex(of: "--port"),
       portIndex + 1 < CommandLine.arguments.count {
        port = Int(CommandLine.arguments[portIndex + 1]) ?? 9091
    }

    let pageHTML = renderShowcase()
    logger.info("showcase page rendered (\(pageHTML.utf8.count) bytes)")

    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

    let bootstrap = ServerBootstrap(group: eventLoopGroup)
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .childChannelInitializer { channel in
            channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                channel.pipeline.addHandler(ShowcaseHTTPHandler(pageHTML: pageHTML, logger: logger))
            }
        }
        .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

    let channel = try await bootstrap.bind(host: "0.0.0.0", port: port).get()
    logger.info("WebUI UI Showcase running at http://localhost:\(port)")

    try await channel.closeFuture.get()
    try await eventLoopGroup.shutdownGracefully()
}

// MARK: - Page Rendering
func renderShowcase() -> String {
    let doc = WebUIDocument(
        title: "WebUI UI Showcase",
        body: ShowcasePage().render()
    )
    return doc.render()
}

// MARK: - HTTP Handler
private final class ShowcaseHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let pageHTML: String
    private let logger: Logger

    init(pageHTML: String, logger: Logger) {
        self.pageHTML = pageHTML
        self.logger = logger
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = unwrapInboundIn(data)
        switch reqPart {
        case .head(let head):
            handleRequest(head, context: context)
        case .body, .end:
            break
        }
    }

    private func handleRequest(_ head: HTTPRequestHead, context: ChannelHandlerContext) {
        let response: (String, String)
        switch (head.method, head.uri) {
        case (.GET, "/"):
            response = ("text/html; charset=utf-8", pageHTML)
        case (.GET, "/ui/styles.css"):
            response = ("text/css; charset=utf-8", WebUIAssets.css)
        case (.GET, "/ui/scripts.js"):
            response = ("application/javascript; charset=utf-8", WebUIAssets.js)
        default:
            response = ("text/plain; charset=utf-8", "404 Not Found")
        }

        var buffer = context.channel.allocator.buffer(capacity: response.1.utf8.count)
        buffer.writeString(response.1)

        let headers = HTTPHeaders([
            ("Content-Type", response.0),
            ("Content-Length", "\(response.1.utf8.count)"),
        ])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}
