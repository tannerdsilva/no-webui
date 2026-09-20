# Interactive, server-re-rendered components in no-webui

Recipe for components whose region is **re-rendered by the server** in
response to a user event (sort, select, expand, filter). Verified against
`WebUITable` sort/select/expand (commit `ea2f554`, 2026-08-30). Complements
the SKILL.md "Interactive components" section — that one is the condensed
contract, this is the worked detail.

## The two surfaces, and which one proves interactivity

- **`showcase.html` is STATIC.** `ShowcasePage.render()` builds a local
  `EventRouter`, renders, and discards it. There is no `/ws` backend for the
  showcase. Anything "interactive" shown there is a *markup reference only*
  (it looks right, does not round-trip). Still vision-verify it both themes.
- **The live proof surface is the smoke page**
  (`Sources/WebUISmokeTest/main.swift`): a real NIO HTTP + `/ws` server +
  `SmokeState` + `EventRouter` handlers. Prove interactivity here, via
  `fullstack-smoke` (raw-WS node driver, spawns a FRESH server per run) or
  `serve` (manual play — note state accumulates across your WS probes on a
  long-lived server; a second select-all click may toggle *off*).

## The five load-bearing facts

1. **`replaceElement` CONSUMES the patched node.**
   `webui-runtime.js` does `replaceChild(fragment, el)` — the element you
   patch is destroyed and swapped. So any node re-rendered by the server
   must re-carry its routing anchor, and the anchor must live on a
   *persistent wrapper* that is NOT the patch target.
2. **Use the stable-ID modifier.** Plain `.onClick(perform:)` allocates an
   auto id (`c0`, `c1`, …) that only stays valid if the element is never
   patched. For re-rendered regions use the stable-ID variant
   (`Sources/WebUI/ModifiedView.swift`):

   ```swift
   .onClick(id: "interactive-table") { event in
       // mutate state, then return [] or [FragmentUpdate]
   }
   ```

   It registers the handler under a **caller-chosen** `ComponentID(id)` and
   emits `data-component-id="interactive-table" data-event="click"` — the
   exact same attribute the runtime's event delegation keys on, so routing
   works identically to the auto id, but it survives re-render.

3. **Single container handler, dispatch on `targetId`.** Put ONE
   `data-component-id` on the persistent wrapper (e.g. the `.table-wrap`
   `div`). Don't give every row/column its own handler. The runtime
   reports the clicked element's id as `event.data["targetId"]` (via
   `clickTargetData`), so give interactive targets stable ids and switch on
   the suffix:

   ```swift
   .onClick(id: "interactive-table") { event in
       let target = event.data["targetId"] ?? ""
       let p = "interactive-table-"
       guard target.hasPrefix(p) else { return [] }
       let s = state
       // MUTATE FIRST (see fact 5), then render the patch from post-state
       switch s.targetAction { … }
   }
   ```

   `pointer-events: none` on any glyph SVG (sort arrow, chevron) so the
   click resolves to the labeled control carrying the id, not the `<svg>`.

4. **Server is source of truth.** Click payloads carry NO form state — the
   runtime does not echo `checked` back. So selection/expansion/sort state
   MUST live server-side (`SmokeState` or equivalent) and be re-emitted by
   the render on every re-render: `tr--selected`, `tr--expanded`,
   `aria-sort`, `aria-checked` (including `mixed` for partial select-all),
   `aria-expanded`. The CSS state rules must also win the cascade over the
   stripe/hover rules (`.table tbody tr.tr--selected` raised specificity —
   see SKILL.md pitfalls). Verify the state visually with a **computed-style
   re-measure** on the live element, not just a WS-frame assertion.

5. **Mutate state BEFORE rendering the patch.** The handler runs with the
   state as it was at event time. If you render the patch from pre-mutation
   state, every update lags exactly one click (an off-by-one). The bug
   looked like "my sort/expand never applies." Pattern:

   ```swift
   let s = state                       // capture (or mutate a struct copy)
   s.apply(target)                      // MUTATE
   return [FragmentUpdate(id: "interactive-table", html: s.tableHTML())]
   ```

## Gate bookkeeping when you touch the smoke page

- **`Plugins/WebUISmokePlugin/WebUISmokePlugin.swift` pins the EXACT
  interactive count** (`interactiveCount == N`, asserted by `==`). Adding
  or removing a `data-component-id` on the smoke page REQUIRES updating
  that number or the `smoke` gate fails. It was `6` (counter×3,
  progress×2, echo input×1) and became `7` when the interactive table
  wrapper added its anchor.
- **`AGENTS.md`** has a pitfall note "smoke pins the interactive count" that
  spells out the expected count — keep it in sync with the plugin.
- **`fullstack-smoke`**'s count check is `>=N` (tolerant), so it won't block
  you; the strict `==` pin is the one that bites.

## Quick verification ladder for an interactive change

1. `swift build` (asset plugin re-embeds CSS; confirm a new/changed selector
   actually made it into `.build/.../Assets+Generated.swift` by `grep`).
2. `swift test` (new unit tests for the emitted markup/ids).
3. `swift package --disable-sandbox plugin fullstack-smoke` — raw-WS
   round-trips on a FRESH server; the strongest proof the server logic +
   stable-id routing work.
4. `swift package --disable-sandbox plugin smoke` — page signatures + the
   pinned interactive count + served bytes == source.
5. `node designer/browser-smoke.mjs` — real DOM invariants + screenshots.
6. Vision pass on the SMOKE PAGE in BOTH themes (it's the live surface): a
   fresh context with the color scheme set per theme, and read the computed
   `background-color` immediately before each full-page shot (a full-page shot
   right after switching the scheme can capture the stale theme).

## Known pitfalls that bit during this work (see SKILL.md "Pitfalls" for
the one-liners)

- Missing leading dot on a BEM modifier (`tr--selected` vs `.tr--selected`)
  = a type selector that silently matches nothing; build + tests pass, the
  state never styles. Check computed style on the live element.
- Chained `.class()` on a tag that already has a `class` attr is SKIPPED
  (`injectAttributes` keeps the first) — pass one combined class string.
- A reset/base rule with many `:not(…)` chains out-specifies component
  classes — exclude the component classes from the base rule and verify
  computed styles on raw AND classed controls.
- Swift labeled-arg order = declaration order; long design-system inits fail
  with "argument X must precede argument Y" — read the init first.
- No nested string literals inside a ternary inside an interpolation
  (`"<tr\(c.isEmpty ? "" : " class=…")>"` breaks the parser) — hoist the
  attribute fragment into a `let`.
- `validateTagBalance` (test helper) miscounts self-closing SVG tags
  (`<path/>`, `<polygon/>`) once a component emits inline SVG — teach the
  helper to skip `/>` terminators before blaming the component.
- Smoke-page shell (gutter, card padding/rhythm) is page-scoped in a
  `<style>` block injected via `WebUIDocument(head:)`, NOT in
  design-system.css — the `.smoke*` classes live there.
