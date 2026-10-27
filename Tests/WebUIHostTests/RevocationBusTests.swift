import Foundation
import Synchronization
import Testing
import NIOCore
import NIOPosix
import WebUI
import WebUIServer
import WebUIAuth
import WebUIHost

// MARK: - C4 gate: revocation
//
// the gate, verbatim: "logout closes the live socket within one event-loop
// turn; an event after logout is refused; `handlerCount` for that session is 0".
//
// the first is not a comment and not a channel double: the test below binds a
// real listener on 127.0.0.1, connects a real client, tracks the *accepted* NIO
// channel in the bus with a close action, then logs the session out and waits
// for the peer to observe EOF. the close the peer sees is the proof.

@Suite("revocation")
struct RevocationBusTests {

	private let sessionA = SessionKey(hash: [1, 1, 1, 1])
	private let sessionB = SessionKey(hash: [2, 2, 2, 2])

	// MARK: the real socket

	@Test("logout closes the live socket, observed by the peer")
	func logoutClosesTheLiveSocket() async throws {
		try await withEventLoopGroup { group in
			// a real listener on a real port
			let accepted = group.next().makePromise(of: Channel.self)
			let server = try await ServerBootstrap(group: group)
				.childChannelInitializer { channel in
					channel.pipeline.addHandler(AcceptProbe(accepted: accepted))
				}
				.bind(host: "127.0.0.1", port: 0)
				.get()
			let port = try #require(server.localAddress?.port)

			// a real client, whose channelInactive is the observation
			let closed = group.next().makePromise(of: Void.self)
			let client = try await ClientBootstrap(group: group)
				.channelInitializer { channel in
					channel.pipeline.addHandler(CloseProbe(closed: closed))
				}
				.connect(host: "127.0.0.1", port: port)
				.get()
			let serverSide = try await accepted.futureResult.get()
			#expect(client.isActive)
			#expect(serverSide.isActive)

			// the host's logout path, reduced to its revocation half
			let bus = SocketRevocationBus()
			let token = ConnectionToken.next { serverSide.close(promise: nil) }
			await bus.track(token, session: sessionA)
			#expect(await bus.connectionCount(for: sessionA) == 1)

			let clock = ContinuousClock()
			let elapsed = try await clock.measure {
				await bus.revoke(session: sessionA)
				// the peer's EOF: this is what "closed" means, from outside
				try await withThrowingTaskGroup(of: Void.self) { racing in
					racing.addTask { try await closed.futureResult.get() }
					racing.addTask {
						try await Task.sleep(for: .seconds(2))
						throw CloseTimeout()
					}
					try await racing.next()
					racing.cancelAll()
				}
			}

			#expect(!client.isActive)
			#expect(await bus.connectionCount(for: sessionA) == 0)
			#expect(await bus.trackedCount == 0)
			// immediate, not on a timer: the close was scheduled in the same turn
			// the revoke ran, so the whole exchange is far inside any idle window.
			#expect(elapsed < .seconds(1))

			try await server.close().get()
		}
	}

	// MARK: what logout leaves behind

