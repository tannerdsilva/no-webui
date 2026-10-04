import WebUICore

// MARK: - the view-side hot vocabulary (DESKTOP_GRADE §1.3.6 / §t3.1)
//
// `WebUI` is host-only and re-exports `WebUICore`, which re-exports
// `WebUISharedCore` — so the seam vocabulary (`ElementID`, `HotOp`,
// `HostCapability`, `IslandBudget`, `HotEffect`, `HotState`/`HotAction`) is in
// scope here and for every consumer of `import WebUI`. the macro
// *implementation* (`WebUIContinuumMacros`) is a separate, host-compiled
// target; nothing in this file is referenced from a wasm-compiled chain.
//
// one body, two emitters: a hot body produces a single `HotTree`; the server
// path renders it to html, a hot placement diffs it (`hotOps(previous:)`).
// the restricted vocabulary (`@HotBuilder`) is a *type-checker* guarantee, not
// a lint: a non-hot view inside a hot body fails to build, with a fix hint
// (the unavailable `buildExpression` overload below).

// MARK: - HotTree

/// the single concrete structure a hot body produces — the value the server
/// path renders to html and a hot placement diffs into `[HotOp]`. one diff
/// implementation, no existential per-view diffing (§t3.1).
public enum HotTree: HotPrimitive, Equatable, Sendable {
    /// no content (an empty body, or an `if` with no else).
    case empty
    /// more than one node from one body; children render in order. anonymous by
    /// design: fragments contribute no structural ops (no parent address) —
    /// their members still diff recursively.
    case fragment([HotTree])
    /// an addressed text leaf; renders `<span id="…">…</span>` so a changed
    /// `content` is exactly one `.text` op (characterData, no element churn).
    case text(id: ElementID, content: String)
    /// an addressed element; renders `<tag id="…" class="…">children</tag>`.
    case container(id: ElementID, tag: String, className: String?, children: [HotTree])
    /// an addressed element carrying extra attributes — the promotion path's
    /// carrier: `data-key`, `data-*`, `aria-*` on a component's root (`Hot`
    /// containers model only id + class; everything else rides `attended`).
    /// the attributes laminate the element the content opens; content that
    /// opens no element drops them (pinned). see `Hot.AttrWrapper`.
    indirect case attended(attributes: [Hot.HotAttribute], content: HotTree)
    /// a layout-only, anonymous gap: no address, no ops.
    case spacer

    // MARK: addresses

    /// the element address this node patches by (`nil` for anonymous nodes).
    public var elementID: ElementID? {
        switch self {
        case .text(let id, _): return id
        case .container(let id, _, _, _): return id
        case .attended(_, let content): return content.elementID
        case .empty, .fragment, .spacer: return nil
        }
    }

    /// the node-kind discriminator the keyed child diff uses to decide between
    /// "reconcile" and "remove + reinsert".
    enum Kind: Equatable {
        case empty, fragment, text, container, spacer
    }

    var kind: Kind {
        switch self {
        case .empty: return .empty
        case .fragment: return .fragment
        case .text: return .text
        case .container: return .container
        case .attended(_, let content): return content.kind
        case .spacer: return .spacer
        }
    }

    /// the builder result flattened into a container's child list: a `fragment`
    /// becomes its members, `empty` becomes no members, anything else is one
    /// child. (children are flattened at construction, so fragments never
    /// appear nested inside a container.)
    var flattenedChildren: [HotTree] {
        switch self {
        case .empty: return []
        case .fragment(let children): return children
        case .attended(_, let content): return content.flattenedChildren
        default: return [self]
        }
    }

    // MARK: rendering

    public func render() -> String {
        switch self {
        case .empty:
            return ""
        case .fragment(let children):
            return children.map { $0.render() }.joined()
        case .text(let id, let content):
            return "<span id=\"\(htmlEscape(id.raw))\">\(htmlEscape(content))</span>"
        case .container(let id, let tag, let className, let children):
            let classAttribute = className.map { " class=\"\(htmlEscape($0))\"" } ?? ""
            let inner = children.map { $0.render() }.joined()
            return "<\(tag) id=\"\(htmlEscape(id.raw))\"\(classAttribute)>\(inner)</\(tag)>"
        case .attended(let attributes, let content):
            return content.attributedRender(attributes)
        case .spacer:
            return "<div class=\"spacer\" style=\"flex:1\"></div>"
        }
    }

