import Foundation
import WebUI
import WebUIDesignSystem
import WebUIChart

// MARK: - Showcase Page
struct ShowcasePage {
    func render() -> String {
        let router = EventRouter()
        let ctx = RenderContext(router: router)
        return RenderContext.$current.withValue(ctx) {
            VStack(spacing: 0) {
                topBar()
                Div(class: "showcase-shell") {
                    HStack(alignment: .top, spacing: 0) {
                        sidebar()
                        mainContent()
                    }
                }
            }.render()
        }
    }

    // MARK: - Top Bar
    func topBar() -> some View {
        Header(class: "showcase-header") {
            HStack(alignment: .center, spacing: 16) {
                Heading("WebUI UI Showcase", level: .h1).class("showcase-title")
                Span(class: "showcase-badge") { Text("v1.0") }
                Spacer()
                Span(class: "showcase-status") { Text("connected").id("ws-status") }
            }.padding(horizontal: 24, vertical: 12)
        }
    }

    // MARK: - Sidebar
    func sidebar() -> some View {
        Navigation(class: "showcase-sidebar") {
            VStack(spacing: 4) {
                sidebarLink("Typography", "#typography")
                sidebarLink("Layout", "#layout")
                sidebarLink("Forms & Input", "#forms")
                sidebarLink("Buttons", "#buttons")
                sidebarLink("Media", "#media")
                sidebarLink("Lists & Tables", "#lists")
                sidebarLink("Data & Navigation", "#data-nav")
                sidebarLink("Semantic HTML", "#semantic")
                sidebarLink("Modifiers", "#modifiers")
                sidebarLink("Design System", "#design-system")
                sidebarLink("Event Handling", "#events")
                sidebarLink("Charts", "#charts")
                sidebarLink("CSS Theme", "#theme")
                sidebarLink("Icons", "#icons")
            }.padding(16)
        }
    }

    func sidebarLink(_ label: String, _ href: String) -> some View {
        Link(label, href: href).class("showcase-sidebar-link").display("block").padding(horizontal: 12, vertical: 6)
    }

