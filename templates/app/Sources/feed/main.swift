import WebUIIslandCore
import WebUISharedCore

// MARK: - the acceptance feed island (dx-accept, capability "feed")
//
// the consumer island cross-built by WebUIAutobuildPlugin during a plain
// `swift build`. self-contained (this dir is the whole wasm main — the graph
// leaves WebUIIslandCore/WebUISharedCore come from the framework): state,
// event decode, region markup, and the op-emitting reduce all live here, on
// the DX-1 island runtime slice (`IslandRuntime<FeedIsland>.run()`).
//
// behavior the acceptance (appendix A) drives:
//   - mount: region html with #feed-count (the counter) and #feed-row-* rows
//   - click #feed-inc            -> text op on #feed-count (counter +1)
//   - click #feed-row-<name>     -> text op on #feed-picked (selection)
//   - region replace             -> webui_state_save / restore keeps count
// element ids are the ones reduceOps targets, so mount + op stream stay in
// agreement (the ProbeIsland discipline).

@main
struct FeedMain {
    static func main() {}
}

#if os(WASI)

struct FeedState: IslandEmptyState {
    var count = 0
    var picked = ""
    init() {}
}

enum FeedAction: HotAction, Equatable {
    case inc
    case pick(String)
    case noop
}

enum FeedIDs {
    static let count = "feed-count"
    static let picked = "feed-picked"
    static let rows = ["alpha", "beta", "gamma"]
}

struct FeedIsland: IslandRuntimeSurface {
    typealias State = FeedState
    typealias Action = FeedAction

    static var name: String { "feed" }
    static var imports: [any HostCapability.Type] { [] }
    static var budget: IslandBudget { IslandBudget(maxBytes: 0, maxGzipBytes: nil) }

    // MARK: events in ({type, key, data} v1 payload -> typed action)

    static func decodeEvent(json: String) -> FeedAction {
        guard let root = try? JSONValue.parse(json),
              case .object(let dict) = root,
              case .string(let type)? = dict["type"] else {
            return .noop
        }
        let key: String?
        if case .string(let k)? = dict["key"] { key = k } else { key = nil }
        guard scalarEquals(type, "click"), let key else { return .noop }
        if scalarEquals(key, "feed-inc") { return .inc }
        for row in FeedIDs.rows where scalarEquals(key, "feed-row-" + row) {
            return .pick(row)
        }
        return .noop
    }

    // MARK: pure reduce -> ordered ops (the t2.3 drain)

    static func reduce(state: inout FeedState, action: FeedAction) -> [HotEffect] {
        var ops: [HotOp] = []
        switch action {
        case .inc:
            state.count += 1
            ops.append(.text(ElementID(FeedIDs.count), "\(state.count)"))
        case .pick(let row):
            state.picked = row
            ops.append(.text(ElementID(FeedIDs.picked), "picked: \(row)"))
        case .noop:
            break
        }
        return ops.isEmpty ? [] : [.ops(ops)]
    }

    // MARK: state channel (webui_state_save / webui_state_restore)

    static func stateToJSON(state: FeedState, renderCount: Int, eventCount: Int) -> JSONValue {
        .object([
            "feed": .object([
                "count": .number(Double(state.count)),
                "picked": .string(state.picked),
            ]),
            "renderCount": .number(Double(renderCount)),
            "eventCount": .number(Double(eventCount)),
        ])
    }

    static func stateFromJSON(_ json: String) -> (state: FeedState, renderCount: Int, eventCount: Int)? {
        guard let root = try? JSONValue.parse(json),
              case .object(let dict) = root,
              case .object(let feedDict)? = dict["feed"] else {
            return nil
        }
        var state = FeedState()
        if case .number(let n)? = feedDict["count"] { state.count = Int(n) }
        if case .string(let p)? = feedDict["picked"] { state.picked = p }
        var renderCount = 0
        var eventCount = 0
        if case .number(let n)? = dict["renderCount"] { renderCount = Int(n) }
        if case .number(let n)? = dict["eventCount"] { eventCount = Int(n) }
        return (state, renderCount, eventCount)
    }

    // MARK: mount html (ids reduceOps targets)

    static func regionHTML(state: FeedState, renderCount: Int, eventCount: Int) -> String {
        var html = "<div class=\"feed island\" data-island-state=\"mounted\""
        html += " data-island-renders=\"\(renderCount)\" data-island-events=\"\(eventCount)\">"
        html += "<div class=\"island__row\">"
        html += "<button type=\"button\" id=\"feed-inc\" aria-label=\"increment\">+</button>"
        html += "<output id=\"\(FeedIDs.count)\" class=\"island__counter\">\(state.count)</output>"
        html += "<span id=\"\(FeedIDs.picked)\" class=\"island__picked\">\(state.picked.isEmpty ? "picked: none" : "picked: " + state.picked)</span>"
        html += "</div>"
        html += "<ul class=\"island__list\">"
        for name in FeedIDs.rows {
            html += "<li id=\"feed-row-\(name)\" class=\"island__item\">\(htmlEscape(name))</li>"
        }
        html += "</ul>"
        html += "</div>"
        return html
    }

    // MARK: scalar-clean literal comparison (embedded-safe)

    static func scalarEquals(_ value: String, _ literal: String) -> Bool {
        value.unicodeScalars.elementsEqual(literal.unicodeScalars)
    }
}

@_silgen_name("webui_island_bind")
func webuiIslandBind() {
    IslandRuntime<FeedIsland>.run()
}

#endif
