import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
import WebUIDesignSystem
@testable import WebUIDesignSystemMacros

// MARK: - strict expansion helper
//
// `assertMacroExpansion` defaults its failure handler to XCTFail, which is a
// no-op under Swift Testing — every mismatch would be silently swallowed and
// reported PASS. the handler below records a real Swift Testing `Issue` so a
// divergence in the emitted text fails the suite.

private func assertExpansion(
    _ source: String,
    expanded expected: String,
    macros: [String: Macro.Type] = [
        "Wired": WiredMacro.self,
        "WireGroup": WireGroupMacro.self,
    ]
) {
    assertMacroExpansion(
        source,
        expandedSource: expected,
        macroSpecs: macros.mapValues { MacroSpec(type: $0) },
        failureHandler: { spec in Issue.record(Comment(stringLiteral: spec.message)) }
    )
}

/// asserts a misuse produces the expected diagnostic. uses the raw expander and
/// compares diagnostic messages (position-immune) — `assertMacroExpansion`'s
/// `DiagnosticSpec` binds line/column, which shift across swift-syntax
/// generations for identical source.
private func assertExpansionThrows(_ source: String, message: String) {
    let file = Parser.parse(source: source)
    let context = BasicMacroExpansionContext()
    _ = file.expand(
        macros: ["WireGroup": WireGroupMacro.self, "Wired": WiredMacro.self],
        contextGenerator: { _ in context }
    )
    let messages = context.diagnostics.map(\.message)
    #expect(messages.contains(message), "expected diagnostic \(String(reflecting: message)); got \(messages)")
}

// MARK: - expansion fixtures

@Suite("@Wired / @WireGroup macro expansion")
struct WiredMacroExpansionTests {

    @Test("@Wired on a func expands to nothing")
    func wiredOnFuncIsEmptyExpansion() {
        assertExpansion(
            """
            @Wired("cb-file", events: [.click])
            func handleAttachFile(_ event: EventData) async -> [FragmentUpdate] { [] }
            """,
            expanded: """
            func handleAttachFile(_ event: EventData) async -> [FragmentUpdate] { [] }
            """
        )
    }

    @Test("@WireGroup generates one registrar per annotated handler")
    func wireGroupGeneratesRegistrar() {
        assertExpansion(
            """
            @WireGroup("chat")
            extension Controller {
                @Wired("cb-file", events: [.click])
                func handleAttachFile(_ event: EventData) async -> [FragmentUpdate] { [] }

                @Wired("cb-send", events: [.click, .submit])
                func handleSend(_ event: EventData) async -> [FragmentUpdate] { [] }
            }
            """,
            expanded: """
            extension Controller {
                func handleAttachFile(_ event: EventData) async -> [FragmentUpdate] { [] }
                func handleSend(_ event: EventData) async -> [FragmentUpdate] { [] }

                func wireGroup_chat(_ router: EventRouter) {
                    let handleAttachFileEvents: [String] = ([.click] as [HTMLEvent]).map(\\.rawValue)
                    router.register({ event in
                        guard handleAttachFileEvents.contains(event.event.rawValue) else {
                            return []
                        }
                        return await self.handleAttachFile(event)
                    }, for: ComponentID("cb-file"))
                    let handleSendEvents: [String] = ([.click, .submit] as [HTMLEvent]).map(\\.rawValue)
                    router.register({ event in
                        guard handleSendEvents.contains(event.event.rawValue) else {
                            return []
                        }
                        return await self.handleSend(event)
                    }, for: ComponentID("cb-send"))
                }
            }
            """
        )
    }

    @Test("@WireGroup preserves declaration order")
    func wireGroupPreservesOrder() {
        assertExpansion(
            """
            @WireGroup("g")
            extension Host {
                @Wired("b", events: [.click])
                func second(_ event: EventData) async -> [FragmentUpdate] { [] }

                @Wired("a", events: [.click])
                func first(_ event: EventData) async -> [FragmentUpdate] { [] }
            }
            """,
            expanded: """
            extension Host {
                func second(_ event: EventData) async -> [FragmentUpdate] { [] }
                func first(_ event: EventData) async -> [FragmentUpdate] { [] }

                func wireGroup_g(_ router: EventRouter) {
                    let secondEvents: [String] = ([.click] as [HTMLEvent]).map(\\.rawValue)
                    router.register({ event in
                        guard secondEvents.contains(event.event.rawValue) else {
                            return []
                        }
                        return await self.second(event)
                    }, for: ComponentID("b"))
                    let firstEvents: [String] = ([.click] as [HTMLEvent]).map(\\.rawValue)
                    router.register({ event in
                        guard firstEvents.contains(event.event.rawValue) else {
                            return []
                        }
                        return await self.first(event)
                    }, for: ComponentID("a"))
                }
            }
            """
        )
    }

    @Test("@WireGroup on a struct host")
    func wireGroupOnStruct() {
        assertExpansion(
            """
            @WireGroup("g")
            struct Host {
                let app: AppState

                @Wired("x", events: [.click])
                func handler(_ event: EventData) async -> [FragmentUpdate] { [] }
            }
            """,
            expanded: """
            struct Host {
                let app: AppState
                func handler(_ event: EventData) async -> [FragmentUpdate] { [] }

                func wireGroup_g(_ router: EventRouter) {
                    let handlerEvents: [String] = ([.click] as [HTMLEvent]).map(\\.rawValue)
                    router.register({ event in
                        guard handlerEvents.contains(event.event.rawValue) else {
                            return []
                        }
                        return await self.handler(event)
                    }, for: ComponentID("x"))
                }
            }
            """
        )
    }

