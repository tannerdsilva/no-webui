# r → orchestrator — lane R base correction (READ AT i1)

**status: lane R complete and pushed on `task/r-livedata`.**

## the base was pre-i0 — the lane self-corrected by fast-forward

at dispatch, `task/r-livedata` (and every other lane branch) was at **`726f123`**
= `origin/dev` — *pre-i0*. The i0 landing
(`b11c2d6`…`2f9c4c2`, DX-12 + DX-14) lives **only** on `origin/dev-subst`, on top
of that same `726f123`.

lane R's contract is unbuildable without i0: item 1 builds `LiveRegion`/`LiveState`
on `LiveSubscription`, and item 3 wires `OutcomeContext.invalidate` through the
**`dispatchOutcome(_:router:invalidate:)`** seam that i0 extracted — none of those
symbols exist at `726f123`.

**the lane did NOT re-cut and did NOT merge.** it fast-forwarded the branch onto
`origin/dev-subst` (`git merge --ff-only origin/dev-subst`), which:

- keeps `726f123` as the branch **base** (it is an ancestor → the report's
  `base sha: 726f123` stays true);
- creates **no merge commit** (i1's rule is no merge *commits*);
- makes i1 a clean fast-forward for R instead of a conflict.

**for i1:** `dev-subst` already contains i0, so `R → T → G` should fast-forward
or merge trivially. **the same pre-i0 base almost certainly affects lanes T and G**
(both need i0's `withCurrent`/`control(_:handler:)`); they should fast-forward onto
`origin/dev-subst` too, or the orchestrator should re-cut all three lane branches
off `dev-subst` before i1.

## owned surface (no forbidden writes)

lane R wrote only: `Sources/WebUIServer/{LiveRegions,LiveState,WebUIServer}.swift`,
`Tests/WebUITests/{LiveRegionsTests,ServerTestHarness,APISurfaceTests}.swift`.
`Sources/WebUICore/**`, `designer/assets/**`, `Package.swift`,
`SubstitutionTests.swift` untouched. engine net growth 0 (no engine bytes).