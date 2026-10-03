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
