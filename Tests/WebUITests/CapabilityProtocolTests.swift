import Testing
import WebUI
import WebUICore

// W2.1's invariant, enforced where it cannot be argued with: at compile time.
//
// `BareView` conforms to `View` and implements rendering, nothing else. every
// capability in `Capabilities.swift` conforms the same way — one word, no
// members. if anyone gives `View` another requirement, or gives a capability
// protocol a requirement without a default, this file stops compiling.
//
// that is the whole test, and it is the right shape for this claim: "no
// capability adds a `View` requirement" is a statement about what compiles, so
// compiling is what checks it. a reflection-based version would assert a count
// an author could satisfy without understanding why.

/// the minimal view: rendering and nothing else.
private struct BareView: View {
    func render() -> String { "bare" }
}

/// each capability, conformed in one word — no members, no ceremony.
private struct BareInteractive: View, Interactive {
    func render() -> String { "i" }
}

private struct BareStreaming: View, StreamingContent {
    func render() -> String { "s" }
}

private struct BareAsync: View, AsyncContent {
    func render() -> String { "a" }
}

/// `Identified` and `Recoverable` do have requirements; the defaults answer them.
private struct BareIdentified: View, Identified {
    func render() -> String { "id" }
}

private struct BareRecoverable: View, Recoverable {
    func render() -> String { "r" }
}

@Suite("capabilities never add a View requirement")
struct CapabilityProtocolTests {

    @Test("a view that implements rendering alone conforms to View")
    func bareViewConforms() {
        #expect(BareView().render() == "bare")
    }

    @Test("every capability conforms in one word")
    func capabilitiesAreOneWord() {
        #expect(BareInteractive().render() == "i")
        #expect(BareStreaming().render() == "s")
        #expect(BareAsync().render() == "a")
        #expect(BareIdentified().render() == "id")
        #expect(BareRecoverable().render() == "r")
    }

    @Test("the defaulted capability requirements answer without work")
    func defaultsAnswer() {
        #expect(BareIdentified().stableID == nil)
        #expect(BareRecoverable().fallback.render() == "")
    }

    @Test("a capability is a distinct thing a caller can ask for")
    func capabilitiesAreDistinct() {
        // asked through `any View`, so this is a real dynamic check rather than
        // a cast the compiler already knows the answer to.
        let views: [any View] = [BareInteractive(), BareView(), BareIdentified()]
        #expect(views[0] is any Interactive)
        #expect(!(views[1] is any Interactive))
        #expect(views[2] is any Identified)
        // and a plain view is not accidentally interactive.
        #expect(!(views[1] is any Identified))
    }

    @Test("a bare view round-trips through the render buffer")
    func bareViewRendersIntoBuffer() {
        var buffer = HTMLBuffer()
        BareView().render(into: &buffer)
        #expect(buffer.finish() == "bare")
    }
}