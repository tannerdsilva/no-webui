# lane d — wave-1 notes (consumer surface)

branch: `task/d-surface` · base: `d9c6cf6` · wave 1 slice: **compilable surface only**
(macro package + declarations + string-based expansion tests). view-side runtime
protocols (`HotView`/`HotPrimitive`/`HotTree`), `@HotBuilder`, the `imports:`/
`budget:` macro parameters, the compiled end-to-end fixture, and the hand-written
equivalent are wave 2 — they need lane C's `Continuum.swift` merged (vocabulary).

## what landed (commits)

- `c4f6ce9` chore(lane-d): push smoke
- `a227864` feat(macros): WebUIContinuumMacros target — @HotView/@HotClass implementations
- `2a7ef85` feat(macros): @HotView/@HotClass public macro declarations in WebUI
- `5bbd7a9` test(macros): WebUIContinuumMacros expansion suite

## files owned this wave

- `Sources/WebUIContinuumMacros/Plugin.swift` — 9-line `CompilerPlugin`, providing
  `HotViewMacro` + `HotClassMacro`.
- `Sources/WebUIContinuumMacros/WebUIContinuumMacro.swift` — both implementations
  (`HotViewMacro` = `ExtensionMacro`; `HotClassMacro` = `MemberMacro`).
- `Sources/WebUI/ContinuumMacros.swift` — the two `public macro` declarations +
  the `ContinuumServerPath` marker (see assumptions 2).
- `Tests/WebUIContinuumMacroTests/` — `ExpansionAssertions.swift` (shared),
  `HotClassMacroTests.swift`, `HotViewMacroTests.swift`. 15 tests green.

## the emission, pinned (what a test asserts)

for `@HotView("feed") struct Feed` (name-only signature) the extension is:

```
extension Feed: ContinuumServerPath {
    static let continuumDescriptor = ContinuumDescriptor(name: "feed", grants: [],
        budget: IslandBudget(maxBytes: 0, maxGzipBytes: nil), className: "")
    struct FeedIsland: ContinuumIsland {
        typealias State = Feed.State
        typealias Action = Feed.Action
        static var name: String { "feed" }
        static var imports: [any HostCapability.Type] { [] }
        static var budget: IslandBudget { Feed.continuumDescriptor.budget }
        static func reduce(state: inout State, action: Action) -> [HotEffect] {
            Feed.reduce(state: &state, action: action)
        }
        @_expose(wasm, "feed_encode") static func _continuumEncode() -> [UInt8] { [] }
        @_expose(wasm, "feed_decode") static func _continuumDecode() -> [HotEffect] { [] }
    }
}
```

`@HotClass("a", "b")` emits the single member
`static let continuumClasses: [String] = ["a", "b"]` (public for public structs).
a sibling `@HotClass` on the same declaration feeds the descriptor's `className`
(joined, space-separated). access modifiers mirror the annotated type.

## assumptions / deviations (conservative choices)

