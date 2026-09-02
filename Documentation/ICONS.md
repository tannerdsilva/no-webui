# WebUIIcon — svg iconography

native svg iconography for the swiftui-for-web stack. icons are stroke-based,
server-rendered **inline `<svg>`** wrapped with `stroke="currentColor"`, so an
icon inherits the surrounding text color by default and recolors through the
existing `ColorToken` slots — no canvas, no client-side icon font, no sprite
sheet, no network fetch.

the design goal is a first-class design-system surface: a curated catalog of
real geometry (206 glyphs from Feather, MIT), a type-safe Swift API, and a
build-time toolset that keeps the generated catalog from ever drifting from the
manifest it came from.

## architecture

one canonical source of truth, one generation path:

```
designer/icons/icon-manifest.json        (authored: name, category, title, tags,
                                           viewBox, geometry per icon)
        │
        ▼  WebUIIconTool (CLI)          ┐
        │  generate                     │
        ▼                                │  WebUIIconPlugin (build tool plugin,
   IconLibrary.swift                    │  applied to the WebUI target) — runs
   (generated, under .build/)           │  `generate` on every `swift build`
        │                               ┘
        ▼
   public API: IconName, WebUIIcon, WebUIIconCustom, IconSize, modifiers
        │
        ▼  render()
   <svg class="icon icon--md" viewBox="0 0 24 24" stroke="currentColor" …>
```

the manifest is the only thing a human edits. everything downstream — the
generated `IconName` enum, the `WebUIIcons` catalog table, the lint gate, the
preview page, the stats report — is derived from it. the build plugin runs the
same generator the CLI does, so a `swift build` cannot produce an icon library
that disagrees with `designer/icons/icon-manifest.json`.

this mirrors the existing `WebUIAssetPlugin` / `WebUIAssetTool` pipeline that
embeds `design-system.css` and `webui-runtime.js` (see `Documentation/ASSEMBLY.md`,
stage 1).

## the catalog

- **206 icons**, 541 svg elements, ~26 KB of geometry payload (avg 126 bytes/icon,
  largest `settings` at 777 bytes).
- **grid 24, stroke 2**, butt cap + miter join — a tightened take on the Feather
  geometry: flat stroke ends and crisp corners read sharper than the original
  round treatment while keeping the same line language and spacing.
  zero-length geometry (the dot markers on `alert-circle`, `info`, `list`, the
  faces, …) carries an explicit `stroke-linecap="round"` on the element, since
  a zero-length line with the svg's butt cap would otherwise render nothing.
- **10 categories**: actions, comms, data, device, files, media, misc,
  navigation, security, status.
- **provenance**: Feather geometry (MIT). the manifest records the license so the
  shipped payload stays clear of trademarked brand marks.

every icon's geometry is validated by the `lint` verb before it may enter the
catalog: allowed-element whitelist, self-closing tags, on-grid bounds (the
bounds checker tokenizes numbers per the svg path grammar, so leading decimals
like `.45` are not misread as out-of-range), and no `stop`/`laptop` duplicates.

## public api

### `WebUIIcon`

a typed icon rendered as a self-contained inline svg.

```swift
WebUIIcon(.search)
    .render()
// <svg class="icon icon--md" viewBox="0 0 24 24" fill="none"
//      stroke="currentColor" stroke-width="2" stroke-linecap="butt"
//      stroke-linejoin="miter" aria-hidden="true"><circle …/><line …/></svg>
```

```swift
WebUIIcon(.download, size: .large, title: "Download file")
    .foregroundColor(.primary)
```

- `name: IconName` — the typed glyph (a generated `CaseIterable` enum, so a typo
  is a compile error, not a blank box).
- `size: IconSize` — semantic size (default `.medium`).
- `title: String?` — when set, the svg is `role="img" aria-label="…"`; when
  absent it is `aria-hidden="true"` (decorative). the label is `htmlEscape`d so
  a hostile title cannot break out of the attribute.

### `IconSize`

