# lane M — the consumer-deletion ladder (MEASURED)

_per the plan's feature D: per seam, delete arc-agent's corresponding layer and substitute the
framework's conforming type; report ΔLOC, Δwire bytes and touchpoints per new control/region —
**measured, never projected** (the plan's own 19% lesson: the CONTINUUM theme port guessed ">50%
shrink" and measured 19%)._

- **provenance:** arc-agent @ `ae67d73a` (its tree has MOVED since the plan's audit — see
  "discrepancies" below) · no-webui @ `4e4636b` (the closed i2 head) · measured 2026-10-05.
- **reproduce:** `bash designer/probes/m-ladder.sh [ARC_PATH] [WEBUI_PATH]` — this file's
  "raw output" section is that script's verbatim stdout. every number below comes from it.

## the ladder

| seam | deleted (arc-agent, measured) | substituted (framework) | measured Δ | touchpoints |
|---|---|---|---|---|
| **1 · wiring** (DX-12/14) | **128** `wire(router, id:events:)` registration sites; a hand **4-line** `btn()` helper (`Helpers.swift:74`); one control's id is hand-stated in **4 markup sites + 1 registration** | the demo's **10** `control(_:event:handler:)` call sites — the routing attributes are *emitted*, never hand-written | the registration scaffold goes to **0**; the handler *logic* stays (it is the consumer's code either way) | **5 → 1** (id stated once, at the call site) |
| **2 · response shape** (DX-14) | **56** hand-assembled `FragmentUpdate(` sites across **6** files | intent as a type: `ViewOutcome` · `RegionInvalidations` · `NoOutcome` · `CombinedOutcome` (the demo uses them at 5/6/6/2 sites); **7** `FragmentUpdate` sites remain — deliberately, to show the union | ids + html are no longer hand-paired with their targets; the one-update shape survives as a first-class outcome | — |
| **3 · the push layer** (DX-13/16) | `PushDeduper` (**12** lines) + `IntervalService` (**47** lines) + the poll vocabulary it serves (**34** `Task.sleep` sites, 4 `IntervalService` mentions); one nav click cost **136,195 B** in a single whole-`#app` `replace` (the audit's measurement, cited) | the four-driver surface: **268 lines** total (closure default · custom `LiveRegion` struct · `StateLiveRegion<LiveBox>` · custom `LiveState` actor, plus its controls); one region push measures **139 B** (frame ≤ html 74 B + 512, asserted live by `g-regions.mjs`) | **bytes collapse (~979×; 136,195 B → 139 B)**; **lines GROW** — see "what did not shrink" | — |
| **4 · theme tooling** (DX-15a) | `ArcAssetTool/main.swift` (**43** lines) + the plugin (**38** lines) + **4** manifest mentions = the plan's 81-line block | **1** manifest line (`plugins: [.plugin(name: "WebUIThemePlugin")]`) + a **47-line** `DemoTheme.swift` — which is the consumer's *content* (palettes + provider), not tooling | **81 lines of tooling → 0**; the consumer keeps only its content | — |
| **5 · styling** (DX-15b) | `ChromeSheet.swift`: **2,810 lines**, **1,028** rule blocks, re-skinning **9 of 9** probed DS classes (chip 3 · kv 5 · toast 3 · modal-overlay 1 · log-line 8 · md 18 · swatch 2 · inline-edit 2 · tool-btn 4) | tokens + typed `@Theme(rules:)`; the one shadow-check implementation reports **0 collisions** on the demo tree | collisions **9 → 0**; the 2,810-line *conversion* is a **follow-on** (d-w), measured here, not promised | — |

## what did NOT shrink (and why)

1. **Seam 3's lines GROW — the surface moves, it does not vanish.** arc's push layer is 59 lines of
   *machinery* (dedupe + interval) plus its call sites; the framework's substituted surface is 268 lines of
   *region definitions*. The consumer stops writing machinery and starts writing declarations — and, unlike
   arc's 59 lines, the declarations are what the consumer was trying to say. **The win here is bytes
   (~979×) and correctness (no client-side dedupe to get wrong), not line count.** This is the honest form
   of the claim the plan warned against over-projecting.
2. **Seam 1's handler bodies stay.** 128 registrations go away, but the logic inside them is the
   consumer's own work. What is deleted is the *scaffold*: the registration call, the id being restated in
   markup, and the hand-built attribute string. The measured touchpoint count (5 → 1) is the real metric,
   not LOC.
3. **Seam 5 is an architecture, not a migration.** 2,810 lines / 1,028 rule blocks of shadowing remain in
   arc-agent today; this arc ships the *substitution mechanism* (tokens + typed rules + a lint that reports
   the collisions) and proves it on one family (the chip-family `rules` proof, byte-identical to the raw
   sheet). The conversion is d-w — scheduled, not done.
4. **The `queue` control's 5 touchpoints are not a worst case, they are the shape.** every interactive
   control in arc restates its id wherever it is rendered and once more where it is registered; that is the
   cost the `control(_:handler:)` seam removes.

## discrepancies with the plan's §1 figures (recorded, not silently swapped)

| figure | plan §1 | measured now @ `ae67d73a` | note |
|---|---|---|---|
| `wire(` registrations | 128 | **128** ✓ (129 occurrences − 1 declaration) | agrees |
| `FragmentUpdate(` sites | 56 | **56** ✓ | agrees |
| `PushDeduper` | 26 lines | **12 lines** | arc-agent has moved since the audit; the measured value wins, the plan's figure is stale |
| `IntervalService` | 47 lines | **47** ✓ (42 non-blank) | agrees |
| `ArcAssetTool` / plugin | 43 / 38 | **43 / 38** ✓ | agrees |
| `ChromeSheet` | 2,810 lines · 999 rules · 509 selectors | **2,810 lines** ✓ · **1,028** rule blocks · (selector count depends on the counting rule) | lines agree exactly; the rule count differs by counting method — recorded rather than reconciled |

## the raw output

```
=== the ladder: deleted (arc) vs substituted (framework) ===
arc:    /Users/tannerdsilva/workspace/arc-agent
arc sha: ae67d73a refactor(deps): the web UI rides no-webui dev, not the master tip
webui:  /tmp/live-dx/work  (4e4636b fix(probes): g-seam asserts the registry push at i2 (the i0-silence claim is mode-dependent))
date:   2026-10-05T15:51:36Z

### seam 1 — wiring (DX-12/14) ###
arc: wire( occurrences: 129 (one is the declaration at Actions.swift:1151)
     wire( REGISTRATION sites: 128
arc: the hand btn() helper, Helpers.swift:74:
     4 lines
arc: one control ('queue') is hand-stated in 4 markup site(s) + 1 registration site(s) = 5 touchpoints
framework: the demo's control call sites (one per interactive control):
     10
framework: the routing attributes are EMITTED by control(_:handler:) — the id is stated once, at the call site

### seam 2 — the response shape (DX-14) ###
arc: hand-assembled FragmentUpdate( sites: 56
arc: files carrying them: 6
framework: the demo states INTENT as a type (occurrences):
     ViewOutcome            5
     RegionInvalidations    6
     NoOutcome              6
     CombinedOutcome        2
framework: hand-assembled FragmentUpdate( sites left in the demo: 7
     (the SWAP control uses the one-update shape on purpose — the union is the point; the rest state intent)

### seam 3 — the push layer (DX-13/16) ###
arc: actor PushDeduper (WebUIHost.swift:15):
     12 lines
arc: IntervalService.swift: 47
arc: poll/timer vocabulary across the tree:
       34 Task.sleep
        4 IntervalService
arc: recorded wire cost of one nav click (whole-#app replace): 136195 B  (plan §1 item 3 — the audit's measurement)
framework: a region push, measured live by g-regions.mjs: frame 139 B <= html 74 B
framework: the demo's four-driver live-data block (the whole surface): 268
     lines (RegionTick + the custom struct region + the LiveState actor + DemoRegions + its 4 drivers + 2 html helpers)

### seam 4 — the theme pipeline (DX-15a) ###
arc: the hand-built tooling
     ArcAssetTool/main.swift      43
     plugin.swift                 38 lines
arc: + the Package.swift block for them: 4 manifest mentions
framework: the consumer surface that replaces it
     the demo target's plugin line:                1  (plugins: [.plugin(name: "WebUIThemePlugin")])
     the catalog + the hand-written twin:          47 lines
     the sheet wiring (emit + serve + link):       3 sites

### seam 5 — styling: colliding classes (DX-15b) ###
arc: Sources/ArcTheme/ChromeSheet.swift: 2810 lines
     rule blocks ({ count): 1028
     the 9 DS classes it re-skins, with their mention counts:
       chip           3
       kv             5
       toast          3
       modal-overlay  1
       log-line       8
       md             18
       swatch         2
       inline-edit    2
       tool-btn       4
     classes shadowing the DS union: 9 of 9
framework: the shadow lint over the demo tree: shadow: 0 collision(s) against the DS class union

=== end of the ladder ===
```