1. **wave-1 @HotView is name-only**; `imports:`/`budget:` parameters and the
   view-side protocols are wave 2 (they reference lane C's unmerged vocabulary).
   the plan's "missing budget → diagnostic" refusal therefore cannot fire until
   the `budget:` parameter exists — the descriptor carries the sentinel budget
   `IslandBudget(maxBytes: 0, maxGzipBytes: nil)` (explicitly "unset").
2. **`ContinuumServerPath` marker added** in `Sources/WebUI/ContinuumMacros.swift`.
   the compiler type-checks `@attached(extension, conformances:)` names at the
   macro *declaration* site even when the macro is never expanded (verified:
   `swift build` fails with "expected type" without it). the marker is empty;
   render/routing requirements land wave 2. home is WebUI (view-side/server-side;
   not in lane C's vocabulary list).
3. **`names: arbitrary`** on the @HotView declaration — the derived island name
   `<Type>Island` cannot be declared as a static `named(...)`. emission stays a
   single `ExtensionMacro` (one extension: descriptor + nested island + the
   `ContinuumServerPath` conformance via `conformances:`).
4. **codec shims emit names only** (`_continuumEncode`/`_continuumDecode`,
   wasm names `<name>_encode`/`<name>_decode`); bodies + the t2.3 record table are
   lane C's handoff (see `d-to-c.md`). anti-shackle rule 5 (no hidden runtime) is
   satisfied: the shims are empty stubs adding no work.
5. **no compiled fixture / hand-written equivalent this wave** (anti-shackle rule
   3) — wave 2, after the vocabulary merges; the plan's W2 row.
6. no ports used (wave 1 has no probes); `Tests/WebUITests/APISurfaceTests.swift`
   additive pins pending wave-2 surface.

## doc fragments (for the orchestrator to fold, per §2 shared-file hygiene)

- `CONTINUUM.md`: a new section on the consumer surface — "@HotView/@HotClass: one
  declaration, two placements" with the generated-members table above; the
  load-bearing placement note (macro declarations in WebUI, implementation
  host-only, never in a wasm-compiled chain); the anti-shackle rules.
- `CHANGELOG.md` (unreleased): "add WebUIContinuumMacros: @HotView/@HotClass
  attached macros (wave-1 name-only signature), ContinuumServerPath marker,
  string-based expansion suite".
- `AGENTS.md`: no change needed (macro house style already documented).

## gates run

- `swift build` — green after each of units 1/2.
- `swift test --filter WebUIContinuumMacroTests` — green after unit 3 (15 tests).
- final full `swift build` + `swift test` — see the lane report.

---

# lane d — wave 2 notes (t3.1 complete + t3.2)

branch `task/d-surface`; merged `origin/dev-continuum` @ `8eac8ae` first. the
vocabulary (`Sources/WebUISharedCore/Continuum.swift`) is merged, so the
generated adapters are now COMPILED, not string-tested.

## what landed (commits)

- `4a4ac4f` feat(webui): the hot vocabulary — `HotView`/`HotPrimitive`/`HotTree`
  protocols, `@HotBuilder`, `ContinuumDescriptor` + a real `ContinuumServerPath`
  requirement, in `Sources/WebUI/` (placement per §t3.1's table: view-side in
  WebUI, host-only; seam types stay in `WebUISharedCore`, surfaced through the
  `WebUICore` re-export chain).
- `bbd0618` feat(macros): @HotView — the `imports:`/`budget:` parameters + the
  refusal diagnostics; expansion suite rewritten (24 tests).
- `a91c04c` fix(macros): `@_expose` shims become peer-emitted globals; the
  compiled fixture + hand-written equivalent land (31 tests green).

## the emission, pinned (wave 2)

for `@HotView("feed", imports: [ClockCapability.self], budget: IslandBudget(...))`:

- `extension Feed: ContinuumServerPath` carries
  `static let continuumDescriptor = ContinuumDescriptor(name:grants:budget:className:)`
  and `struct FeedIsland: ContinuumIsland` (`State`/`Action` alias, `name`,
  `imports`/`budget` = the copied expressions, `reduce` forwards,
  `_continuumEncode`/`_continuumDecode` codec entry points — stubs).
- the new peer role emits global shims
  `@_expose(wasm, "feed_encode") func _continuumEncodeFeed()` /
  `_continuumDecodeFeed()` delegating to the adapter.

## the two compiler facts the first honest compile caught

1. `@_expose(wasm, …)` rejects non-global placement: "can only be applied to
   global functions" — wave-1's static-method shims could never compile; they
   are peer-emitted globals now (verified on host compile).
2. peer names at global scope cannot be `arbitrary` — and `prefixed(p)` covers
   `p` + the annotated DECLARATION's name, not a plain prefix match (verified:
   `_continuumEncode_counter` was rejected; `_continuumEncodeFeed` is accepted).
   shim names derive from the type name (`_continuumEncode<Type>`), while the
   ABI string stays `<island-name>_encode`.

## assumptions / deviations (wave 2)

1. **`HotView` does not inherit `View`.** §1.3.6's sketch had `HotView: View`;
   the operative §t3.1 render returns `HotTree`, and a state-free
   `View.render()` has no defined meaning for a hot view (no initial-state
   vocabulary). `HotTree` (the body) is the `View`. revisit when an SSR embed
   path defines initial render.
2. **the v1 primitive set is `Hot.Text`/`Hot.Container`/`Hot.Spacer`**, nested
   under `Hot` because `WebUICore.Text`/`Spacer` already own module scope. the
   plan marks the set `[open — d3]`; `KeyedList` (t3.3 windowing) and
   `AttrWrapper` (component promotion) are the next additions.
3. **`imports:` non-empty requires `budget:`** (an explicitly empty `imports: []`
   is equivalent to absent). name-only keeps the sentinel
   `IslandBudget(maxBytes: 0, maxGzipBytes: nil)` — the additive path stays
   compatible with wave 1.
4. **`@_expose` shim stubs**: bodies `[]` until the island runtime slice wires
   the frame-buffer op loop (t2.3/C + engine drain). the wasm export name is the
   frozen `<name>_encode`/`_decode`.
5. **`HotTree.hotOps` v1 semantics**: survivors-order diff (removals → moves +
   recursion → inserts; anchors = the next sibling that survived, else append).
   correct for appends/removals/single moves/swaps (pinned); not a minimal LCS;
   root fragment identity changes are the region's replace. the benches decide
   whether minimal-move accounting is needed.
6. **the hotOps contract**: leaf `hotOps(previous:)` emits delta ops for an
   address that already exists; structural ops come from the containing diff;
   `previous == nil` emits nothing (mount is the region html path).
7. **`.lease` is inert by design** (t3.2): no markup, no attribute, no bytes —
   the hint lives in the type (`ModifiedView.modifier.hint`); the consumption
   path (build scan → manifest vs served attribute) is a wave-3 decision, handed
   to E in `d-to-e.md`.
8. **`ContinuumServerPath` gained its descriptor requirement** in wave 2 (was
   the wave-1 empty marker); hand-written conformance remains first-class.
9. **no `Package.swift` edits this wave** — WebUI sees the seam vocabulary
   through `WebUICore`'s `@_exported import WebUISharedCore`; no new deps.
10. **wasm-chain note**: the generated adapter + shims reference only
    `WebUISharedCore` vocabulary + the author's members (no `Codable` synthesis,
    no `JSONEncoder`); the descriptor (a WebUI type) is referenced by host-side
    members only. user-island extraction (d2/d3+) will compile the adapter + the
    author's `State`/`Action`/`reduce`; the descriptor stays host-side.

