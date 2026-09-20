# Pitfalls & debugging (CSS cascade, Swift, tooling)

Deep gotchas that bite when editing no-webui. The layout ones (shrink-to-content,
stretch, full-height, collapse) are in `references/css-layout-shrink-stretch.md`.

## CSS cascade / selector pitfalls

- **Dark-mode component overrides can lose the cascade silently.**
  `design-system.css` is ~8k lines; base rules for late-added components
  (`.button--success` ~6.7k, `.button--warning` ~7.4k) sit AFTER the early
  `@media (prefers-color-scheme: dark)` component block (~6.2k). An
  equal-specificity dark override is beaten by source order. Use two-class
  selectors (`.button.button--success`) and verify with a **computed-style
  re-measure**, not just the token audit.
- **Missing leading dot on a BEM modifier matches nothing.** `tbody tr--selected`
  is a *type selector* (custom element `<tr--selected>`), not a class —
  build passes, the state never styles. When a rule has no visual effect,
  check the computed style on the live element, not the CSS text.
- **Chained `.class()` on a tag that already has `class` is SKIPPED** —
  `injectAttributes` keeps the first occurrence, so `Div(class:"swatch"){…}
  .class("swatch-primary")` emits only `class="swatch"`. Pass one combined
  class string.
- **Reset/base `:not()` chains out-specify component classes** — nine `:not(…)=`
  (0,9,1) beats `.input` (0,1,0). Exclude the component classes from the base
  rule (`:not(.input)`, `:not(.select)`, `:not(.search-field__input)`) and
  verify computed styles on RAW and classed controls after any reset edit.
- **`.progress` is flat markup** `<div class="progress"><div
  class="progress__bar" style="width:NN%">` — the bar IS the fill. Make
  `.progress` a relative block with per-size height; an absolutely-positioned
  `__bar` collapses to 0 height. Label clipping: `%` label sits in the 8px
  track — reserve a lane (`margin-top`) and absolutely place the label.
  Fill centering: the base rule is `flex-direction: column`, so `align-items:
  center` centers the fill HORIZONTALLY — use `flex-direction: row`.
- **`.zstack` needs `> * { grid-area: 1 / 1; }`** to overlap children (the
  framework emits `display:grid; place-items:center`, which otherwise stacks
  children in separate rows).
- **Dark mode must remap the primary tint scale (50–400) and
  `--color-primary-soft/-strong/-ring`** in the dark block; the alias
  definitions must be in the MAIN `:root` (before the dark block) so the dark
  remap wins by source order.
- **`WebUIInput`/`WebUIAvatar` emit wrapper markup** (`.input__label`,
  `.input-wrapper`, `.avatar__status`) — verify emitted classes against
  `Sources/WebUIDesignSystem/WebUIComponents.swift` before styling.
- **Runtime JS quote-bug class**: a sanitizer regex wrapped in single quotes
  broke the inlined script. "Unexpected token" + all demos dead ⇒ the embedded
  runtime didn't parse — `node --check` the extracted `<script>`.

## Swift / generated-HTML pitfalls

- **Swift labeled-argument order = declaration order.** Long inits fail with
  "argument X must precede argument Y" if the call site is out of order.
- **No nested string literals in ternaries inside interpolation** —
  `"<tr\(cond ? "" : " class=\"…\"")>"` breaks the parser (hit in
  `WebUIShell`); compute the fragment into a `let` first.
- **`Optional` has no `.hasValue`** — use `opt != nil`.
- **Component `render()` emits LITERAL `\(…)`/`\"` when the source has doubled
  backslashes.** `write_file`/`patch` do NOT double backslashes, so the doubling
  is authored. Symptom: the page shows raw `\(htmlEscape(item.label))` / `\"`.
  Guard: prefer multiline `"""` strings (no `"` escaping), or verify the served
  page has zero `htmlEscape` fragments.
- **`validateTagBalance` (test helper) miscounts self-closing SVG tags** — teach
  it to skip `/>`.
- **Swift 6: a raw TAB byte (0x09) in a string literal is a parse error** —
  generators must use `\t` escapes. Byte-scan string literals for 0x09 if a
  tool edit suddenly fails to parse.
- **A consumer's config struct hides the app config behind a field** — in
  arc-agent `WebUIService.Configuration` the `ArcConfig` is `config.arcConfig`,
  not `.model`/`.provider` directly (compile error writing
  `config.model.provider`).

## SwiftPM / server pitfalls

- **`swift build --target X` does not re-link executables** — after changing
  an executable target, use a full `swift build` and restart the server (or a
  running server keeps serving the old page).
- **Smoke-gate page assertions go stale when the served page changes** —
  update the assertions to match what the page emits (don't fix the page to
  match the test).
- **Never start a static server** (`python3 -m http.server`) — open the
  preview from disk directly.
- **A rendered artifact showing something the source lacks = stale artifact** —
  diff source vs artifact before touching code; regenerate the showcase, don't
  hand-edit.
- **Smoke gate vs running demo server (false PASS)** — `serve` and the gates
  share :9123 and the `.build` lock; never run a gate while `serve` is up.
- **`exec <bin> &` is not valid for backgrounding** — use plain `<bin> &` +
  `trap … INT TERM EXIT`. New `designer/*.sh` scripts land without the execute
  bit — `chmod +x`.
- **AGENTS.md is a PROTECTED instruction file** — a `patch`/write is blocked by
  an approval prompt that times out silently; don't retry via terminal.
