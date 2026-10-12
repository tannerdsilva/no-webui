import Foundation
import WebUI
import WebUIDesignSystem

// W5.3 host-cascade probe — renders two self-contained pages through the real
// emission path and exits, so the node gate (designer/cascade-probe.mjs) can
// drive them in headless chromium:
//
//   WebUICascadeProbe --generate <path>   the host page: framework sheet +
//                                         a host StyleSheet (the delivered artifact)
//   WebUICascadeProbe --control <path>    the same markup, no host sheet — the
//                                         framework baseline the host overrides
//
// the page uses raw framework-class markup on purpose: the question being
// measured is the cascade, not a component render.

let markup = """
<main style="padding: 2rem">
  <button class="button" id="p-base">base</button>
  <button class="button button--primary" id="p-primary">primary</button>
  <button class="button button--icon button--sm" id="p-size">size</button>
</main>
"""

// the three overrides, each facing a real shipped rule:
//   `.button`                   -> grid: host `.button` (padding)     — EQUAL specificity
//   `.button--primary`          -> host `.button--primary` (background) — EQUAL specificity
//   `.button--icon.button--sm`  -> host `.button--sm` (width)         — host LOWER specificity
// none of them use `!important`; the host wins each by layer origin alone.
let hostSheet = StyleSheet(name: "cascade-probe", layer: .host) {
    CSSRule(".button", [CSSDeclaration("padding", "43px 7px")])
    CSSRule(".button--primary", [CSSDeclaration("background", "rgb(240, 20, 20)")])
    CSSRule(".button--sm", [CSSDeclaration("width", "9rem")])
}

func page(styled: Bool) -> String {
    WebUIDocument(
        title: "cascade probe",
        body: .trusted(markup),
        includeRuntime: false,
        // inline the framework sheet: the page is self-contained, so the gate
        // server has a single html route and no csp-style link order surprises.
        styleSheets: styled ? [hostSheet] : [],
        stylesheetURL: nil
    ).markup.html
}

func write(_ html: String, to path: String) {
    try! html.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--generate"), i + 1 < args.count {
    write(page(styled: true), to: args[i + 1])
    print("host page written to \(args[i + 1])")
} else if let i = args.firstIndex(of: "--control"), i + 1 < args.count {
    write(page(styled: false), to: args[i + 1])
    print("control page written to \(args[i + 1])")
} else {
    print("usage: WebUICascadeProbe --generate <path> | --control <path>")
    exit(1)
}
