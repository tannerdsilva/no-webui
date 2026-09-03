# WebUI — Designer Sandbox

Welcome. This is where you edit the CSS and JS for the WebUI component library.
Everything here is plain HTML, CSS, and JavaScript — no build tools, no
terminal, no Swift code.

## What you need

- **A text editor** (VS Code, Sublime Text, Cursor — anything)
- **A browser** (Chrome, Safari, Firefox — open the preview file)

That's it. No npm install. No dev server. No build step.

## How it works

```
no-webui/
├── designer/                    ← YOU ARE HERE — your workspace
│   ├── assets/
│   │   ├── design-system.css    ← THE file you edit (8,100+ lines)
│   │   └── webui-runtime.js     ← JS runtime (rarely needs changes)
│   ├── icons/
│   │   └── icon-manifest.json   ← the svg icon catalog (618 glyphs, edit to add)
│   ├── previews/
│   │   ├── designer-preview.html  ← OPEN THIS IN YOUR BROWSER
│   │   ├── showcase.html        ← full generated reference page
│   │   └── icons-preview.html   ← icon visual QA page (all glyphs, 3 sizes, both themes)
│   └── README.md                ← this file
├── Sources/                     ← Swift source (you don't touch this)
│   ├── WebUI/                   ← framework code
│   └── WebUIIconTool/           ← the svg icon toolset (generate/lint/list/stats/preview)
└── ...                          ← other project files
```

### Your workflow

```
1. EDIT   designer/assets/design-system.css   (or designer/assets/webui-runtime.js)
2. SAVE   the file
3. RELOAD designer/previews/designer-preview.html  in your browser
```

Changes appear instantly. No server, no terminal, no waiting.

### When you're done

The build system reads directly from `designer/assets/`. There is no sync step.
When anyone runs `swift build`, it automatically picks up your latest changes
from this directory and embeds them into the framework as compiled-in assets.

### Icons

The svg icon catalog lives in `designer/icons/icon-manifest.json`. to add or
edit an icon:

1. EDIT `designer/icons/icon-manifest.json` (name, category, title, tags,
   `viewBox`, and the inner svg geometry — copy from a licensed 24×24 stroke set).
2. Lint it: `swift run WebUIIconTool lint --manifest designer/icons/icon-manifest.json`
3. `swift build` — the `WebUIIconPlugin` regenerates `IconLibrary.swift`; the
   new case appears on `IconName`.
4. Preview it: `swift run WebUIIconTool render-preview --manifest designer/icons/icon-manifest.json --output designer/previews/icons-preview.html`
   then open `designer/previews/icons-preview.html` (light + dark via your OS
   theme).
5. `swift test` — the catalog-integrity suite proves it wired up.

full guide: `Documentation/ICONS.md`.

To see your work in the real framework, the developer runs these commands
(all single commands, no scripts):

```bash
swift package --disable-sandbox plugin serve        # host the real server on :9123
swift package --disable-sandbox plugin smoke        # asset-integrity + page-structure gate
swift package --disable-sandbox plugin fullstack-smoke  # live WebSocket round-trip gate
node designer/browser-smoke.mjs                     # headless-Chromium layout gate
swift package plugin showcase --allow-writing-to-package-directory  # refresh showcase.html
```