| case | css class | box |
|---|---|---|
| `.small` | `icon--sm` | `0.75em` |
| `.medium` | `icon--md` | `1em` |
| `.large` | `icon--lg` | `1.25em` |
| `.extraLarge` | `icon--xl` | `1.5em` |
| `.slot` | `icon` | sized by its container slot |

sizes are `em` multiples, so an icon always sits in proportion to its text
context (deference) and scales with the surrounding `font-size`. `.slot` emits
the bare `icon` class and lets a component's icon-slot css (`.alert__icon`,
`.tree__icon`, `.empty-state__icon`, …) size it — used by every migrated
component so an icon fills exactly the box the component already reserves.

### modifiers

```swift
WebUIIcon(.star)
    .iconSize(.extraLarge)        // swap the size class on the rendered svg
    .foregroundColor(.danger)     // -> style="color:var(--color-danger)" drives currentColor
```

`iconSize(_:)` rewrites the `icon--<size>` suffix (works from a `.slot` base
too). `foregroundColor(_ token:)` emits a `color:var(--color-…)` inline style;
because the stroke is `currentColor`, that is the whole coloring mechanism —
icons ride the existing `ColorToken` system rather than inventing a parallel
one.

### `WebUIIconCustom`

an escape hatch for caller-supplied geometry (your own path data) that is not in
the catalog. the body is **sanitized before emission**: `<script>` tags, `on*`
event-handler attributes, `foreignObject`, and `javascript:`/`data:` hrefs are
stripped, so free-form geometry can never become a script vector.

```swift
WebUIIconCustom(
    name: "custom-diamond",                       // stable key -> data-icon attribute
    body: "<path d=\"M12 2l9 10-9 10-9-10z\"/>",  // inner svg geometry
    size: .large,
    title: "Custom diamond"
)
```

### `IconName` lookups

```swift
IconName.named("search")        // -> .search   (case-insensitive raw-name lookup)
.search.isKnown                 // -> true     (resolves in the generated catalog)
IconName(emoji: "🔍")           // -> .search  (legacy emoji bridge)
```

`init?(emoji:)` is the smooth-migration path for existing call sites that still
pass an emoji string: ~30 glyphs map to their semantic icon (📭→`.inbox`, 🔎→`.search`,
📁→`.folder`, ⚙️→`.settings`, …), with a raw-name fallback, and `nil` for anything
unknown — so a bad value is a signal, not a silent fallback.

## rendering & css

the `.icon` primitives live in `design-system.css` (the "Icons" section):

```css
.icon {
  display: inline-block;
  width: 1em; height: 1em;
  flex: none;
  color: currentColor;
  overflow: visible;
  vertical-align: middle;
}
.icon--sm { width: .75em; height: .75em; }   /* md 1em · lg 1.25em · xl 1.5em */
.fill-slot > svg.icon { width: 100%; height: 100%; }
```

component icon slots reserve an explicit box and pair with `.fill-slot` so the
svg fills it exactly:

| slot | box |
|---|---|
| `.alert__icon` | `1.25rem` |
| `.table__empty-icon` | `2.5rem` |
| `.empty-state__icon` | `3rem` |
| `.tree__icon` | `1rem` |
| `.menu__icon` | `1rem` |
| `.banner__icon` | `1.25rem` |
| `.toast__icon` | `1.5rem` |

the design-system already styled ~30 icon slots through `currentColor`; this
work gives them a consistent box model so the inline svg lands at exactly the
size the slot intends. the shipped css is minified (comments + blank lines
stripped) at render time, per the project's first law.

## toolset — `WebUIIconTool`

a standalone Swift CLI (`swift run WebUIIconTool`, or the plugin's generated
binary) with five verbs. it has no external dependencies — the manifest and svg
geometry are parsed by hand — matching the codebase convention.

