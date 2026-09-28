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
