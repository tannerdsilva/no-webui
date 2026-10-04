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

---

# lane d — wave 3 notes (t3.3 complete + t3.4 delivery)

branch `task/d-surface`; merged `origin/dev-continuum` @ `f9faaba` (i2) first.
three green units pushed: `4e4f08b` (Viewport), `6e5954d` (t3.4 delivery),
`009e982` (KeyedList/AttrWrapper).

## what landed (commits)

- `4e4f08b` feat(design-system): `Viewport<ID, Item>` in
  `Sources/WebUIDesignSystemCore/Viewport.swift` + the pure windowing spec
  (`ViewportSizing`/`ViewportWindow`/`ViewportAnchor`) + `Tests/WebUITests/
  ViewportTests.swift` (13) + `designer/probes/d-viewport.mjs` + the DOM
  contract handoff in `continuum-notes/d-to-e.md`.
- `6e5954d` feat(webui): t3.4 delivery — `.lease(.echo, echoTo:)` →
  `data-webui-echo` emission (buffered decorate path), `InputParity`
  descriptor modifiers + `compositionForwarded()` + `onKeyEvent` in
  `Sources/WebUI/InputParity.swift`; additive pins in `APISurfaceTests`.
- `009e982` feat(webui): `Hot.KeyedList` + `Hot.AttrWrapper` (the `.attended`
  `HotTree` case) in `ContinuumHot.swift` + `HotPrimitiveTests` (11).

## the t3.3 `Viewport` DOM contract (handoff to E — in `d-to-e.md`)

engine finds `[data-webui-viewport]`; reads `data-viewport-total`/
`-rowsize` (52) /`-overscan` (2); rows `<li id="<id>-r<i>" data-viewport-row
data-key="<key>">` (i = global index — stable across window shifts; data-key =
keyed identity); sliced renders emit `.viewport-pad` height pads +
`data-viewport-slice="<first>..<last>"`; server degrade = full list,
paginated past `data-viewport-safe` (10 000, the d0-measured 10k ceiling)
with a self-wiring `.pagination` pager. anchoring on patch:
`ViewportAnchor.scrollDelta = (oldFirst−newFirst)×rowHeight`.

## the windowing semantics the engine's JS twin must match (pinned)

`visible = ceil(rectHeight/rowHeight)`; `window = visible×overscan` (2×, ≈ one
band above + one below the anchor), clamped to `[0,total)`; lead depth
`(window−visible)/2`; the anchor row is the first survivor at/above the old
top edge; re-window when the anchor leaves the visible band.

## t3.4 delivery decisions (conservative choices)

1. **`.lease(.echo)` stays byte-identical; only `.lease(.echo, echoTo:)`
   emits.** the wave-2 pin ("no attribute when unhinted") survives — a hint
   without a target cannot know where to echo, so it is not an echo source.
   recorded as the conservative reading of "delivery wiring".
2. **D-side payloads wear the `Parity`/`ParityKeyEvent` names, not C's.** C
   owns the wasm-visible `KeyEvent`/`Selection`/`ClipboardPayload`/`UndoStack`
   in `WebUISharedCore` and lands them this wave; D's modifiers must compile
   NOW, so the typed handler surface uses D-named delivery twins
   (`ParityKeyEvent.key/modifiers`), whose shapes mirror the frozen §t3.4
   names. i3 hook-up (one file, mechanical): re-point the modifier handler
   signatures at C's types once they merge (typealias/param swap) — no
   behavioral change; recorded here so the reconciler treats it as a
   substitution, not a duplicate.
3. **`InputParity` descriptor is a JSON-array attribute** (`data-webui-input=
   '["key","composition"]'`) — the sibling spell of E's existing
   `data-webui-island-events`, so the engine's t3.4 forwarding reads both with
   one parser. closed vocabulary; `inputParity()` with no args emits nothing.
4. **`HotTree.attended` laminates attributes onto the element its content
   opens**; content that opens no element (empty/fragment/spacer) drops them
   (pinned). attribute-only changes produce no ops (v1 boundary — the engine's
   `attr` op is the future dynamic-row-state channel).