    // MARK: - Main Content
    func mainContent() -> some View {
        return Main(class: "showcase-content") {
            VStack(spacing: 32) {
                // 1. Typography
                section("Typography", "typography") {
                    VStack(spacing: 16) {
                        Heading("Text renders escaped content", level: .h2)
                        demoCard("Text View") {
                            VStack(spacing: 8) {
                                Text("Plain text content")
                                Text("<script>alert('xss')</script>").class("text-escaped")
                            }
                        }
                        demoCard("Heading Levels") {
                            VStack(spacing: 8) {
                                Heading("Heading 1", level: .h1)
                                Heading("Heading 2", level: .h2)
                                Heading("Heading 3", level: .h3)
                                Heading("Heading 4", level: .h4)
                                Heading("Heading 5", level: .h5)
                                Heading("Heading 6", level: .h6)
                            }
                        }
                        demoCard("Paragraph & Link") {
                            VStack(spacing: 8) {
                                Paragraph("This is a paragraph of text demonstrating the Paragraph view.")
                                Link("Visit Example.com", href: "https://example.com", target: .blank, rel: [.noopener, .noreferrer])
                                Paragraph("A link with custom target and rel attributes.")
                            }
                        }
                        demoCard("Raw HTML") {
                            Raw("<div style=\"padding:12px;background:var(--color-bg-inset);border:1px solid var(--color-border);border-radius:8px;\">Raw HTML content — <strong>not escaped</strong></div>")
                        }
                    }
                }

                // 2. Layout
                section("Layout", "layout") {
                    VStack(spacing: 16) {
                        Heading("VStack, HStack, ZStack, Grid, ScrollView", level: .h2)
                        demoCard("VStack (vertical stack)") {
                            VStack(alignment: .center, spacing: 8) {
                                div("Item 1", "demo-box")
                                div("Item 2", "demo-box")
                                div("Item 3", "demo-box")
                            }
                        }
                        demoCard("HStack (horizontal stack)") {
                            HStack(alignment: .center, spacing: 12) {
                                div("A", "demo-box")
                                div("B", "demo-box")
                                div("C", "demo-box")
                            }
                        }
                        demoCard("ZStack (overlay)") {
                            ZStack(alignment: .center, verticalAlignment: .center) {
                                div("Back", "demo-box demo-box--large")
                                Span(class: "demo-overlay") { Text("overlay") }
                            }
                        }
                        demoCard("Grid") {
                            Grid(columns: .fraction(3), spacing: 12) {
                                div("1", "demo-box")
                                div("2", "demo-box")
                                div("3", "demo-box")
                                div("4", "demo-box")
                                div("5", "demo-box")
                                div("6", "demo-box")
                            }
                        }
                        demoCard("ScrollView") {
                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(0..<20) { i in
                                        div("Item \(i + 1)", "demo-box")
                                    }
                                }
                            }.height("200px")
                        }
                        demoCard("Spacer") {
                            HStack(spacing: 0) {
                                div("Left", "demo-box")
                                Spacer(minSize: 8)
                                div("Right", "demo-box")
                            }.width("100%")
                        }
                        demoCard("Section with semantic elements") {
                            Section(class: "demo-section") {
                                Heading("Section Title", level: .h3)
                                Paragraph("Content inside a semantic section element.")
                            }
                        }
                    }
                }

                // 3. Forms & Input
                section("Forms & Input", "forms") {
                    VStack(spacing: 16) {
                        Heading("All input types, textarea, select, form with CSRF", level: .h2)
                        demoCard("Input Types") {
                            VStack(spacing: 12) {
                                Label("Text:").class("demo-label")
                                Input(id: "demo-text", placeholder: "Enter text", type: .text)
                                Label("Email:").class("demo-label")
                                Input(id: "demo-email", placeholder: "user@example.com", type: .email)
                                Label("Password:").class("demo-label")
                                Input(id: "demo-password", placeholder: "••••••••", type: .password)
                                Label("Number:").class("demo-label")
                                Input(id: "demo-number", placeholder: "0", type: .number)
                                Label("Search:").class("demo-label")
                                Input(id: "demo-search", placeholder: "Search...", type: .search)
                                Label("Telephone:").class("demo-label")
                                Input(id: "demo-tel", placeholder: "+1 (555) 000-0000", type: .tel)
                                Label("URL:").class("demo-label")
                                Input(id: "demo-url", placeholder: "https://", type: .url)
                                Label("Date:").class("demo-label")
                                Input(id: "demo-date", type: .date)
                                Label("Color:").class("demo-label")
                                Input(id: "demo-color", type: .color)
                                Label("Range:").class("demo-label")
                                Input(id: "demo-range", type: .range)
                                Label("File:").class("demo-label")
                                Input(id: "demo-file", type: .file)
                                Label("Checkbox:").class("demo-label")
                                Input(id: "demo-checkbox", type: .checkbox)
                                Label("Radio:").class("demo-label")
                                Input(id: "demo-radio", type: .radio)
                                Label("Disabled & Required:").class("demo-label")
                                Input(id: "demo-disabled", placeholder: "Can't touch this", disabled: true, required: true)
                            }
                        }
                        demoCard("TextArea") {
                            VStack(spacing: 8) {
                                Label("Bio:").class("demo-label")
                                TextArea(id: "demo-bio", placeholder: "Tell us about yourself...", rows: 4)
                            }
                        }
                        demoCard("Select") {
                            VStack(spacing: 8) {
                                Label("Country:").class("demo-label")
                                Select(
                                    id: "demo-country",
                                    options: [
                                        SelectOption(value: "us", label: "United States"),
                                        SelectOption(value: "ca", label: "Canada"),
                                        SelectOption(value: "uk", label: "United Kingdom"),
                                        SelectOption(value: "de", label: "Germany"),
                                        SelectOption(value: "jp", label: "Japan"),
                                    ],
                                    selected: "us"
                                )
                            }
                        }
                        demoCard("Form with CSRF") {
                            Form(
                                action: "/submit",
                                method: "post",
                                id: "demo-form",
                                csrfToken: CSRFProtection.token(for: "demo-form", secret: "showcase-secret")
                            ) {
                                VStack(spacing: 12) {
                                    Label("Name:").class("demo-label")
                                    Input(id: "form-name", placeholder: "Your name", type: .text)
                                    Label("Message:").class("demo-label")
                                    TextArea(id: "form-message", placeholder: "Your message", rows: 3)
                                    Button("Submit", id: "form-submit", type: .submit)
                                }
                            }
                        }
                        demoCard("Custom Attributes") {
                            Input(
                                id: "demo-attrs",
                                placeholder: "Custom attributes",
                                type: .text,
                                attributes: [
                                    ("data-custom", "value"),
                                    ("aria-label", "Custom input"),
                                ]
                            )
                        }
                    }
                }

                // 4. Buttons
                section("Buttons", "buttons") {
                    VStack(spacing: 16) {
                        Heading("Button with all types", level: .h2)
                        demoCard("Button Types") {
                            HStack(spacing: 12) {
                                Button("Submit", class: "button button--primary", type: .submit)
                                Button("Button", class: "button button--secondary", type: .button)
                                Button("Reset", class: "button button--ghost", type: .reset)
                            }
                        }
                        demoCard("Button States") {
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    Button("Normal", id: "btn-normal", class: "button button--primary", type: .button)
                                    Button("Disabled", class: "button button--primary", type: .button, disabled: true)
                                }
                                HStack(spacing: 12) {
                                    Button("Named", class: "button button--danger", type: .button, name: "action")
                                }
                            }
                        }
                    }
                }

                // 5. Media
                section("Media", "media") {
                    VStack(spacing: 16) {
                        Heading("Media — self-contained, CSP-friendly", level: .h2)
                        demoCard("Inline SVG placeholder") {
                            VStack(spacing: 8) {
                                Raw(placeholderSVG())
                                Paragraph("Self-contained inline SVG — no network requests, safe under the document's content-security-policy.")
                            }
                        }
                        demoCard("Image with sanitized URL") {
                            VStack(spacing: 8) {
                                Image(
                                    src: "javascript:alert('xss')",
                                    alt: "javascript: URLs are stripped — only the alt text renders"
                                ).class("demo-image demo-image--sanitized")
                                Paragraph("The source URL above is rejected by sanitizeURL(), so the framework renders a safe img without a src. Only http(s) and other vetted schemes ever reach the DOM.")
                            }
                        }
                    }
                }

                // 6. Lists & Tables
                section("Lists & Tables", "lists") {
                    VStack(spacing: 16) {
                        Heading("Unordered, ordered lists, and tables", level: .h2)
                        demoCard("Unordered List") {
                            UnorderedList(class: "demo-list") {
                                Text("First item")
                                Text("Second item")
                                Text("Third item")
                            }
                        }
                        demoCard("Ordered List") {
                            OrderedList(class: "demo-list") {
                                Text("Step one")
                                Text("Step two")
                                Text("Step three")
                            }
                        }
                        demoCard("Table — wrapped, numeric columns, footer") {
                            WebUITable(
                                headers: ["Name", "Role", "Status", "Requests"],
                                rows: [
                                    [Text("Alice Chen"), Text("Admin"), Text("Active"), Text("1,204")],
                                    [Text("Bob Marsh"), Text("Editor"), Text("Active"), Text("842")],
                                    [Text("Charlie Ito"), Text("Viewer"), Text("Idle"), Text("118")],
                                    [Text("Dana Fox"), Text("Editor"), Text("Suspended"), Text("67")],
                                ],
                                wrapped: true,
                                alignments: [.leading, .leading, .center, .trailing],
                                footer: [Text("Total"), Text(""), Text(""), Text("2,231")]
                            )
                        }
                        demoCard("Table — compact density") {
                            WebUITable(
                                headers: ["Service", "Region", "Latency (p95)"],
                                rows: [
                                    [Text("api-gateway"), Text("us-east-1"), Text("42 ms")],
                                    [Text("billing"), Text("eu-west-1"), Text("188 ms")],
                                    [Text("search"), Text("us-west-2"), Text("61 ms")],
                                    [Text("auth"), Text("us-east-1"), Text("23 ms")],
                                    [Text("notifications"), Text("ap-south-1"), Text("104 ms")],
                                ],
                                compact: true,
                                alignments: [.leading, .leading, .trailing]
                            )
                        }
                        demoCard("Table — empty state") {
                            WebUITable(
                                headers: ["Name", "Age", "City"],
                                rows: [],
                                emptyState: .init(
                                    icon: .search,
                                    title: "No people match this filter",
                                    message: "Clear the search box or try a different region."
                                )
                            )
                        }
                        demoCard("Table — responsive (stacks on narrow screens)") {
                            WebUITable(
                                headers: ["Order", "Item", "Price"],
                                rows: [
                                    [Text("#4821"), Text("Mechanical keyboard"), Text("$149.00")],
                                    [Text("#4822"), Text("USB-C dock"), Text("$89.00")],
                                ],
                                responsive: true,
                                wrapped: true,
                                alignments: [.leading, .leading, .trailing]
                            )
                        }
                        demoCard("Table — interactive (sortable · selectable · expandable)") {
                            // Static reference render of the interactive affordances.
                            // Live round-trips (sort toggle, select-all, expand)
                            // are proven on the full-stack smoke page — the
                            // showcase has no WebSocket backend.
                            WebUITable(
                                headers: ["Service", "Region", "p95"],
                                rows: [
                                    [Text("web"), Text("us-east-1"), Text("42 ms")],
                                    [Text("api"), Text("eu-west-2"), Text("18 ms")],
                                    [Text("search"), Text("us-west-2"), Text("61 ms")],
                                ],
                                wrapped: true,
                                alignments: [.leading, .leading, .trailing],
                                id: "demo-interactive",
                                sortableColumns: [0, 1, 2],
                                sort: (column: 2, direction: .descending),
                                selectable: true,
                                rowIds: ["web", "api", "search"],
                                selectedRows: ["search"],
                                expandedRows: ["web"],
                                rowDetails: [
                                    "web": Text("8 instances · 99.98% SLA · canary 10% to v2.14"),
                                    "api": Text("4 instances · 99.95% SLA · zero-downtime deploys"),
                                ]
                            )
                        }
                    }
                }

                // 6b. Data & Navigation
                section("Data & Navigation", "data-nav") {
                    VStack(spacing: 16) {
                        Heading("Data & navigation primitives", level: .h2)

                        demoCard("Stat — KPI with trend + sparkline") {
                            HStack {
                                WebUIStat(label: "Requests", value: "12.4M", size: .lg,
                                          trend: "+8.1%", trendDirection: .up,
                                          compare: "vs last week",
                                          spark: [3, 5, 4, 8, 7, 10, 12])
                                WebUIStat(label: "p95 latency", value: "42ms",
                                          trend: "-3.2%", trendDirection: .up,
                                          compare: "faster")
                                WebUIStat(label: "Errors", value: "0.2%", size: .sm,
                                          trend: "+0.1%", trendDirection: .down)
                            }
                        }

                        demoCard("Pagination — windowed, page 5 of 12") {
                            WebUIPagination(page: 5, pages: 12, id: "demo-pg",
                                            rowsPerPage: 25)
                        }

                        demoCard("Timeline — vertical + horizontal") {
                            VStack(spacing: 16) {
                                WebUITimeline(events: [
                                    WebUITimeline.Event(time: "14:02", title: "Build passed", desc: "main · 389 tests", status: .completed),
                                    WebUITimeline.Event(time: "14:05", title: "Deploying", desc: "canary 10%", status: .current),
                                    WebUITimeline.Event(time: "14:06", title: "Rollout scheduled", status: .plain),
                                ])
                                WebUITimeline(events: [
                                    WebUITimeline.Event(time: "Q1", title: "Planned", status: .completed),
                                    WebUITimeline.Event(time: "Q2", title: "In progress", status: .current),
                                    WebUITimeline.Event(time: "Q3", title: "Review", status: .plain),
                                    WebUITimeline.Event(time: "Q4", title: "Launch", status: .plain),
                                ], orientation: .horizontal)
                            }
                        }

                        demoCard("Tree — file explorer (server-driven open/selection)") {
                            WebUITree(nodes: [
                                WebUITree.Node(id: "src", label: "src", icon: .folder, children: [
                                    WebUITree.Node(id: "main", label: "main.swift", icon: .fileText),
                                    WebUITree.Node(id: "ui", label: "ui", icon: .folder, children: [
                                        WebUITree.Node(id: "view", label: "view.swift", icon: .fileText),
                                        WebUITree.Node(id: "state", label: "state.swift", icon: .fileText),
                                    ]),
                                ]),
                                WebUITree.Node(id: "tests", label: "tests", icon: .folder, children: [
                                    WebUITree.Node(id: "smoke", label: "smoke.swift", icon: .fileText),
                                ]),
                            ], id: "demo-tree", expanded: ["src", "ui"], selected: "view")
                        }

                        demoCard("Breadcrumb — collapsed + short trail") {
                            VStack(spacing: 12) {
                                WebUIBreadcrumb(items: [
                                    WebUIBreadcrumb.Item("Home", href: "/"),
                                    WebUIBreadcrumb.Item("Projects", href: "/projects"),
                                    WebUIBreadcrumb.Item("Design", href: "/design"),
                                    WebUIBreadcrumb.Item("Components", href: "/components"),
                                    WebUIBreadcrumb.Item("Tables", href: "/tables"),
                                ], current: WebUIBreadcrumb.Item("Interactive"))
                                WebUIBreadcrumb(items: [
                                    WebUIBreadcrumb.Item("Docs", href: "/docs"),
                                ], current: WebUIBreadcrumb.Item("API Reference"), slash: true)
                            }
                        }

                        demoCard("Description list — canonical expanded-row payload") {
                            WebUIDescriptionList([
                                ("Status", "Active"),
                                ("Region", "us-east-1"),
                                ("Instances", "8"),
                                ("SLA", "99.98%"),
                            ])
                        }
                    }
                }

                // 7. Semantic HTML
                section("Semantic HTML", "semantic") {
                    VStack(spacing: 16) {
                        Heading("Semantic HTML5 elements", level: .h2)
                        demoCard("Navigation") {
                            Navigation(class: "demo-nav") {
                                Link("Home", href: "/")
                                Link("About", href: "/about")
                                Link("Contact", href: "/contact")
                            }
                        }
                        demoCard("Header / Footer / Main / Aside") {
                            VStack(spacing: 8) {
                                Header(class: "demo-semantic") { Text("Header content") }
                                Main(class: "demo-semantic") { Text("Main content area") }
                                Aside(class: "demo-semantic") { Text("Sidebar content") }
                                Footer(class: "demo-semantic") { Text("Footer content") }
                            }
                        }
                        demoCard("Div / Span") {
                            VStack(spacing: 8) {
                                Div(class: "demo-box") {
                                    Span(class: "demo-highlight") { Text("Span inside a Div") }
                                }
                            }
                        }
                    }
                }

                // 8. Modifiers
                section("Modifiers", "modifiers") {
                    VStack(spacing: 16) {
                        Heading("All modifier methods demonstrated", level: .h2)
                        demoCard("Background & Foreground") {
                            Text("Colored text")
                                .backgroundColor("#f0f9ff")
                                .foregroundColor("#1e40af")
                                .padding(12)
                        }
                        demoCard("Typography Modifiers") {
                            VStack(spacing: 8) {
                                Text("Font size 24, weight bold")
                                    .font(size: 24, weight: "bold")
                                Text("Custom font family")
                                    .fontFamily("Georgia, serif")
                                Text("Right-aligned text")
                                    .textAlign("right")
                                    .width("100%")
                                    .display("block")
                            }
                        }
                        demoCard("Spacing Modifiers") {
                            VStack(spacing: 8) {
                                Text("Padding 20px all sides")
                                    .padding(20)
                                    .backgroundColor("#f0fdf4")
                                Text("Padding horizontal 32, vertical 16")
                                    .padding(horizontal: 32, vertical: 16)
                                    .backgroundColor("#fefce8")
                                Text("Margin 24px")
                                    .margin(24)
                                    .backgroundColor("#fef2f2")
                            }
                        }
                        demoCard("Dimension Modifiers") {
                            VStack(spacing: 8) {
                                Text("Width 300px, height 60px")
                                    .width("300px")
                                    .height("60px")
                                    .backgroundColor("#f5f3ff")
                                Text("Max width 400px")
                                    .maxWidth("400px")
                                    .backgroundColor("#ecfdf5")
                            }
                        }
                        demoCard("Border Modifiers") {
                            VStack(spacing: 8) {
                                Text("Solid border")
                                    .border("2px solid #3b82f6")
                                    .padding(12)
                                Text("Rounded corners")
                                    .border("1px solid #d1d5db")
                                    .cornerRadius("8px")
                                    .padding(12)
                            }
                        }
                        demoCard("Layout Modifiers") {
                            VStack(spacing: 8) {
                                Text("Flex item")
                                    .display("flex")
                                    .flex("1")
                                    .backgroundColor("#f0f9ff")
                                    .padding(12)
                            }
                        }
                        demoCard("Conditional Display (showIf)") {
                            HStack(spacing: 12) {
                                Text("Always visible").padding(12).backgroundColor("#dcfce7")
                                Text("Hidden").showIf(false).padding(12).backgroundColor("#fee2e2")
                                Text("Visible").showIf(true).padding(12).backgroundColor("#dcfce7")
                            }
                        }
                        demoCard("HTML Attributes (id, class)") {
                            Text("Custom ID and class")
                                .id("custom-element")
                                .class("highlight-box")
                                .padding(12)
                                .backgroundColor("#fffbeb")
                        }
                        demoCard("Chained Modifiers") {
                            Text("Chained: font → padding → background → border → corner radius")
                                .font(size: 18, weight: "600")
                                .padding(16)
                                .backgroundColor("#f0f9ff")
                                .border("1px solid #93c5fd")
                                .cornerRadius("12px")
                                .width("100%")
                                .display("block")
                        }
                    }
                }

                // 9. Design System
                section("Design System", "design-system") {
                    VStack(spacing: 16) {
                        Heading("All 16 WebUI components", level: .h2)

                        demoCard("WebUIButton — all variants") {
                            VStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    WebUIButton("Primary", variant: .primary, size: .md)
                                    WebUIButton("Secondary", variant: .secondary, size: .md)
                                    WebUIButton("Outline", variant: .outline, size: .md)
                                    WebUIButton("Ghost", variant: .ghost, size: .md)
                                }
                                HStack(spacing: 8) {
                                    WebUIButton("Danger", variant: .danger, size: .md)
                                    WebUIButton("Success", variant: .success, size: .md)
                                    WebUIButton("Warning", variant: .warning, size: .md)
                                }
                            }
                        }
                        demoCard("WebUIButton — all sizes") {
                            HStack(alignment: .center, spacing: 8) {
                                WebUIButton("Small", variant: .primary, size: .sm)
                                WebUIButton("Medium", variant: .primary, size: .md)
                                WebUIButton("Large", variant: .primary, size: .lg)
                            }
                        }
                        demoCard("WebUIButton — states") {
                            HStack(spacing: 8) {
                                WebUIButton("Disabled", variant: .primary, disabled: true)
                                WebUIButton("Full Width", variant: .primary, fullWidth: true).width("300px")
                                WebUIButton("Loading", variant: .primary, loading: true)
                            }
                        }
                        demoCard("WebUIInput — all states") {
                            VStack(spacing: 12) {
                                WebUIInput(placeholder: "Normal input", state: .normal)
                                WebUIInput(placeholder: "Error state", state: .error)
                                WebUIInput(placeholder: "Success state", state: .success)
                                WebUIInput(placeholder: "Warning state", state: .warning)
                                WebUIInput(placeholder: "Disabled input", disabled: true)
                                WebUIInput(placeholder: "With label", label: "Username")
                                WebUIInput(placeholder: "With help text", helpText: "Must be at least 3 characters")
                                WebUIInput(placeholder: "Email type", type: .email, label: "Email")
                            }
                        }
                        demoCard("WebUICard — all variants") {
                            VStack(spacing: 12) {
                                WebUICard(variant: .elevated) {
                                    VStack(spacing: 8) {
                                        Heading("Elevated Card", level: .h3)
                                        Paragraph("This card has a shadow/elevation effect.")
                                    }.padding(16)
                                }
                                WebUICard(variant: .outlined) {
                                    VStack(spacing: 8) {
                                        Heading("Outlined Card", level: .h3)
                                        Paragraph("This card has a border outline.")
                                    }.padding(16)
                                }
                                WebUICard(variant: .flat) {
                                    VStack(spacing: 8) {
                                        Heading("Flat Card", level: .h3)
                                        Paragraph("This card has no shadow or border.")
                                    }.padding(16)
                                }
                                WebUICard(variant: .interactive) {
                                    VStack(spacing: 8) {
                                        Heading("Interactive Card", level: .h3)
                                        Paragraph("Hover over this card.")
                                    }.padding(16)
                                }.id("card-interactive")
                            }
                        }
                        demoCard("WebUIBadge — all variants and sizes") {
                            VStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    WebUIBadge("Primary", variant: .primary)
                                    WebUIBadge("Secondary", variant: .secondary)
                                    WebUIBadge("Success", variant: .success)
                                    WebUIBadge("Warning", variant: .warning)
                                    WebUIBadge("Danger", variant: .danger)
                                    WebUIBadge("Info", variant: .info)
                                    WebUIBadge("Neutral", variant: .neutral)
                                }
                                HStack(alignment: .center, spacing: 8) {
                                    WebUIBadge("SM", variant: .primary, size: .sm)
                                    WebUIBadge("MD", variant: .primary, size: .md)
                                    WebUIBadge("LG", variant: .primary, size: .lg)
                                }
                                HStack(spacing: 8) {
                                    WebUIBadge("With dot", variant: .success, dot: true)
                                    WebUIBadge("Alert", variant: .danger, dot: true)
                                }
                            }
                        }
                        demoCard("WebUIAlert — all variants") {
                            VStack(spacing: 12) {
                                WebUIAlert(variant: .info, message: "This is an informational alert.")
                                WebUIAlert(variant: .success, message: "Operation completed successfully!")
                                WebUIAlert(variant: .warning, message: "Please review your input before continuing.")
                                WebUIAlert(variant: .danger, message: "An error occurred while processing your request.")
                            }
                        }
                        demoCard("WebUIAlert — with title and dismissible") {
                            VStack(spacing: 12) {
                                WebUIAlert(variant: .info, title: "Heads up!", message: "This alert has a title and can be dismissed.", dismissible: true)
                                WebUIAlert(variant: .warning, title: "Warning", message: "Dismissible warning alert.", dismissible: true)
                            }
                        }
                        demoCard("WebUITabs") {
                            WebUITabs(
                                tabs: [
                                    TabItem(id: "tab-overview", label: "Overview"),
                                    TabItem(id: "tab-details", label: "Details"),
                                    TabItem(id: "tab-settings", label: "Settings"),
                                ],
                                activeTab: "tab-overview",
                                id: "demo-tabs"
                            )
                        }
                        demoCard("WebUIAvatar — all sizes") {
                            HStack(alignment: .center, spacing: 16) {
                                WebUIAvatar(initials: "TS", size: .sm)
                                WebUIAvatar(initials: "TS", size: .md)
                                WebUIAvatar(initials: "TS", size: .lg)
                                WebUIAvatar(initials: "TS", size: .xl)
                            }
                        }
                        demoCard("WebUIAvatar — with status indicator") {
                            HStack(spacing: 16) {
                                WebUIAvatar(initials: "JD", size: .lg, status: "online")
                                WebUIAvatar(initials: "AS", size: .lg, status: "away")
                                WebUIAvatar(initials: "MK", size: .lg, status: "busy")
                            }
                        }
                        demoCard("WebUIProgress — all variants") {
                            VStack(spacing: 12) {
                                WebUIProgress(value: 0.25, variant: .primary, showLabel: true)
                                WebUIProgress(value: 0.5, variant: .success, showLabel: true)
                                WebUIProgress(value: 0.75, variant: .warning, showLabel: true)
                                WebUIProgress(value: 1.0, variant: .danger, showLabel: true)
                            }
                        }
                        demoCard("WebUIProgress — all sizes") {
                            VStack(spacing: 12) {
                                WebUIProgress(value: 0.6, variant: .primary, size: .sm)
                                WebUIProgress(value: 0.6, variant: .primary, size: .md)
                                WebUIProgress(value: 0.6, variant: .primary, size: .lg)
                            }
                        }
                        demoCard("WebUISkeleton — all variants") {
                            VStack(spacing: 12) {
                                WebUISkeleton(variant: .text)
                                WebUISkeleton(variant: .title)
                                WebUISkeleton(variant: .avatar)
                                WebUISkeleton(variant: .card)
                                WebUISkeleton(variant: .text, count: 3)
                            }
                        }
                        demoCard("WebUIToast — all variants") {
                            VStack(spacing: 12) {
                                WebUIToast(variant: .info, message: "Information toast message")
                                WebUIToast(variant: .success, message: "Success! Your changes were saved.")
                                WebUIToast(variant: .warning, message: "Warning: Your session is about to expire.")
                                WebUIToast(variant: .danger, message: "Error: Could not save changes.")
                            }
                        }
                        demoCard("WebUIToast — dismissible") {
                            WebUIToast(variant: .info, message: "This toast can be dismissed.", id: "toast-demo", dismissible: true)
                        }
                        demoCard("WebUIModal") {
                            WebUIModal(title: "Example Modal", id: "demo-modal") {
                                VStack(spacing: 12) {
                                    Paragraph("This is the modal body content.")
                                    Paragraph("You can put any views here.")
                                }
                            } footer: {
                                WebUIButton("Close", variant: .ghost, size: .sm)
                                WebUIButton("Save", variant: .primary, size: .sm)
                            }
                        }
                    }
                }

                // 10. Event Handling
                section("Event Handling", "events") {
                    VStack(spacing: 16) {
                        Heading("Interactive demos with backend event handlers", level: .h2)
                        demoCard("Click Counter") {
                            VStack(spacing: 16) {
                                Paragraph("Click the buttons below. The counter updates via WebSocket.")
                                Div(class: "counter-display") {
                                    Span(id: "counter-value") { Text("0") }.class("counter-number")
                                }
                                HStack(spacing: 12) {
                                    WebUIButton("−", variant: .primary, size: .lg, id: "btn-decrement")
                                    WebUIButton("+", variant: .primary, size: .lg, id: "btn-increment")
                                }
                                WebUIButton("Reset", variant: .ghost, size: .sm, id: "btn-reset")
                            }
                        }
                        demoCard("Form Echo") {
                            VStack(spacing: 12) {
                                Paragraph("Type something and submit — the server echoes it back.")
                                Form(action: "#", method: "post", id: "echo-form") {
                                    VStack(spacing: 12) {
                                        Label("Your message:").class("demo-label")
                                        Input(id: "echo-input", placeholder: "Type something...", type: .text)
                                        WebUIButton("Send", variant: .primary, id: "echo-submit")
                                    }
                                }
                                Div(id: "echo-result") { Text("") }
                            }
                        }
                        demoCard("Live Preview") {
                            VStack(spacing: 12) {
                                Paragraph("Type in the input — the preview updates in real time.")
                                Label("Type here:").class("demo-label")
                                Input(id: "preview-input", placeholder: "Type to preview...", type: .text)
                                Div(class: "preview-box") {
                                    Span(id: "preview-output") { Text("") }
                                }
                            }
                        }
                        demoCard("Tab Content Switching") {
                            VStack(spacing: 12) {
                                Paragraph("Click tabs to switch content via event handlers.")
                                WebUITabs(
                                    tabs: [
                                        TabItem(id: "tab-info", label: "Info"),
                                        TabItem(id: "tab-stats", label: "Stats"),
                                        TabItem(id: "tab-log", label: "Log"),
                                    ],
                                    activeTab: "tab-info",
                                    id: "content-tabs"
                                )
                                Div(id: "tab-content", class: "tab-content-box") {
                                    Paragraph("Information tab content. Click other tabs to switch.")
                                }
                            }
                        }
                    }
                }

                // 11. Charts
                section("Charts", "charts") {
                    VStack(spacing: 16) {
                        Heading("WebUIChart suite", level: .h2)
                        Paragraph("Server-rendered inline-SVG charts mirroring the SwiftUI Charts API. No JS dependencies — styling comes from the design-system tokens, and it reflows in dark mode automatically.")
                        demoCard("Grouped bars") {
                            VStack(spacing: 0) {
                                Chart {
                                    ForEach([("Q1", "A", 42.0), ("Q1", "B", 28.0), ("Q2", "A", 61.0), ("Q2", "B", 39.0), ("Q3", "A", 53.0), ("Q3", "B", 71.0)]) { d in
                                        BarMark(x: .value("Quarter", d.0), y: .value("Value", d.2))
                                            .foregroundStyle(by: d.1)
                                            .stacking(.unstacked)
                                    }
                                }
                                .chartTitle("Revenue by quarter")
                            }
                        }
                        demoCard("Stacked bars") {
                            VStack(spacing: 0) {
                                Chart {
                                    ForEach([("Mon", "Core", 120.0), ("Mon", "Web", 80.0), ("Tue", "Core", 95.0), ("Tue", "Web", 120.0), ("Wed", "Core", 140.0), ("Wed", "Web", 60.0)]) { d in
                                        BarMark(x: .value("Day", d.0), y: .value("Requests", d.2))
                                            .foregroundStyle(by: d.1)
                                    }
                                }
                                .chartTitle("Requests by service")
                            }
                        }
                        demoCard("Line + points + area") {
                            VStack(spacing: 0) {
                                Chart {
                                    ForEach(Array([12.0, 18.0, 15.0, 24.0, 31.0, 27.0, 38.0].enumerated().map { (x: Double($0.offset + 1), y: $0.element) })) { p in
                                        Group {
                                            AreaMark(x: .value("Week", p.x), y: .value("Value", p.y))
                                                .foregroundStyle(by: "series")
                                            LineMark(x: .value("Week", p.x), y: .value("Value", p.y))
                                                .foregroundStyle(by: "series")
                                                .interpolation(.catmullRom)
                                            PointMark(x: .value("Week", p.x), y: .value("Value", p.y))
                                                .foregroundStyle(by: "series")
                                                .symbol(.circle)
                                        }
                                    }
                                }
                                .chartTitle("Weekly growth")
                                .chartYScale(.linear(domain: 0...42))
                            }
                        }
                        demoCard("Pie") {
                            VStack(spacing: 0) {
                                Chart {
                                    SectorMark(angle: .value("Share", 44.0), category: "iOS")
                                    SectorMark(angle: .value("Share", 31.0), category: "Android")
                                    SectorMark(angle: .value("Share", 18.0), category: "web")
                                    SectorMark(angle: .value("Share", 7.0), category: "other")
                                }
                                .chartTitle("Platform share")
                                .chartHeight(300)
                            }
                        }
                        demoCard("Donut + selection") {
                            VStack(spacing: 0) {
                                Chart {
                                    SectorMark(angle: .value("Share", 44.0), category: "iOS")
                                    SectorMark(angle: .value("Share", 31.0), category: "Android")
                                    SectorMark(angle: .value("Share", 18.0), category: "web")
                                    SectorMark(angle: .value("Share", 7.0), category: "other")
                                }
                                .chartTitle("Platform share")
                                .chartHeight(300)
                                .chartInnerRadius(0.55)
                                .chartAngularInset(1.5)
                                .chartXSelection(value: .category("iOS"))
                            }
                        }
                        demoCard("Rules (grid + reference lines)") {
                            VStack(spacing: 0) {
                                Chart {
                                    ForEach(Array([8.0, 14.0, 11.0, 21.0, 26.0].enumerated().map { (x: Double($0.offset + 1), y: $0.element) })) { p in
                                        LineMark(x: .value("X", p.x), y: .value("Y", p.y))
                                            .foregroundStyle(by: "series")
                                            .interpolation(.monotone)
                                    }
                                    RuleMark(y: .value("Target", 15.0))
                                        .foregroundStyle("var(--chart-color-2)")
                                        .lineStyle(ChartLineStyle(width: 2, dash: [6, 4]))
                                }
                                .chartTitle("Against target")
                                .chartYScale(.linear(domain: 0...30))
                            }
                        }
                        demoCard("Heatmap") {
                            VStack(spacing: 0) {
                                Chart(heatmapCells())
                                    .chartTitle("Activity by hour × day")
                            }
                        }
                        demoCard("Empty state") {
                            VStack(spacing: 0) {
                                Chart([])
                                    .chartTitle("No data yet")
                            }
                        }
                    }
                }
                section("CSS Theme", "theme") {
                    VStack(spacing: 16) {
                        Heading("Design tokens and CSS custom properties", level: .h2)
                        demoCard("Color Palette") {
                            VStack(spacing: 8) {
                                colorSwatch("Primary", "--color-primary-500", "#10b89f")
                                colorSwatch("Success", "--color-success", "#16a34a")
                                colorSwatch("Warning", "--color-warning", "#d97706")
                                colorSwatch("Danger", "--color-danger", "#dc2626")
                                colorSwatch("Info", "--color-info", "#2563eb")
                                colorSwatch("Neutral", "--color-neutral-500", "#64748b")
                            }
                        }
                        demoCard("Typography Tokens") {
                            VStack(spacing: 8) {
                                tokenRow("Font Sans", "--font-sans")
                                tokenRow("Font Mono", "--font-mono")
                                tokenRow("Base Size", "--font-size-base", "1rem")
                                tokenRow("Hero Size", "--fs-hero")
                            }
                        }
                        demoCard("Spacing Scale") {
                            HStack(spacing: 8) {
                                spacingSample("--space-2", "0.5rem")
                                spacingSample("--space-4", "1rem")
                                spacingSample("--space-8", "2rem")
                                spacingSample("--space-12", "3rem")
                                spacingSample("--space-16", "4rem")
                            }
                        }
                        demoCard("Border Radius Tokens") {
                            HStack(spacing: 8) {
                                radiusSample("--radius-sm", "2px")
                                radiusSample("--radius-md", "6px")
                                radiusSample("--radius-lg", "8px")
                                radiusSample("--radius-xl", "12px")
                                radiusSample("--radius-full", "50%")
                            }
                        }
                        demoCard("Shadow Tokens") {
                            VStack(spacing: 16) {
                                shadowSample("--shadow-sm", "Small shadow")
                                shadowSample("--shadow-md", "Medium shadow")
                                shadowSample("--shadow-lg", "Large shadow")
                                shadowSample("--shadow-xl", "Extra large shadow")
                            }
                        }
                    }
                }

                // 13. Icons
                section("Icons", "icons") {
                    VStack(spacing: 16) {
                        Heading("WebUIIcon suite", level: .h2)
                        Paragraph("Stroke-based inline-SVG icons generated from the `designer/icons/icon-manifest.json` catalog (206 glyphs, MIT/Feather geometry). Each icon inherits `currentColor`, so it takes the surrounding text color by default and recolors with `.foregroundColor(_:)`.")
                        demoCard("Sizes") {
                            HStack(spacing: 24) {
                                VStack(spacing: 4) {
                                    WebUIIcon(.star, size: .small)
                                    Text(".small").font(size: 12).foregroundColor(.textMuted)
                                }
                                VStack(spacing: 4) {
                                    WebUIIcon(.star, size: .medium)
                                    Text(".medium").font(size: 12).foregroundColor(.textMuted)
                                }
                                VStack(spacing: 4) {
                                    WebUIIcon(.star, size: .large)
                                    Text(".large").font(size: 12).foregroundColor(.textMuted)
                                }
                                VStack(spacing: 4) {
                                    WebUIIcon(.star, size: .extraLarge)
                                    Text(".extraLarge").font(size: 12).foregroundColor(.textMuted)
                                }
                                VStack(spacing: 4) {
                                    WebUIIcon(.star).iconSize(.extraLarge)
                                    Text("iconSize(.extraLarge)").font(size: 12).foregroundColor(.textMuted)
                                }
                            }
                        }
                        demoCard("Color tokens (currentColor)") {
                            HStack(spacing: 24) {
                                WebUIIcon(.heart, size: .large).foregroundColor(.danger)
                                WebUIIcon(.checkCircle, size: .large).foregroundColor(.success)
                                WebUIIcon(.alertTriangle, size: .large).foregroundColor(.warning)
                                WebUIIcon(.info, size: .large).foregroundColor(.info)
                                WebUIIcon(.bell, size: .large).foregroundColor(.primary)
                                WebUIIcon(.activity, size: .large).foregroundColor(.textMuted)
                            }
                        }
                        demoCard("Accessible label (role=img)") {
                            HStack(spacing: 16) {
                                WebUIIcon(.search, size: .large, title: "Search")
                                WebUIIcon(.download, size: .large, title: "Download file")
                                WebUIIcon(.cloud, size: .large, title: "Cloud storage")
                                WebUIIcon(.settings, size: .large)
                                Text("last one: decorative (aria-hidden)").font(size: 12).foregroundColor(.textMuted)
                            }
                        }
                        demoCard("In composition (tree + empty state + alert)") {
                            VStack(spacing: 12) {
                                WebUITree(
                                    nodes: [
                                        WebUITree.Node(id: "src", label: "src", icon: .folder, children: [
                                            WebUITree.Node(id: "views", label: "views", icon: .folder, children: [
                                                WebUITree.Node(id: "HomeView", label: "HomeView.swift", icon: .fileText),
                                                WebUITree.Node(id: "SettingsView", label: "SettingsView.swift", icon: .fileText)
                                            ])
                                        ])
                                    ],
                                    expanded: ["src", "views"]
                                )
                                WebUIEmptyState(icon: .inbox, title: "No messages yet", message: "Check back later or connect a new account.")
                                WebUIAlert(variant: .success, title: "Deployed", message: "Release 2.3.1 is now live in production.")
                            }
                        }
                        demoCard("Custom geometry (WebUIIconCustom, sanitized)") {
                            HStack(spacing: 24) {
                                WebUIIconCustom(
                                    name: "custom-diamond",
                                    body: "<path d=\"M12 2l9 10-9 10-9-10z\"/><line x1=\"3\" y1=\"12\" x2=\"21\" y2=\"12\"/>",
                                    size: .large,
                                    title: "Custom diamond"
                                )
                                WebUIIconCustom(
                                    name: "custom-sanitized",
                                    body: "<script>window.xss=1</script><circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"M8 12h8\" onmouseover=\"alert(1)\"/>",
                                    size: .large
                                )
                                Text("right icon: script tag + on* handler stripped").font(size: 12).foregroundColor(.textMuted)
                            }
                        }
                    }
                }
            }.padding(32)
        }

    // MARK: - Helpers

    func heatmapCells() -> [ChartMark] {
        let intensities: [[Double]] = [
            [0.1, 0.5, 0.9, 0.3, 0.7],
            [0.2, 0.8, 0.4, 0.6, 0.1],
            [0.9, 0.3, 0.7, 0.2, 0.5],
            [0.4, 0.6, 0.1, 0.8, 0.3],
            [0.7, 0.2, 0.5, 0.9, 0.6],
        ]
        var marks: [ChartMark] = []
        for (h, row) in intensities.enumerated() {
            for (d, v) in row.enumerated() {
                marks.append(RectangleMark(
                    xStart: .value("Hour", Double(h)),
                    xEnd: .value("Hour", Double(h + 1)),
                    yStart: .value("Day", Double(d)),
                    yEnd: .value("Day", Double(d + 1)),
                    value: v
                ).makeMark())
            }
        }
        return marks
    }

    func section(_ title: String, _ id: String, @ViewBuilder content: () -> [any View]) -> some View {
        Section(class: "showcase-section") {
            content()
        }.id(id)
    }

    func demoCard(_ title: String, @ViewBuilder content: () -> [any View]) -> some View {
        WebUICard(variant: .outlined) {
            VStack(spacing: 12) {
                Heading(title, level: .h3).class("demo-card-title")
                Div(class: "demo-card-body") {
                    content()
                }
            }.padding(16)
        }
    }

    @Sendable func div(_ text: String, _ className: String) -> some View {
        Div(class: className) { Text(text) }
    }

    func colorSwatch(_ name: String, _ token: String, _ value: String) -> some View {
        // single class string: a chained .class() on a tag that already
        // carries a class attribute is skipped by attribute injection.
        HStack(alignment: .center, spacing: 12) {
            Div(class: "swatch swatch-\(name.lowercased())") { Text("") }.width("40px").height("40px")
            VStack(spacing: 2) {
                Text(name).font(size: 14, weight: "600")
                Text(token).font(size: 12)
                Text(value).font(size: 12)
            }
        }
    }

    func tokenRow(_ name: String, _ token: String, _ value: String? = nil) -> some View {
        HStack(spacing: 12) {
            Text(name).font(size: 14, weight: "600").width("120px")
            Text(token).font(size: 12).width("200px")
            if let value {
                Text(value).font(size: 12)
            }
        }
    }

    func spacingSample(_ token: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Div(class: "spacing-sample") { Text("") }.width(value).height("24px").backgroundColor("#10b89f")
            Text(token).font(size: 10)
            Text(value).font(size: 10)
        }
    }

    func radiusSample(_ token: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Div(class: "radius-sample") { Text("") }
                .width("40px").height("40px")
                .backgroundColor("#e2e8f0")
                .border("1px solid #94a3b8")
            Text(token).font(size: 10)
            Text(value).font(size: 10)
        }
    }

    func shadowSample(_ token: String, _ label: String) -> some View {
        Div(class: "shadow-sample") {
            VStack(spacing: 4) {
                Text(label).font(size: 14, weight: "600")
                Text(token).font(size: 12)
            }.padding(16)
        }.padding(16).backgroundColor("#ffffff").cornerRadius("8px")
    }

    func placeholderSVG() -> String {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="240" height="150" viewBox="0 0 240 150" role="img" aria-label="Sample image">
          <defs>
            <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="#d1faf1"/>
              <stop offset="1" stop-color="#ecfdf9"/>
            </linearGradient>
          </defs>
          <rect width="240" height="150" rx="10" fill="url(#bg)"/>
          <circle cx="58" cy="52" r="16" fill="#10b89f"/>
          <path d="M24 118 L78 74 L112 104 L150 66 L216 118 Z" fill="#10b89f" opacity="0.85"/>
          <text x="120" y="138" text-anchor="middle" font-family="-apple-system, sans-serif" font-size="12" fill="#0d756c">240 × 150 — inline svg</text>
        </svg>
        """
        return svg
    }
}
}
