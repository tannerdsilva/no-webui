# Design System

The WebUI design system (`Sources/WebUIDesignSystem/`) provides ~110 CSS custom
properties (design tokens) and 16 styled components. The CSS is 7,893 lines
(311KB) and is embedded in the binary as a Swift string constant.

## Design Tokens

All tokens are defined as CSS custom properties on `:root` in
`WebUITheme.swift`. They are organized into categories:

### Neutral Palette

Cool slate palette that anchors the entire system. 10 shades from 50 (lightest)
to 900 (darkest).

```
--color-neutral-50:  #f8fafc
--color-neutral-100: #f1f5f9
--color-neutral-200: #e2e8f0
--color-neutral-300: #cbd5e1
--color-neutral-400: #94a3b8
--color-neutral-500: #64748b
--color-neutral-600: #475569
--color-neutral-700: #334155
--color-neutral-800: #1e293b
--color-neutral-900: #0f172a
```

### Brand Colors

| Token | Value | Usage |
|---|---|---|
| `--color-brand-50` through `--color-brand-900` | Blue-violet spectrum | Primary actions, links, active states |
| `--color-brand` | `--color-brand-600` | Default brand color |

### Semantic Colors

| Token | Value | Usage |
|---|---|---|
| `--color-success` | `#10b981` (green) | Success states, confirmations |
| `--color-warning` | `#f59e0b` (amber) | Warnings, cautions |
| `--color-danger` | `#ef4444` (red) | Errors, destructive actions |
| `--color-info` | `#3b82f6` (blue) | Informational messages |

### Surface Colors

| Token | Value | Usage |
|---|---|---|
| `--surface-primary` | `--color-neutral-900` | Primary background |
| `--surface-secondary` | `--color-neutral-800` | Card/container backgrounds |
| `--surface-tertiary` | `--color-neutral-700` | Elevated surfaces |
| `--surface-hover` | `--color-neutral-600` | Hover states |

### Text Colors

| Token | Value | Usage |
|---|---|---|
| `--text-primary` | `--color-neutral-50` | Primary text |
| `--text-secondary` | `--color-neutral-300` | Secondary/muted text |
| `--text-tertiary` | `--color-neutral-400` | Placeholder/disabled text |
| `--text-inverse` | `--color-neutral-900` | Text on light backgrounds |

### Border Colors

| Token | Value |
|---|---|
| `--border-primary` | `--color-neutral-600` |
| `--border-secondary` | `--color-neutral-700` |
| `--border-focus` | `--color-brand-500` |

### Spacing Scale

`--spacing-*`: 0, 1(4px), 2(8px), 3(12px), 4(16px), 5(20px), 6(24px), 8(32px),
10(40px), 12(48px), 16(64px), 20(80px), 24(96px)

### Typography

| Token | Value |
|---|---|
| `--font-sans` | `'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif` |
| `--font-mono` | `'JetBrains Mono', 'Fira Code', monospace` |
| `--font-size-xs` through `--font-size-4xl` | 12px through 48px |
| `--font-weight-normal`, `--font-weight-medium`, `--font-weight-semibold`, `--font-weight-bold` | 400, 500, 600, 700 |
| `--line-height-tight`, `--line-height-normal`, `--line-height-relaxed` | 1.2, 1.5, 1.8 |

### Border Radius

`--radius-sm`(4px), `--radius-md`(8px), `--radius-lg`(12px), `--radius-xl`(16px),
`--radius-full`(9999px)

### Shadows

`--shadow-sm`, `--shadow-md`, `--shadow-lg`, `--shadow-xl` — progressively larger
box-shadows using the neutral palette.

### Transitions

`--transition-fast`(150ms), `--transition-normal`(250ms), `--transition-slow`(350ms)

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

Defined in the CSS as custom properties on `:root`:
- `--bp-sm`: 640px
- `--bp-md`: 768px
- `--bp-lg`: 1024px
- `--bp-xl`: 1280px

The CSS uses `min-width` media queries. Components are mobile-first by default.