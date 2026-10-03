import WebUICore

// MARK: - the server path

/// the server placement of a hot view: `@HotView` generates conformance, and
/// hand-writing it remains possible and tested (the hand-written-equivalent
/// rule, §9). the descriptor is the greppable value the registry scan and the
/// build lint read; the render entry point is the same `render(state:)` the
/// hot placement diffs — one body, two emitters.
public protocol ContinuumServerPath {
    /// name · grants · budget · class — the greppable summary of the declaration.
    static var continuumDescriptor: ContinuumDescriptor { get }
}

// MARK: - the descriptor

/// the generated, greppable summary of an `@HotView` declaration (§t3.1's
/// generated-members table): the island name, the declared capabilities
/// (`grants`, by type — `wireName` is the wire spelling), the island budget,
/// and the class vocabulary (`className`, joined from a sibling `@HotClass`).
public struct ContinuumDescriptor: Equatable, Sendable {
    public let name: String
    public let grants: [any HostCapability.Type]
    public let budget: IslandBudget
    public let className: String

    public init(name: String, grants: [any HostCapability.Type], budget: IslandBudget, className: String) {
        self.name = name
        self.grants = grants
        self.budget = budget
        self.className = className
    }

    /// equality compares grants by `wireName`: the wire spelling is the
    /// contract the engine and the lint key by, and it is stable across the
    /// separate generations an equivalence test compares.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
            && lhs.budget == rhs.budget
            && lhs.className == rhs.className
            && lhs.grants.map { $0.wireName } == rhs.grants.map { $0.wireName }
    }
}