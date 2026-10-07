import WebUICore

// ============================================================================
// MARK: - Data & rich display extras
// ============================================================================

// MARK: WebUI Calendar
/// a month grid calendar with selectable/today/event days.
public struct WebUICalendar: View {
    public struct Day: Sendable {
        public let num: Int
        public let muted: Bool
        public let selected: Bool
        public let today: Bool
        public let inRange: Bool
        public let events: Int
        public init(_ num: Int, muted: Bool = false, selected: Bool = false, today: Bool = false,
                    inRange: Bool = false, events: Int = 0) {
            self.num = num; self.muted = muted; self.selected = selected; self.today = today
            self.inRange = inRange; self.events = events
        }
    }
    public let month: String
    public let weekdays: [String]
    public let days: [Day]
    /// stable component id — the routing anchor; also prefixes child day ids.
    public let id: String?
    public let onChange: EventHandler?
    public init(month: String, weekdays: [String] = ["S", "M", "T", "W", "T", "F", "S"], days: [Day],
                id: String? = nil, onChange: EventHandler? = nil) {
        self.month = month; self.weekdays = weekdays; self.days = days
        self.id = id; self.onChange = onChange
    }

    public func render() -> String {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onChange) } ?? ""
        var html = Tag.begin("div", Tag.classes(["calendar"]), attrs)
        html += Tag.begin("div", Tag.classes(["calendar__header"]))
        html += Tag.element("div", [Tag.classes(["calendar__month"])], htmlEscape(month))
        html += Tag.begin("div", Tag.classes(["calendar__nav"]))
        html += Tag.element("button", [Tag.attr("aria-label", "Previous")], "‹")
        html += Tag.element("button", [Tag.attr("aria-label", "Next")], "›")
        html += Tag.element("button", [Tag.classes(["calendar__today"])], "Today")
        html += Tag.end("div")
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["calendar__grid"]))
        for wd in weekdays { html += Tag.element("div", [Tag.classes(["calendar__weekday"])], htmlEscape(wd)) }
        for (i, day) in days.enumerated() {
            let dayID = id.map { Tag.escAttr("id", "\($0)-day-\(i)") } ?? ""
            html += Tag.begin("button",
                Tag.classes([
                    "calendar__day",
                    day.muted ? " calendar__day--muted" : "",
                    day.selected ? " calendar__day--selected" : "",
                    day.today ? " calendar__day--today" : "",
                    day.inRange ? " calendar__day--range" : "",
                    day.events > 0 ? " calendar__day--event" : "",
                ]),
                dayID)
            html += "\(day.num)"
            if day.events > 0 {
                html += Tag.begin("span", Tag.classes(["calendar__events"]))
                for _ in 0..<min(day.events, 3) { html += Tag.element("i", [Tag.classes(["calendar__event-dot"])], "") }
                html += Tag.end("span")
            }
            html += Tag.end("button")
        }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Date Picker
/// a compact day-grid date picker.
public struct WebUIDatePicker: View {
    public struct Day: Sendable {
        public let num: Int
        public let muted: Bool
        public let disabled: Bool
        public let selected: Bool
        public let today: Bool
        public let rangeStart: Bool
        public let rangeEnd: Bool
        public let inRange: Bool
        public init(_ num: Int, muted: Bool = false, disabled: Bool = false, selected: Bool = false,
                    today: Bool = false, rangeStart: Bool = false, rangeEnd: Bool = false, inRange: Bool = false) {
            self.num = num; self.muted = muted; self.disabled = disabled; self.selected = selected
            self.today = today; self.rangeStart = rangeStart; self.rangeEnd = rangeEnd; self.inRange = inRange
        }
    }
    public let month: String
    public let weekdays: [String]
    public let days: [Day]
    /// stable component id — the routing anchor; also prefixes child day ids.
    public let id: String?
    public let onChange: EventHandler?
    public init(month: String, weekdays: [String] = ["S", "M", "T", "W", "T", "F", "S"], days: [Day],
                id: String? = nil, onChange: EventHandler? = nil) {
        self.month = month; self.weekdays = weekdays; self.days = days
        self.id = id; self.onChange = onChange
    }

