# s-sugar verdict — MACRO_DX feature D (the outcome sugar), lane S

_lane S · 2026-10-07 · branch `task/s-sugar` · base `3230deb` (origin/dev-macro i0 head) · verdict recorded BEFORE any shipped implementation_

## verdict: SHIP-HELPERS — the per-shape helper functions land; the result builder and the peer macro lose

the three candidates were evaluated in the plan's order, each against a **runnable prototype** in
`~/fleet/macro-dx/sugar-spike/` (out of repo; the lane branch touches nothing while these ran):

1. **the `@resultBuilder`** — the mechanism is PROVEN viable (generic-opaque variant; the d-q spelling
   `control("id") { NoOutcome() }` resolves to the builder overload, heterogeneity groups through the
   seam's own `CombinedOutcome`) **but it is REJECTED on the arc's own bar**: it dissolves the frozen
   seam's lone-effect compile guard into a silent `NoOutcome` (B9 vs F7 below) — the "sugar hides the
   protocol" failure this arc exists to avoid. not ship.
2. **the per-shape helpers** — typed, zero magic, each a one-liner over the frozen `control<O>`, no new
   types, no hidden defaults (the no-op intent is the function NAME). **SHIP.**
3. **the peer macro `@Control("id")`** — works (runnable), but the attribute it adds + the declaration it
   requires + the `Wired` sibling + a call site it still costs, all to remove an annotation the
   baseline shows is already optional. loses on cost. not ship.

## the reframe the baseline forced (measured against the REAL frozen seam, not the replica)

the demo annotates every call site `{ (_: EventData) -> O in … }` citing rev4/A2 ("a bare `{ _ in [] }`
cannot infer it"). the real-seam probe (`eval0-real-seam`, `import WebUICore` on the lane clone) shows
**every one of the six call-site shapes compiles WITHOUT the annotation on this toolchain** — single
expression, multi-statement with `return`, with `await`, with captured-state mutation, through a
`demoControl`-shaped generic wrapper, and the bare `[]` literal:

```
R1 single-expr NoOutcome:  data-component-id="r1" data-event="click"
R2 single-expr RegionInvalidations:  data-component-id="r2" data-event="click"
R3 single-expr ViewOutcome:  data-component-id="r3" data-event="click"
R4 single-expr FragmentUpdate:  data-component-id="r4" data-event="click"
R5 multi-statement+return NoOutcome:  data-component-id="r5" data-event="click"
R6 multi-statement async-capable NoOutcome:  data-component-id="r6" data-event="click"
R7 bare array literal:  data-component-id="r7" data-event="click"
R8 single-expr CombinedOutcome:  data-component-id="r8" data-event="click"
W1..W6 un-annotated through a demoControl-shaped wrapper: … w1 | w2 | w3 | w4 | w5 | w6
```

so the annotation is **documented convention, not a compiler requirement** — the honest frame for this
lane is narrower than the plan's: the sugar that loses nothing must be priced against the *residual*
ceremony, which the seam ITSELF still enforces: a handler body that is only an effect (no outcome
expression) is REFUSED by the frozen seam —

```
F7 lone-effect vs frozen seam:
failcases/F7-lone-effect-frozen.swift:13:9: error: type '()' cannot conform to 'EventOutcome'
    `- note: required by global function 'control(_:event:handler:)' where 'O' = '()'
```

— so the three demo `NoOutcome` effect handlers still need `return NoOutcome()` (or the annotation).
**that `return NoOutcome()` is the residual ceremony the shipped helpers remove, without dissolving the
guard** (see "what it hides", candidate 1).

## candidate 1 — the `@resultBuilder` · mechanism proven, verdict: DO NOT SHIP

### mechanism (the measured shape that works)

- **generic-opaque variant**: every builder method is generic and returns `some EventOutcome`, so the
  output type is a concrete type inferred per call (`NoOutcome`, `CombinedOutcome<A, B>`) that satisfies
  the frozen seam's `O: EventOutcome` — the builder CAN funnel through the unmodified frozen `control<O>`.
- **the existential variant is dead on arrival**, two hard errors (raw, build log):
  `type 'any EventOutcome' cannot conform to 'EventOutcome'` at the generic seam, and
  `CombinedOutcome(accumulated, next)` cannot be instantiated with existentials (same non-conformance) —
  it would need a SECOND grouping type the seam doesn't own.
- **name takeover works**: a same-name overload `control(id:event:@OutcomeBuilder handler:)` resolves for
  `control("id") { NoOutcome() }` AND for the heterogeneous body (provably the builder — the frozen
  generic has no grouping) and runs correct ordering:

```
F5-run:  F5a:  data-component-id="f5a" data-event="click" [the builder overload]
         F5b:  data-component-id="f5b" data-event="click" [the builder overload]
         F5b dispatch: frames=["u"] invalidated=["g-a"]
```

- heterogeneity groups through **the seam's own `CombinedOutcome`**, order preserved (B3):

```
PROBE B3 b3: frames=["g-out"] invalidated=["g-region-a"]
```

  the brief's open question ("a canonical grouping type") answers itself: no new type needed — the
  generic-opaque partial-block composes into `CombinedOutcome<A, B>`, the type the seam already ships.

### cost

- `{ _ in … }` (or a named/`$0` arg) is still required — a parameterless builder closure is refused
  (`contextual type for closure argument list expects 1 argument, which cannot be implicitly ignored`)
  for BOTH the builder and the plain seam (raw build log); sugar saves the *type*, not the argument.
- an `if`/branch inside a builder closure is refused until the builder implements `buildEither`
  (`closure containing control flow statement cannot be used with result builder 'OutcomeBuilder'`,
  F4) — branching handlers stay on the raw seam or the builder grows an escape hatch.
- a bare-Void effect statement needs a `buildExpression(_ v: Void) -> …` overload (the SwiftUI
  `EmptyView` trick); without it every effect body errors `type '()' cannot conform to 'EventOutcome'`
  (raw build log).
- an explicit `return` in final position **does** compile (F3 typechecks) — the demo's `return
  NoOutcome()` survives — but the last-expression idiom is the natural spelling.

### what it HIDES (the rejecting finding)

- a handler whose body is ONLY an effect compiles under the builder and **silently sends nothing** (B9
  `frames=[] invalidated=[]`), where the frozen seam REFUSES the same body (F7 above). the builder turns
  "you forgot to say what this handler yields" from a compile error into a silent no-op. that is the
  "one too many" failure — shipping it would be the verdict this arc was created to forbid.
- the grouping into `CombinedOutcome` is invisible at the call site (`{ FragmentUpdate(…);
  RegionInvalidations(…) }` nowhere names composition), and the `NoOutcome()` intent is dropped.

## candidate 2 — the per-shape helpers · verdict: SHIP

### mechanism

typed functions over the frozen generic `control<O>`, one per outcome shape; each body is the shape's
conformance spelled once (`noOutcome` → `NoOutcome()`, `fragments` → `[FragmentUpdate]`,
`replaceView` → `ViewOutcome(await body(data))`, `invalidate` → `RegionInvalidations(ids)`,
`updateThenInvalidate` → `CombinedOutcome(update, invalidations)` in that order). zero new types, zero
hidden defaults. the six demo call sites re-spelled and driven (raw eval2-helpers output):

```
PROBE H1 h-outcome: frames=["h-outcome"] invalidated=[]
PROBE H2 h-region-nudge: frames=[] invalidated=["g-region-a"]
PROBE H3 h-region-combined: frames=["g-combined-out"] invalidated=["g-region-a"]
PROBE H4 h-bump-b: frames=[] invalidated=[]
PROBE H5 h-bump-c: frames=[] invalidated=[]
PROBE H6 h-bump-d: frames=[] invalidated=[]
counter after dispatches = 7
```

the SAME frames/invalidations as the hand-written control group (A5 one–four), i.e. the twin holds.

### cost

six small functions (~60 lines with docs) + their fixtures. three new top-level names
(`fragments`, `invalidate`, `noOutcome`) in `WebUICore` — collision-checked against the module: no
existing `func` of those names (verified by grep; `OutcomeContext.invalidate` is a stored closure
property, unrelated). the demo's annotated spellings keep compiling byte-identical (nothing is
removed).

### what stays hand-written (the plan's honest half)

- payload-dependent selection (a handler that branches on `data.string(_:)`) — always the raw generic
  seam (helpers could add a closure-returning `invalidate` variant later; none shipped now, because the
  demo has no such site and the arc is anti-scope-creep);
- combinations beyond `fragments`/`updateThenInvalidate` (e.g. a view replacement PLUS invalidations) —
  `control` directly;
- the seam's lone-effect guard is PRESERVED: `noOutcome`'s body is the caller's *named* intent; there is
  no silent-Void path (B9 cannot happen — the helper's return type is concrete).

### what it hides

nothing. each helper's body is the protocol conformance in plain sight; the no-op case is the function
NAME, not a default.

## candidate 3 — the peer macro `@Control("id") func swap(…)` · loses, measured

a real macro target was built (swift-syntax 603.0.2 from lane-m's checkout; offline) and the consumer
ran:

```
swapWired() ->  data-component-id="g-swap" data-event="click"
```

`@Control("id") func swap(_ e: EventData) async -> NoOutcome { … }` → `control("g-swap", handler: swap)`
in a generated `swapWired()`. cost measured against the surface it removes: an attribute + the
declaration + the generated sibling + a call site it STILL costs (the HTML assembly must call
`swapWired()`), plus a macro target the helpers do not need. the annotation it removes is
`(_: EventData) -> NoOutcome in` — which the baseline shows is already optional — and a peer macro can
only WRAP (it cannot see the enclosing member list, verified in the skill probe-recorded wall), so it
cannot auto-register the sibling anywhere. strictly more machinery for a smaller saving. loses, as the
plan expected. (bonus: `@attached(peer, names: suffixed(Wired))` IS accepted at global scope on this
toolchain — the documented wall is specific to `names: arbitrary`.)

## what did NOT get better (stated, per the gate)

- the demo's annotated spelling still compiles unchanged; nothing about the convention is removed or
  enforced (Sources/WebUIExample is forbidden to this lane — the stale "cannot infer it" comment there
  is lane D/W's to correct, if anyone).
- single-expression sites gain nothing over the already-annotation-free frozen spelling — the helpers'
  win is concentrated at the three multi-statement effect handlers, plus explicit shape naming.
- the builder that WOULD have removed the most tokens is exactly the one that fails the hiding bar.

## gate (executed after this note)

- the note committed first (this file); then `Sources/WebUICore/EventOutcomeBuilder.swift` (the six
  helpers) + `Tests/WebUITests/EventOutcomeBuilderTests.swift` (fixture twin: each helper's dispatch
  equals the hand-written equal, same frames + same invalidations; the lone-effect guard asserted to
  keep compiling-error behavior: helper bodies are void-by-signature).
- `swift build` · `swift test --filter EventOutcomeBuilder` green; EventHandling.swift byte-unchanged.

recorded by lane S · prototype evidence: `~/fleet/macro-dx/sugar-spike/` (overview below)

## gate: executed (amended after the implementation, 2026-10-07)

the shipped piece landed per this note: `Sources/WebUICore/EventOutcomeBuilder.swift`
(the six helpers) + `Tests/WebUITests/EventOutcomeBuilderTests.swift` (the twin fixtures).
EventHandling.swift, Package.swift, the demo, the server and designer are untouched
(`git status` listed only the two new files; `git diff` over the forbidden surfaces was empty).

```
$ swift build                     → Build complete!
$ swift test --filter EventOutcome → Test run with 11 tests in 2 suites passed.
   (the 6 new twin fixtures + the pre-existing DX-14 outcome suite, unchanged)
```

the twin gate holds: every helper's dispatch equals the hand-written `control("id") { … }`
spelling — same attributes, same frames, same invalidations (asserted per helper in the
suite). the lone-effect guard survives by construction: `noOutcome`'s body is `Void` by
signature, so "yields nothing" is named intent, not a silent default (unlike the builder's
B9 case, which this lane refused to ship).
