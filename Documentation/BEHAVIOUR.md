# the behaviour vocabulary

The client engine applies consequences by reading `data-*` attributes. Every
attribute exists because a typed Swift value (`Behavior`) serialized to it —
never because someone typed the attribute by hand. This document is the
contract between the two halves: the engine reads exactly these names, and
`Tests/WebUITests/BehaviourVocabularyTests.swift` fails when the engine reads
an attribute this document does not name.

Two rules make the contract hold:

1. **typed values, not strings.** a component emits a behavior through
   `.behavior(_:)`, which derives the attribute from the Swift value. hand
   written `data-*` literals are forbidden (a string renderer may splice a
   behavior's `attributeText`, which is still the typed value).
2. **regions are component ids.** a behavior addresses the element it is
   attached to, or an element identified by `data-component-id`; it never
   picks an arbitrary CSS selector.

Islands are behavior-free (§19.1): markup inside `[data-webui-island]` is
render-only, and the engine does not run behavior consequences there. A
behavior attribute inside an island region is inert at boot and after a patch
alike — an interactive control belongs outside the island boundary.

## two assets, one vocabulary

The runtime ships as two files. `webui-engine.js` carries the patch-survival
consequences — scroll follow, scroll memory, scroll-to, draft identity, focus
return, the dismiss stack, disclosure state, the theme choice — and applies them
before the first paint. `webui-engine-ext.js` carries the interaction
consequences and is fetched once at boot into the same dispatch table. The split
is an implementation detail: the names, the consequences and the readiness
contract are identical across the two, and `on.ready` fires only after the
extension settles (loaded or failed), so no behavior races the first patch. A
page whose extension request fails keeps the core consequences, warns once, and
stays functional — it never sees a second protocol or a second name.

## attributes the engine reads today

| attribute | read by the engine as | emitted by |
|---|---|---|
| `data-component-id` | the event-routing identity: dispatch resolves the nearest id-bearing ancestor, and a patch addresses the element by it | `.onClick`/`.onInput`/… modifiers, `controlAttributes(id:event:handler:)`, `.wire(…)` |
| `data-event` | the declared event name a component accepts; the runtime delivers only that event | the same modifiers |
| `data-optimistic` | the render-time prediction payload applied in the click's own turn | `.onOptimisticClick(predict:perform:)` |
| `data-prevent-enter` | `"false"` opts a form control out of enter-to-submit | form primitives |
| `data-no-restore` | opts a control out of fragment value/checked/caret restoration | form primitives |
| `data-dismiss` | the dismiss affordance a layer closes through (Escape and outside-click ordering) | `WebUIDismissible` and overlay components |
| `data-theme` | the theme the page roots at; the pre-paint prelude and the engine both write it | `WebUIDocument` prelude, theme switcher |
| `data-theme-choice` | a theme picker's mode; the engine reconciles `aria-pressed` and applies the choice | `WebUIShell`, theme picker components |
| `data-scheme` | the colour scheme the page roots at | the pre-paint prelude |
| `data-scheme-choice` | a scheme picker's mode (legacy spelling kept live) | `WebUIShell`, scheme pickers |
| `data-webui-key` | keyed reconciliation: the engine remembers a node's state by this key across patches | `.webuiKey(_:)` |
| `data-webui-transition` | `"off"` applies a patch synchronously, bypassing the view-transition wrapper | fragment patches / host policy |
| `data-webui-island` | mounts a wasm capability island by name | `Island`/`ResizableIsland`/`TypedIsland` |
| `data-webui-island-resize` | `"true"` marks a resizable island | `ResizableIsland`/`TypedResizableIsland` |
| `data-webui-island-state` | the mount state the engine writes back (`mounted`, `unmapped`, …) | engine (written) |
| `data-webui-args` | the island's typed argument frame | the island primitives |
| `data-island-input` | binds an input to an island region for local re-render | island input binding |
| `data-webui-state` | the client-state value the engine writes for a bound element | engine (written) |
| `data-webui-status` | the connection-status chip mount point | engine (written) |

## the canonical behavior vocabulary

These are the names the behavior layer introduces (S2/S3). They are normative:
the engine reads exactly these spellings, and `AttributeRepresentable.name` is
where each is declared. No aliases — two names for one consequence is a dead
control.

| behavior | attribute(s) | value |
|---|---|---|
| `ScrollFollow` | `data-follow` | `bottom` (stick while at the bottom, release on upward movement) or `off` |
| `ScrollFollow` (state) | `data-follow-state` | `away` while the reader is detached — the state that shows the jump control (engine-written) |
| `ScrollKey` | `data-scroll-key` | a per-region key whose scroll position survives a patch |
| `ScrollTo` | `data-scroll-to` | the element id to scroll to, with the 1.4 s flash contract; an empty value scrolls the document to the top |
| `ScrollTo` (flash) | `data-scroll-flash` | presence while the scroll-to target flashes (engine-written, removed after 1400 ms) |
| `DraftIdentity` | `data-draft-id` | the draft key a control's unsubmitted value is remembered under |
| `FocusReturn` | `data-focus-return` | the id to return focus to after a patch (empty = the element itself) |
| `DismissStack` | `data-dismiss` | presence marks a layer; the engine orders Escape and outside-click |
| `Reorder` | `data-reorder` | the hidden input id the engine writes the new order into |
| `Clipboard` | `data-copy` | text to copy (empty = the element's own text) |
| `TableEnhance` | `data-table-enhance` | `sort`, `filter`, or `sort filter` |
| `TableEnhance` (filter) | `data-table-filter` | the filter input inside the enhanced region (engine-read) |
| `FilterList` | `data-filter-list` | presence; the region whose input filters its `[role=option]` / `[role=menuitem]` / `.command-palette__item` items by case-insensitive substring, hiding non-matches |
| `SkipTarget` | `data-skip-to` | the id a skip link moves focus to |
| `TickingLabel` | `data-reltime` | ms epoch; the relative-time ladder paints the label |
| `TickingLabel` (elapsed) | `data-started` + `data-elapsed` | ms epoch + presence; the elapsed clock paints `floor(s/60):SS` |
| `Disclosure` | `data-preserve-open` | presence marks a `<details>` whose `open` state survives a patch |
| `InlineEdit` | `data-inline-edit` | presence; local edit entry (no round-trip), save through the server |
| `InlineEdit` (mode) | `data-editing` | presence while the control is in local edit mode (engine-written) |
| `Clipboard` (toast) | `data-webui-toast` | the engine-owned toast element a copy consequence mounts (engine-written) |
| `Roving` | `data-roving` | presence; one tab stop for the group, arrow keys move it |
| `Scrollspy` | `data-scrollspy` | presence; the container whose sections the nav highlights |
| `ThemeChoice` | `data-theme-choice` | the chosen mode (see above; already live) |
| form semantics | `data-autogrow`, `data-submit-on-enter`, `data-clear-on-submit` | presence; autogrow, enter-to-send, clear on submit |
| form semantics (number) | `data-clamp` | `min,max` — the accepted numeric range |
| upload destination | `data-upload-into` | the typed destination: `attachments` or `folder:<path>`; the engine sends it back as `X-Upload-Path` |
| upload route | `data-upload-to` | the route the engine posts the body to (`/upload` by default) |
| upload (tray) | `data-webui-upload-tray` | the tray the transport mounts and owns (engine-written) |
| upload (state) | `data-webui-upload-state` | a tray row's state: `uploading`, `done`, `error`, `cancelled` (engine-written) |

the upload rows' transport — the headers, the route's json shape, the tray's
DOM and class contract — is `Documentation/UPLOAD.md`.

## changing the vocabulary

1. add the behavior as a Swift type whose `AttributeRepresentable.name` is the
   attribute, and emit it through `.behavior(_:)`;
2. add the row here;
3. run `swift test --filter BehaviourVocabularyTests` — the gate compares the
   engine's attribute set with this document in both directions;
4. ship it in a minor tag and name the attribute in the release note.

A new engine behavior with no row here is a bug, not a feature.
