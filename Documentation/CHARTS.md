# WebUIChart — charting

server-rendered charts for the swiftui-for-web stack. `WebUIChart` is a
self-contained Swift target (depends only on `WebUI`): a `Chart` view takes a
collection of marks, resolves scales, and emits **inline SVG** wrapped in a
`<figure class="chart">` — no canvas, no client-side chart library, no
network fetches.

the design goal is a modern Swift Charts surface (the 2nd/3rd-generation API:
`SectorMark`, selection state, `.foregroundStyle(by:)` series, axis label
formats) with a first-class web output format. everything the renderer emits
goes through the same security invariants as the rest of the framework:
attribute/text escaping, sanitized ids, no comments or scripts in the payload.

## the `Chart` view

```swift
Chart(marks)
    .chartTitle("Quarterly sales")
    .chartXAxis(AxisConfig(showsGridLines: true, labelFormat: .automatic))
    .chartYScale(.linear(domain: 0...28))
    .chartLegend(position: .bottom)
    .chartID("sales")                      // enables interactive marks
    .chartSelection(axis: .x, value: .category("Jan"))
    .chartAccessibilityLabel("Bar chart of quarterly sales")
    .render()                              // -> String (a <figure>)
```

or, the Swift Charts style — marks built with the concrete initializers and
grouped with `ForEach` / `Group` (both compose because `ChartContent: View`):

```swift
Chart {
    ForEach(data) { d in
        BarMark(x: .value("Month", d.month), y: .value("Sales", d.sales))
            .foregroundStyle(by: d.product)
    }
}.render()
```

`Chart` conforms to `View`; `render()` returns the full figure HTML.
An empty mark list renders a designed empty state (`.chart--empty`), not a
blank box.

## marks

| mark | data | notes |
|------|------|-------|
| `BarMark(x:y:)` | categorical or linear x | grouped / stacked / centered; corner radius; bar width `.fixed`/`.ratio`/`.automatic` |
| `LineMark(x:y:)` | per-series polyline | interpolation, line style, `.symbol` for inline points |
| `AreaMark(x:y:)` | filled to the zero baseline | shares the series' interpolation |
| `PointMark(x:y:symbol:)` | scatter | circle / square / triangle / diamond / cross / star / pentagon |
| `RectangleMark(xStart:xEnd:yStart:yEnd:value:)` | data-space cell | heatmaps; `value` (0…1) drives `fill-opacity` heat |
| `RuleMark(x:y:)` | reference line | horizontal (x nil) or vertical (y nil) |
| `SectorMark(angle:category:)` | pie / donut | `innerRadiusRatio` → donut (center total overlay); `angularInset` gaps; 12-o'clock start, clockwise |

marks carry a `PlottableValue` per dimension: `.value("label", 42)`,
`.value("label", "Q1")` (category), `.value("label", Date(...))`, or
`yStart`/`yEnd` ranges (error bands, ranges). `AngleMark`-style polar data uses
the same plottables through `SectorMark(angle:)`.

### mark modifiers (Swift Charts parity)

```swift
.foregroundStyle(by: "series")      // categorical series → palette slot + legend
.foregroundStyle("var(--x)")        // explicit color (a css var reference)
.opacity(0.5)
.cornerRadius(6)
.stacking(.normal | .unstacked | .centered)
.interpolation(.linear | .monotone | .cardinal(t) | .catmullRom | .stepStart | .stepEnd)
.symbol(.circle | .square | ...)
.lineStyle(ChartLineStyle(width: 2, dash: [4, 2]))
.annotation("text", position: .top) // svg <text> label (escaped)
```

modifiers return a styled `ChartMark`, so they chain on any `*Mark` and work
inside `ForEach`.

## scales and axes

- **x**: categorical (auto from string data, or `.categorical(domain:)` to
  order/extend), `.linear(domain:)`, `.date(domain:)` (unix-ref seconds on the
  numeric axis, formatted labels), `.automatic`.
