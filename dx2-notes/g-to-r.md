# g-to-r — handoff to lane R (live data, DX-13 + DX-16)

_G's W1 is complete; these are the seams R's `regions:` must satisfy when they land at i1._

## 1. the demo's RegionInvalidations control targets `g-region-a`

`Sources/WebUIExample/main.swift` ships a `RegionInvalidations` control (`g-region-nudge`) whose
handler returns `RegionInvalidations(["g-region-a"])`. at i0 the `invalidate` provider is a no-op
(frames asserted silent), so:

- at **i1**, once `regions:` is attached and a region named `g-region-a` exists in the registry, a
  click on `g-region-nudge` must drive the registry → exactly one region push (`g-region-a`).
- the acceptance harness stub asserts this (`dx12-16-acceptance.mjs`, step 3) — the orchestrator
  flips the PENDING once R's symbols land. **no new demo code is needed from G for that assert; the
  control is already in the served markup.**
- note d-x1/d-x2: `OutcomeContext.invalidate` is established by the dispatch seam; R's server wiring
  supplies the registry's closure at dispatch time. two-push ordering (d-k/A5) is R's to preserve.

## 2. the no-layer audit's positive enumeration grows at i2

the W1 slice of appendix C step 9 enumerates only the W1-required conformances. at i2 the full set
includes the four region drivers (closure default, custom `LiveRegion` struct, `LiveBox` state, custom
`LiveState` actor) — R's twins feed that enumeration. keep the banned-construct set as specified
(exact tokens; the demo today has none).

## 3. nothing else — G owns no `WebUIServer`/`LiveRegions`/`LiveState` file.