    public func render() -> String {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onChange) } ?? ""
        var html = Tag.begin("div", Tag.classes(["date-picker"]), attrs)
        html += Tag.begin("div", Tag.classes(["date-picker__header"]))
        html += Tag.element("button", [Tag.classes(["date-picker__nav"]), Tag.attr("aria-label", "Previous")], "‹")
        html += Tag.element("div", [Tag.classes(["date-picker__month"])], htmlEscape(month))
        html += Tag.element("button", [Tag.classes(["date-picker__nav"]), Tag.attr("aria-label", "Next")], "›")
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["date-picker__grid"]))
        for wd in weekdays { html += Tag.element("div", [Tag.classes(["date-picker__weekday"])], htmlEscape(wd)) }
        for (i, day) in days.enumerated() {
            let dayID = id.map { Tag.escAttr("id", "\($0)-day-\(i)") } ?? ""
            html += Tag.element("button",
                [Tag.classes([
                    "date-picker__day",
                    day.muted ? " date-picker__day--muted" : "",
                    day.disabled ? " date-picker__day--disabled" : "",
                    day.selected ? " date-picker__day--selected" : "",
                    day.today ? " date-picker__day--today" : "",
                    day.rangeStart ? " date-picker__day--range-start" : "",
                    day.rangeEnd ? " date-picker__day--range-end" : "",
                    day.inRange ? " date-picker__day--in-range" : "",
                ]),
                 dayID,
                 day.disabled ? Tag.flag("disabled") : ""],
                "\(day.num)")
        }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI TimeZone Picker
/// a searchable timezone list.
public struct WebUITimeZonePicker: View {
    public struct Entry: Sendable { public let city: String; public let offset: String; public let selected: Bool
        public init(_ city: String, offset: String, selected: Bool = false) { self.city = city; self.offset = offset; self.selected = selected } }
    public let entries: [Entry]
    /// stable component id — the routing anchor; also prefixes child entry ids.
    public let id: String?
    public let onSelect: EventHandler?
    public init(entries: [Entry], id: String? = nil, onSelect: EventHandler? = nil) {
        self.entries = entries; self.id = id; self.onSelect = onSelect
    }

    public func render() -> String {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onSelect) } ?? ""
        var html = Tag.begin("div", Tag.classes(["tz-picker"]), attrs)
        html += Tag.begin("div", Tag.classes(["tz-picker__search"]))
        html += Tag.void("input", Tag.attr("type", "search"), Tag.attr("placeholder", "Find a timezone…"))
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["tz-picker__list"]))
        for (i, e) in entries.enumerated() {
            let entryID = id.map { Tag.escAttr("id", "\($0)-tz-\(i)") } ?? ""
            html += Tag.element("div",
                [Tag.classes(["tz", e.selected ? " tz--selected" : ""]), entryID],
                Tag.element("span", [Tag.classes(["tz__city"])], htmlEscape(e.city))
                    + Tag.element("span", [Tag.classes(["tz__offset"])], htmlEscape(e.offset)))
        }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Country Picker
/// a searchable country list with flag/code/offset.
public struct WebUICountryPicker: View {
    public struct Entry: Sendable { public let flag: String; public let name: String; public let code: String; public let offset: String
        public init(flag: String, name: String, code: String, offset: String) { self.flag = flag; self.name = name; self.code = code; self.offset = offset } }
    public let entries: [Entry]
    /// stable component id — the routing anchor; also prefixes child row ids.
    public let id: String?
    public let onSelect: EventHandler?
    public init(entries: [Entry], id: String? = nil, onSelect: EventHandler? = nil) {
        self.entries = entries; self.id = id; self.onSelect = onSelect
    }

