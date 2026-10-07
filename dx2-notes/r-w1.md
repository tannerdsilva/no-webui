# r-w1 — lane R (MACRO_DX G4): the framework's own markup, centralized

_branch `task/r-markup` · base `origin/dev-macro` @ `3230deb` · lane ports 9440–9449_
_clone: `~/fleet/macro-dx/lane-r`_

## what landed (7 commits, all pushed; full suite + pin green after each)

| sha | commit | surface |
|---|---|---|
| `4627796` | test | byte-exact render fixtures for all five files (captured at base, asserted after each commit) |
| `583170b` + `419713d` | feat | the `Tag` emission helper (`Sources/WebUIDesignSystemCore/Markup.swift`) |
| `95ec314` | refactor | WebUIExtrasNavOverlay |
| `6ac371d` | refactor | WebUIExtrasData |
| `76704cc` | refactor | WebUIComponents (+ the shadow-claim leg, below) |
| `b659b56` | refactor | WebUIExtrasCommsState |
| `f45239e` | refactor | WebUIExtrasForm |

## the helper

`Tag` (package enum, `Markup.swift`): `flag` / `attr` / `escAttr` / `classes` /
`begin` / `end` / `element` / `void` / `selfClose`. leading-space attribute
grammar ⇒ concatenation is byte-exact; escaping decisions stay at the call
site exactly as the old strings made them. `classes` uses a smart single
space (inserted only when the next segment does not already lead with one),
which reproduces every hand-written spelling — leading-space rawValues AND
literal-space templates.

## the warts (byte-pinned, preserved explicitly)

the base renderers had four hidden-spacing warts that a uniform join would
have normalised away; each is preserved with a comment and pinned by the
fixtures:
1. `gantt` bar empty state — trailing space (`class="gantt__bar "`),
2. `WebUIInput` normal state — trailing space (`class="input "`),
3. `WebUISkeleton` custom variant — trailing space (`class="skeleton "`),
4. `WebUIBadgeStatus` — DOUBLE space (template space + leading-space rawValue).
a regex sweep of every interpolated `class="…"` in the base files confirmed
this list is complete.

## gates (per push): `swift build` ✓ · `swift test` ✓ · `dx-content-pin --serve` byte-identical ✓

see the report for the numbers.

## class tokens: unchanged (d-t)

- 627 literal `class="…"` spellings in the five files at base → **0** (all
  assembly now routes through `Tag`; the helper is the only place those files
  assemble tags or attribute strings — greps on the five files confirm zero
  hand-wired `"<tag` / `class="` / ` id="` in any render body; the only
  remaining `<br>` literals are content substitutions in chat bubbles).
- every one of the 614 class tokens `Tag.classes` now emits **exists in the
  base sources** (containment check, zero absent) — nothing invented, nothing
  renamed; and the byte-identical fixtures + pin prove nothing was dropped.
- the win is scattering, never a shrink.

## the fixture battery (the lane's second byte gate)

`Tests/WebUITests/ExtrasRenderTests.swift` renders ~140 instances covering
every public component in the five files (pinned surfaces exercise only ~40
of ~120) and asserts byte-identity against `Tests/WebUITests/Fixtures/R-<file>.json`
captured at base. the one-time capture test ran at base and was removed;
re-capture = regenerate at a measured tree, deliberately.

## cross-lane notes (READ AT i1 — adjudicate ownership)

1. **`Sources/WebUIContinuumTool/ShadowCheck.swift`** gained ONE additive leg
   (`tagEmissionTokens`, wired into `dsComponentClaims`) so the anti-shadow
   DS ownership claim survives G4 — the DS no longer writes escaped
   `class="…"` attribute spells, and that leg was reading exactly that form
   (`ShadowCheckTests.dsScanClaims` was red without it). no other part of the
   tool or the inventory pin (MainProgram) was touched; no served byte moves
   (the engine manifest is unchanged — verified by the pin). if lane G's W1
   edits `WebUIContinuumTool/**`, this 20-line leg may conflict — it is
   feature-G4 collateral, safe to absorb.
2. `@HotClass` was considered and REJECTED for re-claiming classes: it would
   enlarge the generated `ContinuumClassInventory` (tests pin 2 components /
   7 classes) and the served engine manifest — moving pinned bytes.
3. the five files still import `WebUICore` and call `controlAttributes`,
   `htmlEscape`, `sanitizeURL`, `webuiFixedPoint`/`webuiZeroPad` unchanged —
   no primitive was duplicated or moved.

## assumptions

1. `HTMLBuffer`/`Attributes` live in `Sources/WebUISharedCore` (the brief's
   `Sources/WebUICore/HTMLBuffer.swift` path did not exist); `WebUICore`
   re-exports them, so `WebUIDesignSystemCore` reaches them without a new
   manifest dependency. no `Package.swift` change.
2. commit-2 was split into two pushed commits (helper + a doc-comment fix
   caught by the inventory lint) — same message, both pre-push-amend safe,
   never force-pushed.
3. the pin's shadow suite (`dx12-16-acceptance.mjs`) is orchestrator-owned;
   this lane's in-repo gates were `swift build` / `swift test` / the content
   pin, per the brief.
