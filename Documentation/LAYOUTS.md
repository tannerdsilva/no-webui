# Layouts

The layout primitives render as `<div>` elements with flexbox/grid CSS classes
from `LayoutStyles.complete` (shipped via the design system css). each layout
takes its own parameters — see per-section signatures below.

## VStack

Stacks children vertically (column direction).

```swift
VStack(spacing: 16, alignment: .center) {
    Text("Item 1")
    Text("Item 2")
    Text("Item 3")
}
```

**Signature:** `VStack(alignment: HorizontalAlignment = .leading, spacing: Int = 8, @ViewBuilder content:)`

**HTML output:**

```html
<div class="vstack spacing-16 align-center">
    <span>Item 1</span>
    <span>Item 2</span>
    <span>Item 3</span>
</div>
```

**CSS:** `display: flex; flex-direction: column`

**Alignment options:** `.leading` (align-flex-start), `.center` (align-center),
`.trailing` (align-flex-end) — horizontal alignment of the children within the
column.

## HStack

Arranges children horizontally (row direction).

```swift
HStack(spacing: 8, alignment: .center) {
    WebUIButton("Save", variant: .primary)
    WebUIButton("Cancel", variant: .ghost)
}
```

**Signature:** `HStack(alignment: VerticalAlignment = .center, spacing: Int = 8, @ViewBuilder content:)`

**HTML output:**

```html
<div class="hstack spacing-8 align-center">
    <button class="button button--primary">Save</button>
    <button class="button button--ghost">Cancel</button>
</div>
```

**CSS:** `display: flex; flex-direction: row`

**Alignment options:** `.top` (align-flex-start), `.center` (align-center),
`.bottom` (align-flex-end) — vertical alignment of the children within the row.

## ZStack

Layers children on top of each other using a CSS grid overlay — every child
occupies the same grid cell (`grid-area: 1 / 1`, shipped by `LayoutStyles`),
so children paint in order and overlap.

```swift
ZStack {
    Image(src: "/background.jpg", alt: "Background")
    Text("Overlay text")
        .font(size: 24, weight: "700")
}
```

**Signature:** `ZStack(alignment: HorizontalAlignment = .center, verticalAlignment: VerticalAlignment = .center, @ViewBuilder content:)`

**HTML output:**

```html
<div class="zstack" style="display:grid;place-items:center center;">
    <img src="/background.jpg" alt="Background">
    <span style="font-size:24px;font-weight:700">Overlay text</span>
</div>
```

**CSS:** `display: grid; place-items: <h-align> <v-align>` (the `.zstack` rule
pair is `.zstack` + `.zstack > *`, both shipped in `LayoutStyles.complete`).
`alignment` and `verticalAlignment` control where children sit within the cell.

## Spacer

Flexible space that pushes siblings apart.

```swift
HStack {
    Text("Left")
    Spacer()
    Text("Right")
}
```

**Signature:** `Spacer(minSize: Int = 0)`

**HTML output:**

```html
<div class="hstack">
    <span>Left</span>
    <div class="spacer" style="flex:1;min-width:0px;min-height:0px"></div>
    <span>Right</span>
</div>
```

**CSS:** `flex: 1` on the `.spacer` class; `minSize` sets a floor on
`min-width`/`min-height` so the gap cannot collapse to nothing.

## ScrollView

Creates a scrollable container.

```swift
ScrollView {
    VStack(spacing: 8) {
        for i in 1...50 {
            Text("Row \(i)")
        }
    }
}
```

**Signature:** `ScrollView(@ViewBuilder content:)` — takes only the content
builder. constrain dimensions on the children (or wrap in a sized `Div`) when
a bounded scroll box is needed.

**HTML output:**

```html
<div class="scrollview">
    <div class="vstack spacing-8">...</div>
</div>
```

**CSS:** `overflow: auto` on the `.scrollview` class.

## Grid

Creates a CSS Grid layout.

```swift
Grid(columns: .fraction(3), spacing: 16) {
    for i in 1...6 {
        WebUICard { Text("Item \(i)") }
    }
}
```

**Signature:** `Grid(columns: GridColumns = .fraction(2), spacing: Int = 16, @ViewBuilder content:)`

**HTML output:**

```html
<div class="grid" style="display:grid;grid-template-columns:repeat(3, 1fr);gap:16px;">
    <div class="card">...</div>
    <div class="card">...</div>
    ...
</div>
```

**CSS:** inline `display: grid; grid-template-columns: <columns.cssValue>; gap: <spacing>px`

**`GridColumns` cases:**

| Case | Emits |
|---|---|
| `.fixed(n)` | `repeat(n, minmax(0, 1fr))` — grid-safe equal tracks |
| `.fraction(n)` | `repeat(n, 1fr)` |
| `.minmax(a, b)` | `repeat(auto-fill, minmax(a, b))` |
| `.autoFill(n)` / `.autoFit(n)` | `repeat(auto-fill, minmax(npx, 1fr))` — n is the minimum track size in px |
| `.custom(String)` | passthrough |

## Nesting

Layouts nest arbitrarily:

```swift
VStack(spacing: 24) {
    // Header
    HStack(spacing: 16, alignment: .center) {
        WebUIAvatar(initials: "JD", size: .md)
        VStack(spacing: 2) {
            Text("John Doe").font(size: 18, weight: "600")
            Text("Online").foregroundColor(.textMuted)
        }
        Spacer()
        WebUIBadge("Admin", variant: .primary)
    }

    // Content
    Grid(columns: .fraction(2), spacing: 16) {
        WebUICard { Text("Stats") }
        WebUICard { Text("Activity") }
    }

    // Footer
    HStack(spacing: 8) {
        WebUIButton("Save", variant: .primary)
        WebUIButton("Cancel", variant: .ghost)
    }
}
.padding(32)
```
