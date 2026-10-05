# lane D — W2 record (the substitution guide + docs + skill)

_branch: `task/d-docs` · base: `c24857a` (= `origin/dev-subst` = i1) · clone `/tmp/continuum-fleet/lane-d2`_

## what landed (commits)

| commit | content |
|---|---|
| `da22eec` | `Documentation/SUBSTITUTION.md` (NEW) — the consumer guide: one section per axis (events / live data / themes / components), protocol / default / injection / a minimal example, the biting semantics, the adjacent-name ledger, the twin table |
| `3df7168` | `Documentation/API.md` — the live_dx symbols (Event Handling + a live-regions subsection + `## WebUIThemeBuild`) and the `## WebUIExample` reconciliation (route set, `--port`, line cites) |
| `90fb99e` | `Documentation/STABILITY.md` (three additive I5 bullets) + `Documentation/JS_RUNTIME.md` (one note: the runtime is unchanged) |
| `c2ed151` | `CHANGELOG.md` (the live_dx unreleased entry) + `README.md` (docs pointer + file-count fix) |
| `d198701` | `skills/webui-design-system/` — `references/substitution.md` (new), `references/live-regions.md` (new), `SKILL.md` (section + index rows + v1.16.0), `references/live-server-and-showcase.md` (the `regions:` attach) |
| this commit | these notes + the AGENTS.md fold proposal below |

## the example-provenance decision (read this first)

the brief: "every axis example is the demo's real code (cite file/line)". at the
i1 head the reference demo exercises **two** axes:

- **events** — the SWAP control (`main.swift:64–74`), `ViewOutcome` (`:88–105`),
  `RegionInvalidations` (`:111–121`), the `demoControl` helper (`:48–56`);
- **components** — the counter buttons (`:139–150`), the echo input (`:155–159`),
  the composed cards (`:135–172`).

the demo's own **live-data drivers and theme catalog land in W2 lane G2** (running
in parallel; `briefs/w2-G2-attempt2.md` — "the four live-region drivers in the
demo … plus the custom `ThemeCatalog` and the hand-written `WebUIThemeProvider`"),
so they cannot be cited from the i1 demo. conservative choice, recorded here:

- the live-data example is the **handoff-fixed driver shape** (`dx2-notes/r-to-g.md`
  §"what the demo must ship"), byte-mirroring the committed W1 twins
  (`Tests/WebUITests/LiveRegionsTests.swift:38–49` TwinRegion, `:79–95` TwinState);
  its region id is the one the *served* demo already declares — its nudge control
  targets `g-region-a` (`main.swift:113`);
- the themes example is the **committed fixture catalog**
  (`designer/probes/fixtures/t-theme-catalog/Catalog.swift:8–30`) whose own header
  records it "mirrors the demo catalog shape", plus the plugin attach fixed by
  `dx2-notes/t-to-g.md`;
- each example carries its provenance caption in the guide; every symbol and every
  file:line citation resolves at `c24857a` (gate below).

## the adjacent-name ledger (the brief's item 2, stated correctly)

the brief's trio `WebUITheme` (runtime protocol) / `WebUIThemeBuild` / `WebUIBuild`
resolves on the tree to a **four**-name ledger; the guide documents the tree as it
greps (the "runtime protocol" role belongs to `WebUIThemeProvider`, not to
`WebUITheme`, which is a struct):

| name | role (at i1) |
|---|---|
| `WebUITheme` (`WebUIDesignSystemCore/WebUITheme.swift:143`) | runtime **value** |
| `WebUIThemeProvider` (`:314`) | runtime **protocol** |
| `WebUIThemeBuild` (`Sources/WebUIThemeBuild/WebUIThemeBuild.swift:21`) | build **library** |
| `WebUIBuild` (`Sources/WebUIBuild/Emit.swift:83`) | build **emitter** |

## AGENTS.md — the drift fold is BLOCKED (environment guard) — PROPOSAL below

the write to `AGENTS.md` was refused by the environment:
"BLOCKED: write to protected agent-instruction file(s) (AGENTS.md) was denied by
the user … Do NOT retry it or attempt the same edit via another path." no retry
was attempted. **the fold is ready to apply by the orchestrator/owner** — it
replaces the `RenderContext` bullet in `### web UI framework conventions` with
the `RenderContext` bullet + four new bullets:

