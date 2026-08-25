# Design System

The WebUI design system provides the nexus token set and styled components.
the canonical token source is `designer/assets/design-system.css` — all tokens
are CSS custom properties on `:root` (plus a `prefers-color-scheme: dark`
remap), embedded in the binary as `WebUIAssets.css` (8,038 lines, 303KB).
the design-token sections below are pinned by the `Design Token Integrity`
suite and by a deployment guard that every backticked `--` token documented
here exists in the shipped css.

## Design Tokens

### Neutral Palette

cool slate palette that anchors the entire system. 11 shades from 50
(lightest) to 950 (darkest).

```
--color-neutral-50:  #f8fafc
--color-neutral-100: #f4f6f8
--color-neutral-200: #e9edf2
--color-neutral-300: #d4dbe3
--color-neutral-400: #9aa7b8
--color-neutral-500: #64748b
--color-neutral-600: #475569
--color-neutral-700: #334155
--color-neutral-800: #1e293b
--color-neutral-900: #0f172a
--color-neutral-950: #0a0f1c
```

### Primary Palette (the single brand accent)

indigo spectrum. primary actions, links, active states. one accent per screen —
reserve indigo for the primary action, keep everything else neutral.

| token | value |
|---|---|
| `--color-primary-50` … `--color-primary-300` | `#eef2ff` … `#a5b4fc` (tints) |
| `--color-primary-400` | `#818cf8` |
| `--color-primary-500` | `#6366f1` |
| `--color-primary-600` | `#4f46e5` |
| `--color-primary-700` | `#4338ca` |
| `--color-primary-800` | `#3730a3` |
| `--color-primary-900` | `#312e81` |
| `--color-primary-950` | `#1e1b4b` |
| `--color-primary-solid` | `var(--color-primary-600)` (solid fill) |
| `--color-primary-solid-hover` / `-active` | `var(--color-primary-700)` / `-800` |
| `--color-primary-soft` / `-strong` / `-ring` | tint aliases for chips, badges, focus |
| `--color-on-primary-solid` | `#ffffff` (ink on solid primary) |
| `--color-primary` | `var(--color-primary-500)` (alias) |

### Semantic Colors

| token | light value | usage |
|---|---|---|
| `--color-success` | `#10b981` | success states, confirmations |
| `--color-warning` | `#d97706` | warnings, cautions |
| `--color-danger` | `#dc2626` | errors, destructive actions |
| `--color-info` | `#2563eb` | informational messages |

each semantic color also has `-strong`, `-soft`, and `-ring` slots. dark mode
re-tints the fills bright and swaps the ink to `--color-on-color` (see below).

### Surface & Text (light)

| token | value |
|---|---|
| `--color-bg` | `#f4f6f8` |
| `--color-bg-raised` | `#ffffff` |
| `--color-bg-inset` | `#eef2f6` |
| `--color-bg-subtle` | `#f1f5f9` |
| `--color-text` | `#0f172a` |
| `--color-text-muted` | `#5b6b81` |
| `--color-text-faint` | `#5f6f86` |
| `--color-on-color` | `#ffffff` |
| `--color-border` | `#e2e8f0` |
| `--color-border-strong` | `#cbd5e1` |

surface ladder: page `--color-bg` → raised `--color-bg-raised` → inset
`--color-bg-inset`. a card floats one level above its container; never stack
more than three levels of elevation.

### Dark Theme

near-black-first, applied via `@media (prefers-color-scheme: dark)`. every new
surface gets a dark remap in the same commit.

| token | dark value |
|---|---|
| `--color-bg` | `#060910` |
| `--color-bg-raised` | `#0c111c` |
| `--color-bg-inset` | `#0a0e18` |
| `--color-bg-subtle` | `#141b2b` |
| `--color-text` | `#e7ecf5` |
| `--color-text-muted` | `#97a3b8` |
| `--color-text-faint` | `#8494ab` |
| `--color-on-color` | `#060910` |
| `--color-primary-solid` | `#4f46e5` (white ink preserved) |
| success / warning / danger / info | `#34d399` / `#fbbf24` / `#f87171` / `#60a5fa` (bright fills, dark ink) |

the dark ink-on-fill is the near-black `--color-on-color`, not white — the WCAG
contrast guards in `DeploymentIntegrityTests` pin this for both themes.

### Spacing Scale

`--space-0` … `--space-24` form the base scale (values at 16px root): 0, 1(4px),
2(8px), 3(12px), 4(16px), 5(20px), 6(24px), 8(32px), 10(40px), 12(48px),
16(64px), 20(80px), 24(96px). --space-* wildcards are never written literally;
`--spacing-0` … `--spacing-24` are aliases onto the same scale. never invent
numbers between the steps — if you can't find a token, add one with both a
light and dark definition.

### Typography

all-sans type. `--font-sans` and `--font-display` share the `-apple-system`
stack (the display serif was retired in the nexus redesign); `--font-mono` is
`ui-monospace`.

