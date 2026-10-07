# lane G — W2: the ratchet re-baseline (MACRO_DX), record

_branch: `task/g-styling` · base `origin/dev-macro` merged at `a4ddd52` (i1 = `869c00a` + `b747e97` + `a4ddd52`) · work in the lane-g clone only._

## the drift, quantified per file (baseline → merged head, non-allowlisted only)

the audit (`WebUIContinuumTool lint --sources Sources/WebUIExample --debt-sources Sources
--baseline designer/markup-debt.json --fail-on-increase`) at the merged head reported **2 increases**
against the W1-committed baseline. a programmatic diff of the full per-file scan against the
committed baseline confirms **exactly these two files changed** — no other non-allowlisted file
moved, no file disappeared:

| file | baseline | merged head | delta |
|---|---|---|---|
| `Sources/WebUIExample/main.swift` | tags=26 class=11 | tags=28 class=11 | **tags +2** (class/style/colors/var unchanged) |
| `Sources/WebUIContinuumTool/ShadowCheck.swift` | absent (all-zero at W1) | tags=0 class=1 style=0 colors=0 var=0 | **new entry: class 0 → 1** |

head totals (ratcheted scope): tags=543 class=217 style=13 colors=35 var=117.

## the causes

### 1. `main.swift` tags 26 → 28 — lane D's macro twin, the expected cause, deliberate ✓

`git log 6d106e8..HEAD -- Sources/WebUIExample/main.swift` → exactly one commit:
`3ec4665 feat(demo): the macro twin beside the hand-written live-data controls (MACRO_DX feature E)`
— lane D added `@LiveRegions` / `@LiveRegion` / `@RegionState` / `@LiveState` markup
(`MacroDemoRegions`, `g-mreg-*` regions) BESIDE the untouched hand-written control group, *after*
lane G committed the baseline. the +2 tags are the two new rendered-region markup sites the twin
introduces. **this is a deliberate, reviewed increase — the ratchet did its job by catching it.**

### 2. `ShadowCheck.swift` class 0 → 1 — a MEASUREMENT ARTIFACT, not markup growth (finding, NOT re-pinned as growth)

`git log 6d106e8..HEAD -- Sources/WebUIContinuumTool/ShadowCheck.swift` → exactly one commit:
`76704cc refactor(markup): WebUIComponents through the Tag helper` (lane R). lane R's collateral
change added the `tagEmissionTokens(in:)` scan leg to the class-inventory scanner. that function's
regex literal at line 218,
`let stringLit = /"((?:[^"\\]|\\.)*)"/`,
contains a **bare `"` inside the character class** (byte 26 of the line, preceded by `^`, not by a
backslash — Swift regex syntax allows an unescaped `"` in a character class). the audit's
comment-stripper (`MarkupDebt.swift`, `strippingComments`) is a documented text scanner whose
string-literal tracking ("single-line strings only", no regex-literal awareness) turns ON at that
bare `"` at end-of-line 218 and never closes it, so the following `///` doc-comment lines 222–226
are swallowed as "string content" instead of stripped. the doc comment's prose `` `class="…"` `` on
line 224 is then counted by the `/class\s*=\\?"/` pattern → **phantom class=1**.

**evidence this is an artifact, not growth:**
- `git show 76704cc^:Sources/WebUIContinuumTool/ShadowCheck.swift` scanned with the exact
  `MarkupDebt` logic → **class count 0**. after 76704cc → **1**, and the one match is the doc-comment
  line 224 (byte-exact trace: string-open at line 218, no close until line 223, line 224 counted).
- ShadowCheck.swift emits no `class=` attribute at all — it is the *inventory scanner*, not markup.

**conclusion: the true class-literal count of ShadowCheck.swift is 0.** the ratchet entry is pinned
at the *measured* value (1) so the ratchet can run green on the merged head; the artifact is owned
and will drop back to 0 the moment the stripper learns regex literals (or lane R escapes the
character-class quote). **handed off** — see handoffs. this could not be fixed here: the fix lives
in `Sources/**` (the stripper), which this lane is forbidden from touching by brief.

## the re-pin (`designer/markup-debt.json`)

- `main.swift`: `rawTags` 26 → 28. deliberate, reviewed, named above.
- `ShadowCheck.swift`: added as a new entry at the measured value (class=1), the artifact named
  here — **never swallowed silently**.
- everything else untouched; baseline version stays 1.

## the ratchet, after the re-pin

```
.build/out/Products/Debug/WebUIContinuumTool lint --sources Sources/WebUIExample \
  --debt-sources Sources --baseline designer/markup-debt.json --fail-on-increase
```
→ `baseline: 39 file(s) committed (allowlist: Sources/WebUIDesignSystemCore) — increases: 0`
→ **exit 0** (was exit 1 on the merged head before the re-pin).

## gates

- `swift build` ✓ (step 0)
- ratchet with `--fail-on-increase` **exit 0** ✓
- `swift test --filter "LayoutSpacing|TokenDebt|MarkupDebt"` → see below (run at close)
- `node designer/probes/g-styling.mjs` → see below (run at close)

## assumptions

1. **the other-file increase is a scanner artifact, and it is pinned at the measured value only**
   to keep the ratchet green — the baseline records what the tool measures at the merged head, and
   the note names the cause. no real markup was invented; no finding was swallowed.
2. **the stripper's regex-literal blindness is a documented limit** (`MarkupDebt.swift`:
   "single-line strings only"), so the artifact is attributable, not astonishing.
3. **lane D's twin is the whole story for main.swift** — `git log` confirms exactly one commit
   touched it since W1.

## handoffs

- to **R / tool owner** (or a follow-up G slice): the `strippingComments` scan in
  `Sources/WebUIContinuumTool/MarkupDebt.swift` does not understand Swift regex literals
  (`/…/`). lane R's `tagEmissionTokens` regex `/"((?:[^"\\]|\\.)*)"/` has a bare `"` in its
  character class, which opens the string tracker and lets the following `///` doc comment be
  counted as a `class=` literal. once the stripper skips regex literals (or the quote is
  escaped), the ShadowCheck.swift entry drops to 0 and a future re-pin removes it.
- to **orchestrator**: the acceptance gate's step 12 ratchet now exits 0 — the recorded i1
  pending flips to a pass with no gate edit. `designer/markup-debt.json` remains warn-only;
  `--fail-on-increase` as a CI gate is the owner's call (§10.7), not wired here.