    /// render with `attributes` laminated onto the element this tree opens.
    /// delegates down through nested `attended` wrappers so promoted nodes
    /// compose; content that opens no element (empty / anonymous fragment /
    /// spacer) keeps its bytes and drops the attributes — there is no element
    /// to carry them (pinned).
    private func attributedRender(_ attributes: [Hot.HotAttribute]) -> String {
        switch self {
        case .attended(let inner, let content):
            return content.attributedRender(attributes + inner)
        case .container(let id, let tag, let className, let children):
            let attrText = Hot.HotAttribute.attributeText(attributes)
            let classAttribute = className.map { " class=\"\(htmlEscape($0))\"" } ?? ""
            let inner = children.map { $0.render() }.joined()
            return "<\(tag) id=\"\(htmlEscape(id.raw))\"\(classAttribute)\(attrText)>\(inner)</\(tag)>"
        case .text(let id, let content):
            let attrText = Hot.HotAttribute.attributeText(attributes)
            return "<span id=\"\(htmlEscape(id.raw))\"\(attrText)>\(htmlEscape(content))</span>"
        default:
            return render()
        }
    }

    // MARK: the diff

    public var hotTree: HotTree { self }

    /// the steady-state delta from a previously *applied* tree to this one.
    /// `nil` previous means the mount path owns the first pixels (region html,
    /// a `replace`): there is nothing applied to reconcile against, so no ops.
    /// structural ops (insert/remove/move) are emitted by the containing
    /// container's diff, which knows the parent address and sibling anchors;
    /// a root whose identity or kind changed is the region's replace.
    public func hotOps(previous: HotTree?) -> [HotOp] {
        guard let previous, self != previous else { return [] }
        switch (previous, self) {
        case (.text(let previousID, _), .text(let id, let content)):
            guard previousID == id else { return [] }
            return [.text(id, content)]

        case (.container(let previousID, let previousTag, let previousClass, let previousChildren),
              .container(let id, let tag, let className, let children)):
            guard previousID == id else { return [] }
            var ops: [HotOp] = []
            if previousClass != className {
                // the cheap row-state channel: `class` is allowlisted for the
                // engine's attr op; value escapes at the DOM API.
                ops.append(.attr(id, "class", className ?? ""))
            }
            if previousTag == tag {
                ops.append(contentsOf: HotTree.containerOps(
                    parent: id, previous: previousChildren, current: children
                ))
            }
            return ops

        case (.fragment(let previousChildren), .fragment(let children)):
            return HotTree.fragmentOps(previous: previousChildren, current: children)

        case (.attended(_, let previousContent), .attended(_, let content)):
            // attributes are stable per render by the promotion contract
            // (data-key, data-*, aria-* — constant for an addressed node), so
            // the delta is entirely the content's. an attribute-only change
            // yields no ops (v1 boundary: the engine's attr op is the future
            // channel for dynamic row state).
            return content.hotOps(previous: previousContent)

        case (_, .attended(_, let content)):
            // a promotion laminated over a previously plain node: diff against
            // the unwrapped previous.
            return content.hotOps(previous: previous)

        case (.attended(_, let previousContent), _):
            // a promotion stripped from a previously wrapped node: diff the
            // plain self against the unwrapped previous.
            return hotOps(previous: previousContent)

        default:
            // kind or identity changed at this address: structural, owned by
            // the containing diff; a root is the region's replace.
            return []
        }
    }

    // MARK: child diff (keyed by ElementID, §1.3.2 semantics)