- sizes: `--font-size-xs`(0.75rem) … `--font-size-5xl`(3rem), with --text-*
  aliases (`--text-sm`, `--text-lg`, …) on the same scale and `--fs-hero` for
  hero headings.
- weights: 400/500/600/700 (`--font-weight-normal/-medium/-semibold/-bold`).
- line-heights: 1.25/1.5/1.75 (`--line-height-tight/-normal/-relaxed`).
- letter-spacing: `--letter-spacing-tight/-normal/-wide/-wider`.

body text ≥ 16px (1rem), line-height 1.4–1.6, contrast AA. headings semibold or
bold, body regular — max 3 levels of emphasis on one screen.

### Border Radius

`--radius-none`(0), `--radius-sm`(0.25rem), `--radius-md`(0.375rem),
`--radius-lg`(0.5rem), `--radius-xl`(0.75rem), `--radius-2xl`(1rem),
`--radius-full`(9999px). nexus geometry aliases: `--radius-button` and
`--radius-input` = `--radius-md` (soft 6px), `--radius-card` = `--radius-xl`,
`--radius-elevated` = `--radius-lg`.

### Shadows

`--shadow-sm` … `--shadow-xl` — progressively larger box-shadows over the
neutral palette. `--ring-focus` and `--ring-focus-danger` are the only focus
rings: always `box-shadow: var(--ring-focus)` on `:focus-visible`, never
remove the ring.

### Motion

`--transition-fast`(150ms ease), `--transition-base`(200ms ease),
`--transition-slow`(300ms ease), `--ease-out` cubic-bezier. nothing bounces,
nothing linear, nothing over 300ms unless the user initiated the transition.

### Z-Index

use the scale, never raw integers:

| token | value |
|---|---|
| `--z-base` | 0 |
| `--z-raised` | 1 |
| `--z-dropdown` | 10 |
| `--z-sticky` | 100 |
| `--z-overlay` | 1000 |
| `--z-modal` | 1100 |
| `--z-scrim` | 1200 |
| `--z-toast` | 1300 |

## Components

All components are in `WebUIComponents.swift`. Each accepts standard modifiers
(`.font()`, `.padding()`, …) since they conform to `View`. every parameter is
validated in `Tests/WebUITests/` and every class below exists in the shipped
css.

### WebUIButton

```swift
WebUIButton("Submit", variant: .primary, size: .md)
WebUIButton("Delete", variant: .danger, disabled: true)
WebUIButton("Save…", variant: .primary, loading: true)
WebUIButton("Full", fullWidth: true)
```

**Variants:** `primary`, `secondary`, `outline`, `ghost`, `danger`, `success`, `warning`
**Sizes:** `sm`, `md`, `lg`
**Parameters:** `label`, `variant`, `size`, `disabled`, `id`, `fullWidth`, `loading`

CSS classes: `button button--{variant} button--{size}` (+ `button--full` when
`fullWidth`, `button--loading` when `loading`); children `button__spinner`,
`button__label`.

### WebUIInput

```swift
WebUIInput(placeholder: "Enter text...")
WebUIInput(placeholder: "Your name", label: "Name", helpText: "As shown on your profile")
WebUIInput(placeholder: "Password", type: .password, state: .error)
```

**States:** `normal`, `error`, `success`, `warning`
**Types:** any `InputType` (`.text`, `.password`, `.email`, `.number`, `.tel`,
`.url`, `.search`, `.date`, …)

