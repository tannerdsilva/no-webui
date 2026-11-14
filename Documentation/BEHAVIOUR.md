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
   picks an arbitrary CSS selector. the one exception is `FilterList`'s
   `source`, which names the field that carries the query and may be a
   selector or a bare id — a composer textarea a palette filters is a
   plain form control, not a component. the write-back's `data-filter-insert`
   target is always a bare id.

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
| `data-dismiss` | the dismiss affordance a layer closes through (Escape and outside-click ordering); an open-stateful layer is armed only while its `data-open` holder is open | `WebUIDismissible` and overlay components |
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
| `ScrollFollow` (state) | `data-follow-state` | `away` while the reader is detached — the state that shows the jump control (engine-written). evaluated on every patch kind, including appended and streamed-text batches; first bind evaluates the mount position |
| `ScrollKey` | `data-scroll-key` | a per-region key whose scroll position survives a patch |
| `ReadingKeys` | `data-reading-keys` | presence on a focusable (`tabindex="0"`) scrolling region: `ArrowUp`/`PageUp` scroll it, `Home`/`End` go to the top/the bottom, and `Escape` returns to the live tail only while no layer is open. deliberately not a plural of `data-scroll-key` — that name remembers an offset across a patch, this one moves the offset from the keyboard |
| `ScrollTo` | `data-scroll-to` | the element id to scroll to, with the 1.4 s flash contract; an empty value scrolls the document to the top |
| `ScrollTo` (flash) | `data-scroll-flash` | presence while the scroll-to target flashes (engine-written, removed after 1400 ms) |
| `DraftIdentity` | `data-draft-id` | the draft key a control's unsubmitted value is remembered under. **pairing:** the same control may also carry `data-draft-value`, the server-rendered text (`DraftSeed`). on a patch that changes the identity the seed wins — it replaces the field's value and rewrites the store under the new key — because the reader's unsubmitted text belonged to the old draft. on a patch that keeps the identity the reader's keystrokes and the store are left alone, and an empty field still restores from the store. **clear on submit:** a control carrying both `data-clear-on-submit` and this attribute has its store entry (`webui-draft:<identity>`) removed when the form submits, so the replacing patch that answers the submit cannot refill the field from the store — the control and the store are cleared together |
| `DraftSeed` | `data-draft-value` | the server-rendered draft text that seeds the field when the identity changes (see the pairing above). read inside the draft binder — not its own dispatch key. an empty seed clears the field on an identity change, and a seed with no identity on the control is inert: the engine iterates `[data-draft-id]` only |
| `FocusReturn` | `data-focus-return` | the id to return focus to after a patch (empty = the element itself). activation — a click, or `Enter`/`Space` — on an element carrying the attribute records the id it names, keyed by the element's own id, and the record is only strings, so it survives the element's removal; after a patch, an element that carried the attribute and no longer resolves hands focus to the id it named (the "closed by a server round-trip" path, not Escape). covers `button` as well as `[tabindex]`: a focused button replaced by its own region patch is restored by id like any non-input that carries one |
| `FocusInto` | `data-focus-into` | the id to focus inside a region a patch has just inserted or replaced (empty = the region itself). the binder takes focus only while the live one is vacant (`body`/null) or sits **outside** the region — a field the reader is already using inside it is never yanked. a target with no `tabindex` gets `tabindex="-1"`, the same door `data-skip-to` uses, so naming a `div` is not a dead promise. runs in the bind pass (boot, and after every patch that inserts or replaces the region); the `data-focus-return` restore runs after that pass, so a focus-return declaration wins when both would fire |
| `FocusOnAppear` | `data-focus-on-appear` | presence; focus the element and put the caret at the end when it appears — on boot when it is already rendered, and after a patch that inserts or replaces it (a new-chat composer, a form fragment). the guard is stricter than `data-focus-into`'s and deliberately narrower: focus is taken only when **nothing** holds it (`body`/null), so a reader mid-field is never interrupted by a re-render. `preventScroll` keeps a boot-time bind from moving the document. precedence: `data-focus-into` wins when both sit on the same element, and `data-focus-return` wins over both (it restores after the bind pass) |
| `DismissStack` | `data-dismiss` | presence marks a layer; the engine orders Escape and outside-click. **arming:** when the element's open state lives on itself (`data-open`) or on a drawer root that names it (the ancestor whose id a `data-drawer-toggle` in that ancestor's subtree names — a `.drawer` and its `.drawer__panel`), it is a layer only while the holder carries `data-open`: it registers when the holder opens and unregisters when it closes, through one `MutationObserver` on `data-open`. without any holder (a toast, a permanently visible dismissible) the bind-time registration is unchanged, so Escape and outside-click behave exactly as before |
| layer open state | `data-open` | presence while a client-owned panel is open (engine-written). CSS keys on `[data-open]` — never on a class — and the attribute's absence is the closed state. `.combo__panel` is hidden unless it carries the attribute: the field's focus opens it, typing keeps it open, and a selection, `Escape` or an outside click closes it. `.drawer` is the same state one level up: below 860px the root is off-canvas unless it carries the attribute, and the drawer's scrim, its close control and any host `data-drawer-toggle` flip it without a round-trip. not a dispatch key: the binders write it, `closeLayer` clears it |
| `DrawerToggle` | `data-drawer-toggle` | the id of the drawer root a control opens and closes. a click flips `data-open` on `#<id>` with no round-trip: opening moves focus into `.drawer__panel` (its first focusable, else the panel itself through `tabindex="-1"`), and closing returns focus to the toggle that opened the drawer. `preventDefault()` always, so an anchor toggle never navigates; at 861px and wider the control is inert and the drawer keeps its static rail form. the drawer's own scrim and close control carry the attribute too |
| `Reorder` | `data-reorder` | the hidden input id the engine writes the new order into |
| `Clipboard` | `data-copy` | text to copy (empty = the element's own text). a copy control inside a `<summary>` takes the activation: the click copies and does **not** toggle the disclosure — the binder's `preventDefault()` is what keeps the two consequences apart |
| `TableEnhance` | `data-table-enhance` | `sort`, `filter`, or `sort filter` |
| `TableEnhance` (filter) | `data-table-filter` | the filter input inside the enhanced region (engine-read) |
| `FilterList` | `data-filter-list` | presence (the region's own `input`) or the field that carries the query — a selector or a bare id, for a field outside the region. the items `[role=option]` / `[role=menuitem]` / `.command-palette__item` inside the region are filtered by case-insensitive substring, hiding non-matches. a source that does not resolve is inert. **token form:** the value is `prefix\|source` when the region declares a token prefix (`FilterList(source:token:)`, e.g. `/\|#composer`; a prefix with no source is `/\|`, so the two parts are never ambiguous). the query is then the last whitespace-delimited token **before the field's caret** with the prefix stripped, the panel carries `data-open` only while that token starts with the prefix, and a selection replaces that whole token — prefix included — with the template's output. an empty/whitespace token, or one without the prefix, closes the panel and leaves every item visible. a value with no `\|` is the whole-field form above, byte-identical to 2.17.0 |
| `FilterInsert` | `data-filter-insert` | the id of the field a selected item is written into. read inside the filter binder — not its own dispatch key |
| `FilterTemplate` | `data-filter-template` | the text an inserted selection takes; `{value}` is the item's trimmed text, every occurrence replaced. **pairing:** a template with no insert is inert, an insert with no template is inert — the three filter write-back attributes are one consequence |
| `FilterClear` | `data-filter-clear` | presence: before the insert, the engine strips the run of non-whitespace immediately before the destination's caret — the token the reader was typing — and inserts at that point. `selectionStart`/`selectionEnd` place the insert; a field without selection support appends |
| `SkipTarget` | `data-skip-to` | the id a skip link moves focus to |
| `TickingLabel` | `data-reltime` | ms epoch; the relative-time ladder paints the label |
| `TickingLabel` (elapsed) | `data-started` + `data-elapsed` | ms epoch + presence; the elapsed clock paints `floor(s/60):SS` |
| `Disclosure` | `data-preserve-open` | presence marks a `<details>` whose `open` state survives a patch |
| `InlineEdit` | `data-inline-edit` | presence; local edit entry (no round-trip), save through the server |
| `InlineEdit` (mode) | `data-editing` | presence while the control is in local edit mode (engine-written) |
| `Clipboard` (toast) | `data-webui-toast` | the engine-owned toast element a copy consequence mounts (engine-written) |
| `Roving` | `data-roving` | presence; one tab stop for the group, arrow keys move it |
| `Scrollspy` | `data-scrollspy` | presence; the container whose sections the nav highlights |
| `ThemeChoice` | `data-theme-choice` | the chosen mode. **`aria-pressed` is the theme-selected contract:** exactly one button of the toggle carries `aria-pressed="true"`, it tracks `<html data-theme>`, and the engine reconciles it on boot and on every press. hosts key their sheets on `[aria-pressed="true"]` (or the root `data-theme`), never on a server-only class. no-JS/first-paint limitation: the server renders all three `false` and the boot press corrects it |
| form semantics | `data-autogrow`, `data-clear-on-submit` | presence; autogrow, clear on submit |
| form semantics (enter) | `data-submit-on-enter` | the three-value vocabulary: bare (the `SubmitOnEnter()` default, `legacy`) — `Enter` without `Shift` submits a single-line control and a `textarea` stays exempt; `plain` — `Enter` submits and `Shift+Enter` inserts a newline; `meta` — `Meta`/`Ctrl`+`Enter` submits and plain `Enter` inserts a newline. **the one attribute where value and presence do different jobs:** bare is the legacy rule every existing page already has, and a textarea opts in by value, never by presence. an IME composition (`isComposing`, or `keyCode === 229`) never submits in any mode, and `data-prevent-enter="false"` opts out in every mode |
| form semantics (number) | `data-clamp` | `min,max` — the accepted numeric range |
| upload destination | `data-upload-into` | the typed destination as a **relative directory**: `attachments` or `docs/x` (no scheme). the engine composes `<directory>/<name>` into `X-Upload-Path`, and the route's `200 {path}` answer is authoritative |
| upload name template | `data-upload-name-template` | optional filename template the engine resolves before composing the path: `{name}`, `{ext}`, `{ts}`, `{seq}`; unknown tokens stay literal. read inside the upload binder — not its own dispatch key |
| upload route | `data-upload-to` | the route the engine posts the body to (`/upload` by default) |
| upload picker opt-out | `data-no-upload-pick` | presence on a subtree inside a zone: a click there never opens the file picker — for controls that live inside a container zone |
| upload (tray) | `data-webui-upload-tray` | the tray the transport mounts and owns (engine-written) |
| upload (state) | `data-webui-upload-state` | a tray row's state: `uploading`, `done`, `error`, `cancelled` (engine-written) |

the upload rows' transport — the headers, the route's json shape, the tray's
DOM and class contract — is `Documentation/UPLOAD.md`.

## the migration seam

Two engine hooks are the only client seam a consumer may use while adopting
the vocabulary, and both are temporary:

- `WebUIEngine.on.afterPatch(fn)` — called after a fragment patch applies.
- `WebUIEngine.on.ready(fn)` — called once the page is live; with the split
  engine it fires after the extension asset settles (loaded or failed), so a
  behavior never races the first patch.

They are supported through `2.10.0`, deprecated at `3.0.0`, and removed later.
App code must not register on them: they exist for migration and for framework
debugging, and a consumer still relying on one at `3.0.0` has a **capability
request** — a ledger row and a slice — not a supported seam.

## changing the vocabulary

1. add the behavior as a Swift type whose `AttributeRepresentable.name` is the
   attribute, and emit it through `.behavior(_:)`;
2. add the row here;
3. add the name to `BehaviourVocabularyTests.canonical` — the gate pins this
   document against that set. add it to the suite's `dispatched` set **only**
   when the attribute is its own `BEHAVIORS[...]` key: the gate also asserts
   the engine's dispatch keys equal `dispatched`, so a parameter attribute read
   inside another binder (`data-upload-name-template` is read by the upload
   binder) would make that assertion red;
4. run `swift test --filter BehaviourVocabularyTests` — the gate compares the
   engine's attribute set with this document in both directions;
5. ship it in a minor tag and name the attribute in the release note.

A new engine behavior with no row here is a bug, not a feature.
