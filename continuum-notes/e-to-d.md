# lane E → lane D handoff (wave 1)

## op semantics for the consumer surface

- `FragmentUpdate` gained `.remove(id:)`, `.attr(id:name:value:)`, `.move(id:before:)`
  (all in `Sources/WebUICore/WebSocketProtocol.swift`). your server-side
  adapters can emit these directly; the engine applies them per the §1.3.2
  table (see `continuum-notes/e-docs.md`).
- `attr` is the cheap row-state channel: allowlisted names are `class`, `aria-*`,
  `data-*` (wave-1 seed). use `data-*` for transient UI state (e.g.
  `tr--selected`); `class` for token-driven styling. any other name skips +
  warns once.
- `move` reorders within the parent — do not emit it with markup.

## echo contract (first lease) — available to `.lease` authors in a later wave

any element carrying `data-webui-echo="<id>"` reflects its value into `#<id>`'s
text in the same turn, engine-locally, no ws. a component-wired source still
round-trips at the debounce edge (one frame). the authoritative `text`/`replace`
always wins. see `continuum-notes/e-docs.md` §t1.4 for the full contract.

---

## wave 3 — the `.lease(.viewport)` DOM contract (t3.3, the engine half)

the engine's windowing support consumes the hint through a **served attribute**:
D's `Viewport` component renders `data-webui-lease="viewport"` on the windowed
list root, and the engine's `createWindowManager` (webui-engine.js) takes over
that container at boot. this is the engine's consumption path for
`.lease(.viewport)` (the modifier itself carries no bytes; the attribute is the
wire). your `Viewport` Swift component emits:

```html
<div data-webui-lease="viewport" id="...">   <!-- the list root -->
  <div class="row" id="row-0">…</div>        <!-- rows: direct children -->
  <div class="row" id="row-1">…</div>
  …
</div>
```

### required structure (v1)

| piece | requirement |
|---|---|
| container | `data-webui-lease="viewport"`; CSS `position: relative`; in normal document flow (page tall → document scrolls) OR a fixed-height self-scrolling region (`overflow-y: auto/scroll` — auto-detected as self-scroll mode) |
| rows | **direct element children** of the container, **uniform height** (the engine measures the first row's `offsetHeight`), **stable ids** (the exact ids your server ops target: `text`/`attr`/`remove`/`append`) |
| `data-webui-row-height` | optional `<px>`; used when the first-row measurement is unreliable (hidden-at-init container) |
| `data-webui-overscan` | optional row count pasted above/below the viewport; **default = one viewport's worth of rows each side** (the 2× rule) |
| spacer | the engine injects ONE child `<div data-webui-window-spacer>` that holds the full list height; your renderer never emits it |

### engine behaviors your Viewport can rely on

- at boot (and after every whole-container `replace`) the engine detaches the
  row pool, keeps only the viewport ± overscan rows attached (absolutely
  positioned at `i × rowHeight`), and maintains total height via the spacer, so
  the page keeps its full scrollbar.
- scroll re-windowing is engine-local: only the **entering/leaving window rows**
  are inserted/removed per scroll (the d3 mutation-census contract), and the
  engine's own scroll listener replaces the d0 page-side observer.
- whole-container `replace` re-windows in place with scroll anchoring: the
  browser keeps the document/container scroll position and the window reforms at
  the same index band — no visual jump.

### v1 boundaries (recorded, extend later)

- row-level fragment ops (`append`/`remove`/`text`/`attr`/`move` on a single
  row) currently apply to **attached** rows only; a detached row's op waits
  until it re-enters the window. for head-inserts / large mutated slices,
  emit a whole-container `replace` (the engine re-inits + anchors) until the
  junction extends a row-level pool path.
- uniform row height is a hard requirement of the absolute-position window;
  mixed-height rows need the later measurement pass.

the probe that gates this at i3 is `designer/probes/e-windowed.mjs` (scroll
p95 ≤ 20 ms at 10k + window-only census + memory flat over 60 s).
