import Foundation
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
    public init(month: String, weekdays: [String] = ["S", "M", "T", "W", "T", "F", "S"], days: [Day]) {
        self.month = month; self.weekdays = weekdays; self.days = days
    }

    public func render() -> String {
        var html = "<div class=\"calendar\">"
        html += "<div class=\"calendar__header\">"
        html += "<div class=\"calendar__month\">\(htmlEscape(month))</div>"
        html += "<div class=\"calendar__nav\"><button aria-label=\"Previous\">‹</button><button aria-label=\"Next\">›</button><button class=\"calendar__today\">Today</button></div>"
        html += "</div>"
        html += "<div class=\"calendar__grid\">"
        for wd in weekdays { html += "<div class=\"calendar__weekday\">\(htmlEscape(wd))</div>" }
        for day in days {
            var cls = "calendar__day"
            if day.muted { cls += " calendar__day--muted" }
            if day.selected { cls += " calendar__day--selected" }
            if day.today { cls += " calendar__day--today" }
            if day.inRange { cls += " calendar__day--range" }
            if day.events > 0 { cls += " calendar__day--event" }
            html += "<button class=\"\(cls)\">\(day.num)"
            if day.events > 0 {
                html += "<span class=\"calendar__events\">"
                for _ in 0..<min(day.events, 3) { html += "<i class=\"calendar__event-dot\"></i>" }
                html += "</span>"
            }
            html += "</button>"
        }
        html += "</div></div>"
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
    public init(month: String, weekdays: [String] = ["S", "M", "T", "W", "T", "F", "S"], days: [Day]) {
        self.month = month; self.weekdays = weekdays; self.days = days
    }

    public func render() -> String {
        var html = "<div class=\"date-picker\">"
        html += "<div class=\"date-picker__header\"><button class=\"date-picker__nav\" aria-label=\"Previous\">‹</button>"
        html += "<div class=\"date-picker__month\">\(htmlEscape(month))</div>"
        html += "<button class=\"date-picker__nav\" aria-label=\"Next\">›</button></div>"
        html += "<div class=\"date-picker__grid\">"
        for wd in weekdays { html += "<div class=\"date-picker__weekday\">\(htmlEscape(wd))</div>" }
        for day in days {
            var cls = "date-picker__day"
            if day.muted { cls += " date-picker__day--muted" }
            if day.disabled { cls += " date-picker__day--disabled" }
            if day.selected { cls += " date-picker__day--selected" }
            if day.today { cls += " date-picker__day--today" }
            if day.rangeStart { cls += " date-picker__day--range-start" }
            if day.rangeEnd { cls += " date-picker__day--range-end" }
            if day.inRange { cls += " date-picker__day--in-range" }
            html += "<button class=\"\(cls)\"\(day.disabled ? " disabled" : "")>\(day.num)</button>"
        }
        html += "</div></div>"
        return html
    }
}

// MARK: WebUI TimeZone Picker
/// a searchable timezone list.
public struct WebUITimeZonePicker: View {
    public struct Entry: Sendable { public let city: String; public let offset: String; public let selected: Bool
        public init(_ city: String, offset: String, selected: Bool = false) { self.city = city; self.offset = offset; self.selected = selected } }
    public let entries: [Entry]
    public init(entries: [Entry]) { self.entries = entries }

    public func render() -> String {
        var html = "<div class=\"tz-picker\">"
        html += "<div class=\"tz-picker__search\"><input type=\"search\" placeholder=\"Find a timezone…\"></div>"
        html += "<div class=\"tz-picker__list\">"
        for e in entries {
            html += "<div class=\"tz\(e.selected ? " tz--selected" : "")\"><span class=\"tz__city\">\(htmlEscape(e.city))</span><span class=\"tz__offset\">\(htmlEscape(e.offset))</span></div>"
        }
        html += "</div></div>"
        return html
    }
}

// MARK: WebUI Country Picker
/// a searchable country list with flag/code/offset.
public struct WebUICountryPicker: View {
    public struct Entry: Sendable { public let flag: String; public let name: String; public let code: String; public let offset: String
        public init(flag: String, name: String, code: String, offset: String) { self.flag = flag; self.name = name; self.code = code; self.offset = offset } }
    public let entries: [Entry]
    public init(entries: [Entry]) { self.entries = entries }