    @Test("default events is [.click]")
    func wiredDefaultEvents() {
        assertExpansion(
            """
            @Wired("x")
            func handler(_ event: EventData) async -> [FragmentUpdate] { [] }
            """,
            expanded: """
            func handler(_ event: EventData) async -> [FragmentUpdate] { [] }
            """
        )
    }

    @Test("a .custom(_:) event keeps its payload — the case name is not the wire name")
    func customEventKeepsPayload() {
        assertExpansion(
            """
            @WireGroup("g")
            extension Host {
                @Wired("cb-split", events: [.custom("split:commit")])
                func handleSplit(_ event: EventData) async -> [FragmentUpdate] { [] }
            }
            """,
            expanded: """
            extension Host {
                func handleSplit(_ event: EventData) async -> [FragmentUpdate] { [] }

                func wireGroup_g(_ router: EventRouter) {
                    let handleSplitEvents: [String] = ([.custom("split:commit")] as [HTMLEvent]).map(\\.rawValue)
                    router.register({ event in
                        guard handleSplitEvents.contains(event.event.rawValue) else {
                            return []
                        }
                        return await self.handleSplit(event)
                    }, for: ComponentID("cb-split"))
                }
            }
            """
        )
    }

    @Test("a non-literal events expression is carried through, not collapsed to []")
    func nonLiteralEventsExpression() {
        assertExpansion(
            """
            @WireGroup("g")
            extension Host {
                @Wired("x", events: chatEvents)
                func handler(_ event: EventData) async -> [FragmentUpdate] { [] }
            }
            """,
            expanded: """
            extension Host {
                func handler(_ event: EventData) async -> [FragmentUpdate] { [] }

                func wireGroup_g(_ router: EventRouter) {
                    let handlerEvents: [String] = (chatEvents as [HTMLEvent]).map(\\.rawValue)
                    router.register({ event in
                        guard handlerEvents.contains(event.event.rawValue) else {
                            return []
                        }
                        return await self.handler(event)
                    }, for: ComponentID("x"))
                }
            }
            """
        )
    }

    @Test("a qualified return type is the same type, not a different spelling")
    func qualifiedReturnTypeAccepted() {
        assertExpansion(
            """
            @Wired("x")
            func handler(_ event: EventData) async -> [WebUI.FragmentUpdate] { [] }
            """,
            expanded: """
            func handler(_ event: EventData) async -> [WebUI.FragmentUpdate] { [] }
            """
        )
    }
}

// MARK: - negative cases

@Suite("@Wired / @WireGroup macro misuse")
struct WiredMacroNegativeTests {

    @Test("@Wired on a non-func throws")
    func wiredOnNonFuncThrows() {
        assertExpansionThrows(
            """
            @Wired("x", events: [.click])
            let value: Int = 1
            """,
            message: "@Wired can only be applied to a func"
        )
    }

    @Test("@Wired on a non-async func throws")
    func wiredOnNonAsyncThrows() {
        assertExpansionThrows(
            """
            @Wired("x", events: [.click])
            func handler(_ event: EventData) -> [FragmentUpdate] { [] }
            """,
            message: "@Wired on 'handler' requires an 'async' function"
        )
    }

    @Test("@Wired with wrong return type throws")
    func wiredWrongReturnThrows() {
        assertExpansionThrows(
            """
            @Wired("x", events: [.click])
            func handler(_ event: EventData) async -> Int { 0 }
            """,
            message: "@Wired on 'handler' must return '[FragmentUpdate]', got 'Int'"
        )
    }

    @Test("an interpolated id is not a compile-time id")
    func interpolatedIdThrows() {
        assertExpansionThrows(
            """
            @Wired("cb-\\(suffix)")
            func handler(_ event: EventData) async -> [FragmentUpdate] { [] }
            """,
            message: "@Wired requires an id string literal (interpolation is not a compile-time id)"
        )
    }

    @Test("duplicate id within a group throws")
    func duplicateIdThrows() {
        assertExpansionThrows(
            """
            @WireGroup("g")
            extension Controller {
                @Wired("cb-file", events: [.click])
                func a(_ event: EventData) async -> [FragmentUpdate] { [] }

                @Wired("cb-file", events: [.click])
                func b(_ event: EventData) async -> [FragmentUpdate] { [] }
            }
            """,
            message: "wire id \"cb-file\" already declared by a in group \"g\""
        )
    }

    @Test("bad group name throws")
    func badGroupNameThrows() {
        assertExpansionThrows(
            """
            @WireGroup("Chat")
            extension Controller {
                @Wired("x", events: [.click])
                func handler(_ event: EventData) async -> [FragmentUpdate] { [] }
            }
            """,
            message: "@WireGroup name 'Chat' must match [a-z][a-z0-9_]*"
        )
    }

    @Test("non-nominal host throws")
    func nonNominalHostThrows() {
        assertExpansionThrows(
            """
            @WireGroup("g")
            protocol P {
                @Wired("x", events: [.click])
                func handler(_ event: EventData) async -> [FragmentUpdate] { [] }
            }
            """,
            message: "@WireGroup can only be applied to a struct, class, or extension"
        )
    }
}