    /// the children diff: removals first, then order corrections (`move`) and
    /// recursive deltas in current order, then insertions — so that a
    /// left-to-right apply of the emitted ops lands the current order
    /// regardless of how moves and inserts interleave. anchors are the next
    /// sibling that survived from the previous tree (else append).
    ///
    /// v1 boundary, documented: this is a survivors-order approximation, not a
    /// minimal LCS — correct for appends, removals, single moves and swaps
    /// (pinned in the macro tests); the feed/grid benches decide whether
    /// minimal-move accounting is needed.
    static func containerOps(parent: ElementID, previous: [HotTree], current: [HotTree]) -> [HotOp] {
        var ops: [HotOp] = []

        var previousByID: [ElementID: HotTree] = [:]
        var previousIndex: [ElementID: Int] = [:]
        for (index, child) in previous.enumerated() {
            if let id = child.elementID {
                previousByID[id] = child
                previousIndex[id] = index
            }
        }
        var currentIDs: Set<ElementID> = []
        for child in current {
            if let id = child.elementID { currentIDs.insert(id) }
        }
        // the sibling set both trees share: the only anchors that exist in the
        // DOM when the batch applies (removals run first, insertions last), and
        // the only siblings a `move` may be judged against.
        let survivorIDs = Set(previousByID.keys).intersection(currentIDs)

        // 1. removals — an address gone from the current tree, or one whose
        //    node kind changed (removed here, reinserted below).
        for child in previous {
            guard let id = child.elementID else { continue }
            if !currentIDs.contains(id) {
                ops.append(.remove(id))
            } else if let replacement = current.first(where: { $0.elementID == id }),
                      replacement.kind != child.kind {
                ops.append(.remove(id))
            }
        }

        // 2. order corrections + recursive deltas, in current order.
        for (index, child) in current.enumerated() {
            guard let id = child.elementID,
                  let old = previousByID[id], old.kind == child.kind else { continue }
            let previousNext = HotTree.nextSiblingID(
                in: previous, after: previousIndex[id] ?? 0, survivingInto: survivorIDs
            )
            let currentNext = HotTree.nextSiblingID(
                in: current, after: index, survivingInto: survivorIDs
            )
            if previousNext != currentNext {
                ops.append(.move(id, before: currentNext))
            }
            ops.append(contentsOf: child.hotOps(previous: old))
        }

        // 3. insertions — after every move, so anchors already sit in final order.
        for (index, child) in current.enumerated() {
            guard let id = child.elementID else { continue }
            let kindChanged = previousByID[id].map { $0.kind != child.kind } ?? false
            guard previousByID[id] == nil || kindChanged else { continue }
            let anchor = HotTree.nextSiblingID(
                in: current, after: index, survivingInto: survivorIDs
            )
            ops.append(.insert(parent: parent, before: anchor, html: child.render()))
        }

        return ops
    }

    /// fragments are anonymous: pairwise recursion at shared positions, no
    /// structural ops; unequal shapes are the region's replace.
    static func fragmentOps(previous: [HotTree], current: [HotTree]) -> [HotOp] {
        guard previous.count == current.count else { return [] }
        var ops: [HotOp] = []
        for (old, new) in zip(previous, current) {
            ops.append(contentsOf: new.hotOps(previous: old))
        }
        return ops
    }

    /// the next sibling (in `children`, after `index`) whose address is in
    /// `ids` — the anchor rule shared by moves and inserts.
    static func nextSiblingID(in children: [HotTree], after index: Int, survivingInto ids: Set<ElementID>) -> ElementID? {
        var cursor = index + 1
        while cursor < children.count {
            if let id = children[cursor].elementID, ids.contains(id) { return id }
            cursor += 1
        }
        return nil
    }
}

// MARK: - the primitive set
//
// nested under `Hot` because the full-vocabulary `Text` and `Spacer` already
// occupy module scope in `WebUICore`; `Hot.Text` keeps the plan's names while
// staying unambiguous in every file that imports both vocabularies. the set is
// deliberately small for v1 (the plan marks the initial set `[open — d3]`):
// Text · Container · Spacer. KeyedList arrives with the windowing work (t3.3)
// and AttrWrapper with the component-promotion path.

public enum Hot {}

extension Hot {

    /// an addressed text leaf: renders `<span id="…">…</span>`; a changed
    /// content is one `.text` op — characterData, no element churn.
    public struct Text: HotPrimitive {
        public let id: ElementID
        public let content: String

        public init(id: ElementID, _ content: String) {
            self.id = id
            self.content = content
        }

        public var hotTree: HotTree { .text(id: id, content: content) }

        public func render() -> String { hotTree.render() }

