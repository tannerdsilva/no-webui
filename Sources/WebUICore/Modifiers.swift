import Foundation

// MARK: - Typography Tokens

public enum FontWeight: Sendable {
    case thin
    case light
    case normal
    case medium
    case semibold
    case bold
    case extraBold
    case black
    case custom(String)

    public var rawValue: String {
        switch self {
        case .thin:     return "100"
        case .light:    return "200"
        case .normal:   return "400"
        case .medium:   return "500"
        case .semibold: return "600"
        case .bold:     return "700"
        case .extraBold: return "800"
        case .black:    return "900"
        case .custom(let v): return v
        }
    }
}

public enum TextAlignment: String, Sendable {
    case left = "left"
    case center = "center"
    case right = "right"
    case justify = "justify"
}

// MARK: - View Modifier Methods

extension View {

    // MARK: - Background & Foreground
    public func backgroundColor(_ color: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.backgroundColor, color))
    }
    public func foregroundColor(_ color: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.color, color))
    }
    public func foregroundColor(_ token: ColorToken) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.color, "var(\(token.cssVariable))"))
    }

    // MARK: - Typography
    public func font(size: Int, weight: String = "normal") -> ModifiedView<Self, ComposedModifier<InlineStyle, InlineStyle>> {
        let first = InlineStyle(.fontSize, "\(size)px")
        let second = InlineStyle(.fontWeight, weight)
        return ModifiedView(content: self, modifier: ComposedModifier(first: first, second: second))
    }
    public func font(size: Int, weight: FontWeight) -> ModifiedView<Self, ComposedModifier<InlineStyle, InlineStyle>> {
        font(size: size, weight: weight.rawValue)
    }
    public func fontFamily(_ family: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.fontFamily, family))
    }
    public func textAlign(_ alignment: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.textAlign, alignment))
    }
    public func textAlign(_ alignment: TextAlignment) -> ModifiedView<Self, InlineStyle> {
        textAlign(alignment.rawValue)
    }

    // MARK: - Spacing
    public func padding(_ all: Int) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.padding, "\(all)px"))
    }
    public func padding(_ token: SpaceToken) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.padding, "var(\(token.cssVariable))"))
    }
    public func padding(horizontal: Int, vertical: Int) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(
            content: self,
            modifier: InlineStyle(.padding, "\(vertical)px \(horizontal)px")
        )
    }
    public func margin(_ all: Int) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.margin, "\(all)px"))
    }

    // MARK: - Dimensions
    public func width(_ width: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.width, width))
    }
    public func height(_ height: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.height, height))
    }
    public func maxWidth(_ width: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.maxWidth, width))
    }

    // MARK: - Layout
    public func display(_ display: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.display, display))
    }
    public func flex(_ flex: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.flex, flex))
    }

    // MARK: - Borders
    public func border(_ border: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.border, border))
    }
    public func cornerRadius(_ radius: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.borderRadius, radius))
    }

    // MARK: - Visibility
    public func showIf(_ condition: Bool) -> ModifiedView<Self, AnyViewModifier> {
        ModifiedView(
            content: self,
            modifier: condition ? AnyViewModifier(NoopModifier()) : AnyViewModifier(InlineStyle(.display, "none"))
        )
    }

    // MARK: - HTML Attributes
    public func id(_ id: String) -> ModifiedView<Self, HTMLAttribute> {
        ModifiedView(content: self, modifier: HTMLAttribute("id", id))
    }
    public func `class`(_ name: String) -> ModifiedView<Self, HTMLAttribute> {
        ModifiedView(content: self, modifier: HTMLAttribute("class", name))
    }
    public func attribute(_ key: String, _ value: String) -> ModifiedView<Self, HTMLAttribute> {
        ModifiedView(content: self, modifier: HTMLAttribute(key, value))
    }

    // MARK: - Event Handlers
    public func onClick(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .click, handler: handler))
    }
    public func onSubmit(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .submit, handler: handler))
    }
    public func onInput(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .input, handler: handler))
    }
    public func onChange(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .change, handler: handler))
    }
    public func onFocus(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .focus, handler: handler))
    }
    public func onBlur(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .blur, handler: handler))
    }
    public func onKeyDown(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .keydown, handler: handler))
    }
    public func onKeyUp(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .keyup, handler: handler))
    }
    public func onKeyPress(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .keypress, handler: handler))
    }
    public func onMouseDown(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .mousedown, handler: handler))
    }
    public func onMouseUp(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .mouseup, handler: handler))
    }
    public func onMouseOver(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .mouseover, handler: handler))
    }
    public func onMouseOut(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .mouseout, handler: handler))
    }
    public func onFocusIn(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .focusin, handler: handler))
    }
    public func onFocusOut(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .focusout, handler: handler))
    }

    // MARK: - Optimistic Events

    public func onOptimisticClick(predict: @escaping () -> [FragmentUpdate], perform: @escaping EventHandler) -> ModifiedView<Self, OptimisticClickModifier> {
        ModifiedView(content: self, modifier: OptimisticClickModifier(prediction: predict(), handler: perform))
    }
}
