import WebUICore

/// the smallest `Dismissible`: `View` plus the protocol's own four members — no
/// extra requirements.
struct DismissibleProbe: Dismissible {
    var dismissButtonClass: String { "probe__close" }
    var dismissMarker: String { "" }
    var dismissRootIdentifier: String? { nil }
    var onDismiss: DismissHandler?

    func render(into buffer: inout HTMLBuffer) {
        buffer.beginElement("div", " class=\"probe\"")
        buffer.endOpenTag()
        buffer.endElement()
    }
}
