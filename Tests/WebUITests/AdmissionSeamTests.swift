import Logging
import NIOEmbedded
import NIOCore
import Testing
import WebUI
import WebUIServer

// MARK: - 0.8 admission seam
//
// the seam exists so a later stage can answer a capacity refusal with a 503
// without editing `WebUIServer.swift`. these tests pin the three claims that
// makes: the refusal carries a real 503 + `Retry-After`, the responder answers a
// refused connection's first request, and a connection that sends nothing is
// closed by the read-idle window rather than answered.

private let rejectionLog = Logger(label: "webui.tests.admission")

@Suite("Admission")
struct AdmissionTests {

	@Test("a refusal carries a 503 with Retry-After and a body naming the limit")
	func rejectionShape() {
		let rejection = AdmissionRejection(kind: .connections, limit: 256)
		let wire = String(decoding: rejection.wireBytes(), as: UTF8.self)

		#expect(wire.hasPrefix("HTTP/1.1 503 Service Unavailable\r\n"))
		#expect(wire.contains("Retry-After: 1\r\n"))
		#expect(wire.contains("Content-Type: text/plain; charset=utf-8\r\n"))
		#expect(wire.contains("Content-Length: \(rejection.body.utf8.count)\r\n"))
		#expect(wire.contains("Connection: close\r\n"))
		#expect(wire.hasSuffix(rejection.body))
		#expect(rejection.body.contains("connections"))
		#expect(rejection.body.contains("256"))
		// the head and the body are separated by exactly one blank line
		#expect(wire.components(separatedBy: "\r\n\r\n").count == 2)
	}

	@Test("a refused connection's first request is answered 503, then closed")
	func responderAnswersFirstRequest() throws {
		let rejection = AdmissionRejection(kind: .connections, limit: 2)
		let channel = EmbeddedChannel()
		try channel.pipeline.syncOperations.addHandler(
			AdmissionRejectionResponder(response: rejection.wireBytes())
		)

		try channel.writeInbound(ByteBuffer(string: "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n"))
		let written = try #require(try channel.readOutbound(as: ByteBuffer.self))
		let text = String(buffer: written)
		#expect(text.hasPrefix("HTTP/1.1 503 Service Unavailable"))
		#expect(text.contains("Retry-After: 1"))

		// the write completes, then the responder closes the channel
		channel.embeddedEventLoop.run()
		#expect(channel.isActive == false)
	}

	@Test("a refused connection that sends nothing is written nothing")
	func requestlessConnectGetsNoUnsolicitedBytes() throws {
		let rejection = AdmissionRejection(kind: .connections, limit: 2)
		let channel = EmbeddedChannel()
		try channel.pipeline.syncOperations.addHandler(
			AdmissionRejectionResponder(response: rejection.wireBytes())
		)
		channel.embeddedEventLoop.run()
		#expect(try channel.readOutbound(as: ByteBuffer.self) == nil)
		_ = try? channel.finish()
	}

	@Test("the answer disposition installs the responder on the refused channel")
	func answerDisposition() throws {
		let gate = ConnectionGate(maximum: 1)
		#expect(gate.tryAcquire())
		let admission = Admission(
			gate: gate,
			logger: rejectionLog,
			disposition: .answer,
			readIdleSeconds: 5
		)
		let channel = EmbeddedChannel()
		#expect(admission.admit(channel) == false)

		try channel.writeInbound(ByteBuffer(string: "GET / HTTP/1.1\r\n\r\n"))
		let written = try #require(try channel.readOutbound(as: ByteBuffer.self))
		#expect(String(buffer: written).hasPrefix("HTTP/1.1 503 Service Unavailable"))
		#expect(admission.refusalCount == 1)
		_ = try? channel.finish()
	}

	@Test("the answer disposition installs a read-idle window and the idle close")
	func answerDispositionInstallsIdleWindow() throws {
		let gate = ConnectionGate(maximum: 1)
		#expect(gate.tryAcquire())
		let admission = Admission(
			gate: gate,
			logger: rejectionLog,
			disposition: .answer,
			readIdleSeconds: 5
		)
		let channel = EmbeddedChannel()
		#expect(admission.admit(channel) == false)

		// the timeout itself is `IdleStateHandler`'s, and its scheduling mixes
		// wall-clock with event-loop time — so this pins what the seam installs
		// (the handler, its configured window, and the close behind it) rather
		// than pretending an `EmbeddedEventLoop` can drive it.
		let idleContext = try channel.pipeline.context(handlerType: IdleStateHandler.self).wait()
		let idle = try #require(idleContext.handler as? IdleStateHandler)
		#expect(idle.readTimeout == .seconds(5))
		_ = try channel.pipeline.context(handlerType: AdmissionIdleCloseHandler.self).wait()
		_ = try? channel.finish()
	}

	@Test("the decision admits up to the cap and counts every refusal")
	func decisionCountsRefusals() {
		let gate = ConnectionGate(maximum: 2)
		let admission = Admission(gate: gate, logger: rejectionLog)

		#expect(admission.decide() == AdmissionDecision.admit)
		#expect(admission.decide() == AdmissionDecision.admit)
		#expect(admission.refusalCount == 0)
		#expect(admission.rejection == nil)

		guard case .refuse(let rejection) = admission.decide() else {
			Issue.record("a third acquisition against a cap of two must be refused")
			return
		}
		#expect(rejection.kind == .connections)
		#expect(rejection.limit == 2)
		#expect(admission.refusalCount == 1)
		#expect(admission.rejection == rejection)

		// a released slot is capacity again
		gate.release()
		#expect(admission.decide() == AdmissionDecision.admit)
	}

	@Test("today's disposition refuses with a bare close and no bytes")
	func closeDispositionWritesNothing() throws {
		let gate = ConnectionGate(maximum: 1)
		#expect(gate.tryAcquire())
		let admission = Admission(gate: gate, logger: rejectionLog)
		let channel = EmbeddedChannel()

		#expect(admission.admit(channel) == false)
		channel.embeddedEventLoop.run()
		#expect(channel.isActive == false)
		#expect(try channel.readOutbound(as: ByteBuffer.self) == nil)
	}
}
