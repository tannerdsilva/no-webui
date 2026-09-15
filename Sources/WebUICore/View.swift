import Foundation

// MARK: - View Protocol
public protocol View: Sendable {
    func render() -> String
}

// MARK: - ViewModifier Protocol
public protocol ViewModifier: Sendable {
    func apply(to html: String) -> String
}

// MARK: - EmptyView
public struct EmptyView: View {
    public init() {}
    public func render() -> String { "" }
}

// MARK: - AnyView (type-erased wrapper)
public struct AnyView: View {
    private let _render: @Sendable () -> String

    public init<V: View>(_ view: V) {
        self._render = view.render
    }

    public func render() -> String {
        _render()
    }
}
