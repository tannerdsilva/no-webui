# API Reference

## WebUI

### Protocols

| Protocol | Requirement | Description |
|---|---|---|
| `View` | `func render() -> String` | A renderable UI component |
| `ViewModifier` | `func apply(to html: String) -> String` | Wraps rendered HTML with attributes/styles |
| `Observable` | `func observe(_ event: ObservableEvent)` | Receives framework events |

### Views

| Type | Parameters | HTML |
|---|---|---|
| `Text(_ text: String)` | text | `<span>text</span>` |
| `Button(_ label: String)` | label, disabled, loading, fullWidth, id | `<button>label</button>` |
| `Input` | type, value, placeholder, name, label, error, helperText, disabled, id | `<input type="...">` |
| `TextArea` | value, placeholder, name, label, rows, error, disabled, id | `<textarea>value</textarea>` |
| `Select` | options: [(String, String)], placeholder, value, name, label, error, id | `<select><option>...</select>` |
| `Link(_ text: String, href: String)` | text, href, target, class | `<a href="...">text</a>` |
| `Image(src: String, alt: String)` | src, alt, loading, class | `<img src="..." alt="...">` |
| `Form(action:method:)` | action, method, id, class, csrfToken, content | `<form>...<input type="hidden" name="_csrf">...</form>` |
| `Raw(_ html: String)` | html | Raw passthrough (no escaping) |
| `Spacer()` | — | `<div class="spacer"></div>` |
| `Divider()` | — | `<hr>` |
| `EmptyView()` | — | `""` |
| `AnyView<V: View>(_ view: V)` | view | Type-erased wrapper |

### Layouts

| Type | Parameters | CSS |
|---|---|---|
| `VStack` | spacing, alignment, padding, width, height | `flex-direction: column` |
| `HStack` | spacing, alignment, padding, width, height | `flex-direction: row` |
| `ZStack` | alignment, width, height | `position: relative` + absolute children |
| `Grid` | columns, spacing, alignment, padding, width, height | `display: grid; grid-template-columns: repeat(N, 1fr)` |
| `ScrollView` | spacing, alignment, width, height | `overflow: auto` |

### Modifiers (View extensions)

| Method | Effect |
|---|---|
| `.font(size:weight:)` | `style="font-size:Npx;font-weight:W"` |
| `.foregroundColor(_ color: String)` | `style="color:..."` |
| `.backgroundColor(_ color: String)` | `style="background-color:..."` |
| `.padding(_ value: Int)` | `style="padding:Npx"` |
| `.cornerRadius(_ value: Int)` | `style="border-radius:Npx"` |
| `.width(_ value: String)` | `style="width:..."` |
| `.height(_ value: String)` | `style="height:..."` |
| `.class(_ name: String)` | `class="..."` |
| `.id(_ id: String)` | `id="..."` |
| `.onClick(_ handler: @escaping EventHandler)` | `data-component-id="cN" data-event="click"` |
| `.onInput(_ handler: @escaping EventHandler)` | `data-component-id="cN" data-event="input"` |
| `.onSubmit(_ handler: @escaping EventHandler)` | `data-component-id="cN" data-event="submit"` |
| `.onChange(_ handler: @escaping EventHandler)` | `data-component-id="cN" data-event="change"` |
| `.onKeyDown(_ handler: @escaping EventHandler)` | `data-component-id="cN" data-event="keydown"` |
| `.onFocus(_ handler: @escaping EventHandler)` | `data-component-id="cN" data-event="focus"` |
| `.onBlur(_ handler: @escaping EventHandler)` | `data-component-id="cN" data-event="blur"` |

### Event Handling

| Type | Description |
|---|---|
| `EventData` | `{ component: String, event: String, data: [String: String] }` |
| `EventHandler` | `@Sendable (EventData) async -> [FragmentUpdate]` |
| `EventRouter` | Routes events to registered handlers. `maxHandlers: Int` (default 10,000) |
| `RenderContext` | `@TaskLocal` context providing component ID generation and handler registration |
| `FragmentUpdate` | `{ id: String, html: String }` — DOM patch instruction |

### Observability

