# Layouts

All layouts accept `spacing`, `alignment`, `padding`, `width`, and `height`
parameters. They render as `<div>` elements with flexbox/grid CSS classes.

## VStack

Stacks children vertically (column direction).

```swift
VStack(spacing: 16, alignment: .center) {
    Text("Item 1")
    Text("Item 2")
    Text("Item 3")
}
```

**HTML output:**
```html
<div class="vstack spacing-16 align-center">
    <span>Item 1</span>
    <span>Item 2</span>
    <span>Item 3</span>
</div>
```

**CSS:** `display: flex; flex-direction: column`

**Alignment options:** `.leading` (flex-start), `.center`, `.trailing` (flex-end),
`.stretch` (stretch)

## HStack

Arranges children horizontally (row direction).

```swift
HStack(spacing: 8, alignment: .center) {
    WebUIButton("Save", variant: .primary)
    WebUIButton("Cancel", variant: .ghost)
}
```

**HTML output:**
```html
<div class="hstack spacing-8 align-center">
    <button class="button button--primary">Save</button>
    <button class="button button--ghost">Cancel</button>
</div>
```

**CSS:** `display: flex; flex-direction: row`

**Alignment options:** `.top` (flex-start), `.center`, `.bottom` (flex-end),
`.stretch` (stretch)

## ZStack

Layers children on the z-axis using absolute positioning.

```swift
ZStack {
    Image(src: "/background.jpg", alt: "Background")
    Text("Overlay text")
        .font(size: 24, weight: "700")
}
```

**HTML output:**
```html
<div class="zstack">
    <img src="/background.jpg" alt="Background" style="position:absolute;inset:0">
    <span style="position:relative;z-index:1">Overlay text</span>
</div>
```

**CSS:** `position: relative` on container. Children are positioned absolutely
with `inset: 0` by default. Use `.alignment()` to control child positioning.

## Grid

Creates a CSS Grid layout.

```swift
Grid(columns: 3, spacing: 16) {
    for i in 1...6 {
        WebUICard { Text("Item \(i)") }
    }
}
```

**HTML output:**
```html
<div class="grid grid-cols-3 spacing-16">
    <div class="card">...</div>
    <div class="card">...</div>
    ...
</div>
```

**CSS:** `display: grid; grid-template-columns: repeat(3, 1fr)`

**Parameters:**
- `columns`: number of grid columns (default: 2)
- `spacing`: gap between grid items (default: 16)
- `alignment`: `.leading`, `.center`, `.trailing`, `.stretch` (default)

## ScrollView

Creates a scrollable container.

```swift
ScrollView(width: 300, height: 400) {
    VStack(spacing: 8) {
        for i in 1...50 {
            Text("Row \(i)")
        }
    }
}
```

**HTML output:**
```html
<div class="scrollview" style="width:300px;height:400px">
    <div class="vstack spacing-8">...</div>
</div>
```

**CSS:** `overflow: auto`

**Parameters:**
- `width` / `height`: constrain dimensions (optional)
- `spacing`: spacing between children (passed through to internal VStack)
- `alignment`: content alignment

## Spacer

Flexible space that pushes siblings apart.

```swift
HStack {
    Text("Left")
    Spacer()
    Text("Right")
}
```

**HTML output:**
```html
<div class="hstack">
    <span>Left</span>
    <div class="spacer"></div>
    <span>Right</span>
</div>
```

**CSS:** `flex: 1`

## Divider

A thematic break (`<hr>`).

```swift
VStack {
    Text("Section 1")
    Divider()
    Text("Section 2")
}
```

## Nesting

Layouts nest arbitrarily:

```swift
VStack(spacing: 24) {
    // Header
    HStack(spacing: 16, alignment: .center) {
        WebUIAvatar(initials: "JD", size: .md)
        VStack(spacing: 2) {
            Text("John Doe").font(size: 18, weight: "600")
            Text("Online").foregroundColor("--text-secondary")
        }
        Spacer()
        WebUIBadge("Admin", variant: .primary)
    }

    // Content
    Grid(columns: 2, spacing: 16) {
        WebUICard(title: "Stats") { Text("...") }
        WebUICard(title: "Activity") { Text("...") }
    }

    // Footer
    HStack(spacing: 8) {
        WebUIButton("Save", variant: .primary)
        WebUIButton("Cancel", variant: .ghost)
    }
}
.padding(32)
```