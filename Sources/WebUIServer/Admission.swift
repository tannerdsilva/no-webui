import Logging
import NIOCore
import Synchronization
import WebUI

// MARK: - Admission
//
// the seam a capacity refusal lives behind. before this file, the decision was
// three lines inside the bind child initializer: acquire a slot or close the
// socket, with no status, no log and no counter. moving the decision here means
// a later stage can make a refusal *answerable* (503 + `Retry-After`) without
// touching `WebUIServer.swift` — which stage 2 does not own.
//
// today's disposition is `.answer`: a refused connection's *first request* is
// answered `503` + `Retry-After` from raw bytes, because a capacity refusal
// that nobody can see is the failure mode §7.2 rule 1 bans. `.close` survives
// as the explicit 1.x opt-in for a host that pins the old wire behaviour.
//
// why a request-less connect is closed rather than answered: the refused
// channel carries no HTTP codec (`channel.pipeline` has no
// `HTTPResponseEncoder` at this point), so there is no decoded request to
// answer. a connect that never sends a byte has nothing to refuse at all — it
// is closed by the read-idle window. that is what the `.answer` disposition
// installs alongside its responder.

/// how a refusal is delivered to the client.
package enum AdmissionDisposition: Sendable, Equatable {
	/// the 1.x behaviour, opt-in only: close the connection with no response
	/// bytes. kept so a host can pin the old wire shape; nothing in the
	/// framework selects it.
	case close
	/// answer the connection's first request `503` + `Retry-After`, then
	/// close. a connection that sends nothing is closed by the read-idle
	/// window instead.
	case answer
}

/// what a refusal would say if it were answered: the status line, the headers
/// and a body naming the capacity that ran out.
package struct AdmissionRejection: Sendable, Equatable {
	/// the capacity that is full.
	package let kind: CapacityKind
	/// the limit that was reached.
	package let limit: Int
	/// how long the client should wait before retrying, in seconds.
	package let retryAfterSeconds: Int

	package init(kind: CapacityKind, limit: Int, retryAfterSeconds: Int = 1) {
		self.kind = kind
		self.limit = limit
		self.retryAfterSeconds = retryAfterSeconds
	}

	/// `HTTP/1.1 503 Service Unavailable`.
	package var statusLine: String {
		"HTTP/1.1 503 Service Unavailable"
	}

	/// the body: one line naming the capacity and its limit, so an operator
	/// reading a `curl` output learns which knob to turn.
	package var body: String {
		"service unavailable: \(kind.rawValue) at capacity (limit \(limit))\n"
	}

	/// the headers a 503 carries, in wire order.
	package var headers: [(name: String, value: String)] {
		[
			(name: "Retry-After", value: "\(retryAfterSeconds)"),
			(name: "Content-Type", value: "text/plain; charset=utf-8"),
			(name: "Content-Length", value: "\(body.utf8.count)"),
			(name: "Connection", value: "close"),
		]
	}

	/// the complete response, head + body, as bytes: what a refusal responder
	/// writes to a channel that has no HTTP codec to encode a head for it.
	package func wireBytes() -> [UInt8] {
		var out = Array((statusLine + "\r\n").utf8)
		for header in headers {
			out.append(contentsOf: "\(header.name): \(header.value)\r\n".utf8)
		}
		out.append(contentsOf: "\r\n".utf8)
		out.append(contentsOf: body.utf8)
		return out
	}
}

/// the outcome of asking to admit one connection.
package enum AdmissionDecision: Sendable, Equatable {
	case admit
	case refuse(AdmissionRejection)
}

/// answers a refused connection's first request with a canned response and
/// closes it.
///
/// it reads raw bytes — the refused channel never had a codec installed, so
/// there is no `HTTPServerRequestPart` to decode and waiting for one would hang
/// the answer forever. the first inbound bytes are the request line, which is
/// all a canned refusal needs.
package final class AdmissionRejectionResponder: ChannelInboundHandler, @unchecked Sendable {
	package typealias InboundIn = ByteBuffer
	package typealias OutboundOut = ByteBuffer

	private let response: [UInt8]
	private var answered = false

	package init(response: [UInt8]) {
		self.response = response
	}

	package func channelRead(context: ChannelHandlerContext, data: NIOAny) {
		// a refused connection is answered once and closed: a pipelined second
		// request is not served, which is what `Connection: close` promises.
		guard !answered else { return }
		answered = true
		var buffer = context.channel.allocator.buffer(capacity: response.count)
		buffer.writeBytes(response)
		context.writeAndFlush(Self.wrapOutboundOut(buffer)).whenComplete { _ in
			context.close(promise: nil)
		}
	}
}

