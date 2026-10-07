# lane G — the styling axis (MACRO_DX), W1 record

_branch: `task/g-styling` · base `origin/dev-macro` @ `3230deb` (i0 head after `a260dd2`)._

## what landed (commits, oldest → newest)

| commit | content |
|---|---|
| `4290aca` | **G1** the spacing correctness fix: `VStack`/`HStack` keep `spacing-N` class for in-scale values (byte-identical) and emit `gap:Npx` inline for off-scale values (Grid's existing shape) — `LayoutStyles.spacingScale` is the single source of truth; `LayoutSpacingTests` proves `spacing: 7` renders a real 7px gap AND every in-scale value stays byte-unchanged |
| `4434e07` | **G2** the five typed-surface gaps: `justifyContent(JustifyContent/String)`, `flexBasis(Int/SpaceToken)` (token-typed on the space scale), `alignSelf(AlignSelf/String)`, `position(Position/String)`, `zIndex(Int)` — CSSProperty gains the five cases; `fill()`/`stretch()` ride `.alignSelf`, byte-identical |
| `8980b29` | **G3** the markup-debt audit, additive to the ONE `lint` verb: five code-borne metrics per file (raw tags via a closed element list · `class=` literals · inline `style=` · `#hex` colours · `var(--)` refs), comment-stripped and string-aware; framework allowlist (`Sources/WebUIDesignSystemCore/**`) reported-not-ratcheted; committed baseline `designer/markup-debt.json` + `--fail-on-increase`; the directory walker is recursive (the class-inventory scan stays flat by contract); `MarkupDebtTests` (five metrics, allowlist, grown-fixture trips) + `TokenDebtTests` (the colour/var/style axis) |
| *(next)* | `designer/probes/g-styling.mjs` — the rendered-gap probe (a scratch package OUTSIDE the repo, path-dep on the clone, renders `VStack(spacing: 7)` and asserts the inline gap + in-scale byte identity) plus the audit numbers on the demo tree + the committed-ratchet green run + a grown-fixture trip |

## the measurements (evidence over claims)

- **content pin**: `node designer/dx-content-pin.mjs --serve` → clean, all five surfaces byte-identical (smoke 27075 · blocks-index 4090 · block-1 9355 · blocks-standalone 4090 · showcase 167887). the spacing fix moved **no** served byte — every stack on the pinned pages is in-scale; no re-pin needed.
- **the demo tree** (`Sources/WebUIExample`), via `lint --debt-sources Sources/WebUIExample`:
  - `main.swift`: tags=26 class=11 style=0 colors=0 var=17
  - `DemoTheme.swift`: tags=0 class=0 style=0 colors=5 var=0
  - totals: **tags=26 class=11 style=0 colors=5 var=17**
- **the framework** (`Sources`, recursive; DS core allowlisted): totals **tags=1811 class=842 style=28 colors=35 var=117**; allowlisted (WebUIDesignSystemCore) 9 files: tags=1427 class=702 style=16 colors=2 var=1. the repo's own ratchet with `--fail-on-increase` is green (exit 0).

## done-when, as stated

- `VStack(spacing: 7)` renders a real gap (fixture + compiled probe prove `style="gap:7px;"`) and in-scale values are byte-unchanged (fixture pins `spacing-8` output == pre-G1 bytes; pin clean) ✓
- the five typed gaps exist, token-typed where a scale exists (flex-basis on `SpaceToken`) ✓
- the audit prints the five metrics on a planted fixture and the demo tree's own counts, and a grown fixture trips `--fail-on-increase` ✓ (unit + CLI + probe)
- counts reported as measured, never sold as a shrink ✓

## assumptions

1. **the demo tree's counts are real, not 0/0/0** — `Sources/WebUIExample/main.swift` carries 26 tags / 11 class literals / 17 `var(--)` refs (its live-region demo markup, inherited from the LIVE_DX demo). the plan's §4.1 "0/0/0 on the demo tree" line was aspirational; the honest number is reported and now ratcheted by the committed baseline.
2. **the audit targets the repo's `Sources/` tree as its committed baseline scope**, with `Tests/` out of scope (test fixtures are appendix-E-named false positives; the demo tree and any consumer tree scan cleanly).
3. **the rendered-gap probe builds a scratch package OUTSIDE the repo** (`~/fleet/macro-dx/g-styling-probe/`, the lane-S spike pattern) — `Sources/WebUIExample` is forbidden to lane G, so the probe proves the gap at the compiled level against the clone itself, never against a forbidden file.
4. **the out-of-tree path dependency works** in this SwiftPM (6.4): the scratch probe's `.package(path:)` on the lane-g clone resolves and builds (9 s cold, cached after); no sandbox flag needed.
5. **G2's `flex: 0 0 N` consumer sites migrate through `flexBasis`** (the brief's named gap) or the existing `.flex(String)` — the typed surface is what G5 (lane C) composes against.
6. the class-lint/capability behavior of `lint` is byte-unchanged when the new debt flags are absent (the plugin's own `lint` invocation is untouched).

## handoffs

- to **C** (consumer migration, G5): G1 + G2 are landed and byte-safe — off-scale `gap` values now migrate to `VStack(spacing:)`/`HStack(spacing:)` and render real gaps; `justify-content`/`flex-basis`(SpaceToken)/`align-self`/`position`/`z-index` named modifiers exist. the audit reports consumer-side counts via `lint --debt-sources <app>`.
- to **orchestrator**: the acceptance's step 12 (`LayoutSpacing|TokenDebt` + `g-styling.mjs` + pin) and step 13 (five metrics reproduce + grown fixture trips) run green on this branch head. `designer/markup-debt.json` is the G6 ratchet baseline (warn-only at W2 per §10.7).
- reminder from the brief: `WebUIDesignSystemCore` emission is allowlisted — a consumer reports its OWN number; the framework's DS-core counts are reported, not ratcheted.