    public func render() -> String {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onSelect) } ?? ""
        var html = Tag.begin("div", Tag.classes(["country-picker"]), attrs)
        html += Tag.begin("div", Tag.classes(["country-picker__search"]))
        html += Tag.void("input", Tag.attr("type", "search"), Tag.attr("placeholder", "Search countries…"))
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["country-picker__list"]))
        for (i, e) in entries.enumerated() {
            let rowID = id.map { Tag.escAttr("id", "\($0)-row-\(i)") } ?? ""
            html += Tag.begin("div", Tag.classes(["country-picker__row"]), rowID)
            html += Tag.element("span", [Tag.classes(["country-picker__flag"])], htmlEscape(e.flag))
            html += Tag.element("span", [Tag.classes(["country-picker__name"])], htmlEscape(e.name))
            html += Tag.element("span", [Tag.classes(["country-picker__code"])], htmlEscape(e.code))
            html += Tag.element("span", [Tag.classes(["country-picker__offset"])], htmlEscape(e.offset))
            html += Tag.end("div")
        }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Gantt
/// a timeline gantt view with task bars.
public struct WebUIGantt: View {
    public struct Bar: Sendable { public let label: String; public let start: Int; public let span: Int; public let state: String
        public init(_ label: String, start: Int, span: Int, state: String = "") { self.label = label; self.start = start; self.span = span; self.state = state } }
    public struct Row: Sendable { public let label: String; public let bars: [Bar]
        public init(_ label: String, bars: [Bar]) { self.label = label; self.bars = bars } }
    public let rows: [Row]
    public init(rows: [Row]) { self.rows = rows }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["gantt"]))
        html += Tag.begin("div", Tag.classes(["gantt__header"]))
        html += Tag.element("div", [Tag.classes(["gantt__label-col"])], "Tasks")
        html += Tag.element("div", [Tag.classes(["gantt__week"])], "")
        html += Tag.end("div")
        for row in rows {
            html += Tag.begin("div", Tag.classes(["gantt__row"]))
            html += Tag.element("div", [Tag.classes(["gantt__label-col gantt__label"])], htmlEscape(row.label))
            html += Tag.begin("div", Tag.classes(["gantt__track"]))
            for bar in row.bars {
                // the empty state keeps its trailing space — byte-pinned by the base capture
                html += Tag.element("div",
                    [Tag.classes(["gantt__bar", " " + bar.state]),
                     Tag.attr("style", "margin-left:\(bar.start * 10)%;width:\(bar.span)px")],
                    Tag.element("span", [Tag.classes(["gantt__bar-label"])], htmlEscape(bar.label)))
            }
            html += Tag.end("div")
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Kanban
/// a column-based kanban board.
public struct WebUIKanban: View {
    public struct Card: Sendable { public let title: String; public let meta: String; public let tags: [String]; public let wip: Bool
        public init(_ title: String, meta: String = "", tags: [String] = [], wip: Bool = false) { self.title = title; self.meta = meta; self.tags = tags; self.wip = wip } }
    public struct Column: Sendable { public let title: String; public let cards: [Card]
        public init(_ title: String, cards: [Card]) { self.title = title; self.cards = cards } }
    public let columns: [Column]
    public init(columns: [Column]) { self.columns = columns }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["kanban"]))
        for column in columns {
            html += Tag.begin("div", Tag.classes(["kanban__column"]))
            html += Tag.begin("div", Tag.classes(["kanban__header"]))
            html += htmlEscape(column.title)
            html += Tag.element("span", [Tag.classes(["kanban__count"])], "\(column.cards.count)")
            html += Tag.end("div")
            html += Tag.begin("div", Tag.classes(["kanban__body"]))
            for card in column.cards {
                html += Tag.begin("div", Tag.classes(["kanban__card", card.wip ? " kanban__card--wip" : ""]))
                html += htmlEscape(card.title)
                if !card.tags.isEmpty {
                    html += Tag.begin("div", Tag.classes(["kanban__card-tags"]))
                    for (i, tag) in card.tags.enumerated() {
                        let variant = ["kanban__card-tag--blue", "kanban__card-tag--amber", "kanban__card-tag--violet"][i % 3]
                        html += Tag.element("span", [Tag.classes(["kanban__card-tag", variant])], htmlEscape(tag))
                    }
                    html += Tag.end("div")
                }
                if !card.meta.isEmpty {
                    html += Tag.begin("div", Tag.classes(["kanban__card-foot"]))
                    html += Tag.element("span", [Tag.classes(["kanban__card-meta"])], htmlEscape(card.meta))
                    html += Tag.end("div")
                }
                html += Tag.end("div")
            }
            html += Tag.end("div")
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Data Sheet
/// a spreadsheet-style grid with a formula bar.
public struct WebUIDataSheet: View {
    public struct Cell: Sendable { public let ref: String; public let value: String; public let num: Bool; public let selected: Bool
        public init(_ ref: String, _ value: String, num: Bool = false, selected: Bool = false) { self.ref = ref; self.value = value; self.num = num; self.selected = selected } }
    public let cells: [Cell]
    public init(cells: [Cell]) { self.cells = cells }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["sheet"]))
        html += Tag.begin("div", Tag.classes(["sheet__formula"]))
        html += Tag.element("span", [Tag.classes(["sheet__cellref"])], "Fx")
        html += Tag.element("span", [Tag.classes(["sheet__formula-input"])], "")
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["sheet__grid"]))
        html += Tag.begin("div", Tag.classes(["sheet__row"]))
        html += Tag.element("span", [Tag.classes(["sheet__corner"])], "")
        for col in ["A", "B", "C", "D", "E"] { html += Tag.element("span", [Tag.classes(["sheet__colhead"])], col) }
        html += Tag.end("div")
        for cell in cells {
            html += Tag.element("div",
                [Tag.classes(["sheet__cell",
                              cell.num ? " sheet__cell--num" : "",
                              cell.selected ? " sheet__cell--selected" : ""]),
                 Tag.escAttr("data-ref", cell.ref)],
                htmlEscape(cell.value))
        }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Json Tree