5. **id etymology differs by placement (documented for E):** the server
   Viewport rows are positionally addressed (`-r<i>`, a slot) + keyed by
   `data-key`; the hot `KeyedList` rows are key-derived (`-k<key>`) so the hot
   diff reconciles by key. both emit the same `data-key` identity channel; the
   engine windows by membership in the full ordered list.

## gates run (wave 3)

- `swift build` — green after each unit; `swift test` for each unit's filter
  green (Viewport 13, delivery 8, hot primitives 11, pins 3).
- `node designer/probes/d-viewport.mjs` — all contract checks green.
- final full `swift build` + `swift test` + macro filter — see the lane report.

## doc fragments (wave 3, for the orchestrator)

- `CONTINUUM.md`: the t3.3 `Viewport` section (the signal: windowed surface +
  server degrade) + the DOM-contract table; the t3.4 delivery section
  (`.lease(.echo, echoTo:)`, the `InputParity` descriptor, composition
  forwarding, the `ParityKeyEvent` grammar + the i3 hook-up); the
  component-promotion path (`AttrWrapper`/`attended`) — how an existing
  design-system component gains `hotOps` without forking the hot vocabulary.
- `CHANGELOG.md` (unreleased): "Viewport windowing component (t3.3) with the
  engine DOM contract + server-degrade pagination; t3.4 input-parity
  delivery (data-webui-echo emission, data-webui-input descriptor,
  composition forwarding, ParityKeyEvent); Hot.KeyedList + Hot.AttrWrapper".

---

# lane d — polish (the i3 hook-up closed, on `dev-continuum` d5cb0c4)