| Type | Description |
|---|---|
| `ObservableEvent` | Enum with 10 cases: viewRendered, eventReceived, eventHandled, fragmentSent, websocketConnected/Disconnected/Error, error, debug |
| `ObserverList` | Thread-safe collection of `Observable` conformers. `maxObservers: Int` (default 100) |
| `Logger.emit(_:observers:)` | Logs an event and notifies observers |

### HTML Document

| Type | Parameters | Description |
|---|---|---|
| `HTMLDocument` | title, body, styles, rawStyles, scripts, contentSecurityPolicy, includeRuntime, devMode, headExtra | Complete HTML document with auto-generated CSP and nonce |
| `WebUIDocument` | Same as HTMLDocument + full design system CSS | HTML document with WebUI design system |

### CSS

| Type | Description |
|---|---|
| `CSSRule(_ selector: String, _ declarations: [(String, String)])` | A single CSS rule |
| `CSSStylesheet(_ rules: CSSRule...)` | A collection of CSS rules, renders to `<style>` block |

### Utilities

| Function | Description |
|---|---|
| `htmlEscape(_ string: String) -> String` | Escape HTML special characters (&, <, >, ", ') |
| `injectAttributes(into html: String, _ attributes: String) -> String` | Inject attributes into the first HTML tag |
| `sanitizeURL(_ url: String) -> String?` | Block javascript:, data:, vbscript: URLs |
| `markdownToHTML(_ markdown: String) -> String` | Render markdown to HTML (stub) |
| `highlightCode(_ code: String, language: String) -> String` | Syntax highlight code (stub) |
| `inlineSVG(viewBox:width:height:_ content: String) -> String` | Create inline SVG element |
| `attrIf(_ name: String, _ value: String, _ condition: Bool) -> String` | Conditional HTML attribute |
| `classIf(_ className: String, _ condition: Bool) -> String` | Conditional CSS class |

### CSRF Protection

| Method | Description |
|---|---|
| `CSRFProtection.generateSecret() -> String` | 32-byte random server secret |
| `CSRFProtection.token(for:secret:maxAge:) -> String` | HMAC-SHA256 stateless token |
| `CSRFProtection.validate(_:for:secret:) -> Bool` | Validate token (signature + expiration) |

## WebUIDesignSystem

### WebUITheme

Static enum with ~110 CSS custom properties organized into categories:
- `neutralPalette`, `brandColors`, `semanticColors`, `surfaceColors`, `textColors`, `borderColors`
- `spacing`, `typography`, `borderRadius`, `shadows`, `transitions`
- `all` — convenience array of all tokens

### WebUIDocument

`HTMLDocument` subclass that includes the full design system CSS via
`WebUITheme.css`.

### Components

| Component | Key Parameters |
|---|---|
| `WebUIButton` | label, variant (.primary/.secondary/.outline/.ghost/.danger/.success/.warning), size (.sm/.md/.lg), disabled, loading, fullWidth |
| `WebUICard` | title, padding (.sm/.md/.lg), content |
| `WebUIInput` | type, value, placeholder, label, error, helperText, disabled |
| `WebUITextArea` | value, placeholder, label, rows, error, disabled |
| `WebUISelect` | options: [(String, String)], placeholder, value, label, error |
| `WebUIBadge` | text, variant, size (.sm/.md) |
| `WebUIModal` | title, isOpen, content |
| `WebUIToast` | message, variant, duration |
| `WebUIAvatar` | initials, imageUrl, alt, size (.sm/.md/.lg/.xl) |
| `WebUIProgress` | value (0.0-1.0), variant, showLabel, size (.sm/.md) |
| `WebUIToggle` | isOn, label, disabled |
| `WebUITabs` | tabs: [(id, label)], activeTab |
| `WebUITable` | headers: [String], rows: [[String]] |
| `WebUIAlert` | message, variant, dismissible |
| `WebUITooltip` | text, position, content |
| `WebUIDropdown` | title, items: [(label, id)] |

## WebUIExample

A SwiftNIO-based HTTP/WebSocket server that serves a click counter page.

**Endpoints:**
- `GET /` — the counter page HTML
- `GET /ui/styles.css` — design system CSS (dev mode)
- `GET /ui/scripts.js` — JS runtime (dev mode)
- `WebSocket /ws` — event handling endpoint

**Port:** 9090 (configurable in source)