/// a collapsible JSON viewer.
public struct WebUIJsonTree: View {
    public struct Node: Sendable { public let key: String; public let value: String; public let type: String; public let open: Bool; public let children: [Node]
        public init(_ key: String, value: String, type: String = "str", open: Bool = false, children: [Node] = []) { self.key = key; self.value = value; self.type = type; self.open = open; self.children = children } }
    public let nodes: [Node]
    public init(nodes: [Node]) { self.nodes = nodes }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["json-tree"]))
        for node in nodes { html += renderNode(node) }
        html += Tag.end("div")
        return html
    }

    private func renderNode(_ node: Node) -> String {
        let openClass = node.open ? " json-tree__node--open" : ""
        var html = Tag.begin("div", Tag.classes(["json-tree__node", openClass]))
        html += Tag.begin("div", Tag.classes(["json-tree__row"]))
        if !node.children.isEmpty { html += Tag.element("span", [Tag.classes(["json-tree__toggle"])], "") }
        html += Tag.element("span", [Tag.classes(["json-tree__key"])], htmlEscape(node.key))
        html += Tag.element("span", [Tag.classes(["json-tree__punct"])], ": ")
        if node.children.isEmpty {
            html += Tag.element("span", [Tag.classes(["json-tree__\(node.type)"])], htmlEscape(node.value))
        }
        html += Tag.end("div")
        if !node.children.isEmpty {
            html += Tag.begin("div", Tag.classes(["json-tree__children"]))
            for child in node.children { html += renderNode(child) }
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Diff
/// a unified diff view.
public struct WebUIDiff: View {
    public struct Line: Sendable { public let kind: String; public let num: Int; public let text: String
        public init(_ kind: String, num: Int, text: String) { self.kind = kind; self.num = num; self.text = text } }
    public let file: String
    public let stats: String
    public let lines: [Line]
    public init(file: String, stats: String = "", lines: [Line]) { self.file = file; self.stats = stats; self.lines = lines }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["diff"]))
        html += Tag.begin("div", Tag.classes(["diff__header"]))
        html += Tag.element("span", [Tag.classes(["diff__file"])], htmlEscape(file))
        if !stats.isEmpty { html += Tag.element("span", [Tag.classes(["diff__stats"])], htmlEscape(stats)) }
        html += Tag.end("div")
        for line in lines {
            var mods = ""
            switch line.kind {
            case "add": mods = " diff__line--add"
            case "del": mods = " diff__line--del"
            case "hunk": mods = " diff__line--hunk"
            default: mods = " diff__line--ctx"
            }
            html += Tag.begin("div", Tag.classes(["diff__line", mods]))
            html += Tag.element("span", [Tag.classes(["diff__lineno"])], "\(line.num)")
            html += Tag.element("span", [Tag.classes(["diff__content"])], htmlEscape(line.text))
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Terminal
/// a terminal window with a title bar and output lines.
public struct WebUITerminal: View {
    public struct Line: Sendable { public let kind: String; public let text: String
        public init(_ kind: String, text: String) { self.kind = kind; self.text = text } }
    public let title: String
    public let lines: [Line]
    public init(title: String = "terminal", lines: [Line]) { self.title = title; self.lines = lines }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["terminal"]))
        html += Tag.begin("div", Tag.classes(["terminal__bar"]))
        html += Tag.element("span", [Tag.classes(["terminal__dot terminal__dot--r"])], "")
        html += Tag.element("span", [Tag.classes(["terminal__dot terminal__dot--y"])], "")
        html += Tag.element("span", [Tag.classes(["terminal__dot terminal__dot--g"])], "")
        html += Tag.element("span", [Tag.classes(["terminal__title"])], htmlEscape(title))
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["terminal__body"]))
        for line in lines {
            var mods = ""
            switch line.kind {
            case "ok": mods = " terminal__line--ok"
            case "warn": mods = " terminal__line--warn"
            case "err": mods = " terminal__line--err"
            default: break
            }
            html += Tag.element("div", [Tag.classes(["terminal__line", mods])], htmlEscape(line.text))
        }
        html += Tag.begin("div", Tag.classes(["terminal__line"]))
        html += Tag.element("span", [Tag.classes(["terminal__prompt"])], "$ ")
        html += Tag.element("span", [Tag.classes(["terminal__cmd"])], "")
        html += Tag.end("div")
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Code Block
/// a code block with a language bar.
public struct WebUICodeBlock: View {
    public let language: String
    public let code: String
    public init(_ code: String, language: String = "swift") { self.code = code; self.language = language }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["codeblock"]))
        html += Tag.begin("div", Tag.classes(["codeblock__bar"]))
        html += Tag.element("span", [Tag.classes(["codeblock__lang"])], htmlEscape(language))
        html += Tag.element("button", [Tag.classes(["code__copy"]), Tag.attr("aria-label", "Copy")], "copy")
        html += Tag.end("div")
        html += Tag.begin("pre", Tag.classes(["codeblock__code"]))
        html += Tag.element("code", [], htmlEscape(code))
        html += Tag.end("pre")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Bar Chart
