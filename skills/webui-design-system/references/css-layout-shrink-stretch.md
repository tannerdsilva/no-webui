# CSS layout gotchas: shrink-to-content, stretch, and full-height

The single most common class of bug when composing a no-webui app (a shell,
a chat surface, a dashboard) is **content collapsing to its intrinsic size**
inside a flex/`VStack(alignment: .leading)` parent, instead of filling it.
The framework faithfully mirrors SwiftUI, so `VStack(alignment: .leading)`
emits `.vstack { align-items: flex-start }` and `HStack(alignment: .top)`
emits `align-items: flex-start` — children **shrink-wrap**. Every fix below is
the same idea applied to a different component.

## The shrink-to-content family (add `align-self: stretch` when it bites)

- **Block components** (`.card`, `.alert`, `.input`, `.table`, `.progress`,
  `section`) collapse to their content width in a flex column. Fix:
  `align-self: stretch` on the block. (Also applies to `.showcase-header`.)
  This is test-pinned; do not change the `.vstack` mapping, only the block.
- **`.grid`** — `Grid` emits `<div class="grid">` with no width, so a flex-column
  child collapses (a single `autoFit` card rendered 220px wide). `.grid` now
  carries `align-self: stretch`.
- **`.list` (WebUIListView)** — collapses to content width; rows render as a
  narrow clipped column with a gap to the right (measured 139px in a 280px
  panel). `.list` now carries `align-self: stretch; min-width: 0`.
- **Host pages** placed inside `VStack(alignment:.leading)` — `.stretch()` the
  page content or the whole sub-page collapses to ~220–330px with dead space
  right (fix in arc-agent `AppShell` non-fills branch).

**Diagnose by measuring, not eyeballing**: `list.getBoundingClientRect().width`
vs the panel-body width (a screenshot of a shrink-wrapped list reads as
"items clipped / misaligned").

## Centering content in a flex-start parent: `.stretch()` the row FIRST

Inside `VStack(alignment:.leading)` (align-items: flex-start) a bar/header row
*shrink-wraps*, so a `Spacer` on each side of a centered group has zero room
and the group stays pinned left. Give the row `align-self: stretch`
(`.stretch()`) so it fills the width, THEN the leading/trailing `Spacer`s
center the inner content. Verified on the chat top-bar pill: without
`.stretch()` the group's left edge sat at ~94px (near-left) regardless of the
spacers; with it, the pill centered in the content column. This is the fix
for "this control should be in the middle, not hugging the left."

## `.composer` / form rows: width AND height

- **Width**: `.composer` is a flex-column with `max-width`; a `max-width`
  alone still shrink-wraps to its content (measured ~217px, textarea ~103px)
  inside a 600px+ thread column, rendering as a narrow left-aligned strip
  (user: "not autosizing… width is not very wide"). Fix:
  `align-self: stretch; max-width: 100%; min-width: 0`.
- **Height**: `.composer__textarea` uses `field-sizing: content` (Chrome 123+,
  no JS) with `max-height: 6rem` so multi-line input grows instead of
  scrolling; give `.composer` `min-width: 0` so it can shrink with the
  centre column on narrow screens.

## `.list--desc dd` long-value wrapping

The two-column `max-content 1fr` grid blows out when a value is one
unbreakable token (long model ids, IPv6 `http://[…]/v1` base URLs): the
`1fr` track's min-content forces overflow and labels collide with values.
Base rule has `min-width: 0; overflow-wrap: anywhere` on `dd`. Verify with
computed `gridTemplateColumns` + `overflowWrap`, not a low-res screenshot (a
wrapped value reads as "jumbled" when it's actually correct).

## Agent-shell side panels: collapse on narrow + fill full height

- **Collapse**: fixed-width `.panel--leading`/`.panel--trailing` overlay the
  thread on small viewports. `@media (max-width:48rem){ .panel--trailing{
  display:none } }` and `40rem` for `.panel--leading`. Plus `.composer{
  min-width:0 }` so the composer shrinks with the centre column (a flex item
  with `max-width` alone clamps at its content min → horizontal overflow).
  `document.scrollWidth > innerWidth` is the deterministic overflow signal.
- **Full height** (two symptoms, same family):
  1. Content top-anchored in a tall body ("the panel isn't full height") —
     make `.panel__body { display:flex; flex-direction:column }` AND
     `.fill()` the panel's content (`WebUIListView`/`WebUITree` and their
     content `VStack`), so the body's content region stretches to the full
     panel height instead of leaving a huge empty gap under the rows.
  2. A panel that measures *full height* in the DOM (`getBoundingClientRect()`
     returns the bottom) but *looks* short because its `--color-bg-raised`
     fill is barely distinguishable from the page bg — don't trust the DOM
     height alone; verify the visible raised fill and that content uses it.
- **`.tree__label`** needs `min-width:0; overflow:hidden;
  text-overflow:ellipsis; white-space:nowrap` so long real filenames clip
  instead of blowing the pane.

## Interactive rows: `pointer-events` (row-click targeting)

- `.sidebar__item > *, .list__item > *, .segmented__item > * { pointer-events:
  none }` and `.tree--interactive .tree__row > * { pointer-events: none }` so
  clicks resolve to the row (whose id becomes `event.data.targetId`).
- **Consequence for test targeting**: a text-locator targets the span,
  which is `pointer-events:none`, so the row "intercepts" and the locator
  retries until it times out. Click the **row element** (`#<base>-node-<id>`)
  directly to drive tree/list toggles.
- **`WebUITree` node ids are used directly as DOM row ids**
  (`<base>-node-<id>`), so they must be path-unique and `-`/`/`-safe. For a
  real on-disk tree use path-relative ids (e.g. `Sources/Agent`) and have the
  handler strip the `<base>-node-` prefix to recover the id (see arc-agent
  `WorkspaceTreeBuilder`).
