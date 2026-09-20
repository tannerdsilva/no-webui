# Vision pass: WCAG contrast audit + guardrail lock-in

Method from the 2026-08 intense vision pass ("make it look as exquisite as
possible"). The sharp-geometry/serif redesign direction itself read as a
coherent aesthetic and was kept; the pass found 7 genuine WCAG AA failures
that screenshots alone would have under-reported. Everything here is
re-runnable and token-driven — no hardcoded colors.

## 1. Deterministic audit before touching anything

Extract the tokens and compute WCAG ratios for every fg/bg pair, light AND
dark, in one script. Far more reliable than eyeballing:

- Light scope: the main `:root { … }` block.
- Dark scope: the dark `@media (prefers-color-scheme: dark)` `:root` remap
  layered over the light tokens (tokens it doesn't redefine inherit).
- `resolve()` any `var(--x)` chains; parse `#hex`, `#hex3`, `rgb()/rgba()`.
  Literal colors in the pair list stay literals — the resolver is for
  tokens only (see the harness-artifact list below).

WCAG math:

```python
def luminance(rgb):
    r, g, b = (v / 255 for v in rgb)
    f = lambda v: v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)

def ratio(fg, bg):
    la, lb = luminance(fg), luminance(bg)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)   # AA body text needs >= 4.5
```

Audit every pair that matters: all solid button variants (fg on fill),
`a` + `.button--link` (on white AND page bg), badges (fg on their soft
fill), alerts (text on soft fill), body/muted/faint/placeholder text,
progress labels. **Both themes** — the dark remap inverts the treatment
(bright fills, dark ink) and is where most of the failures live.

### Translucent fills must be composited

Dark soft fills are `rgba(tint, 0.15)` over the card (`#101625`). Testing
the fg against `rgba(…,0)` (black) or against the raw tint both give false
results:

```python
bg = tuple(round(tint[i] * 0.15 + card[i] * 0.85) for i in range(3))
```

In a browser harness, "walk ancestors, composite alpha-on-alpha bottom-up"
(the naive first pass reports ~1.2 for soft badges that are really 5.7–8.5
once composited — a harness artifact, not a defect).

More browser-harness artifacts (2026-08-22 re-audit pass):

- In a `page.evaluate` audit, only `--token` names go through the
  computed-style resolver; raw literals (`#ffffff`, `rgba(...)`) must be
  parsed directly. Feeding a hex literal through the token resolver returns
  `''` → false `UNPARSED` / `1.0x FAIL` rows that look like real defects.
- Test solid-button labels against their **fill** token
  (`--color-on-primary-solid` on `--color-primary-solid`, `#fff` on
  `--color-danger-strong`, dark `--color-on-color` on the bright fills) —
  never against the page background. A pass that pairs the label against
  `--color-bg` reports "primary 1.06 FAIL" — an artifact, not a defect.
- `page.evaluate` cannot close over harness-side variables: pass anything
  the page-side function needs as an argument, or it throws
  `ReferenceError` (a `bgName` referenced but not passed).

## 2. Choosing fix values

Pick the lightest/darkest passing value to preserve the intended hierarchy
(faint must stay visibly lighter than muted):

- Light solid buttons: use the semantic `-strong` fill for white labels
  (`--color-success-strong` 5.02 vs `--color-success` 3.30; warning the
  same). White on `--color-danger` already passes.
- Text tokens: darken to the lightest passing shade. `#94a3b8` (2.4–2.6)
  → `#5f6f86` (4.8–5.1 on white/page-bg/inset); keep it visibly lighter
  than `--color-text-muted` (`#64748b`, 4.76).
- Dark solid buttons: bright fill + **dark ink** (`--color-on-color`),
  matching primary's inverted treatment — never white on a bright fill.
- Dark links: `--color-primary-400` (8.1 on raised) — light `primary-600`
  is too dim on the dark bg (3.5).
- Badge fills keep their tint; fix the fg token instead (dark
  `badge--primary`: `primary-800` on the dark tint = 1.81 → `primary-400`
  = 6.2).

## 3. Cascade pitfall (bit us once — verify computed style, not just tokens)

The early dark `@media` block sits BEFORE late base rules. First-pass
override:

```css
@media (prefers-color-scheme: dark) {
  .button--success { color: var(--color-on-color); }  /* specificity (0,1,0) */
}
/* later in file, same specificity wins the cascade: */
.button--success { background: var(--color-success); color: #fff; }
```

Result: token audit green, live computed style still `rgb(255,255,255)`,
buttons still illegible. Fix = two-class specificity:

```css
.button.button--danger,
.button.button--success,
.button.button--warning { color: var(--color-on-color); }
```

`.button--danger` (defined early, ~line 437) needed no bump; `.button--success`
(~6748) and `.button--warning` (~7423) did. General rule: for component
overrides inside the dark block, use two-class selectors and confirm with a
computed-style re-measure, not just the token audit.

## 4. Guardrail tests (make the tuning checkable)

The pass is not done when the CSS is fixed — it's done when the fix can't
silently regress. Add tests to `Tests/WebUITests/DeploymentIntegrityTests.swift`
that compute real WCAG ratios from the embedded CSS tokens:

```swift
func wcagLuminance(_ hex: String) -> Double { /* sRGB linearization */ }
func wcagRatio(_ a: String, _ b: String) -> Double { /* (hi+.05)/(lo+.05) */ }
func cssTokenValue(_ name: String, in css: String) -> String? {
    // first "--name:" occurrence, value up to ";" or newline
}

@Test("faint text and links meet WCAG AA on their surfaces (light + dark)")
func faintAndLinkContrast() {
    let css = WebUIAssets.css
    #expect(wcagRatio(cssTokenValue("color-text-faint", in: css) ?? "000000",
                      cssTokenValue("color-bg", in: css) ?? "ffffff") >= 4.5)
    let dark = css.range(of: "@media (prefers-color-scheme: dark)")
        .map { String(css[$0.lowerBound...]) } ?? css
    #expect(wcagRatio(cssTokenValue("color-text-faint", in: dark) ?? "000000",
                      cssTokenValue("color-bg-raised", in: dark) ?? "000000") >= 4.5)
}
```

For dark-theme assertions, slice the CSS at `@media (prefers-color-scheme: dark)`
and read tokens from that slice (the remap wins there). Include an
**override-presence** assertion (e.g. `dark.contains(".button.button--success")`)
so someone deleting the override fails loudly instead of regressing
silently.

## 5. Verification loop

1. `swift build` (full — re-links the executable; `--target` builds skip
   the link step, see SKILL.md pitfalls) → `designer/sync.sh --no-test`
   (regenerates `showcase.html` with the new embedded CSS).
2. Re-run the deterministic token audit → every pair ≥ 4.5 in both themes.
3. Live browser check: computed-style contrast on the rendered page
   (verifies the cascade actually applied), plus fresh light+dark
   screenshots for the eye.
4. All gates: `swift test` (includes the new guardrails) +
   `designer/smoke.sh` + `designer/fullstack-smoke.sh`.
5. Commit CSS + tests + regenerated showcase together.