- **y**: always numeric. bars/areas pin the baseline to `0` when all data is
  non-negative; a 5% headroom extends the top. override with `.chartYScale` /
  `.chartYDomain`.
- **ticks**: nice-number algorithm (`1/2/5 × 10^k`), in-domain filtering, or
  `AxisConfig(explicitValues:)`.
- **label formats**: `.automatic` `.integer` `.decimal(n)` `.percent`
  `.currency("USD")` `.numberCompact` `.hidden` `.dateTime(.short/.monthYear/
  .weekday)` — per axis via `AxisConfig(labelFormat:)`.

## selection and interactivity

charts are **server-rendered**; interactivity rides the existing WebSocket
event system. the preferred path is the typed `.onSelectMark` handler — the
chart wires each painted mark as its own routed component under a stable id
(`{chartID}-mark-<category>-<series>` for bars, `{chartID}-mark-<i>` for
sectors) and delivers the clicked category directly:

```swift
Chart(marks)
    .chartID("chart")
    .chartSelection(axis: .x, value: .category(sel ?? ""))
    .onSelectMark { me, category in
        state.selected = (state.selected == category) ? nil : category
        return [me.replace(with: chartHTML(state: state))]
    }
```

`me` references the chart root (the `<figure>` carrying `chartID`), so the
handler patches the chart in place with zero id strings. re-rendered figures
re-emit the same stable mark ids, so the page-build registrations keep routing.

the legacy container pattern still works unchanged: wrap the figure in a div
with `.onClick(id: "chart")` and parse `event.data["targetId"]` (prefix
`chart-mark-`, first segment = category).

the selection also has Swift-Charts-style convenience modifiers:
`.chartXSelection(value:)` / `.chartYSelection(value:)` (category or number),
and the polar chart-level controls `.chartInnerRadius(0…1)` and
`.chartAngularInset(degrees)` (per-mark values win).

notes:

- the anchor element that carries `data-component-id` must **not** be the
  element the fragment replaces (the patcher replaces the named element
  wholesale). patch the inner figure by its `.chartID` instead.
- the runtime's event delegation walks `parentNode` (not `parentElement`), so
  clicks landing on inner `<svg>` elements bubble to HTML containers.
- `.chartSelection(axis:value:)` draws a selection indicator (axis line for
  cartesian, highlighted sector for polar) on the server-rendered frame.
- hover feedback is pure CSS (`.chart__mark:hover`); no client JS.

## theming

the design system owns all chart styling (see `DESIGN_SYSTEM.md → Charts`):

- `--color-chart-1 … --color-chart-8` — categorical palette (remapped lighter
  in dark mode for contrast);
- `.chart__c1 … .chart__c8` — palette slots; a mark's class references the
  slot, and an explicit `.foregroundStyle("…")` wins via an inline
  `--chart-mark-color` variable;
- grid/baseline/axis/legend/annotation/donut-center/empty-state classes are
  all `.chart__*` (BEM), consuming `--color-*`, `--space-*`, `--font-*`
  tokens — no raw values in the chart css.

angle convention: `0°` = 12 o'clock, clockwise (matches Swift Charts).

## a11y and payload hygiene

- every figure is `<figure role="img" aria-label="…">`; labels, titles and
  mark ids are `htmlEscape`-ed; `chartID` values are sanitized (spaces
  stripped) before use in ids;
- a visually-hidden data table (`.chart__sr`) mirrors the series values so
  screen readers get the numbers, not just the shapes;
- the output is deterministic (no random nonces inside the chart) and
  comment-free — it ships in the page body like any other view.

## limits

- one series dimension (`.foregroundStyle(by:)`); multi-series grouping on the
  x-axis is not modeled (series stack/group within a category only);
- linear and categorical scales; log/normalised scales are rejected at render
  time (empty chart, not garbage);
- no client-side redraw: every state change re-renders the figure on the
  server (the same model as the interactive table).
