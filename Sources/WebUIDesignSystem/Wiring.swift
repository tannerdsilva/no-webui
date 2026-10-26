import WebUI

// MARK: - @Wired / @WireGroup

/// marker annotation on a handler: `@WireGroup` reads the annotated func
/// members in its host and emits one `router.register` call per handler.
/// peer role, empty expansion — the marker itself contributes nothing to the
/// host; all generation happens in the enclosing group macro.
///
/// ```swift
/// @WireGroup("chat")
/// extension Controller {
///     @Wired("cb-file", events: [.click])
///     func handleAttachFile(_ event: EventData) async -> [FragmentUpdate] { … }
/// }
/// ```
/// - Parameter id: the component id this handler is registered for.
/// - Parameter events: the event types this handler accepts; anything else
///   returns empty fragments from the generated registration block.
@attached(peer)
public macro Wired(_ id: String, events: [HTMLEvent] = [.click]) =
    #externalMacro(module: "WebUIDesignSystemMacros", type: "WiredMacro")

/// container macro: generates one `wireGroup_<name>(_ router:)` registrar on
/// the host type from the `@Wired`-annotated func members it sees, in
/// declaration order. one registration per annotated handler; a duplicate id
/// inside a group is a compile error.
///
/// ```swift
/// @WireGroup("chat")
/// extension Controller {
///     @Wired("cb-file", events: [.click])
///     func handleAttachFile(_ event: EventData) async -> [FragmentUpdate] { … }
/// }
/// // controller.wireGroup_chat(router)
/// ```
/// - Parameter name: the group name, which becomes the identifier fragment of
///   the generated `wireGroup_<name>` method. must match `[a-z][a-z0-9_]*`.
// the registrar's name is `wireGroup_<group>`, and `<group>` is a macro
// argument — `names: named(...)` cannot enumerate it, and this compiler rejects
// `prefixed(wireGroup_)` for a member macro whose name is built at expansion
// time ("declaration name 'wireGroup_chat' is not covered by macro"). `arbitrary`
// is therefore required, not a shortcut.
@attached(member, names: arbitrary)
public macro WireGroup(_ name: String) =
    #externalMacro(module: "WebUIDesignSystemMacros", type: "WireGroupMacro")

// MARK: - @HTMLComponent

/// the content-case vocabulary for ``HTMLComponent``: one case per content
/// source. the case name is both the init parameter label and the generated
/// `Content` enum case.
public struct ContentCase: Sendable {
    public enum Style: Sendable { case text, builder }
    public let name: String
    public let style: Style
    public let unlabeled: Bool

    public static func text(_ name: String, unlabeled: Bool = false) -> ContentCase {
        ContentCase(name: name, style: .text, unlabeled: unlabeled)
    }

    public static func builder(_ name: String) -> ContentCase {
        ContentCase(name: name, style: .builder, unlabeled: false)
    }
}

/// one init is generated per content case; every stored property of the host
/// struct becomes a shared parameter (declaration order and default
/// expressions preserved verbatim); computed properties are skipped.
///
/// ```swift
/// @HTMLComponent(.text("label", unlabeled: true), .builder("views"))
/// struct ArcButton: WebUI.View {
///     var id: String? = nil
///     var body: some View { … }
/// }
/// ```
/// - Parameter cases: the content cases, one of which may be a `.builder`; it
///   is always the trailing parameter and carries `@ViewBuilder`.
@attached(member, names: named(init), named(content), named(Content))
public macro HTMLComponent(_ cases: ContentCase...) =
    #externalMacro(module: "WebUIDesignSystemMacros", type: "ComponentMacro")