    public func render() -> String {
        var html = "<div class=\"country-picker\">"
        html += "<div class=\"country-picker__search\"><input type=\"search\" placeholder=\"Search countries…\"></div>"
        html += "<div class=\"country-picker__list\">"
        for e in entries {
            html += "<div class=\"country-picker__row\"><span class=\"country-picker__flag\">\(htmlEscape(e.flag))</span>"
            html += "<span class=\"country-picker__name\">\(htmlEscape(e.name))</span>"
            html += "<span class=\"country-picker__code\">\(htmlEscape(e.code))</span>"
            html += "<span class=\"country-picker__offset\">\(htmlEscape(e.offset))</span></div>"
        }
        html += "</div></div>"
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
        var html = "<div class=\"gantt\">"
        html += "<div class=\"gantt__header\"><div class=\"gantt__label-col\">Tasks</div><div class=\"gantt__week\"></div></div>"
        for row in rows {
            html += "<div class=\"gantt__row\"><div class=\"gantt__label-col gantt__label\">\(htmlEscape(row.label))</div><div class=\"gantt__track\">"
            for bar in row.bars {
                html += "<div class=\"gantt__bar \(bar.state)\" style=\"margin-left:\(bar.start * 10)%;width:\(bar.span)px\"><span class=\"gantt__bar-label\">\(htmlEscape(bar.label))</span></div>"
            }
            html += "</div></div>"
        }
        html += "</div>"
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
        var html = "<div class=\"kanban\">"
        for column in columns {
            html += "<div class=\"kanban__column\"><div class=\"kanban__header\">\(htmlEscape(column.title))<span class=\"kanban__count\">\(column.cards.count)</span></div><div class=\"kanban__body\">"
            for card in column.cards {
                html += "<div class=\"kanban__card\(card.wip ? " kanban__card--wip" : "")\">\(htmlEscape(card.title))"
                if !card.tags.isEmpty {
                    html += "<div class=\"kanban__card-tags\">"
                    for (i, tag) in card.tags.enumerated() {
                        let variant = ["kanban__card-tag--blue", "kanban__card-tag--amber", "kanban__card-tag--violet"][i % 3]
                        html += "<span class=\"kanban__card-tag \(variant)\">\(htmlEscape(tag))</span>"
                    }
                    html += "</div>"
                }
                if !card.meta.isEmpty { html += "<div class=\"kanban__card-foot\"><span class=\"kanban__card-meta\">\(htmlEscape(card.meta))</span></div>" }
                html += "</div>"
            }
            html += "</div></div>"
        }
        html += "</div>"
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
        var html = "<div class=\"sheet\">"
        html += "<div class=\"sheet__formula\"><span class=\"sheet__cellref\">Fx</span><span class=\"sheet__formula-input\"></span></div>"
        html += "<div class=\"sheet__grid\">"
        html += "<div class=\"sheet__row\"><span class=\"sheet__corner\"></span>"
        for col in ["A", "B", "C", "D", "E"] { html += "<span class=\"sheet__colhead\">\(col)</span>" }
        html += "</div>"
        for cell in cells {
            html += "<div class=\"sheet__cell\(cell.num ? " sheet__cell--num" : "")\(cell.selected ? " sheet__cell--selected" : "")\" data-ref=\"\(htmlEscape(cell.ref))\">\(htmlEscape(cell.value))</div>"
        }
        html += "</div></div>"
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
        var html = "<div class=\"json-tree\">"
        for node in nodes { html += renderNode(node) }
        html += "</div>"
        return html
    }

