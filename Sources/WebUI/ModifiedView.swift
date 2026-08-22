import Foundation
import Logging

// MARK: - ModifiedView
public struct ModifiedView<Content: View, M: ViewModifier>: View {
    public let content: Content
    public let modifier: M
    public init(content: Content, modifier: M) {
        self.content = content
        self.modifier = modifier
    }

    public func render() -> String {
        modifier.apply(to: content.render())
    }
}

// MARK: - AnyViewModifier (type eraser for conditional modifier use)
public struct AnyViewModifier: ViewModifier {
    private let _apply: @Sendable (String) -> String
    public init<M: ViewModifier>(_ modifier: M) {
        self._apply = modifier.apply
    }
    public func apply(to html: String) -> String {
        _apply(html)
    }
}

// MARK: - CSS Property Enum
public enum CSSProperty: Sendable, Hashable {
    case backgroundColor
    case color
    case fontSize
    case fontWeight
    case fontFamily
    case textAlign
    case padding
    case margin
    case width
    case height
    case maxWidth
    case display
    case flex
    case flexDirection
    case border
    case borderRadius
    case gap
    case alignItems
    case placeItems
    case overflow
    case gridTemplateColumns
    case custom(String)

    public var rawValue: String {
        switch self {
        case .backgroundColor:    return "background-color"
        case .color:              return "color"
        case .fontSize:           return "font-size"
        case .fontWeight:         return "font-weight"
        case .fontFamily:         return "font-family"
        case .textAlign:          return "text-align"
        case .padding:            return "padding"
        case .margin:             return "margin"
        case .width:              return "width"
        case .height:             return "height"
        case .maxWidth:           return "max-width"
        case .display:            return "display"
        case .flex:               return "flex"
        case .flexDirection:      return "flex-direction"
        case .border:             return "border"
        case .borderRadius:       return "border-radius"
        case .gap:                return "gap"
        case .alignItems:         return "align-items"
        case .placeItems:         return "place-items"
        case .overflow:           return "overflow"
        case .gridTemplateColumns: return "grid-template-columns"
        case .custom(let v):      return v
        }
    }
}

// MARK: - Concrete Modifiers
public struct InlineStyle: ViewModifier {
    public let property: CSSProperty
    public let value: String
    public init(_ property: CSSProperty, _ value: String) {
        self.property = property
        self.value = value
    }

    public func apply(to html: String) -> String {
        injectAttributes(into: html, "style=\"\(htmlEscape(property.rawValue)): \(htmlEscape(value));\"")
    }
}
public struct HTMLAttribute: ViewModifier {
    public let key: String
    public let value: String
    public init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    public func apply(to html: String) -> String {
        injectAttributes(into: html, "\(htmlEscape(key))=\"\(htmlEscape(value))\"")
    }
}

// MARK: - Modifier Composition
public struct ComposedModifier<First: ViewModifier, Second: ViewModifier>: ViewModifier {
    public let first: First
    public let second: Second
    public init(first: First, second: Second) {
        self.first = first
        self.second = second
    }

    public func apply(to html: String) -> String {
        second.apply(to: first.apply(to: html))
    }
}

extension ViewModifier {
    public func andThen<Other: ViewModifier>(_ other: Other) -> ComposedModifier<Self, Other> {
        ComposedModifier(first: self, second: other)
    }
}
public struct NoopModifier: ViewModifier {
    public init() {}
    public func apply(to html: String) -> String { html }
}

// MARK: - HTML Event Type
public enum HTMLEvent: Sendable, Hashable {
    case click, submit, input, change
    case mouseover, mouseout, mousedown, mouseup
    case keydown, keyup, keypress
    case focus, blur, focusin, focusout
    case custom(String)

    public var rawValue: String {
        switch self {
        case .click:    return "click"
        case .submit:   return "submit"
        case .input:    return "input"
        case .change:   return "change"
        case .mouseover: return "mouseover"
        case .mouseout:  return "mouseout"
        case .mousedown: return "mousedown"
        case .mouseup:   return "mouseup"
        case .keydown:   return "keydown"
        case .keyup:     return "keyup"
        case .keypress:  return "keypress"
        case .focus:     return "focus"
        case .blur:      return "blur"
        case .focusin:   return "focusin"
        case .focusout:  return "focusout"
        case .custom(let v): return v
        }
    }
}

// MARK: - Event Handler Modifier
public struct EventHandlerModifier: ViewModifier {
    public let event: HTMLEvent
    public let handler: EventHandler
    private static let log = Logger(label: "webui.modifiers")
    public init(event: HTMLEvent, handler: @escaping EventHandler) {
        self.event = event
        self.handler = handler
    }

    public func apply(to html: String) -> String {
        guard var context = RenderContext.current else {
            Self.log.warning("EventHandlerModifier used without RenderContext. Wrap your render call in RenderContext.$current.withValue(...). The event handler for '\(event.rawValue)' will not fire.")
            return html
        }
        let componentID = context.nextComponentID()
        context.register(handler: handler, for: componentID)
        return injectAttributes(
            into: html,
            "data-component-id=\"\(componentID.value)\" data-event=\"\(htmlEscape(event.rawValue))\""
        )
    }
}
