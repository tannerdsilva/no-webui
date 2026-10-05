# lane G — W1 record (demos + gates + acceptance, the i0 half)

_branch: `task/g-gates` (clone `/tmp/continuum-fleet/lane-b`) · base `726f123` (origin/dev, the CONTINUUM landing)._

## what landed (W1, i0-dependent half only)

| commit | content |
|---|---|
| `a60c421` | step-0 bootstrap — empty commit + push smoke |
| `65e5a1a` | **merge `origin/dev-subst`** — brings the i0 freeze in (see §assumptions — the lane re-cut at 726f123 predates i0) |
| `ec641e0` | `Sources/WebUIExample/main.swift` — DX-12 adoption + the three W1 outcome controls |
| `4aca1b3` | `designer/probes/g-seam.mjs` — raw-WS seam probe (green + hostile) |

## the demo (`Sources/WebUIExample/main.swift`)

- deleted the hand-roll: `withValueBody` (`:93–96`) and the `RenderContext` hand-wrap (`:40–41`);
  the page build now runs inside `RenderContext.withCurrent(router:)` — the demo host no longer
  re-implements what the framework hosts (step 9 of appendix C audits this).
- **(1) SWAP** — `g-swap` (served); its handler renders a NEW control `g-swap-stage2` *inside* the
  handler body via `control(_:handler:)`. because dispatch runs inside the seam, the nested control
  self-registers and a later event reaches it (the pre-i0 state leaves it dead). every call site
  annotates the closure's return type (`O` inference, rev4/A2).
- **(2) ViewOutcome** — `g-outcome`; the replaceable ROOT carries `id="g-outcome"` beside
  `data-component-id="g-outcome"` (rev4/a2) so the update fragment id is in the served markup id set.
- **(3) RegionInvalidations** — `g-region-nudge` → `RegionInvalidations(["g-region-a"])`. compiles and
  renders; at i0 the `invalidate` provider is a no-op so resolve carries no fragments. the registry
  push is asserted end-to-end at i1 (needs lane R's `regions:`).

## gates green

- `swift build` → Build complete (12 s incremental / 34 s scratch)
- `.build/debug/WebUIExample --port 9370` boots; served markup carries all three g-* controls;
  `g-swap-stage2` absent until a handler renders it
- `node designer/probes/g-seam.mjs` → **12/12 PASS (green)**
- `node designer/probes/g-seam.mjs --binary <hostile> --port 9371 --mode hostile` → **12/12 PASS**,
  the load-bearing assert: `g-swap-stage2 click -> ZERO frames` (frames-only; the debug-line half
  lives in-process via `router.observers`, i0-owned `SubstitutionTests`)
- `node designer/gates/dx12-16-acceptance.mjs --hostile-binary <hostile>` → **26 passed, 0 failed,
  8 pending (i1/i2)** — DX-12/14 + no-layer-audit W1 slice live; DX-13/15a/16 + the ladder stubbed
  behind `pending: lane R/T symbols` guards.

## assumptions (the ones that changed the plan)

1. **the lanes were re-cut at 726f123 BEFORE i0 landed on `dev-subst`.** every W1 lane branch
   (`task/r-livedata`, `task/t-themes`, `task/g-gates`…) sits at 726f123 — none contains i0. W1's
   work is explicitly "the i0-dependent half" and its gates (`swift build`, the probes) are
   impossible without i0's symbols. the brief's own W2 line sanctions `git merge origin/dev-subst`
   as the lane mechanism for picking up orchestrator work, and i0 is file-disjoint from everything
   lane G owns — so I merged `origin/dev-subst` (i0) ONCE at the top of the branch. this is NOT
   merging R/T (their branches are still at 726f123 and untouched); i1 still merges R → T → G.
   flag for the orchestrator: **check whether R and T have been given the same i0-merge line.**
2. empty-update suppression: `WebUIServer:662` (`guard !updates.isEmpty else { return }`) means an
   empty `EventOutcome` (e.g. `RegionInvalidations` at i0, `NoOutcome`) sends NO frame — the W1
   probe asserts silence accordingly.
3. the hostile build's first SWAP click still returns a frame (the page-render path registers
   `g-swap`; only the dispatch seam is reverted via c8487c7), so the hostile verdict is scoped to
   the *handler-rendered* control — matching `handlerIntroducedControlIsDeadWithoutTheSeam`.

## done-when (W1)

- seam green + both outcome probes green on lane ports ✓ (incl. frames-only hostile)
- reported verbatim in the §3.8 report.
