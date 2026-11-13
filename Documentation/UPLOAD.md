# the upload contract

the framework owns the wire and the tray. it does not own storage, quotas, or a
filesystem layout — a route decides what a destination means and where a byte
lands (plan §22.3, risk 4). a page that drops a `WebUIDropZone` on itself
uploads with **zero consumer JavaScript**: the engine ships the transport, the
progress tray and the paste/directory inputs, and a host handler answers
`upload-complete` with `.refresh`.

## the typed destination

```swift
WebUIDropZone("Drop a file here", destination: .folder(path: "docs"), id: "upload-a")
```

`UploadDestination` (`WebUICore`) is a value, not a string convention:

| case | `data-upload-into` | `X-Upload-Path` |
|---|---|---|
| `.attachments` | `attachments` | `attachments` |
| `.folder(path: "docs/x")` | `folder:docs/x` | `folder:docs/x` |

the engine never parses a destination out of a url, a class name or a header it
invented: `WebUIDropZone` serializes the value to `data-upload-into`, and the
transport sends that same text as `X-Upload-Path`. the attribute is declared in
`Documentation/BEHAVIOUR.md` like every other behavior name.

the zone also carries:

- `data-upload-to` — the route it posts to (`route:`, default `/upload`);
- `data-component-id` + `data-event="upload-complete"` when `id:` is set. the
  declared event is the one the component accepts, so a DOM click on the zone is
  never routed as an event of its own.

## the wire

one `POST` per file, over `XMLHttpRequest` (progress requires it — `fetch` has
no upload progress event):

| header | value |
|---|---|
| `X-Render-Token` | `RuntimeConfig.renderToken` — the render the page was minted for, so the server binds the frame to that session |
| `X-Upload-Name` | the file's name, verbatim |
| `X-Upload-Path` | the destination text (`attachments`, `folder:<path>`) |

the body is the file itself. `Content-Type` is the file's own type, set by the
browser from the `File` — the engine does not override it. the engine does
**not** set `Origin`: that header is browser-owned, and a browser sends it on a
same-origin POST by itself. a route that wants the check can compare it to
`Host` when it is present (the smoke host's `/upload/contract` does).

the route answers json, verbatim:

```json
{"ok":true,"path":"folder:docs","name":"note.txt","bytes":12}
```

or, for a refusal the route itself decided:

```json
{"ok":false,"error":"missing X-Upload-Name header"}
```

a body over the route's `limit:` is refused by the framework **before** the
handler runs — status `413` with its own text body
(`413 — request body too large: Route.upload(limit:) is N bytes; received M`).
that is the server's error, not a second policy: the engine renders whatever
text came back. on success it dispatches a typed frame:

```json
{"type":"event","component":"<the zone's data-component-id>","event":"upload-complete","data":{"name":"note.txt","path":"folder:docs","bytes":"12"},"token":"<render token>"}
```

a host handler registered for that component returns `.refresh` and the server
re-renders the session's page, patching what moved. nothing client-side
synthesises a click, and nothing client-side decides what the page now shows.

## the inputs

all three feed the one route, with the same headers:

1. **file picker** — a click (or Enter/Space) on the zone opens its hidden
   `input[type=file]`; `change` uploads every selected file.
2. **paste** — a `paste` on the zone uploads every `image/*` file the clipboard
   carries. the zone is focusable (`tabindex="0"`), so click-then-paste targets
   the destination the reader chose. the native clipboard path is a manual pass
   per browser (see the probe note below).
3. **directory drop** — `drop` reads `DataTransferItem.webkitGetAsEntry()`;
   a directory is walked recursively (`createReader().readEntries()` until an
   empty batch), and every file it yields uploads into the same destination.
   a browser without the entry api falls back to `dataTransfer.files`.

## the tray

the transport mounts one tray on `document.body` and appends one row per file.
the DOM is the contract:

```html
<div class="upload-tray" data-webui-upload-tray role="status" aria-live="polite">
  <div class="upload-tray__row" data-webui-upload-state="uploading|done|error|cancelled">
    <span class="upload-tray__name">note.txt</span>
    <span class="upload-tray__status">uploading…</span>
    <button class="upload-tray__cancel" type="button">Cancel</button>
    <div class="upload-tray__track"><div class="upload-tray__bar" style="width:42%"></div></div>
  </div>
</div>
```

- `data-webui-upload-tray` and `data-webui-upload-state` are engine-written; both
  are named in `Documentation/BEHAVIOUR.md`.
- the bar's `width` is the only inline style — a progress value, never a colour.
  every colour, radius, space and font size comes from the sheet's tokens, so the
  tray follows the active theme in all 27 schemes.
- the cancel button aborts the request (`XMLHttpRequest.abort()`); the row then
  reads `cancelled` and keeps whatever progress it had.
- an error row carries the route's own `error` text, or the server's non-2xx body
  verbatim. the transport never invents a message it did not receive, except
  `HTTP <status>` when the body is empty and `network error` when no answer
  arrived at all.

## what a host must do

1. serve a route that reads the body (streaming or buffered) and answers the json
   shape above — `Route.upload(_:limit:handler:)` is the streaming door;
2. register one handler for the zone's component id that stores what it needs and
   returns `.refresh`;
3. link the design-system sheet (the default `WebUIDocument` does) so the tray
   inherits the theme.

no script tag, no `upload.js`, no token meta: `RuntimeConfig.renderToken` is the
one token source.