/// close the channel when the read-idle window elapses. the refused path's
/// twin of `ServerIdleCloseHandler`, typed for a channel with no codec.
package final class AdmissionIdleCloseHandler: ChannelInboundHandler, @unchecked Sendable {
	package typealias InboundIn = ByteBuffer

	package init() {}

	package func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
		if event is IdleStateHandler.IdleStateEvent {
			context.close(promise: nil)
		} else {
			context.fireUserInboundEventTriggered(event)
		}
	}
}

/// the admission seam: one slot per connection, and a refusal that is logged,
/// counted, and (when the disposition says so) answered.
///
/// it is a `final class` behind a `Mutex`, like `ConnectionGate` itself: the
/// slot count is shared mutable state read from every event loop, so the lock
/// is the synchronization and the type stays `Sendable` without `@unchecked`.
package final class Admission: Sendable {
	/// the slot counter — the same gate the server releases on `channelInactive`.
	package let gate: ConnectionGate
	/// how a refusal is delivered. `.answer` is the default (§7.2 rule 1);
	/// `.close` is the explicit 1.x opt-in.
	package let disposition: AdmissionDisposition
	/// the read-idle window a refused connection is held for while it sends its
	/// first request (and is closed at, when it sends none).
	package let readIdleSeconds: Int64

	private let logger: Logger
	private let refusals = Mutex(0)
	private let lastRefusal = Mutex<AdmissionRejection?>(nil)

	package init(
		gate: ConnectionGate,
		logger: Logger,
		disposition: AdmissionDisposition = .answer,
		readIdleSeconds: Int64 = 120
	) {
		self.gate = gate
		self.logger = logger
		self.disposition = disposition
		self.readIdleSeconds = readIdleSeconds
	}

	/// how many connections have been refused since the server started.
	package var refusalCount: Int {
		refusals.withLock { $0 }
	}

	/// the most recent refusal, or `nil` when nothing has been refused.
	package var rejection: AdmissionRejection? {
		lastRefusal.withLock { $0 }
	}

	/// ask for a slot without touching a channel: the decision, on its own.
	package func decide() -> AdmissionDecision {
		guard gate.tryAcquire() else {
			let refusal = AdmissionRejection(kind: .connections, limit: gate.maximum)
			record(refusal)
			return .refuse(refusal)
		}
		return .admit
	}

	/// count and log a refusal. a capacity refusal is never silent.
	private func record(_ refusal: AdmissionRejection) {
		refusals.withLock { $0 += 1 }
		lastRefusal.withLock { $0 = refusal }
		logger.error(
			"admission refused: \(refusal.kind.rawValue) at capacity (limit \(refusal.limit))"
		)
	}

	/// the server's one call: take a slot or refuse `channel`.
	///
	/// returns `true` when the connection was admitted (the caller installs the
	/// real pipeline). on refusal the disposition decides what the client sees —
	/// today, a close — and the caller fails the negotiation future either way.
	package func admit(_ channel: any Channel) -> Bool {
		switch decide() {
		case .admit:
			return true
		case .refuse(let refusal):
			switch disposition {
			case .close:
				channel.close(promise: nil)
			case .answer:
				// install the answer on the raw channel: the idle window so a
				// connect that sends nothing is closed, then the responder.
				do {
					try channel.pipeline.syncOperations.addHandler(
						IdleStateHandler(readTimeout: .seconds(readIdleSeconds))
					)
					try channel.pipeline.syncOperations.addHandler(AdmissionIdleCloseHandler())
					try channel.pipeline.syncOperations.addHandler(
						AdmissionRejectionResponder(response: refusal.wireBytes())
					)
				} catch {
					// a pipeline that cannot take the responder must still not
					// hold the connection open — and the reason it could not is
					// logged, so this close is not a third silent path.
					logger.error(
						"admission refusal could not install its responder: \(String(describing: error))"
					)
					channel.close(promise: nil)
				}
			}
			return false
		}
	}
}
