# lane W — the close (MACRO_DX feature F): the macro chapter, the pins, the ladder re-measure

_branch `task/w-close` · cloned at `~/fleet/macro-dx/lane-w` · merged forward to `a4ddd52` (i1 +
the acceptance extensions) · no server ports._

## what landed (per file)

- `Documentation/SUBSTITUTION.md` — the macro chapter ("live data, macro-spelled": the four
  declarations, the explicit optionality + hand-path parity, the generated surface exactly as i0
  froze it — dual-role declarations, computed witnesses, the syntactic classification rule — the
  three retired footguns `source`/`nonisolated`/registry assembly, when the hand path is clearer,
  the measured net), plus the six per-shape outcome helpers documented as new public API with S's
  honest finding (the `O` annotation was already optional; the helpers remove residual ceremony and
  name each shape, they do not replace the protocol). the doc's old "a bare `{ _ in [] }` cannot
  infer it" bullet is corrected to the measured truth.
- `Documentation/STABILITY.md` + `Tests/WebUITests/APISurfaceTests.swift` — additive rows
  (`macroSurfacePins`, `outcomeHelperSurfacePins`) pinning the four macros and the six helpers as
  additive public surface (I5); `Documentation/API.md` — the same symbols in the file's existing
  form (helpers row in Event Handling, "live data, macro-spelled" under WebUIServer).
- `skills/webui-design-system/` — `references/live-data-declarations.md` (consumer-stated), the
  SKILL.md reference-index row + substitution bullet, and cross-links in
  `references/substitution.md` and `references/live-regions.md`.
- `designer/probes/m-ladder.sh` — seam 3 gains a macro column (per-spelling code-line counts,
  MARK-bounded, `index()`-matched so attribute parens are not eaten by the awk pattern engine).
- `dx2-notes/m-consumer-deletion-ladder.md` — an APPENDED section (the measured history is not
  rewritten): hand 89 → macro **72** code lines (−17, −19%), including what did NOT shrink.

## the ladder figure

the demo's live-data surface was **89 code lines** hand-written; the macro spelling measures
**72 code lines** at the merged head (hand span now reads 105 = 89 + the 16-line lane-D
`regionList` composition seam). what did NOT shrink: the `render()` bodies, the states' own
properties and mutators, the choice of mechanisms and ids, and the five controls' handler bodies
(the macros generate the declarations + the registry, not the handlers).

## escape-drift note (recorded per the steer)

the write tool doubled backslashes in two of my interpolation literals
(`APISurfaceTests.swift` PinStruct/PinActor render bodies, `SUBSTITUTION.md` example) — a silent
isolation breaker (the `\(value)` rendered as literal text). both collapsed to a single backslash;
a raw-bytes scan (`\\+(?=\()`) now passes on every file this lane wrote. the pre-existing
single-backslash literals in the test file were left untouched.
