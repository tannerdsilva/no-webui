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
                    .andThen(InlineStyle(.custom("align-self"), "stretch"))
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
                InlineStyle(.custom("align-self"), "stretch")
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

    /// declare any DOM event, including one the vocabulary does not name.
    ///
    /// every named case above has its own sugar; this is the way to the rest —
    /// `HTMLEvent.custom("dragstart")`, or a case added to the enum before its
    /// sugar lands. it is what made the vocabulary's own escape hatch reachable:
    /// `HTMLEvent` has always accepted `.custom(_:)`, and until this existed no
    /// modifier could attach one.
    public func on(
        _ event: HTMLEvent,
        perform handler: @escaping EventHandler
    ) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: event, handler: handler))
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

    // MARK: - Wave-4 Event Deck (W4.1)
    //
    // one typed modifier per deck event, in the spelling convention above. the
    // handler receives an `EventData` whose typed payload decodes through the
    // accessors in `EventHandling.swift` (`event.pointer()`, `event.drag()`,
    // `event.paste()`, ...) — the magic strings are retired for these events.

    // MARK: pointer
    public func onPointerDown(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .pointerdown, handler: handler))
    }
    public func onPointerMove(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .pointermove, handler: handler))
    }
    public func onPointerUp(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .pointerup, handler: handler))
    }
    public func onPointerCancel(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .pointercancel, handler: handler))
    }
    public func onPointerEnter(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .pointerenter, handler: handler))
    }
    public func onPointerLeave(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .pointerleave, handler: handler))
    }

    // MARK: touch
    public func onTouchStart(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .touchstart, handler: handler))
    }
    public func onTouchMove(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .touchmove, handler: handler))
    }
    public func onTouchEnd(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .touchend, handler: handler))
    }

    // MARK: drag & drop
    public func onDragStart(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .dragstart, handler: handler))
    }
    public func onDrag(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .drag, handler: handler))
    }
    public func onDragEnd(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .dragend, handler: handler))
    }
    public func onDragEnter(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .dragenter, handler: handler))
    }
    public func onDragOver(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .dragover, handler: handler))
    }
    public func onDragLeave(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .dragleave, handler: handler))
    }
    public func onDrop(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .drop, handler: handler))
    }

    // MARK: clipboard
    public func onCopy(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .copy, handler: handler))
    }
    public func onCut(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .cut, handler: handler))
    }
    public func onPaste(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .paste, handler: handler))
    }

    // MARK: wheel & scroll
    public func onWheel(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .wheel, handler: handler))
    }
    public func onScroll(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .scroll, handler: handler))
    }

    // MARK: misc
    public func onDoubleClick(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .dblclick, handler: handler))
    }
    public func onContextMenu(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .contextmenu, handler: handler))
    }
    public func onAnimationEnd(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .animationend, handler: handler))
    }
    public func onTransitionEnd(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .transitionend, handler: handler))
    }

    // MARK: media
    public func onPlay(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .play, handler: handler))
    }
    public func onPause(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .pause, handler: handler))
    }
    public func onEnded(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .ended, handler: handler))
    }
    public func onTimeUpdate(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .timeupdate, handler: handler))
    }
    public func onLoadedMetadata(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .loadedmetadata, handler: handler))
    }
    public func onError(perform handler: @escaping EventHandler) -> ModifiedView<Self, EventHandlerModifier> {
        ModifiedView(content: self, modifier: EventHandlerModifier(event: .error, handler: handler))
    }

    // MARK: - Optimistic Events

    public func onOptimisticClick(predict: @escaping () -> [FragmentUpdate], perform: @escaping EventHandler) -> ModifiedView<Self, OptimisticClickModifier> {
        ModifiedView(content: self, modifier: OptimisticClickModifier(prediction: predict(), handler: perform))
    }
}

// MARK: - Class Names

/// a class name, as distinct from any other string that can appear in a view
/// expression.
///
/// `.class(_:)` and its siblings merge into the content's own classes (2.0).
/// this type exists so a call site says what it means — an id, a label and an
/// event handler are different things from a class, and only one of the four
/// merges.
public struct ClassName: Sendable, ExpressibleByStringLiteral, Hashable {
    public let value: String
    public init(_ value: String) { self.value = value }
    public init(stringLiteral value: String) { self.value = value }
}

extension View {
    /// add class names to the content's own, keeping both.
    ///
    /// the merge is what changed in 2.0: before, a modifier's `class` replaced
    /// whatever the content rendered, so `WebUIButton("x").class("mine")`
    /// erased `button button--primary button--md`. now both survive, and a name
    /// already present is not repeated.
    public func classes(_ names: ClassName...) -> ModifiedView<Self, HTMLAttribute> {
        ModifiedView(content: self, modifier: HTMLAttribute("class", names.map(\.value).joined(separator: " ")))
    }

    /// add one class name — the singular reading of `classes(_:)`.
    public func addClass(_ name: ClassName) -> ModifiedView<Self, HTMLAttribute> {
        ModifiedView(content: self, modifier: HTMLAttribute("class", name.value))
    }
}