/// a simple CSS-bar chart.
public struct WebUIBarChart: View {
    public struct Series: Sendable { public let label: String; public let value: Double; public let accent: Bool
        public init(_ label: String, value: Double, accent: Bool = false) { self.label = label; self.value = value; self.accent = accent } }
    public let series: [Series]
    public init(series: [Series]) { self.series = series }

    public func render() -> String {
        let maxV = series.map(\.value).max() ?? 1
        var html = Tag.begin("div", Tag.classes(["bar-chart"]))
        for s in series {
            let h = Int((s.value / maxV) * 100.0)
            html += Tag.begin("div", Tag.classes(["bar-chart__col"]))
            html += Tag.element("div",
                [Tag.classes(["bar-chart__bar", s.accent ? " bar-chart__bar--accent" : ""]),
                 Tag.attr("style", "height:\(h)%")],
                "")
            html += Tag.element("span", [Tag.classes(["bar-chart__label"])], htmlEscape(s.label))
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Line Chart
/// a lightweight inline-SVG line chart.
public struct WebUILineChart: View {
    public struct Point: Sendable { public let x: Double; public let y: Double; public let label: String
        public init(_ x: Double, _ y: Double, label: String = "") { self.x = x; self.y = y; self.label = label } }
    public let points: [Point]
    public init(points: [Point]) { self.points = points }

    public func render() -> String {
        let w = 320.0, h = 120.0, pad = 8.0
        guard points.count > 1 else {
            return Tag.element("div", [Tag.classes(["line-chart"])], Tag.element("svg", [Tag.attr("viewBox", "0 0 \(Int(w)) \(Int(h))")], ""))
        }
        let xs = points.map(\.x); let ys = points.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        let rangeX = max(maxX - minX, 1e-9), rangeY = max(maxY - minY, 1e-9)
        let coords = points.map { p in
            (pad + ((p.x - minX) / rangeX) * (w - 2 * pad),
             h - pad - ((p.y - minY) / rangeY) * (h - 2 * pad))
        }
        let lineStr = coords.map { "\(Int($0.0)),\(Int($0.1))" }.joined(separator: " ")
        var html = Tag.begin("div", Tag.classes(["line-chart"]))
        html += Tag.begin("svg", Tag.attr("viewBox", "0 0 \(Int(w)) \(Int(h))"), Tag.attr("role", "img"), Tag.attr("aria-hidden", "true"))
        html += Tag.element("polyline", [Tag.classes(["line-chart__line"]), Tag.attr("points", lineStr)], "")
        for c in coords {
            html += Tag.element("circle",
                [Tag.classes(["line-chart__dot"]),
                 Tag.attr("cx", "\(Int(c.0))"), Tag.attr("cy", "\(Int(c.1))"), Tag.attr("r", "3")],
                "")
        }
        html += Tag.end("svg")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Donut
/// a donut chart with a center value.
public struct WebUIDonut: View {
    public struct Slice: Sendable { public let label: String; public let value: Double; public let color: String
        public init(_ label: String, value: Double, color: String) { self.label = label; self.value = value; self.color = color } }
    public let slices: [Slice]
    public let centerValue: String
    public let centerLabel: String
    public init(slices: [Slice], centerValue: String, centerLabel: String = "") {
        self.slices = slices; self.centerValue = centerValue; self.centerLabel = centerLabel
    }

    public func render() -> String {
        let total = max(slices.map(\.value).reduce(0, +), 1e-9)
        var segments: [String] = []
        var acc = 0.0
        for s in slices {
            let start = acc / total * 360.0
            let end = (acc + s.value) / total * 360.0
            segments.append("\(htmlEscape(s.color)) \(webuiFixedPoint(start, places: 1))deg \(webuiFixedPoint(end, places: 1))deg")
            acc += s.value
        }
        let conic = "conic-gradient(\(segments.joined(separator: ", ")))"
        var html = Tag.begin("div", Tag.classes(["donut"]), Tag.attr("style", "background:\(conic)"))
        html += Tag.begin("div", Tag.classes(["donut__center"]))
        html += Tag.element("div", [Tag.classes(["donut__center-value"])], htmlEscape(centerValue))
        if !centerLabel.isEmpty { html += Tag.element("div", [Tag.classes(["donut__center-label"])], htmlEscape(centerLabel)) }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Masonry
/// a masonry grid of media/content cards.
public struct WebUIMasonry: View {
    public struct Item: Sendable { public let title: String; public let meta: String; public let accent: Bool
        public init(_ title: String, meta: String = "", accent: Bool = false) { self.title = title; self.meta = meta; self.accent = accent } }
    public let items: [Item]
    public init(items: [Item]) { self.items = items }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["masonry"]))
        for item in items {
            html += Tag.begin("div", Tag.classes(["masonry__item", item.accent ? " masonry__item--accent" : ""]))
            html += Tag.element("div", [Tag.classes(["masonry__title"])], htmlEscape(item.title))
            if !item.meta.isEmpty { html += Tag.element("div", [Tag.classes(["masonry__meta"])], htmlEscape(item.meta)) }
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Map
/// a stylised map with pins and a popup.
public struct WebUIMap: View {
    public struct Pin: Sendable { public let label: String; public let x: Double; public let y: Double; public let active: Bool
        public init(_ label: String, x: Double, y: Double, active: Bool = false) { self.label = label; self.x = x; self.y = y; self.active = active } }
    public let pins: [Pin]
    public init(pins: [Pin]) { self.pins = pins }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["map"]))
        html += Tag.element("div", [Tag.classes(["map__grid"])], "")
        for i in 0..<3 { html += Tag.element("div", [Tag.classes(["map__road map__road--h"]), Tag.attr("style", "top:\(25 + i * 25)%")], "") }
        for i in 0..<4 { html += Tag.element("div", [Tag.classes(["map__road map__road--v"]), Tag.attr("style", "left:\(10 + i * 20)%")], "") }
        for pin in pins {
            html += Tag.element("div",
                [Tag.classes(["map__pin", pin.active ? " map__pin--active" : ""]),
                 Tag.attr("style", "left:\(Int(pin.x))%;top:\(Int(pin.y))%"),
                 Tag.escAttr("aria-label", pin.label)],
                htmlEscape(String(pin.label.prefix(1))))
            if pin.active {
                html += Tag.begin("div", Tag.classes(["map__popup"]), Tag.attr("style", "left:\(Int(pin.x))%;top:\(Int(pin.y))%"))
                html += Tag.element("span", [Tag.classes(["map__popup-arrow"])], "")
                html += htmlEscape(pin.label)
                html += Tag.end("div")
            }
        }
        html += Tag.element("div", [Tag.classes(["map__attribution"])], "map")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Qr
/// a deterministic QR-style matrix.
public struct WebUIQr: View {
    public let data: String
    public let label: String?
    public init(_ data: String, label: String? = nil) { self.data = data; self.label = label }

    public func render() -> String {
        var seed = 0
        for b in data.utf8 { seed = seed &* 31 &+ Int(b) }
        var html = Tag.begin("div", Tag.classes(["qr"]))
        html += Tag.begin("div", Tag.classes(["qr__code"]))
        let size = 11
        var state = seed
        for _ in 0..<(size * size) {
            state = (state &* 1103515245 &+ 12345) & 0x7fffffff
            html += Tag.element("span", [Tag.classes(["qr__cell", state % 2 == 0 ? " qr__cell--on" : ""])], "")
        }
        html += Tag.end("div")
        if let label { html += Tag.element("div", [Tag.classes(["qr__label"])], htmlEscape(label)) }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Pay Card
/// a payment card preview.
public struct WebUIPayCard: View {
    public enum Brand: String, Sendable { case visa, mc, amex }
    public let number: String
    public let holder: String
    public let brand: Brand
    public init(number: String, holder: String, brand: Brand = .visa) { self.number = number; self.holder = holder; self.brand = brand }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["paycard"]))
        html += Tag.begin("div", Tag.classes(["paycard__top"]))
        html += Tag.element("span", [Tag.classes(["paycard__brand"])], htmlEscape(brand.rawValue.uppercased()))
        html += Tag.element("span", [Tag.classes(["paycard__chip"])], "")
        html += Tag.end("div")
        html += Tag.element("div", [Tag.classes(["paycard__number"])], htmlEscape(number))
        html += Tag.begin("div", Tag.classes(["paycard__row"]))
        html += Tag.element("div", [Tag.classes(["paycard__label"])], "Card holder")
        html += Tag.element("div", [Tag.classes(["paycard__value"])], htmlEscape(holder))
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}