branch `task/d-surface`; merged `origin/dev-continuum` @ `d5cb0c4` (i3) first
— lane C's REAL t3.4 types (`Sources/WebUISharedCore/{KeyEvent,Selection,
ClipboardPayload,UndoStack}.swift`) are on the tree. three green units pushed:
`7d5aa80` (re-point), `d14bbb3` (transport mapping + probe).

## wave-3 assumption 2/3: CLOSED — the delivery twins are gone

wave-3 note 2 (D-side payloads wear `Parity*` names) and note 3's i3 deferral
are the polish this closes. the delivery surface now IS lane C's real
grammar — `ParityKey`/`ParityModifiers`/`ParityKeyEvent` are DELETED from the
public surface (the sanctioned substitution, recorded here so the reconciler
treats it as a re-point, not a removal of capability):

- `ParityKey` → `Key`. `character(String)` → `printable(String)` (single
  scalar — the same thing, spelled C's way). `composition` had NO `Key`
  counterpart and is dropped: its payload rides the composition channel
  (`compositionForwarded()` → `{type, key: "composition", data}`), never the
  key channel — the wave-3 file comment already said so. `Key` ADDS
  `space`/`function(Int)`/`unknown` (C's superset; the engine cannot deliver
  `.space` from the DOM — see the space friction below).
- `ParityModifiers` → `ModifierSet`. bit positions 1<<0…1<<3 for
  shift/control/option/command are IDENTICAL (the twins mirrored C's
  layout); `ModifierSet` adds capsLock/function/numLock. rawValue widens
  `Int` → `UInt16`.
- `ParityKeyEvent` → `KeyEvent`. `key`/`modifiers` unchanged;
  `modifiers:` is now REQUIRED at the call site (C's init has no default —
  the twin did); `isRepeat` is new (`false` default). stricter surface,
  same reading.

behavior is byte-identical: the `data-webui-input` descriptor, the `key`
channel emission (`data-webui-input='["key"]'`), `compositionForwarded()`
(→ `data-webui-composition=""`), and `InputParityModifier` canonical order
are untouched.

## the island transport mapping (next-slice #3, now landed)

`KeyEvent → {type, key, data}` v1, exactly as frozen in c-to-e.md and proven
by E's real-island handshake (e-island-e2e-real.mjs):

| KeyEvent | island payload (v1) |
|---|---|
| `key: Key` | `{"type":"key","key":"<Key.identifier>"}` — data OMITTED |
| `key = .function(n)` | `{"type":"key","key":"F<n>"}` |
| `key = .printable(s)` | `{"type":"key","key":"<s>"}` (single scalar) |
| `modifiers` / `isRepeat` | NO v1 wire field (boundary — see below) |

concretely: `KeyEvent.islandPayloadV1` (in `InputParity.swift`) returns
`["type": "key", "key": key.identifier]`; the engine's real
`deliverIslandEvent` forwards `type:"key"`, `key` = `String(event.key)` (the
DOM `KeyboardEvent.key` string), and the island's `decodeEvent` parses it
back via `Key(identifier:)` (never traps; unmatched → `.unknown` → island
`.noop`). the bridge is C's `Key.identifier` / `Key(identifier:)` —
round-trip pinned natively in WebUISharedCoreTests + the parity corpus.

**v1 boundaries (recorded — the consumer must not assume more):**
1. `modifiers`/`isRepeat` are NOT on the wire at v1. the engine's current
   artifact additionally forwards `ctrlKey`/`shiftKey`/`altKey`/`metaKey`
   (boolean-as-string) inside `data` — INFORMATIONAL only; the island's
   `decodeEvent` keys on `key` alone. a v2 modifier field is the open
   extension (would need c-to-e + island-side decode changes).
2. `type:"key"` carries the key identity; `type:"click"`/`type:"input"`
   carry the ELEMENT id as `key` (the real handshake: `probe-inc`, …).
3. **the space friction:** the DOM spacebar's `event.key` is a single space
   scalar `" "`, which `Key(identifier:)` parses to `.printable(" ")`, NOT
   `.space` (whose canonical wire id is the author-side `"Space"`). authors
   that want the physical spacebar should match `.printable(" ")` or the
   identifier `" "` on the wire; `.space`/`"Space"` will not fire from a
   real browser today. recorded; a v2 engine normalization
   (`" "` → `"Space"`) is the candidate fix.

## tests / probes

- `LeaseDeliveryTests.keyEventDelivery` — the twins' only pin SUBSTITUTED to
  `KeyEvent` (same assertions). APISurfaceTests + ViewportTests: NO twin
  references, additive pins untouched (verified in wave-3 form).
- NEW `LeaseDeliveryTests.islandPayloadV1` — additive pin: the exact payload,
  the omit-`data` boundary (`count == 2`, no modifiers/isRepeat keys), the
  printable/function wire strings, and the `Key(identifier:)` round-trip +
  never-trapping `unknown`.
- NEW `designer/probes/d-transport.mjs` — pure Node (no port): parses the
  REAL `KeyEvent.swift` identifier table off disk (a C-side table drift fails
  here), asserts the round-trip rule, the F1…F24 range (`F0`/`F25`/`F100`/
  `Fabc` → unknown — mirrors the digit-scan-then-range Swift), single-scalar
  printables, `Unknown` self-round-trip, the exact `{type,key}` shape, the
  element-id rule for click/input, and the space friction. 15 checks.

## gates run (polish)

- `swift build` — green after each unit.
- `swift test --filter LeaseDeliveryTests` / `--filter APISurfaceTests` —
  green (9 / 14).
- `node designer/probes/d-transport.mjs` — 15 PASS, 0 FAIL.
- final full `swift build` + `swift test` + `node designer/probes/d-viewport.mjs`
  — see the lane report.

## doc fragments (polish, for the orchestrator)

- `CONTINUUM.md` (t3.4 section): replace the `ParityKeyEvent` grammar + "i3
  hook-up" with the real `KeyEvent`/`ModifierSet`/`Key` surface, the
  `islandPayloadV1` mapping table, and the v1 boundaries listed above.
- `CHANGELOG.md` (unreleased): amend the t3.4 line — "input-parity delivery
  re-pointed onto lane C's KeyEvent/ModifierSet/Key (twins removed);
  KeyEvent → island {type,key} v1 transport mapping + d-transport probe".

## handoffs

- to E: the engine's t3.4 forwarding still keys off `data-webui-island-events`
  today; D's `data-webui-input` descriptor is its declared sibling (one
  parser). wiring `data-webui-input` into `islandRegionSubscribed`/
  `deliverIslandEvent` is E's next-slice (recorded in d-to-e). the modifier
  booleans E already forwards in `data` are informational at v1 — keep them,
  they pre-seed v2.
- to B: the twins' removal is a genuine public-surface deletion (approved
  polish) — coordinate the CHANGELOG/CONTINUUM fold.

---

# lane d — CONTINUUM_DX wave 1 (DX-4a region view · DX-7d lease · W2 codec-prep design · DX-9 id-vocabulary design)

branch `task/d-surface`; base `ec1bcbc` (= `origin/dev-continuum` tip,
verified at dispatch). three green units pushed: `a8d0f86` (WebUIIsland),
`a3e95b3` (Viewport lease), and this notes commit.

## what landed (commits)

- `a8d0f86` feat(webui): `WebUIIsland(id:name:args:)` region view + the
  declaration-ordered `WebUIIslandArgs` serialization; byte-diff suite (13
  tests) vs the committed W0 fixture
  `Tests/WebUITests/Fixtures/dx-w0-island-regions.html`.
- `a3e95b3` feat(design-system): the `Viewport` container emits the engine
  lease `data-webui-lease="viewport"` (DX-7d) + `ViewportTests.leaseEmission`.

## DX-4a decisions

1. **the region `id` is explicit, with an `island-<name>` derived default** —
   the byte capture proved no derivation rule reproduces both regions:
   `name "validate"` → `id "island-validate"` (the derived form), but `name
   "never-built"` → `id "island-never"` (a hand-chosen shorter id, no rule).
   the convenience `WebUIIsland("feed", args:)` (the plan's spelling, and
   appendix-A's template form) derives the id; the designated
   `WebUIIsland(id:name:args:)` pins the full contract byte-for-byte.
2. **the pinned serialization contract**: attributes in order `id` →
   `data-webui-island` → `data-webui-args`; args single-quoted; a
   declaration-ordered typed args payload. `args` defaults to `.empty`
   (`{}`) — a lone `@HotView` region pre-emits the empty object.
3. **the args type** (`WebUIIslandArgs` + `WebUIIslandArgsValue`): ordered
   `[Pair]`, hand-rolled JSON (no `[String: Any]`/`JSONSerialization` —
   per-process key order and the `4.0` Double bridge cannot match a pinned
   capture). `int` renders `4`, never `4.0`; apostrophes/amps in values become
   `&#39;`/`&amp;` so the single-quoted attribute round-trips through the
   browser's entity decoding + the engine's `JSON.parse` (identity on every
   captured byte).
