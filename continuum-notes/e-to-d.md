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