        public func hotOps(previous: Text?) -> [HotOp] {
            guard let previous else { return [] }
            return hotTree.hotOps(previous: previous.hotTree)
        }
    }

    /// an addressed element. `tag` is author-declared vocabulary, never data
    /// (values are escaped; the tag token is the declaration's own). a changed
    /// `className` diffs as one `.attr` op on the `class` channel.
    public struct Container: HotPrimitive {
        public let id: ElementID
        public let tag: String
        public let className: String?
        public let children: [HotTree]

        public init(id: ElementID, tag: String = "div", className: String? = nil, children: [HotTree]) {
            self.id = id
            self.tag = tag
            self.className = className
            self.children = children
        }

        public init(id: ElementID, tag: String = "div", className: String? = nil, @HotBuilder children: () -> HotTree) {
            self.init(id: id, tag: tag, className: className, children: children().flattenedChildren)
        }

        public var hotTree: HotTree {
            .container(id: id, tag: tag, className: className, children: children)
        }

        public func render() -> String { hotTree.render() }

        public func hotOps(previous: Container?) -> [HotOp] {
            guard let previous else { return [] }
            return hotTree.hotOps(previous: previous.hotTree)
        }
    }

    /// a layout-only gap: no address, no ops — it exists so hot bodies can
    /// spell spacing honestly without escaping the vocabulary.
    public struct Spacer: HotPrimitive {
        public init() {}
        public var hotTree: HotTree { .spacer }
        public func render() -> String { hotTree.render() }
        public func hotOps(previous: Spacer?) -> [HotOp] { [] }
    }

    /// one extra attribute an `AttrWrapper` laminates onto an addressed node.
    /// both halves are escaped at render; the name is author-declared
    /// vocabulary, never data.
    public struct HotAttribute: Equatable, Sendable {
        public let name: AttributeName
        public let value: String

        public init(_ name: AttributeName, _ value: String) {
            self.name = name
            self.value = value
        }

        public init(_ name: String, _ value: String) {
            self.name = AttributeName(name)
            self.value = value
        }

        /// the rendered `name="value"` text, both halves escaped.
        static func attributeText(_ attributes: [HotAttribute]) -> String {
            guard !attributes.isEmpty else { return "" }
            return attributes.map { " \(htmlEscape($0.name.raw))=\"\(htmlEscape($0.value))\"" }.joined()
        }
    }

    /// the component-promotion carrier: laminates extra attributes onto the
    /// element an existing hot node opens, without forking its structure —
    /// `Hot` containers model `id` + `class`; everything else (`data-key`,
    /// `data-*`, `aria-*`) rides a promotion. attributes are constant per
    /// render by contract; an attribute-only change is v1 out of diff scope.
    public struct AttrWrapper: HotPrimitive {
        public let attributes: [HotAttribute]
        public let content: HotTree

        public init(attributes: [HotAttribute], @HotBuilder content: () -> HotTree) {
            self.attributes = attributes
            self.content = content()
        }

        public var hotTree: HotTree { .attended(attributes: attributes, content: content) }
        public func render() -> String { hotTree.render() }
        public func hotOps(previous: AttrWrapper?) -> [HotOp] {
            hotTree.hotOps(previous: previous?.hotTree)
        }
    }

    /// keyed identity over a list body (t3.3's `KeyedList` semantics): rows
    /// reconcile by KEY, never by position. each row's address derives from
    /// its key (`<base>-k<key>`), so a reorder is a `move`, an insert a
    /// same-key `insert`, a removal a `remove` — same-key rows keep their DOM
    /// nodes, which is what lets a windowed patch (or a sorted feed) mutate
    /// only the rows that genuinely changed. each row also carries
    /// `data-key` (the engine's identity channel) via an `AttrWrapper`.
    ///
    ///     Hot.KeyedList(id: "feed", keys: ["a", "b", "c"]) { key in
    ///         Hot.Container(id: "feed-row-\(key)") { Hot.Text(id: "t-\(key)", key) }
    ///     }
    public struct KeyedList<Key: Hashable & Sendable>: HotPrimitive {
        /// the container address (its own element, anonymous children).
        public let id: ElementID
        public let tag: String
        public let rowTag: String
        public let rowClass: String?
        /// the attended rows, in list order; each row is keyed by its derived
        /// address `id-k<key>` — the identity map the diff keys on.
        public let rows: [HotTree]

