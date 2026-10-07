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

// MARK: - Typed Layout Values

/// the main-axis distribution a flex container applies to its children
/// (`justify-content`). closed to the css vocabulary the migration needs;
/// `.custom` stays for anything the enum does not name.
public enum JustifyContent: Sendable {
    case flexStart
    case flexEnd
    case center
    case spaceBetween
    case spaceAround
    case spaceEvenly
    case custom(String)

    public var rawValue: String {
        switch self {
        case .flexStart:    return "flex-start"
        case .flexEnd:      return "flex-end"
        case .center:       return "center"
        case .spaceBetween: return "space-between"
        case .spaceAround:  return "space-around"
        case .spaceEvenly:  return "space-evenly"
        case .custom(let v): return v
        }
    }
}

/// a flex/grid item's cross-axis alignment (`align-self`), the per-child
/// override of the container's `align-items`.
public enum AlignSelf: Sendable {
    case auto
    case flexStart
    case flexEnd
    case center
    case baseline
    case stretch
    case custom(String)

    public var rawValue: String {
        switch self {
        case .auto:        return "auto"
        case .flexStart:   return "flex-start"
        case .flexEnd:     return "flex-end"
        case .center:      return "center"
        case .baseline:    return "baseline"
        case .stretch:     return "stretch"
        case .custom(let v): return v
        }
    }
}

/// the css `position` vocabulary.
public enum Position: String, Sendable {
    case `static` = "static"
    case relative = "relative"
    case absolute = "absolute"
    case fixed = "fixed"
    case sticky = "sticky"
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
    public func minWidth(_ width: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.custom("min-width"), width))
    }
    public func minHeight(_ height: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.custom("min-height"), height))
    }

    // MARK: - Layout
    public func display(_ display: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.display, display))
    }
    public func flex(_ flex: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.flex, flex))
    }

    // MARK: - Filled Layout Gaps (MACRO_DX G2)
    /// the five properties the consumer migration measured at zero-coverage —
    /// `justify-content`, `flex-basis`, `align-self`, `position`, `z-index` —
    /// now named modifiers instead of a `.style` escape hatch. token-typed
    /// where a scale exists: `flexBasis` takes the `SpaceToken` scale; the
    /// keyword properties are closed vocabularies.
    public func justifyContent(_ value: JustifyContent) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.justifyContent, value.rawValue))
    }
    public func justifyContent(_ value: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.justifyContent, value))
    }
    /// the flex item's initial main-axis size (`flex-basis`), in points.
    public func flexBasis(_ points: Int) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.flexBasis, "\(points)px"))
    }
    /// the flex item's initial main-axis size, token-typed to the space scale.
    public func flexBasis(_ token: SpaceToken) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.flexBasis, "var(\(token.cssVariable))"))
    }
    /// this item's cross-axis alignment, overriding the container's
    /// `align-items`.
    public func alignSelf(_ value: AlignSelf) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.alignSelf, value.rawValue))
    }
    public func alignSelf(_ value: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.alignSelf, value))
    }
    public func position(_ value: Position) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.position, value.rawValue))
    }
    public func position(_ value: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.position, value))
    }
    /// the stacking order (`z-index`); no token scale exists for it, so the
    /// value is a plain integer.
    public func zIndex(_ value: Int) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.zIndex, "\(value)"))
    }

    // MARK: - Fill
    /// make this view occupy all remaining space of a flex/grid parent: grow
    /// on the main axis, shrink below content size, stretch across the cross
    /// axis, and drop the flex min-size floors so a large child (a textarea,
    /// a table) scrolls the parent instead of blowing it open.
    /// the layout primitives (`VStack`, `HStack`, `ScrollView`) are
    /// content-sized by default — this is the explicit opt-in to filling.
    public func fill() -> ModifiedView<Self, AnyViewModifier> {
        ModifiedView(
            content: self,
            modifier: AnyViewModifier(
                InlineStyle(.flex, "1 1 0%")
                    .andThen(InlineStyle(.custom("min-width"), "0"))
                    .andThen(InlineStyle(.custom("min-height"), "0"))
                    .andThen(InlineStyle(.alignSelf, "stretch"))
            )
        )
    }

    /// stretch across the parent's cross axis without growing on the main
    /// axis — the fixed-size counterpart of ``fill()`` (a 220px sidebar that
    /// still spans the row's full height, a header bar that spans the width).
    public func stretch() -> ModifiedView<Self, AnyViewModifier> {
        ModifiedView(
            content: self,
            modifier: AnyViewModifier(
                InlineStyle(.alignSelf, "stretch")
                    .andThen(InlineStyle(.custom("min-width"), "0"))
                    .andThen(InlineStyle(.custom("min-height"), "0"))
            )
        )
    }

    /// a single arbitrary css declaration — the escape hatch for properties
    /// the named modifiers don't cover (`border-bottom`, `z-index`, …).
    public func style(_ property: String, _ value: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.custom(property), value))
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