```diff
-- **RenderContext** — `@TaskLocal` context for component ID generation and
-  handler registration. must be set before rendering.
+- **RenderContext** — `@TaskLocal` context for component ID generation and
+  handler registration. the server establishes it around the page render **and**
+  every dispatch (`RenderContext.withCurrent(router:)`, DX-12), so a control first
+  rendered *inside* a handler self-registers; registration is overwrite-wins
+  (last-render-wins) for a stable id.
+- **event outcomes (DX-14)** — `control(_:event:handler:)` takes a handler that
+  yields an `EventOutcome` (six framework conformances: `FragmentUpdate`,
+  `[FragmentUpdate]`, `ViewOutcome`, `RegionInvalidations`, `NoOutcome`,
+  `CombinedOutcome`). the closure's return type fixes `O` — annotate it.
+  `ViewOutcome` replaces `#<component-id>`: the control's replaceable root must
+  carry that DOM id (minted `cN` ids return fragments instead).
+  `controlAttributes`/`EventHandler` path byte-unchanged (I5); the dispatch wrap is
+  the `@testable` `dispatchOutcome` in `WebUIServer.swift`.
+- **live regions (DX-13 + DX-16)** — `LiveRegion` protocol (`id` = DOM id +
+  fragment id, `cadence`, `source`, `render() -> String?`) with `ClosureLiveRegion`
+  / `StateLiveRegion` defaults and the `LiveState` binding (`LiveBox`,
+  `LiveNotifier`, `LiveSubscription`); the `WebUILiveRegions` registry is passed as
+  `regions:` to **both** `WebUIServer` inits (defaulted nil = zero new work).
+  baselines push nothing; unchanged renders push zero frames; a change pushes
+  ≤ html + 512 B on the existing `update` frame; dispatch invalidations keep the
+  two-push order (dispatch frame first). consumer guide: `Documentation/SUBSTITUTION.md`.
+- **theme pipeline (DX-15a + DX-15b)** — `WebUIThemeBuild.emit` renders a consumer
+  `ThemeCatalog` to a stamped, gzipped `WebUIShippedAsset` through the `WebUIBuild`
+  emitter; consumers attach `WebUIThemePlugin` to the catalog's target (no consumer
+  tool target) and reference the emitted sheet. `WebUIContinuumTool shadow` is the
+  anti-shadow lint (selector-extraction leg; demo tree reports 0).
```

## the gate (symbol resolution against the i1 head `c24857a`)

```
$ python3 /tmp/continuum-fleet/symbol_gate_added.py
added-text symbols: 121; unresolved: 0
```

(extracts every code-span symbol token from the lane's added text — 121 tokens,
incl. `LiveRegion`, `StateLiveRegion`, `LiveBox`, `LiveSubscription`,
`OutcomeContext.$current`, `control(_:event:handler:)`, `WebUIThemeBuild`,
`WebUIBuild`, `WebUIThemePlugin`, `WebUIThemeTool`, `dispatchOutcome`,
`livedataSurfacePins`, `ProbeCatalogSheet`, … — every one greps in
`Sources/`/`Tests/`/`Plugins/`/`designer/`/`skills/`/`templates/`.)

```
$ python3 /tmp/continuum-fleet/verify_cites.py Documentation/SUBSTITUTION.md lane-d2
all swift citations resolved
$ python3 /tmp/continuum-fleet/verify_cites.py Documentation/API.md lane-d2
all swift citations resolved
```

headline greps (the evidence set; run from the clone root):

```
grep -n "public protocol LiveRegion" Sources/WebUIServer/LiveRegions.swift         # :19
grep -n "public protocol LiveState" Sources/WebUIServer/LiveState.swift           # :19
grep -n "public final class WebUILiveRegions" Sources/WebUIServer/LiveRegions.swift  # :97
grep -n "regions: WebUILiveRegions? = nil" Sources/WebUIServer/WebUIServer.swift  # :306, :323
grep -n "public protocol EventOutcome" Sources/WebUICore/EventHandling.swift      # :47
grep -n "public func control<O: EventOutcome>" Sources/WebUICore/EventHandling.swift  # :307
grep -n "public enum WebUIThemeBuild" Sources/WebUIThemeBuild/WebUIThemeBuild.swift  # :21
grep -n "struct WebUIThemePlugin" Plugins/WebUIThemePlugin/WebUIThemePlugin.swift  # :28
grep -n "public enum WebUIAssetBuilder" Sources/WebUIBuild/Emit.swift             # :83
```

## assumptions / notes for the orchestrator

1. the AGENTS.md fold is **blocked by the protected-file guard** (above) — apply
   the proposal, or accept the block as a known delta.
2. the demo-lift provenance decision (above): live-data/themes examples are
   handoff-shaped because the demo's W2 drivers land in G2; no citation claims
   otherwise.
3. the guide deliberately states `WebUITheme` as the runtime **value** and
   `WebUIThemeProvider` as the runtime **protocol** (the tree, not the brief's
   shorthand) — recorded here so a reviewer reading the brief side-by-side is not
   surprised.
4. `Documentation/README.md` (the folder's legacy overview) is untouched — out of
   the lane's owned set; the root README's docs index now carries the pointer.
---

## sidecar §3.8 report (drafted at `dd67cb3`; the notes-append commit and later polish commits extend the branch — the returned message carries the final head sha)

```
lane: D · branch head sha: dd67cb3 · base sha: c24857a
tasks:
  Documentation/SUBSTITUTION.md (new)                     done (da22eec)
  Documentation/API.md (live_dx symbols + WebUIExample)   done (3df7168)
  Documentation/JS_RUNTIME.md (one note)                  done (90fb99e)
  Documentation/STABILITY.md (additive I5 entries)        done (90fb99e)
  CHANGELOG.md + README.md                                done (c2ed151)
  skills/webui-design-system/** (2 refs + SKILL pointer)  done (d198701)
  dx2-notes/d-w2.md (lane record)                         done (103d197)
  AGENTS.md (drift fold)                                  BLOCKED (environment guard; proposal in this file)
  citation polish                                         done (dd67cb3)
green:
  python3 /tmp/continuum-fleet/symbol_gate_added.py   -> branch-diff added text: 129 symbols, 0 unresolved
  python3 /tmp/continuum-fleet/verify_cites.py Documentation/SUBSTITUTION.md lane-d2 -> all swift citations resolved
  python3 /tmp/continuum-fleet/verify_cites.py Documentation/API.md lane-d2 -> all swift citations resolved
  grep -n "public protocol LiveRegion" Sources/WebUIServer/LiveRegions.swift -> :19
  grep -n "public protocol EventOutcome" Sources/WebUICore/EventHandling.swift -> :47
  grep -n "public func control<O: EventOutcome>" Sources/WebUICore/EventHandling.swift -> :307
  grep -n "regions: WebUILiveRegions? = nil" Sources/WebUIServer/WebUIServer.swift -> :306, :323
  grep -n "public enum WebUIThemeBuild" Sources/WebUIThemeBuild/WebUIThemeBuild.swift -> :21
  grep -n "struct WebUIThemePlugin" Plugins/WebUIThemePlugin/WebUIThemePlugin.swift -> :28
  git diff --name-only c24857a..HEAD | grep -E "^(Sources|Tests|designer|Package.swift)" -> empty (no forbidden paths)
assumptions:
  1) the demo's live-data drivers + theme catalog land in parallel lane G2 (w2-G2-attempt2),
     so the live-data/themes examples are the handoff-fixed driver shapes (r-to-g/t-to-g)
     mirroring the committed twins/fixture; events/components examples are demo-verbatim.
  2) WebUITheme is documented as the runtime VALUE and WebUIThemeProvider as the runtime
     PROTOCOL (the brief's "WebUITheme (runtime protocol)" shorthand resolves to that pair).
  3) AGENTS.md is blocked by the protected-agent-instruction guard; fold ready to apply.
next-slice: apply the AGENTS.md fold (or accept); at i2 verify the guide's live/theme examples
  against the merged G2 demo (ids: g-region-a; catalog name) and adjust captions if G2 differs.
```
