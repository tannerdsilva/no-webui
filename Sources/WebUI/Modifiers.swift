import Foundation

// MARK: - View Modifier Methods

extension View {

    // MARK: - Background & Foreground
    public func backgroundColor(_ color: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.backgroundColor, color))
    }
    public func foregroundColor(_ color: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.color, color))
    }

    // MARK: - Typography
    public func font(size: Int, weight: String = "normal") -> ModifiedView<Self, ComposedModifier<InlineStyle, InlineStyle>> {
        let first = InlineStyle(.fontSize, "\(size)px")
        let second = InlineStyle(.fontWeight, weight)
        return ModifiedView(content: self, modifier: ComposedModifier(first: first, second: second))
    }
    public func fontFamily(_ family: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.fontFamily, family))
    }
    public func textAlign(_ alignment: String) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.textAlign, alignment))
    }

    // MARK: - Spacing
    public func padding(_ all: Int) -> ModifiedView<Self, InlineStyle> {
        ModifiedView(content: self, modifier: InlineStyle(.padding, "\(all)px"))
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
}