| verb | what it does | flags |
|---|---|---|
| `generate` | manifest → `IconLibrary.swift` (the build path) | `--manifest <path> --swift-output <path>` |
| `lint` | validate the manifest + report issues (CI gate) | `--manifest <path>` |
| `list` | print the catalog for discovery | `--manifest <path> [--grep <s>] [--category <c>] [--json]` |
| `stats` | coverage + payload report | `--manifest <path> [--json]` |
| `render-preview` | emit a self-contained visual QA page (all icons × 3 sizes, light/dark) | `--manifest <path> --output <file.html>` |

the generator is deterministic: given the same manifest it emits the same
`IconLibrary.swift` byte-for-byte, so there are no spurious diffs and the build
plugin's output is stable. reserved-word cases (e.g. `repeat`) are
backtick-escaped, and category labels use member-access form (`.actions`).

## build plugin — `WebUIIconPlugin`

`WebUIIconPlugin` (a build tool plugin applied to the `WebUI` target, alongside
`WebUIAssetPlugin`) runs `WebUIIconTool generate` on every `swift build` and
emits `IconLibrary.swift` into the target. the generated file declares the
`IconName` enum, the `WebUIIcons` catalog table (`Meta(name:category:title:body:)`
+ `meta(named:)` / `meta(for:)`), and the category enum. it lands under `.build/`
(gitignored) and joins the target automatically — no manual step.

## security

every emitted icon goes through the same invariants as the rest of the
framework:

- **attribute/text escaping** — `htmlEscape()` on the icon `class`, `aria-label`,
  and `data-icon` values. a `title` containing `"` or an `on*` payload is
  neutralized (covered by a dedicated test).
- **custom-geometry sanitization** — `WebUIIconCustom` strips `<script>`, `on*`
  handlers, `foreignObject`, and `javascript:`/`data:` hrefs before emission.
- **no-emoji guardrail** — a test asserts no shipped icon slot emits an emoji
  code point, so the migration cannot silently regress.
- **first law** — a test asserts the *minified* shipped css is comment-free.

## adding an icon

1. add a new object to `designer/icons/icon-manifest.json` (name, category,
   title, tags, `viewBox`, and the inner svg elements — copy real geometry from
   a licensed 24×24 stroke set).
2. `swift run WebUIIconTool lint --manifest designer/icons/icon-manifest.json` —
   validate bounds/whitelist before it can enter the catalog.
3. `swift build` — the plugin regenerates `IconLibrary.swift`; the new case
   appears on `IconName`.
4. `swift test` — the catalog-integrity suite (every manifest icon resolves to a
   generated entry, case count matches the manifest) proves it wired up.
5. `swift run WebUIIconTool render-preview --manifest … --output designer/previews/icons-preview.html`
   and eyeball it in both themes.

## migrating from emoji

the four components that previously took an emoji `String` now take a typed
`IconName`:

| component | was | now |
|---|---|---|
| `WebUIEmptyState` | `icon: String = "📭"` | `icon: IconName = .inbox` |
| `WebUITable.EmptyState` | `icon: String = "📭"` | `icon: IconName = .inbox` |
| `WebUIAlert` | `icon: String?` | `icon: IconName?` (nil → variant's semantic glyph) |
| `WebUITree.Node` | `icon: String?` | `icon: IconName?` |

this is a single breaking change applied across the repo in one commit. for any
out-of-repo call site that still passes an emoji string, `IconName(emoji:)`
bridges the ~30 common glyphs to their semantic icon and returns `nil` for
unknown ones.

## files

- `designer/icons/icon-manifest.json` — the canonical catalog (authored).
- `Sources/WebUIIconTool/MainProgram.swift` — the CLI + generator + lint + sanitizer.
- `Plugins/WebUIIconPlugin/WebUIIconPlugin.swift` — the build-time generator.
- `Sources/WebUI/Icon.swift` — `WebUIIcon`, `WebUIIconCustom`, `IconSize`, modifiers, `IconName` lookups.
- `IconLibrary.swift` (generated, `.build/`) — `IconName`, `WebUIIcons`, categories.
- `designer/previews/icons-preview.html` — the visual QA page (regenerate with `render-preview`).
