import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import WebUI
import WebUIDesignSystem

// MARK: - WebUI Web UI Example Server
@main
struct WebUIExample {
    static func main() async throws {
        let logger = Logger(label: "webui.example")

        let pageHTML = renderPage()
        logger.info("page rendered (\(pageHTML.utf8.count) bytes)")

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                    channel.pipeline.addHandler(HTTPHandler(pageHTML: pageHTML, logger: logger))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        let channel = try await bootstrap.bind(host: "0.0.0.0", port: 9090).get()
        logger.info("WebUI UI Counter running at http://localhost:9090")

        try await channel.closeFuture.get()

        try await eventLoopGroup.shutdownGracefully()
    }
    static func renderPage() -> String {
        let doc = WebUIDocument(
            title: "WebUI UI Counter",
            body: Div(class: "app") {
                Header(class: "app__header") {
                    Heading("WebUI UI Counter", level: .h1)
                        .class("app__title")
                }

                Main(class: "app__content") {
                    WebUICard(variant: .elevated) {
                        Div(class: "counter") {
                            Span(class: "counter__value") {
                                Text("0")
                            }.id("counter-value")

                            Div(class: "counter__actions") {
                                WebUIButton("−", variant: .primary, size: .lg, id: "btn-decrement")
                                WebUIButton("+", variant: .primary, size: .lg, id: "btn-increment")
                            }

                            WebUIButton("Reset", variant: .ghost, size: .sm, id: "btn-reset")
                        }.class("counter")
                    }
                }

                Footer(class: "app__footer") {
                    Text("Powered by WebUI UI")
                        .class("app__footer-text")
                }
            }.render()
        )

        return doc.render()
    }
}

// MARK: - HTTP Handler
private final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
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
