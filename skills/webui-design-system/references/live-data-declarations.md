# Live data, declared — the four macro spellings (@LiveRegion · @RegionState · @LiveRegions · @LiveState)

The live-data layer has one customization model: **a conforming type passed in** (see
`substitution.md`). The four declaration macros are an *optional* shortcut on top of it:

> **the macros are optional.** each generates only the members the hand-written conformance already
> spells — `id`, `cadence`, `source`, `subscribe`/`notify`, and the `registry` assembly — and the
> hand-written spelling keeps compiling and stays **byte-identical** on the wire. if you delete the
> attributes, your regions still build and still behave identically. a twin test proves the two
> spellings push byte-equal frames for the same input sequence.

Reach for the macros when writing a live region by hand means typing ceremony you do not want:

```swift
import WebUIServer

@LiveRegions                       // generates `registry` from the property list
struct NewsRegions {
    // (2) a custom region struct: the conformance, id, cadence and source hook are generated
    @LiveRegion(id: "headline")
    struct Headline {
        @RegionState let box: LiveBox<String>   // this property IS the source
        func render() async -> String? {
            "<span id=\"headline\">\(box.value)</span>"
        }
    }

    // (4) a custom state actor: subscribe (nonisolated, by construction) + notify() are generated
    @LiveState
    actor Feed {
        private var items: [String] = []
        func append(_ s: String) { items.append(s); notify() }   // notify(): the wake-up call
        func snapshot() -> [String] { items }
    }

    let headline = Headline(box: LiveBox("…"))
    let feed = StateLiveRegion(id: "feed", state: Feed()) { state in
        let items = await state.snapshot()
        return "<span id=\"feed\">\(items.count) items</span>"
    }
}

let server = WebUIServer(
    render: { renderPage() }, router: router,
    config: WebUIServerConfig(port: 9090),
    regions: WebUILiveRegions(NewsRegions().registry)   // the generated assembly
)
```

## the four declarations

| attribute | put on | what it generates |
|---|---|---|
| `@LiveRegion(id:cadence:)` | a struct/class/actor with a `render()` | the `LiveRegion` conformance — `id` and `cadence` from the attribute, `source` from the marked property |
| `@RegionState` | the ONE stored property that is the region's `source` | nothing alone — **a marker** `@LiveRegion` reads. one marked property = `source`; none = `source == nil` (legal, the framework default); two = a compile diagnostic |
| `@LiveRegions` | the group struct that owns the region properties | `registry: WebUILiveRegions`, assembled **in declaration order** |
| `@LiveState` | an actor | the `LiveState` conformance — a `nonisolated subscribe` (safe by construction) forwarding to an injected notifier, and `notify()` |

the three footguns they retire:

1. **`source` is the subscription hook.** with a hand-written conformance, forget `source` and
   state changes silently never wake the region. `@RegionState` makes the property you already
   wrote the source — it cannot be forgotten.
2. **`subscribe` must be `nonisolated`.** write a hand actor's witness the natural way and the
   registry's synchronous subscribe hops onto the actor; a busy actor then stalls `start()`. the
   macro emits `nonisolated` by construction.
3. **the registry array assembly.** the hand spelling writes
   `var registry { WebUILiveRegions([…]) }` (≈20 lines on the demo); `@LiveRegions` generates it
   from the property list.

## what it cannot do for you (so you set the right expectations)

The macro layer removes *declaration ceremony only*. It does **not** remove — measure it on the
demo (89 hand code lines → 72 macro-spelled for the same four mechanisms + five controls +
registry):

- the `render()` bodies and their markup — yours, both spellings;
- the states' own properties and mutators — `private var items`, `append(_:)`, `snapshot()` etc.
  stay hand-written (a macro cannot rewrite a mutator, and you would not want it to);
- the **choice of mechanisms and ids** — which driver form to use per region and the DOM ids are
  content the macro cannot invent. it generates the plumbing, never the design.

so the honest rule: reach for the macros when you are writing a custom struct/actor conformance
**and** the ceremony outweighs the attribute lines; keep the hand path when you compose the
framework defaults (`ClosureLiveRegion`, `StateLiveRegion<LiveBox>` need no conformance at all),
when a region's id must be computed at runtime (the attribute takes a literal), or when your
library product cannot depend on a macro target.

## generated-code facts that matter when reading it

- the witnesses are **computed**, not stored (`var id: String { "…" }`) — the memberwise
  initializer of your type is unchanged (`Headline(box:)` still constructs).
- `@LiveRegions` classifies by **syntax, not types**: a property is a region when its written type
  (or initializer) names a nested `@LiveRegion` type, `ClosureLiveRegion` or `StateLiveRegion`;
  nested `@LiveState` types, `LiveBox`, `LiveNotifier` are skipped; **anything else is a
  diagnostic** — never a silently dropped region.
- misuse is a **diagnostic, never `fatalError`**: `@LiveState` on a non-actor, a hand-written
  member colliding with a generated one, a group with no region properties, duplicate ids
  (warning).

## the outcome-side companion: six per-shape helpers

`WebUICore/EventOutcomeBuilder.swift` ships six typed entry points —
`noOutcome(_:event:_:)`, `fragments(_:event:_:)`, `replaceFragment(_:event:_:)`,
`replaceView(_:event:_:)`, `invalidate(_:event:ids:)`, `updateThenInvalidate(_:ids:event:_:)` —
one per `EventOutcome` shape. they name what a handler yields:

```swift
noOutcome("bump") { _ in state.value += 1 }                       // effect-only, named
replaceView("cell") { _ in Text("replaced") }                     // render + replace #cell
invalidate("nudge", ids: ["headline"])                            // declare; registry pushes
updateThenInvalidate("swap", ids: ["headline"]) { _ in FragmentUpdate(id: "out", html: "…") }
```

measured honesty: the `O`-annotation on `control("id") { (_: EventData) -> O in … }` was
**already optional** on this toolchain (a bare `{ _ in … }` infers it in every probed shape) — the
helpers remove the *residual* ceremony at the effect-only sites (`_ in`, `return NoOutcome()`) and
spell each shape's name. they do not replace the protocol: a hand-written `EventOutcome`, a
payload-dependent combination, or any new shape still calls `control` directly, and a handler
body that yields nothing is still a compile error at `control` (never a silent no-op).

## proof

the parity twin is gate-executed, not asserted: `Tests/WebUITests/MacroParityTests.swift` drives
the macro spelling and the hand spelling through the same registry seam and asserts **byte-equal
frames** (ids, html, order) for the same input sequence; the demo (`Sources/WebUIExample`) serves
both spellings (`g-mreg-*` beside `g-region-*`) and the acceptance gate runs the same twin live.
