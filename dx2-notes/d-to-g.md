# d → G — what lane D exposed for the acceptance's steps 9b/9c (MACRO_DX)

_branch: `task/d-adopt` (lane D) · base `3230deb` (origin/dev-macro)._

## step 9b — the no-layer audit's macro half

the demo source (`Sources/WebUIExample/main.swift`) now carries BOTH spellings:

- the four macro declarations, used: `@LiveRegions` (on `MacroDemoRegions`),
  `@LiveRegion(id: "g-mreg-b")` + `@RegionState` (on `MacroDemoRegions.MacroStructRegion`),
  `@LiveState` (on `MacroDemoRegions.MacroDemoFeed`).
- the hand-written path, intact and constant: `struct DemoStructRegion: LiveRegion`
  (with a written `var source`/`var cadence`/`var id`), `actor DemoFeedState: LiveState`
  (with a written `nonisolated func subscribe`), and the hand-written assembly
  `WebUILiveRegions([` inside `DemoRegions.registry`. `registry` is byte-unchanged;
  the demo's served registry is composed as `WebUILiveRegions(regions.regionList +
  macroRegions.regionList)` (a single `WebUILiveRegions` — the frozen server takes one).

the banned-token set: nothing new was introduced (`fatalError`, hand-rolled dedupe,
timers, `wire(`, `withValueBody`, `btn(`, `.register(` never appear in the demo).

## step 9c — the macro-variant frame parity, gate-executed

what is exposed on the served page (ids readable from the served markup exactly as
g-regions.mjs already reads the hand block's):

- macro region roots: `id="g-mreg-a"` … `id="g-mreg-d"`
- macro controls: `data-component-id="g-mreg-nudge"` · `g-mreg-combined` ·
  `g-mreg-b-bump` · `g-mreg-c-bump` · `g-mreg-d-bump`
- the four drivers map one-for-one onto the hand ones: closure default
  (`g-mreg-a`, static tick), custom `@LiveRegion` struct (`g-mreg-b`), and the
  `StateLiveRegion<LiveBox>` twin (`g-mreg-c`) + `StateLiveRegion<@LiveState actor>`
  twin (`g-mreg-d`).

the byte-equality claim (the twin) is established in `MacroParityTests`
(`Tests/WebUITests/MacroParityTests.swift`): the macro-spelled and hand-spelled
variants are driven through the SAME registry seam (`WebUILiveRegions.start(router:
push:)`, the seam the hand path uses) with the same input sequence and asserted
byte-equal — same ids, same html, same order, and the wire bytes equal under a
deterministic encoder; both conform (`any LiveRegion` / `any LiveState`); I7 quiet
on both spellings. that is the unit half of the twin (I11).

for the gate half (9c) against the LIVE server: the macro variant's frames for a
driver are byte-identical to the hand's EXCEPT the id (g-mreg-* vs g-region-*); the
fragment html is otherwise identical (the macro regions render the same
`DemoRegions.html` template with the same labels — a macro frame differs from its
hand twin only in the id substring). suggest: after driving g-regions's four-driver
sequence against `g-mreg-*`, substitute `g-mreg-` → `g-region-` in the fragment ids
(or compare html payloads) and assert byte-equality against the hand frames — that
is the page-level twin. `MacroParityTests.byteEqualFrames` holds the same-ids form.

## handoff specifics

- `designer/probes/g-regions.mjs` now asserts both variants (20 passes). note the
  probe's `collect` gained a retry on a failed socket and the port block is lane
  D's 9410–9419: the reference server transiently resets a bare connection that
  immediately follows a closed one (verified pre-existing on base `3230deb`); the
  i0 probe's second socket was the I7 idle check, which passes vacuously on an
  errored socket, so the quirk never surfaced.
- do not dedupe or normalize anything server-side for 9c — the twin is the
  assertion; the acceptance should drive the live server, not read source.