    private func renderNode(_ node: Node) -> String {
        let openClass = node.open ? " json-tree__node--open" : ""
        var html = "<div class=\"json-tree__node\(openClass)\">"
        html += "<div class=\"json-tree__row\">"
        if !node.children.isEmpty { html += "<span class=\"json-tree__toggle\"></span>" }
        html += "<span class=\"json-tree__key\">\(htmlEscape(node.key))</span><span class=\"json-tree__punct\">: </span>"
        if node.children.isEmpty {
            html += "<span class=\"json-tree__\(node.type)\">\(htmlEscape(node.value))</span>"
        }
        html += "</div>"
        if !node.children.isEmpty {
            html += "<div class=\"json-tree__children\">"
            for child in node.children { html += renderNode(child) }
            html += "</div>"
        }
        html += "</div>"
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
        var html = "<div class=\"diff\">"
        html += "<div class=\"diff__header\"><span class=\"diff__file\">\(htmlEscape(file))</span>"
        if !stats.isEmpty { html += "<span class=\"diff__stats\">\(htmlEscape(stats))</span>" }
        html += "</div>"
        for line in lines {
            var cls = "diff__line"
            switch line.kind {
            case "add": cls += " diff__line--add"
            case "del": cls += " diff__line--del"
            case "hunk": cls += " diff__line--hunk"
            default: cls += " diff__line--ctx"
            }
            html += "<div class=\"\(cls)\"><span class=\"diff__lineno\">\(line.num)</span><span class=\"diff__content\">\(htmlEscape(line.text))</span></div>"
        }
        html += "</div>"
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
        var html = "<div class=\"terminal\">"
        html += "<div class=\"terminal__bar\"><span class=\"terminal__dot terminal__dot--r\"></span><span class=\"terminal__dot terminal__dot--y\"></span><span class=\"terminal__dot terminal__dot--g\"></span><span class=\"terminal__title\">\(htmlEscape(title))</span></div>"
        html += "<div class=\"terminal__body\">"
        for line in lines {
            var cls = "terminal__line"
            switch line.kind {
            case "ok": cls += " terminal__line--ok"
            case "warn": cls += " terminal__line--warn"
            case "err": cls += " terminal__line--err"
            default: break
            }
            html += "<div class=\"\(cls)\">\(htmlEscape(line.text))</div>"
        }
        html += "<div class=\"terminal__line\"><span class=\"terminal__prompt\">$ </span><span class=\"terminal__cmd\"></span></div>"
        html += "</div></div>"
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
        var html = "<div class=\"codeblock\">"
        html += "<div class=\"codeblock__bar\"><span class=\"codeblock__lang\">\(htmlEscape(language))</span><button class=\"code__copy\" aria-label=\"Copy\">copy</button></div>"
        html += "<pre class=\"codeblock__code\"><code>\(htmlEscape(code))</code></pre>"
        html += "</div>"
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
        var html = "<div class=\"bar-chart\">"
        for s in series {
            let h = Int((s.value / maxV) * 100.0)
            html += "<div class=\"bar-chart__col\"><div class=\"bar-chart__bar\(s.accent ? " bar-chart__bar--accent" : "")\" style=\"height:\(h)%\"></div><span class=\"bar-chart__label\">\(htmlEscape(s.label))</span></div>"
        }
        html += "</div>"
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
            return "<div class=\"line-chart\"><svg viewBox=\"0 0 \(Int(w)) \(Int(h))\"></svg></div>"
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
        var html = "<div class=\"line-chart\"><svg viewBox=\"0 0 \(Int(w)) \(Int(h))\" role=\"img\" aria-hidden=\"true\">"
        html += "<polyline class=\"line-chart__line\" points=\"\(lineStr)\"></polyline>"
        for c in coords { html += "<circle class=\"line-chart__dot\" cx=\"\(Int(c.0))\" cy=\"\(Int(c.1))\" r=\"3\"></circle>" }
        html += "</svg></div>"
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
            segments.append("\(htmlEscape(s.color)) \(String(format: "%.1f", start))deg \(String(format: "%.1f", end))deg")
            acc += s.value
        }
        let conic = "conic-gradient(\(segments.joined(separator: ", ")))"
        var html = "<div class=\"donut\" style=\"background:\(conic)\">"
        html += "<div class=\"donut__center\"><div class=\"donut__center-value\">\(htmlEscape(centerValue))</div>"
        if !centerLabel.isEmpty { html += "<div class=\"donut__center-label\">\(htmlEscape(centerLabel))</div>" }
        html += "</div></div>"
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
        var html = "<div class=\"masonry\">"
        for item in items {
            html += "<div class=\"masonry__item\(item.accent ? " masonry__item--accent" : "")\">"
            html += "<div class=\"masonry__title\">\(htmlEscape(item.title))</div>"
            if !item.meta.isEmpty { html += "<div class=\"masonry__meta\">\(htmlEscape(item.meta))</div>" }
            html += "</div>"
        }
        html += "</div>"
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
        var html = "<div class=\"map\">"
        html += "<div class=\"map__grid\"></div>"
        for i in 0..<3 { html += "<div class=\"map__road map__road--h\" style=\"top:\(25 + i * 25)%\"></div>" }
        for i in 0..<4 { html += "<div class=\"map__road map__road--v\" style=\"left:\(10 + i * 20)%\"></div>" }
        for pin in pins {
            html += "<div class=\"map__pin\(pin.active ? " map__pin--active" : "")\" style=\"left:\(Int(pin.x))%;top:\(Int(pin.y))%\" aria-label=\"\(htmlEscape(pin.label))\">\(htmlEscape(String(pin.label.prefix(1))))</div>"
            if pin.active {
                html += "<div class=\"map__popup\" style=\"left:\(Int(pin.x))%;top:\(Int(pin.y))%\"><span class=\"map__popup-arrow\"></span>\(htmlEscape(pin.label))</div>"
            }
        }
        html += "<div class=\"map__attribution\">map</div>"
        html += "</div>"
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
        var html = "<div class=\"qr\"><div class=\"qr__code\">"
        let size = 11
        var state = seed
        for _ in 0..<(size * size) {
            state = (state &* 1103515245 &+ 12345) & 0x7fffffff
            html += "<span class=\"qr__cell\(state % 2 == 0 ? " qr__cell--on" : "")\"></span>"
        }
        html += "</div>"
        if let label { html += "<div class=\"qr__label\">\(htmlEscape(label))</div>" }
        html += "</div>"
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
        var html = "<div class=\"paycard\">"
        html += "<div class=\"paycard__top\"><span class=\"paycard__brand\">\(htmlEscape(brand.rawValue.uppercased()))</span><span class=\"paycard__chip\"></span></div>"
        html += "<div class=\"paycard__number\">\(htmlEscape(number))</div>"
        html += "<div class=\"paycard__row\"><div class=\"paycard__label\">Card holder</div><div class=\"paycard__value\">\(htmlEscape(holder))</div></div>"
        html += "</div>"
        return html
    }
}
