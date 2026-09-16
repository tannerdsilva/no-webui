import Testing
import Synchronization
@testable import WebUIClientRuntime

// p5-t2: pure swift validation (both hosts).
struct ClientFieldValidatorTests {
	@Test("required rejects empty and blank values")
	func required() {
		let validator = ClientFieldValidator(rules: [.required])
		#expect(validator.validate("") != nil)
		#expect(validator.validate("   ") != nil)
		#expect(validator.validate("x") == nil)
	}

	@Test("email accepts plausible addresses only")
	func email() {
		let validator = ClientFieldValidator(rules: [.email])
		#expect(validator.validate("user@example.com") == nil)
		#expect(validator.validate("a.b+c@sub.example.co") == nil)
		#expect(validator.validate("no-at-sign") != nil)
		#expect(validator.validate("a@b") != nil)
		#expect(validator.validate("a b@c.com") != nil)
	}

	@Test("length and contains rules report their messages")
	func lengthAndContains() {
		let validator = ClientFieldValidator(rules: [.minLength(4), .maxLength(8), .contains("swift")])
		#expect(validator.validate("swift") == nil)
		#expect(validator.validate("x") == "at least 4 characters")
		#expect(validator.validate("swift and more") == "at most 8 characters")
		#expect(validator.validate("ruby") == "must contain \"swift\"")
	}

	@Test("first failing rule wins")
	func firstFailureWins() {
		let validator = ClientFieldValidator(rules: [.required, .email])
		#expect(validator.validate("") == "this field is required")
		#expect(validator.validate("plain") == "enter a valid email address")
	}
}

// p5-t1: the optimistic-patch ledger composed with the sync coordinator.
struct ClientPatchLedgerTests {
	@Test("records sequence and confirm prunes superseded fragments")
	func ledgerLifecycle() {
		let ledger = ClientPatchLedger()
		let sync = ClientSyncCoordinator(renderToken: "t")
		let seq1 = sync.beginLocalPatch()
		ledger.record(seq: seq1, id: "a", html: "<a/>")
		let seq2 = sync.beginLocalPatch()
		ledger.record(seq: seq2, id: "b", html: "<b/>")
		#expect(ledger.pending == ["a": 1, "b": 2])
		#expect(sync.pendingLocalPatches == 2)

		// authority confirms up to seq1: only fragment a was superseded.
		let confirmedSeq = 1
		#expect(sync.applyAuthoritative(seq: confirmedSeq) == 1)
		let superseded = ledger.confirm(authoritativeSeq: confirmedSeq)
		#expect(superseded == ["a"])
		#expect(ledger.pending == ["b": 2])
		#expect(sync.pendingLocalPatches == 1)
	}

	@Test("rollback restores the pre-optimistic html")
	func rollback() {
		let ledger = ClientPatchLedger()
		ledger.record(seq: 1, id: "x", html: "<div>optimistic</div>")
		let prior = ledger.rollback(id: "x")
		#expect(prior == "<div>optimistic</div>")
		#expect(ledger.pending.isEmpty)
		#expect(ledger.rollback(id: "x") == nil)
	}
}