## gates run (wave 2)

- `swift test --filter WebUIContinuumMacroTests` — 31 tests green (expansion +
  misuse + compiled fixture equivalence).
- `swift build` — green after each push.
- builder negative path (full-vocabulary view in a hot body): the compiler emits
  the fix-hint message with file/line (verified by a module-level typecheck
  probe; recorded in the lane report).
- argument typing at the use site (verified by probe): `imports: [String.self]`
  fails with "cannot convert '[String.Type]' to '[any HostCapability.Type]'";
  `budget: 4096` fails with "cannot convert 'Int' to 'IslandBudget'".
- `swift test --filter placementHintSurfacePins` — green.
- final full `swift build` + `swift test` — 9 bundles · 1108 tests · 119 suites ·
  0 failures (see the lane report).

## doc fragments (wave 2, for the orchestrator)

- `CONTINUUM.md`: advance the consumer-surface section to the wave-2 shape:
  `imports:`/`budget:` typing rule (missing budget → build error), the
  diagnostic list, the two compiler facts (`@_expose` globals; `prefixed` peer
  names), the `Hot.*` primitive set + `@HotBuilder` guarantee, `.lease` hints.
- `CHANGELOG.md` (unreleased): "@HotView gains imports:/budget: with refusal
  diagnostics; the hot vocabulary (HotView/HotPrimitive/HotTree/@HotBuilder) +
  the compiled equivalent fixture; .lease placement hints (inert, byte-identical)".
