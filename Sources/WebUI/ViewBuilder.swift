import Foundation

// MARK: - ViewBuilder
@resultBuilder
public enum ViewBuilder {
    public static func buildBlock(_ components: [any View]...) -> [any View] {
        components.flatMap { $0 }
    }
    public static func buildExpression(_ expression: any View) -> [any View] {
        [expression]
    }
    public static func buildExpression(_ expression: [any View]) -> [any View] {
        expression
    }
    public static func buildOptional(_ component: [any View]?) -> [any View] {
        component ?? []
    }
    public static func buildEither(first: [any View]) -> [any View] {
        first
    }
    public static func buildEither(second: [any View]) -> [any View] {
        second
    }
    public static func buildArray(_ components: [[any View]]) -> [any View] {
        components.flatMap { $0 }
    }
    public static func buildLimitedAvailability(_ component: [any View]) -> [any View] {
        component
    }
}

// MARK: - ViewBuilder for single-view contexts

extension ViewBuilder {
    public static func buildBlock<V: View>(_ view: V) -> V {
        view
    }
}
