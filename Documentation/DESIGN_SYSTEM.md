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
(`.font()`, `.padding()`, etc.) since they conform to `View`.

### WebUIButton

```swift
WebUIButton("Submit", variant: .primary, size: .md)
WebUIButton("Delete", variant: .danger, disabled: true)
WebUIButton("Loading...", variant: .primary, loading: true)
```

**Variants:** `primary`, `secondary`, `outline`, `ghost`, `danger`, `success`, `warning`
**Sizes:** `sm`, `md`, `lg`
**States:** `disabled`, `loading` (shows spinner), `fullWidth`

CSS classes: `button button--{variant} button--{size}` (+ `button--full-width`,
`button--loading`, `button--disabled`)

### WebUICard

```swift
WebUICard {
    Text("Card content")
}
WebUICard(title: "Settings", padding: .lg) {
    Text("Settings content")
}
```

CSS classes: `card` (+ `card--padding-sm/md/lg`)

### WebUIInput

```swift
WebUIInput(placeholder: "Enter text...")
WebUIInput(value: "prefilled", label: "Name", helperText: "Your full name")
WebUIInput(type: .password, placeholder: "Password", error: "Required")
```

**Types:** `text`, `password`, `email`, `number`, `tel`, `url`, `search`, `date`
**States:** `error` (shows error message), `disabled`

CSS classes: `input-wrapper`, `input-label`, `input`, `input-error`, `input-helper`

### WebUITextArea

```swift
WebUITextArea(placeholder: "Write...")
WebUITextArea(value: "Content", label: "Description", rows: 6)
```

CSS classes: `textarea-wrapper`, `textarea-label`, `textarea`

### WebUISelect

```swift
WebUISelect(options: [
    ("Option 1", "opt1"),
    ("Option 2", "opt2"),
], placeholder: "Choose...")
```

CSS classes: `select-wrapper`, `select`

### WebUIBadge

```swift
WebUIBadge("New", variant: .success)
WebUIBadge("3", variant: .danger, size: .sm)
```

**Variants:** `primary`, `success`, `warning`, `danger`, `info`, `neutral`
**Sizes:** `sm`, `md`

CSS classes: `badge badge--{variant} badge--{size}`

### WebUIModal

```swift
WebUIModal(title: "Confirm", isOpen: true) {
    Text("Are you sure?")
}
```

CSS classes: `modal-overlay`, `modal`, `modal-header`, `modal-body`, `modal-footer`

### WebUIToast

```swift
WebUIToast(message: "Saved!", variant: .success)
```

**Variants:** `success`, `error`, `warning`, `info`

CSS classes: `toast toast--{variant}`

### WebUIAvatar

```swift
WebUIAvatar(initials: "JD", size: .md)
WebUIAvatar(imageUrl: "/profile.jpg", alt: "User")
```

**Sizes:** `sm`, `md`, `lg`, `xl`

CSS classes: `avatar avatar--{size}`

### WebUIProgress

```swift
WebUIProgress(value: 0.75)
WebUIProgress(value: 0.5, variant: .warning, showLabel: true)
```

**Variants:** `primary`, `success`, `warning`, `danger`

CSS classes: `progress-bar`, `progress-fill`, `progress-label`

### WebUIToggle

```swift
WebUIToggle(isOn: true)
WebUIToggle(isOn: false, label: "Enable notifications")
```

CSS classes: `toggle`, `toggle--active`, `toggle-label`

### WebUITabs

```swift
WebUITabs(tabs: [
    ("tab1", "General"),
    ("tab2", "Settings"),
], activeTab: "tab1")
```

CSS classes: `tabs`, `tab`, `tab--active`

### WebUITable

```swift
WebUITable(
    headers: ["Name", "Value"],
    rows: [["Age", "30"], ["Role", "Admin"]]
)
```

CSS classes: `table`, `table-header`, `table-row`, `table-cell`

### WebUIAlert

```swift
WebUIAlert("Operation completed", variant: .success)
WebUIAlert("An error occurred", variant: .error, dismissible: true)
```

**Variants:** `info`, `success`, `warning`, `error`

CSS classes: `alert alert--{variant}` (+ `alert--dismissible`)

### WebUITooltip

```swift
WebUITooltip(text: "More info") {
    Text("Hover me")
}
```

CSS classes: `tooltip-container`, `tooltip`, `tooltip--visible`

### WebUIDropdown

```swift
WebUIDropdown(title: "Menu", items: [
    ("Profile", "profile"),
    ("Settings", "settings"),
    ("Logout", "logout"),
])
```

CSS classes: `dropdown`, `dropdown-trigger`, `dropdown-menu`, `dropdown-item`

## CSS Class Naming Convention

All classes follow BEM-like naming:
- Block: component name (`button`, `card`, `input`)
- Element: double underscore (`input__label`, `card__title`)
- Modifier: double dash (`button--primary`, `card--padding-lg`)

## Responsive Breakpoints

there are no --bp-* tokens. the css uses raw `min-width` media queries; the
breakpoint currently in use is 1100px (`@media (min-width: 1100px)`).
components are mobile-first by default.