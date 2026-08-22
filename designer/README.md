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
│   │   ├── design-system.css    ← THE file you edit (7,500+ lines)
│   │   └── webui-runtime.js     ← JS runtime (rarely needs changes)
│   ├── previews/
│   │   ├── designer-preview.html  ← OPEN THIS IN YOUR BROWSER
│   │   └── showcase.html        ← full generated reference page
│   └── README.md                ← this file
├── Sources/                     ← Swift source (you don't touch this)
│   └── WebUI/                   ← framework code
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
When Tanner runs `swift build`, it automatically picks up your latest changes
from this directory.

To verify your changes work end-to-end:

```bash
cd no-webui
designer/sync.sh               # build + test + regenerate the showcase
```

`sync.sh` runs `swift build` (which embeds the current `designer/assets/`
CSS/JS), `swift test` (242 tests), then regenerates
`designer/previews/showcase.html` via the freshly built `WebUIShowcase`
binary. Use `designer/sync.sh --no-test` to skip the suite during quick
iteration.

### Smoke-testing your deployment

Two one-command gates prove the design actually reaches a browser intact.
Both are safe to run repeatedly and exit non-zero on the first failure.

```bash
designer/smoke.sh          # asset integrity + deployed page structure
designer/fullstack-smoke.sh # live WebSocket event round-trips (full stack)
```

- `smoke.sh` builds the `WebUISmokeTest` server, starts it, and checks that the
  CSS/JS it serves are **byte-identical** to `designer/assets/`, that the page
  is self-contained (no external asset refs, CSP present), and that every
  visual fix survived into the deployed HTML.
- `fullstack-smoke.sh` goes further: it deploys the real stack (NIO HTTP +
  WebSocket upgrade + Swift `EventRouter` + interactive WebUI views) and drives
  **live events over the wire** — click a button, type in an input, and asserts
  the DOM patches back correctly. This catches event-routing bugs a static
  check can't.

You need `node` + `playwright` on PATH for `fullstack-smoke.sh`'s browser
layer; the Node WebSocket round-trip needs only `node`.

> Why a script instead of a `swift package plugin` command? A command plugin
> holds the package build lock for the whole `swift package plugin` run, so
> any nested `swift build`/`swift test` deadlocks on it; and command plugins
> run in a write-sandbox that cannot write back into the package directory
> (the copy into `designer/previews/` fails with EPERM). The shell script has
> neither constraint. The `showcase` plugin remains for ad-hoc generation to
> an arbitrary path: `swift package plugin showcase --output /tmp/x.html`.

## What's in the CSS file

The `design-system.css` file contains everything that controls how components
look. It's organized into sections:

| Section | What it controls |
|---|---|
| Design tokens (~110) | Colors, fonts, spacing, shadows, radii — the foundation |
| Reset & base | Box-sizing, body defaults, focus styles |
| Button | All button variants, sizes, states |
| Input | All input states (default, error, success, disabled) |
| Card | Elevated, outlined, flat, interactive variants |
| Badge | All badge variants, sizes, dot indicator |
| Alert | Info, success, warning, danger variants |
| Tabs | Tab bar and tab items |
| Progress | All sizes, striped fill |
| Avatar | All sizes, initials display |
| Skeleton | Text, title, avatar, card variants |
| Toast | Info, success, warning, danger variants |
| Modal | Modal overlay and content |
| Chip | All chip variants |
| Spinner | All spinner sizes |
| Table | Table variants (striped, hoverable, compact) |
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
