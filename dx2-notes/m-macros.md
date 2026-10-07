# lane M — the live-data macros: full diagnostic set, frozen fixtures, shape gate

_the W1 deliverable for features A–C. branch `task/m-macros`, cut from `origin/dev-macro` @ `3230deb`
(the i0 head; base `a260dd2` ancestor-verified). everything below is evidence over claims: the exact
commands and their output._

## the diagnostic set (feature A/B/C) — complete, pinned by the negative fixtures

| misuse (§3.1 / i0-landing lists) | diagnostic (the frozen message) | pinned by |
|---|---|---|
| `@LiveRegion` on a non-type | `@LiveRegion can only be applied to a struct, class or actor` | enum + protocol negatives |
| `@LiveRegion` missing `id:` | `@LiveRegion requires an id: argument` | negative |
| `id:` not a literal | `@LiveRegion(id:) must be a string literal — the id is the DOM id and the pushed fragment id, stated once` | negative |
| missing `render()` | `@LiveRegion requires the type to declare 'func render() async -> String?' in its body (a member added in an extension is invisible to this macro)` | negative |
| hand-written `id`/`cadence`/`source` | `@LiveRegion generates '<name>' — a hand-written '<name>' on the same type is ambiguous; remove it` | three negatives |
| two `@RegionState` markers | `@RegionState marks 2 properties (a, b) — exactly one, or none, is allowed` | negative (names both) |
| zero `@RegionState` markers | **no diagnostic** — `source == nil` (the protocol default), frozen in `regionNoSource` + compiled `Driven` | positive + compiled |
| `@LiveRegions` on a non-struct/class | `@LiveRegions can only be applied to a struct or class` | negative (actor) |
| zero region properties | `@LiveRegions found zero region properties — an empty registry is a silent mistake` | negative |
| unclassifiable member (explicit unknown type) | `@LiveRegions cannot tell whether '<name>' ('<Type>') is a live region — … anything else does not belong in the group` | negative |
| unclassifiable member (no type, no init) | `@LiveRegions cannot tell whether '<name>' is a live region — give it an explicit type (…)` | negative |
| duplicate ids | **warning**: `duplicate live-region id '<id>' — already used by an earlier member; the registry keeps the last definition` | negative (severity-asserted WARNING) |
| unreadable id | **warning**: `@LiveRegions cannot compare '<name>''s id — it is not a string literal, so a duplicate would go unnoticed` | negative (severity-asserted WARNING) |
| `@LiveState` on a non-actor | `@LiveState can only be applied to an actor` | negative (struct) |
| actor already declares `subscribe` | `@LiveState generates 'subscribe' — a hand-written 'subscribe' on the same actor is ambiguous; remove it` | negative |
| actor already declares `notify` / `liveNotifier` | same shape, per name | two negatives |

every message above is asserted through `Parser.parse` + `file.expand(macros:contextGenerator:)` and a
message comparison in `context.diagnostics` (position-immune — positions shift across swift-syntax
generations; `assertMacroExpansion`'s `DiagnosticSpec` binds line/column and does not capture thrown
member-macro diagnostics at all). the negative helper records a real Swift-Testing `Issue`, so a
misuse that stops diagnosing fails the suite.

## the classification rule — kept exactly as i0 froze it

the `@LiveRegions` syntactic classifier (region = nested-`@LiveRegion` type or `ClosureLiveRegion` /
`StateLiveRegion`; skip = nested-`@LiveState`, `LiveBox`, `LiveNotifier`; else diagnose) was probed at
i0 (`members=6 regions=["tick","clock","count"]`), is re-asserted by the frozen `group` fixture
(`WebUILiveRegions([tick, clock, count])`, declaration order, `feed` and `countBox` skipped), and no
change was needed. two additions were NOT needed and were NOT made: any reordering knob (explicitly
out) and any type-based classification (a macro sees syntax, not types — recorded).

## the marker-visibility probe — answer carried from i0, and proven live

the probe (a temp `context.diagnose` warning, run through the EXTERNAL plugin by building the test
target — the expansion harness auto-seeds member-full contexts and is not ground truth for this) was
run and recorded verbatim at i0 (`i0-landing.md`):

```
warning: PROBE-LiveRegions members=6 regions=["tick", "clock", "count"] nested=["Tick", "Feed"] (from macro 'LiveRegions')
warning: PROBE-LiveRegion members=2 markers=["box"] type=Tick (from macro 'LiveRegion')
```

it is visible to the member scan; the temp diagnostics were removed at i0. lane M re-confirms the
SAME fact through the compiled runtime fixture in this clone (`Tests/WebUIServerMacroTests/RuntimeFixtures.swift`,
compiled by the real compiler through the external plugin): `@RegionState let box: LiveBox<Int>` on
`MacroWidgetGroup.Tick` reaches the generator, `tick.source` is the same box, and
`guard let source = region.source` in `WebUILiveRegions.start()` subscribes it — the marker and its
delivery path are live in the type-checked build, not only in the in-process harness.

## the fixture suite — captured, never hand-written