CSS classes: `input__label`, `input-wrapper`, `input` (+
`input--error`/`input--success`/`input--warning`), `input__help` (+
`input__help--error`.

### WebUICard

```swift
WebUICard {
    Text("Card content")
}
WebUICard(variant: .outlined, id: "settings") {
    Text("Settings content")
}
```

**Variants:** `elevated`, `outlined`, `flat`, `interactive`

CSS classes: `card card--{variant}`

### WebUIBadge

```swift
WebUIBadge("New", variant: .success)
WebUIBadge("3", variant: .danger, size: .sm, dot: true)
```

**Variants:** `primary`, `secondary`, `success`, `warning`, `danger`, `info`, `neutral`
**Sizes:** `sm`, `md`, `lg`

CSS classes: `badge badge--{variant} badge--{size}` (+ `badge--dot`); child
`badge__dot`.

### WebUIAlert

```swift
WebUIAlert(variant: .warning, message: "Disk space low")
WebUIAlert(variant: .danger, title: "Error", message: "Something broke", dismissible: true)
```

**Variants:** `info`, `success`, `warning`, `danger`
**Parameters:** `variant`, `title`, `message`, `dismissible`, `icon`

CSS classes: `alert alert--{variant}`, children `alert__icon`, `alert__body`,
`alert__title`, `alert__message`, `alert__close` (dismissible only; carries
`data-dismiss`). the container has `role="alert"`.

### WebUITabs

```swift
WebUITabs(
    tabs: [TabItem(id: "general", label: "General"), TabItem(id: "settings", label: "Settings")],
    activeTab: "general"
)
```

CSS classes: `tabs`, `tabs__tab`, `tabs__tab--active`; `role="tablist"` /
`role="tab"` plus `aria-selected` and a `data-tab` marker on each tab.

### WebUIAvatar

```swift
WebUIAvatar(initials: "JD", size: .md)
WebUIAvatar(initials: "JD", src: "/profile.jpg", status: "online")
```

**Sizes:** `sm`, `md`, `lg`, `xl`
**Parameters:** `initials`, `size`, `src`, `status`

CSS classes: `avatar avatar--{size}`, children `avatar__img`, `avatar__initials`,
`avatar__status` (set only when `status` is given; carries `data-status`).

### WebUIProgress

```swift
WebUIProgress(value: 0.75)
WebUIProgress(value: 0.5, variant: .warning, showLabel: true)
```

**Variants:** `primary`, `success`, `warning`, `danger`; `value` clamps to 0…1.

CSS classes: `progress progress--{variant} progress--{size}`, children
`progress__bar`, `progress__label`; `role="progressbar"` plus `aria-valuenow`
when accessible.

### WebUISkeleton

```swift
WebUISkeleton()
WebUISkeleton(variant: .card, count: 3)
```

**Variants:** `text`, `title`, `avatar`, `card`, `custom`; optional `width` /
`height`; `count` clamps to ≥ 1.

CSS classes: `skeleton skeleton--{variant}`; `aria-hidden="true"`.

### WebUIToast

```swift
WebUIToast(message: "Saved", variant: .success)
WebUIToast(message: "Failed", variant: .danger, dismissible: false)
```

**Variants:** `info`, `success`, `warning`, `danger`; dismissible by default.

CSS classes: `toast toast--{variant}`, children `toast__icon`,
`toast__message`, `toast__close` (dismissible; carries `data-dismiss`);
`role="alert"`.

### WebUIModal

```swift
WebUIModal(title: "Confirm") {
    Text("Are you sure?")
} footer: {
    WebUIButton("OK", variant: .primary)
}
```

**Parameters:** `title`, `id`, `content`, `footer` (both view builders).

CSS classes: `modal-overlay`, `modal`, `modal__header`, `modal__title`,
`modal__body`, `modal__footer`, `modal__close` (carries `data-dismiss`);
`role="dialog"` + `aria-modal="true"` + `aria-labelledby`.

### WebUITable

```swift
WebUITable(
    headers: ["Name", "Role"],
    rows: [[Text("Ada"), Text("Admin")], [Text("Linus"), Text("Dev")]],
    striped: true, hoverable: true, compact: false
)
```

rows are `[[any View]]`, so cells can be any view (not just strings).

CSS classes: `table` (+ `table--striped`, `table--hoverable`, `table--compact`).

### WebUIChip

```swift
WebUIChip("Swift", variant: .primary)
WebUIChip("Clear", variant: .neutral, removable: true)
```

**Variants:** `primary`, `secondary`, `success`, `warning`, `danger`, `info`, `neutral`

CSS classes: `chip chip--{variant}`, children `chip__label`, `chip__remove`
(removable; carries `data-remove`).

### WebUIEmptyState

```swift
WebUIEmptyState(title: "No results", message: "Try a different filter.")
WebUIEmptyState(icon: "📦", title: "Empty", message: "Add your first item", action: ("Add Item", "add-btn"))
```

CSS classes: `empty-state`, `empty-state__icon`, `empty-state__title`,
`empty-state__message`.

### WebUISpinner

```swift
WebUISpinner(size: .md)
WebUISpinner(size: .lg, label: "Loading…")
```

**Sizes:** `sm`, `md`, `lg`

CSS classes: `spinner spinner--{size}`, children `spinner__ring`,
`spinner__label`; `role="status"` (+ `aria-label` when labeled).

### WebUITooltip

```swift
WebUITooltip("More info", position: .top) {
    Text("Hover me")
}
```

the tooltip text is the first, unlabeled parameter; **position** is
`top`, `bottom`, `left`, or `right`.

CSS classes: `tooltip-container`, `tooltip tooltip--{position}`, children
`tooltip__arrow`, `tooltip__text`; `role="tooltip"`.

## CSS Class Naming Convention

All classes follow BEM-like naming:
- Block: component name (`button`, `card`, `input`)
- Element: double underscore (`button__label`, `modal__title`, `chip__remove`)
- Modifier: double dash (`button--primary`, `alert--danger`, `table--compact`)

## Responsive Breakpoints

there are no --bp-* tokens. the css uses raw `min-width` media queries; the
breakpoint currently in use is 1100px (`@media (min-width: 1100px)`).
components are mobile-first by default.