- `serve` keeps the live server up (the interactive counter / progress / echo
  demo page on http://127.0.0.1:9123). Ctrl+C stops it.
- `smoke` proves the CSS/JS the server serves are **byte-identical** to
  `designer/assets/`, that the page is self-contained, and that every visual
  fix survived into the deployed HTML.
- `fullstack-smoke` goes further — it drives **live events over the wire**
  (a click, a keystroke) and asserts the DOM patches back correctly. this
  catches event-routing bugs a static check can't.
- `browser-smoke` loads the page in headless Chromium and asserts real-layout
  invariants (left-anchored fills, label placement, no console errors). you
  need `node` + `playwright` for this one; it writes a screenshot to
  `.smoke/browser.png`.
- `showcase` regenerates `previews/showcase.html` — the full reference page —
  from the current Swift sources and embedded assets.

if you need a port check, there's a probe too:
`swift package plugin probe 9123`.

> why do `serve`/`smoke`/`fullstack-smoke` need `--disable-sandbox`? package
> plugins run in a sandbox that forbids binding a listening port (even with the
> network permission, which is outbound-only). the flag lifts the sandbox for
> that one invocation, which is what lets the server bind and listen. if you
> see `server did not become ready — run with --disable-sandbox`, that's the
> missing flag.

## What's in the CSS file

The `design-system.css` file contains everything that controls how components
look. It's organized into sections:

| Section | What it controls |
|---|---|
| Design tokens (~225) | Colors, fonts, spacing, shadows, radii — the foundation |
| Reset & base | Box-sizing, body defaults, focus styles |
| Button | All button variants, sizes, states |
| Input | All input states (default, error, success, disabled) |
| Card | Elevated, outlined, flat, interactive variants |
| Badge | All badge variants, sizes, dot indicator |
| Alert | Info, success, warning, danger variants |
| Tabs | Tab bar and tab items |
| Breadcrumb | Trail, separators, ellipsis collapse |
| Pagination | Page list, prev/next, ellipsis, rows-per-page select |
| Tree | Recursive rows, carets, open/closed children |
| Progress | All sizes, striped fill |
| Avatar | All sizes, initials display |
| Skeleton | Text, title, avatar, card variants |
| Stat | KPI card, trend arrow, sparkline |
| Timeline | Event rows, status dots |
| Toast | Info, success, warning, danger variants |
| Modal | Modal overlay and content |
| Chip | All chip variants |
| Spinner | All spinner sizes |
| Table | Striped/hoverable/compact variants, sort headers, select + expand controls, `.num` numeric column, `.table-wrap` scroll container |
| Description List | Two-column `dl.list--desc` |
| Tooltip | Tooltip positions |
| Empty State | Empty state layout |
| WebUI compat | Additional classes for Swift component compatibility |

## Naming convention (BEM)

Every CSS class follows this pattern:

```
.component               → the component block
.component--variant      → a variant or state
.component__element      → a child part of the component
```

**Examples:**

```css
.button                    /* the button component */
.button--primary           /* primary variant */
.button--sm                /* small size */
.button__label             /* the label inside a button */

.card                      /* the card component */
.card--elevated            /* elevated variant */
.card__body                /* the card body */
```

**Rules:**
- One underscore level max (`__` for elements)
- Two hyphens for modifiers (`--`)
- Multiple modifiers can stack: `class="button button--primary button--md"`
- Never use inline `style` attributes in production components

## Design tokens — the most important rule

**Never use raw CSS values.** Always reference a design token:

```css
/* ✅ CORRECT — uses tokens */
.my-class {
  color: var(--color-primary);
  padding: var(--space-4);
  font-size: var(--font-size-base);
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-sm);
}

/* ❌ WRONG — raw values will be rejected */
.my-class {
  color: #3b82f6;
  padding: 16px;
  font-size: 16px;
  border-radius: 6px;
}
```

The preview page has a complete visual reference of all available tokens —
open `previews/designer-preview.html` and scroll through the color palette,
spacing scale, typography, shadows, and radii sections.

## If you want to add a new component

1. Add the CSS classes to `assets/design-system.css` following BEM convention
2. Add a demo to `previews/designer-preview.html` so you can see it
3. Tell Tanner — they'll create the corresponding Swift view struct

## What NOT to do

- **Don't edit files outside `designer/`** — the Swift source code is in `Sources/`
- **Don't add npm packages or external CSS/JS** — everything must be self-contained
- **Don't change the BEM convention** — the Swift code depends on it
- **Don't use raw color/spacing values** — always use `var(--token)`
- **Don't add inline styles in production components** — use CSS classes
- **Don't worry about the JS file** — it handles event routing and rarely needs changes