        public init(
            id: ElementID,
            tag: String = "div",
            rowTag: String = "div",
            rowClass: String? = nil,
            keys: [Key],
            keyString: @escaping @Sendable (Key) -> String = { String(describing: $0) },
            @HotBuilder row: @escaping @Sendable (Key) -> HotTree
        ) {
            self.id = id
            self.tag = tag
            self.rowTag = rowTag
            self.rowClass = rowClass
            self.rows = keys.map { key in
                let keyText = keyString(key)
                let rowID = ElementID("\(id.raw)-k\(keyText)")
                return HotTree.attended(
                    attributes: [HotAttribute("data-key", keyText)],
                    content: .container(id: rowID, tag: rowTag, className: rowClass, children: [row(key)])
                )
            }
        }

        public var hotTree: HotTree { .container(id: id, tag: tag, className: nil, children: rows) }

        public func render() -> String { hotTree.render() }

        public func hotOps(previous: KeyedList?) -> [HotOp] {
            hotTree.hotOps(previous: previous?.hotTree)
        }
    }
}

// MARK: - the protocols

/// a view that can render at more than one placement. `render(state:)` is the
/// single body: the server path turns it into html, a hot placement diffs it
/// into ops.
///
/// note on §1.3.6: the architecture sketch had `HotView: View`; the operative
/// §t3.1 shape renders `HotTree`, and a state-free `View.render()` has no
/// defined meaning for a hot view (there is no initial-state vocabulary yet),
/// so the conformance is deliberately *not* declared. `HotTree` — the body —
/// is the `View`; the server adapter renders it with the state authority holds.
public protocol HotView {
    associatedtype State: HotState
    associatedtype Action: HotAction
    /// the single body: html for the server, ops for a hot placement.
    @HotBuilder func render(state: State) -> HotTree
}

/// everything a hot body may construct. `hotOps` is the steady-state delta for
/// an address that already exists; structural reconciliation (insert/remove/
/// move) is contributed by the containing tree's diff, which owns the parent
/// address and the sibling anchors.
public protocol HotPrimitive: View {
    /// the concrete tree this primitive contributes — the builder's currency.
    var hotTree: HotTree { get }
    /// the steady-state delta against the previously applied value.
    func hotOps(previous: Self?) -> [HotOp]
}

// MARK: - @HotBuilder

/// the restricted builder: only `HotPrimitive` expressions type-check inside.
/// the catch-all overload is *unavailable* with a human message, so a
/// full-vocabulary view in a hot body fails with the fix, not a type soup —
/// the vocabulary is a type-checker guarantee, not a lint (§1.3.6, §t3.1).
@resultBuilder
public struct HotBuilder {
    /// one primitive contributes its concrete tree.
    public static func buildExpression<P: HotPrimitive>(_ expression: P) -> HotTree {
        expression.hotTree
    }

    /// the diagnostic arm: any other view gets the fix hint instead of a bare
    /// conversion error. never called (unavailable); the body satisfies the
    /// type checker.
    @available(*, unavailable, message: "hot bodies may construct only hot primitives — Hot.Text, Hot.Container, Hot.Spacer; a full-vocabulary view compiles only for server placement")
    public static func buildExpression<V: View>(_ expression: V) -> HotTree {
        .empty
    }

    public static func buildBlock() -> HotTree {
        .empty
    }

    public static func buildBlock(_ components: HotTree...) -> HotTree {
        combine(components)
    }

    public static func buildOptional(_ component: HotTree?) -> HotTree {
        component ?? .empty
    }

    public static func buildEither(first component: HotTree) -> HotTree {
        component
    }

    public static func buildEither(second component: HotTree) -> HotTree {
        component
    }

    public static func buildArray(_ components: [HotTree]) -> HotTree {
        combine(components)
    }

    /// one member stays itself (so a single-child container's child list is the
    /// child, not a wrapper); zero is `empty`; many is a `fragment`.
    private static func combine(_ components: [HotTree]) -> HotTree {
        switch components.count {
        case 0: return .empty
        case 1: return components[0]
        default: return .fragment(components)
        }
    }
}