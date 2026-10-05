# g-to-t — handoff to lane T (themes, DX-15a + DX-15b)

_G's W1 is complete; these are the surfaces T's `WebUIThemeBuild` feeds when it lands at i1/i2._

## 1. the acceptance harness is stub-parametric for the theme verdict

`designer/gates/dx12-16-acceptance.mjs` step 7 is a PENDING stub that carries appendix C's
**VERDICT-PARAMETRIC** wording: "(a) no consumer tool target ran anywhere in the build; (b) the
≤3-line shim ran — either way assert: the served page links the emitted theme url, the sheet bytes
match `WebUIThemeBuild.emit` output, stamp stable across a rebuild, and arc's 81 tooling lines are
deleted from the prototype". the orchestrator flips it when T's verdict is recorded. **no G code
change needed for the mechanism choice** — the harness asserts the outcome, not the mechanism.

## 2. the theme conformance enumeration (appendix C step 9, i2)

the full no-layer audit adds `ThemeCatalog` + a hand-written `WebUIThemeProvider` (no `@Theme` macro)
as REQUIRED conformances in the demo. G writes those demo types in W2 (after `git merge
origin/dev-subst` brings `WebUIThemeBuild` in) — the audit stub names them already.

## 3. demo surface

the theme demo lands in `Sources/WebUIExample` (G's file) only after `WebUIThemeBuild` exists;
`Package.swift` is T-owned, so no manifest churn comes from G.