`Tests/WebUIServerMacroTests/FrozenFixtures.swift` is GENERATED (header says so): a scratch dump
harness replicated `assertMacroExpansion`'s OWN expand call
(`file.expand(macroSpecs:contextGenerator:allMacroLexicalContexts, indentationWidth: .spaces(4))`),
wrote the raw `description` to `/tmp/lane-m-dump/*.txt`, and a generator splices those bytes into raw
`#"""` literals. the splice was verified byte-exact against the dumps before freezing (a decode
check on every fixture: all 6 matched, 274–1,116 bytes each). the scratch harness was deleted after
the freeze.

| fixture | input | captured expansion |
|---|---|---|
| `regionSource` | `@LiveRegion(id:)` struct + one `@RegionState` | `id`/`cadence`/`source` witnesses + `extension Tick: LiveRegion {}` |
| `regionNoSource` | no marker | `source == nil` witness |
| `regionCadence` | `cadence: .seconds(2)` | the expression carried inline (`{ .seconds(2) }`) |
| `publicRegion` | `public struct` | witnesses are `public` (the access prefix) |
| `group` | `@LiveRegions` with nested `Tick`/`Feed` + clock/count/countBox | registry `[tick, clock, count]` in order, qualified extensions (`DemoRegions.Tick`), `@LiveState` member injection |
| `stateActor` | `@LiveState` actor | `liveNotifier` storage + `nonisolated subscribe` + `notify()` + conformance |

on 603.x the expander re-indents generated members (BasicFormat) — the capture is frozen with that
indentation, and `assertMacroExpansion`'s hardcoded `indentationWidth: .spaces(4)` matches. the
`assertMacroExpansion` failure handler here is the BANNED-variant replacement (explicit
`failureHandler` recording an `Issue.record(Comment(...))`) — the default XCTFail handler is a
silent no-op under Swift Testing and the suite must be able to fail.

### the re-expansion parse gate (appendix D.2)

every positive fixture is re-expanded through the raw expander, must emit ZERO diagnostics, and the
generated source must re-parse cleanly (`!reparsed.hasError`).

### the shape gate (appendix D.3, the automated half of d-h)

a SyntaxVisitor over every frozen expansion asserts: no `func` nested inside another `func`'s body;
no `: ()` Void-marker parameters (an empty-tuple parameter type); no immediately-invoked closures
(a call whose `calledExpression` is a `ClosureExprSyntax`). direct-inline bodies and direct init
composition are the frozen bytes; the scanner reds on any reappearance of a rejected shape.

## the harness can fail — demonstrated twice, recorded, reverted

the demonstration: a one-byte deliberate mismatch in a frozen expectation
(frozen `regionSource` expansion: `"g-region-b"` → `"g-region-x"` in the generated `var id` body),
run, then reverted to the byte-exact capture. raw output (filtered suite, `EXIT=1`):

```
✘ Test expansionMatchesTheFrozenCapture(fixture:) recorded an issue with 1 argument fixture → FrozenFixture(name: "regionSource", … expanded: "struct Tick { … var id: String {
        \"g-region-x\"
    } … ") at MacroAssertions.swift:34:41: Issue recorded
↳ Macro expansion did not produce the expected expanded source
✘ Test expansionMatchesTheFrozenCapture(fixture:) with 6 test cases failed after 0.026 seconds with 1 issue.
✘ Test run with 1 test in 1 suite failed after 0.026 seconds with 1 issue.
```

the revert re-ran the generator from the same captures; the tree was verified corruption-free
(`g-region-x` absent) and the suite re-ran green. the first attempt taught the lesson recorded in
`swift-macro-development`: corrupting BOTH the input attribute and the expectation coherently is a
self-consistent mismatch that still passes — the honest demo flips the expectation ONLY.

## gates (exact commands → result)

```
swift build                                    → Build complete, 0 warnings
swift test --filter WebUIServerMacroTests      → ✔ Test run with 28 tests in 5 suites passed (5 of 5 suites green)
swift test --filter ExpansionFixturesTests     → ✔ (the frozen byte-exact expansions)
```

the compiled runtime fixtures expand through the EXTERNAL plugin (the test target build loads
`WebUIServerMacros` via `-load-plugin-executable` — visible in the build transcript) and type-check
and run: the generated conformance (`Tick(box:)` still constructs — the witnesses are computed),
the member injection (`nonisolated subscribe` callable synchronously, deliveries counted and
cancelled), the registry assembly, plus the new cadence-carrying and no-source regions.

## assumptions

1. the marker-visibility probe evidence is i0's, carried forward (the temp diagnostic was already
   removed there; the live compiled fixture re-proves the same fact in this clone). no re-probe run
   was needed and none was run.
2. the `@LiveState` collision diagnostics extend the mandated `subscribe` check to `notify` and
   `liveNotifier` (all three are generated members of the same type — an author-declared one is the
   same class of footgun; additive, within the owned surface).
3. fixture indentation is the expander's own output on 603.x with `.spaces(4)`; a future toolchain
   that re-indents differently is a deliberate, recorded re-freeze — never an edit.