	@Test("an event after logout is refused, and the session holds no handlers")
	func eventAfterLogoutIsRefused() async throws {
		let fixture = TestHost(pages: [Fixture.page("/")])
		let login = try await fixture.logIn()

		let html = bodyText(try await fixture.host.respond(to: Fixture.request("/", cookie: login.cookie)))
		let token = RenderKey(value: try #require(renderToken(in: html)))
		let router = try #require(await fixture.table.router(for: login.sessionKey, renderToken: token))
		// the page registered its control in the render session the token names
		#expect(router.router.handlerCount(in: RenderSessionID(token.value)) == 1)

		_ = try await fixture.host.signOut(for: Fixture.request("/", cookie: login.cookie))

		// the handlers are gone ...
		#expect(router.router.handlerCount(in: RenderSessionID(token.value)) == 0)
		#expect(await fixture.table.router(for: login.sessionKey, renderToken: token) == nil)
		// ... and a frame that arrives anyway is refused, naming the token
		let dispatch = await fixture.host.dispatch(click(), session: login.sessionKey, renderToken: token)
		#expect(dispatch.isRefused)
		#expect(dispatch.refreshedToken == nil)
	}

	@Test("revocation closes only the revoked session's sockets")
	func revokeIsScoped() async throws {
		let bus = SocketRevocationBus()
		let closes = CountingCloses()

		let a = ConnectionToken.next { closes.record("a") }
		let b = ConnectionToken.next { closes.record("b") }
		await bus.track(a, session: sessionA)
		await bus.track(b, session: sessionB)

		await bus.revoke(session: sessionA)

		#expect(closes.values == ["a"])
		#expect(await bus.connectionCount(for: sessionA) == 0)
		#expect(await bus.connectionCount(for: sessionB) == 1)
	}

	@Test("an untracked connection is not closed twice")
	func untrackedIsNotClosedAgain() async throws {
		let bus = SocketRevocationBus()
		let closes = CountingCloses()
		let token = ConnectionToken.next { closes.record("x") }

		await bus.track(token, session: sessionA)
		// the socket ended on its own (idle reap, client close) and told the bus
		await bus.untrack(token)
		await bus.revoke(session: sessionA)

		// revocation must not close a descriptor the kernel already reclaimed
		#expect(closes.values.isEmpty)
		#expect(await bus.trackedCount == 0)
	}

	@Test("re-tracking a connection under another session moves it")
	func reTrackMoves() async throws {
		let bus = SocketRevocationBus()
		let closes = CountingCloses()
		let token = ConnectionToken.next { closes.record("moved") }

		await bus.track(token, session: sessionA)
		await bus.track(token, session: sessionB)

		#expect(await bus.connectionCount(for: sessionA) == 0)
		#expect(await bus.connectionCount(for: sessionB) == 1)

		await bus.revoke(session: sessionA)
		#expect(closes.values.isEmpty)

		await bus.revoke(session: sessionB)
		#expect(closes.values == ["moved"])
	}

	@Test("revoking a session with no sockets is a no-op")
	func revokeEmptyIsNoop() async throws {
		let bus = SocketRevocationBus()
		await bus.revoke(session: sessionA)
		#expect(await bus.trackedCount == 0)
	}
}

// MARK: - helpers

struct CloseTimeout: Error {}

/// run `body` against a fresh single-threaded event loop group and shut it down
/// whatever happens. `syncShutdownGracefully` is `noasync`, so the cleanup has to
/// be the async form — and it has to be here rather than in a `defer`, because
/// `defer` cannot await.
func withEventLoopGroup(_ body: (MultiThreadedEventLoopGroup) async throws -> Void) async throws {
	let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
	do {
		try await body(group)
	} catch {
		try? await group.shutdownGracefully()
		throw error
	}
	try await group.shutdownGracefully()
}

/// records that a connection's peer went away.
final class CloseProbe: ChannelInboundHandler {
	typealias InboundIn = ByteBuffer

	private let closed: EventLoopPromise<Void>

	init(closed: EventLoopPromise<Void>) {
		self.closed = closed
	}

	func channelInactive(context: ChannelHandlerContext) {
		closed.succeed(())
		context.fireChannelInactive()
	}
}

/// hands the accepted channel back to the test.
final class AcceptProbe: ChannelInboundHandler {
	typealias InboundIn = ByteBuffer

	private let accepted: EventLoopPromise<Channel>

	init(accepted: EventLoopPromise<Channel>) {
		self.accepted = accepted
	}

	func channelActive(context: ChannelHandlerContext) {
		accepted.succeed(context.channel)
		context.fireChannelActive()
	}
}

/// a thread-safe tally of close actions, so a fake token can prove it was (or
/// was not) closed.
final class CountingCloses: Sendable {
	private let storage = Mutex<[String]>([])

	func record(_ name: String) {
		storage.withLock { $0.append(name) }
	}

	var values: [String] {
		storage.withLock { $0 }
	}
}