4. **byte-identity is proven twice**: against the committed fixture (byte-equal
   whole-file compare, incl. a `count("\n")==2` shape check + per-line compares)
   AND against spelling-out raw-string assertions of both captured lines (guards
   the fixture against a transcription typo). W3's host migration additionally
   asserts page bytes under §3.1's register.

## DX-7d decision

- the COMPONENT emits `data-webui-lease="viewport"` immediately after the
  `data-webui-viewport` discovery marker; the MODIFIER (`.lease(.viewport)`)
  stays inert and byte-identical — both its live pins untouched (the
  red-team's finding: emission lives in the component, never the modifier).
- both name sets are emitted this wave (`data-webui-lease` + `data-viewport-*`),
  so E's engine and the bench bridge may read either; the bench's
  string-replace server-adapter lease becomes a no-op duplicate → retire at
  integration (handed to E via d-to-e.md; B is told at the report).
- pinned by `ViewportTests.leaseEmission`: exact container prefix, exactly one
  lease occurrence, rows/pads never carry it.

## W2 codec bodies — the delegation design (no implementation this wave)

**the emission point stays** (`WebUIContinuumMacro.swift:362/364`): the
generated adapter's `_continuumEncode() -> [UInt8]` / `_continuumDecode() ->
[HotEffect]` members, plus their `@_expose(wasm, "<name>_encode"/"<name>_decode")`
peer globals. the ABI strings are frozen (c-to-d's recorded table); W2 swaps
ONLY the bodies.

**the delegated shape**: each body becomes a thin shim over lane C's DX-1
runtime slice (`WebUIIslandCore/IslandRuntime.swift`) and `HotOpCodec`:

- `_continuumEncode() -> [UInt8]` → `IslandRuntime<<Type>Island>.encodedState()`
  — the runtime-held `State` serialized through `HotOpCodec` into the frame
  bytes (`webui_state_save` / engine `restoreIslandRegionState` path);
- `_continuumDecode() -> [HotEffect]` → `HotOpCodec.decode(...)` of the pending
  op batch (the record-format-v1 frame records the runtime drains) into
  `[HotEffect]` for the island's `reduce` loop.

**seam rules**:
1. generated code may reference only `WebUISharedCore` vocabulary +
   `WebUIIslandCore`'s runtime + the author's members — no `Codable`, no
   `JSONEncoder` (the embed-Codable gate, c-to-d).
2. the exact `IslandRuntime`/`HotOpCodec` signatures are lane C's W1
   deliverable (not on the tree at D-W1 time) — W2-D starts by chasing C's
   merged `IslandRuntime.swift` and fitting the two shim bodies to the real
   call surface, then re-asserting the expansion suite (string-level first,
   then the compiled fixture, then the hand-written equivalence).
3. stub-retirement gate (grep-asserted in W2): no `{ [] }` codec body remains
   in the macro emission.
4. anti-shackle: the delegation is a real runtime call — the hand-written
   equivalent must produce identical op streams (the existing fixture).

## DX-9 id-vocabulary design (no implementation this wave)

- **compile-time vocabulary**: the `@HotView` macro (which already parses the
  render body) walks the `@HotBuilder` body collecting LITERAL `id:` string
  arguments (the spelled `ElementID` literals across `Hot.Text`/`AttrWrapper`/
  `KeyedList` and the built-ins) and emits a generated static mirror of the
  hand-kept `WebUIIslandCore.ProbeIslandIDs` pattern:
  `static let elementIDs: Set<ElementID>` (spelling TBD against C's
  `ElementID`; raw-value keyed for O(1) membership). over-collection is
  permissive-safe (the dev check ignores ids the island never emits); a
  missed literal is the only bug class.
- **the literal-only boundary**: interpolated/dynamic ids
  (`ElementID("t-\(key)")`, key-derived `-k<key>` list ids) are NOT statically
  knowable — they defer to the runtime dev check, not compile time. the check
  is a dev-time assertion, not a type guarantee.
- **build-flag-gated dev check** (runtime side, lane C W2): a custom debug
  flag (e.g. `-DCONTINUUM_ID_CHECK`) compiles in an assertion in the runtime
  slice — every op the island emits on mount/first-event must target a known
  id; unknown → dev-time failure naming the id. production builds compile it
  out — zero runtime tax (I4).
- **the hand-written pattern stays**: `ProbeIslandIDs` remains the fallback,
  still tested; the macro-emitted vocabulary is diffed against it in the
  equivalent-fixture test. W3 takes it end-to-end (emission + dev check +
  probe).

## W2 codec bodies — implementation record (lane D, wave 2)

_committed `task/d-surface2` — the emission swaps from `{ [] }` stubs to a real
record-plane delegation._

### what landed

- `_continuumEncode() -> [UInt8]` / `_continuumDecode() -> [HotEffect]` are now
  **HotOpCodec-backed delegations** (the plan's own wording, §2.1: "the bodies
  delegate to the runtime slice (`HotOpCodec`-backed)"):
  - encode: `(try? HotOpCodec.encodeBatch([])) ?? []` — the pending op batch on
    the record-v1 plane, encoded by the exact codec the runtime's
    `webui_take_ops` drain serves (`IslandRuntimeCore.onEvent` queues reduce ops
    through `HotOpCodec.encodeBatch`);
  - decode: `guard let op = try? HotOpCodec.decode([]) else { return [] };
    return [.ops([op])]` — the pending records decoded back into effects for
    the reduce loop.
- the generated adapter is `ContinuumIsland`-only and keeps its name-only /
  additive contract: an untethered surface (no mounted runtime instance) holds
  no retained state, so the entries report the **drained batch** (empty record
  stream) — documented in the emission, not hidden.
- the record-loop REALITY is proven by `ContinuumFixtureTests.codecRoundTrip`
  (encode → decode identity on a real op, byte-exact) and the anti-shackle
  equality (`HandCounterIsland` carries the same bodies; the two generations
  agree on the drained batch).
- grep gate: no `{ [] }` codec body remains in the emission.

### why not `IslandRuntime<<Type>Island>.encodedState()` verbatim (the recorded delta)

the d-docs delegation design (above) names `IslandRuntime<<Type>Island>
.encodedState()` / `.decodePendingOps()`: those accessors are **not on the
merged runtime** (lane C's W2 landed `consumeMountEnvelope` +
`writeExport(input:_:compute:)`, not the codec state accessors), AND the shape
is untypeable in every `@HotView` consumer of record:

1. `IslandRuntime<I>` is constrained `I: IslandRuntimeSurface`; the macro
   cannot synthesize `decodeEvent`/`stateToJSON`/`stateFromJSON` for an
   arbitrary author State, so the generated adapter cannot satisfy the surface
   (name-only additivity, I5);
2. the acceptance/template App target depends on WebUI/WebUIDesignSystem/
   WebUIServer products only — `WebUIIslandCore` is not in the graph, so even a
   surface-conforming adapter could not name `IslandRuntime` there, and the
   acceptance's lone name-only `@HotView` MUST compile.

**the i2 delta (to lane C, d-to-c.md):** when C lands
`IslandRuntime<I>.encodedState()` (bound-instance `stateSave()`) /
`.decodePendingOps()` (bound pending records) **and** the consumer graph
exposes `WebUIIslandCore` to `@HotView` targets, the emission swaps these two
bodies verbatim to the documented spell — one self-contained patch, string
suite + fixture pin it.

## DX-11a — implementation record (lane D, wave 2) + the byte-identity exception

_committed `task/d-surface2`. the typed per-control id vocabulary ships; gate =
`Tests/WebUITests/APISurfaceTests.swift` `dx11a*` (byte-diff)._

### the contract (pinned byte-exact)

- **`WebUITable`, INTERACTIVE tables** (wired = at least one typed handler,
  `.onSort`/`.onSelectAll`/`.onSelect`/`.onToggleExpand`): every data row
  carries `<tr id="{id}-r{rowIndex}" data-key="{rowId}">` (attribute order
  id → data-key → class). `data-key` is the SAME `rowId` the select/expand
  control ids derive from (`{id}-select-{rowId}` / `{id}-expand-{rowId}`) —
  one id vocabulary, no string math. sortable headers keep the routed control
  `{id}-sort-{i}` (the span INSIDE the `<th>` — pinned there by the smoke gate
  `<th class="sort-cell"><span class="sort" id="...-sort-{i}">`; the plan's
  "ids on sortable `<th>`s" reads as these header-control ids; moving the id
  onto the `<th>` element itself is a W3 routing re-target, deferred).
- **`WebUIPagination`**: `{id}-prev/next/page-{n}/rows` (already existed —
  pinned as the contract).
- **chart marks** (`WebUIChart`): `{id}-mark-{i}` (sectors/categorical),
  `{id}-mark-pt` (points) — already existed, pinned.
- **static tables stay byte-identical**: a table without typed handlers (or
  without an id) emits NO row ids / `data-key` — so showcase/blocks display
  tables and the BEM pins (`<tr class="tr--selected">` etc.) are untouched.

### the byte-identity exception (I1 migration register, §3.1/§2.11)

rows of the smoke page's `interactive-table` (wired) gain the two row
attributes → **the smoke page's served bytes change**. recorded exception,
named in d-to-b.md for the dx-content-pin harness: page `smoke`, table
`interactive-table`, rows `{id}-r{i}` + `data-key` added. no other reference
page (showcase/blocks) carries a wired table. the change is purely additive
to the row tag; the interactive count pin (25 `data-component-id`) is
unchanged (rows carry no routing attrs).

## doc fragments (W1, for the orchestrator)

- `CONTINUUM.md`: §2.4 gains `WebUIIsland`'s pinned contract table (attribute
  order, single-quote, declaration-ordered typed args, explicit-id +
  derived-default), and §2.7's DX-7d line gains "shipped: the component emits
  the lease; `.lease` stays inert".
- `CHANGELOG.md` (unreleased): "WebUIIsland region view (DX-4a) byte-identical
  to the hand-written smoke markup + the declaration-ordered args
  serialization; Viewport emits `data-webui-lease="viewport"` (DX-7d)".

## handoffs

- to E (also in d-to-e.md): the container now emits `data-webui-lease="viewport"`;
  the bench's adapter lease is a duplicate → retire at integration.
- to C (also in d-to-c.md): W2 codec bodies delegate to `IslandRuntime`/
  `HotOpCodec` per the design above — the generated shims chase C's real
  signatures at W2 start.

