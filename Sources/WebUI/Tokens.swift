import Foundation

// MARK: - SpaceToken

public enum SpaceToken: Int, CaseIterable, Sendable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case eight = 8
    case ten = 10
    case twelve = 12
    case sixteen = 16
    case twenty = 20
    case twentyFour = 24

    public var cssVariable: String { "--space-\(rawValue)" }
}

// MARK: - ColorToken

public enum ColorToken: String, CaseIterable, Sendable {
    case primary = "color-primary-500"
    case primarySolid = "color-primary-solid"
    case onPrimarySolid = "color-on-primary-solid"
    case text = "color-text"
    case textMuted = "color-text-muted"
    case textFaint = "color-text-faint"
    case onColor = "color-on-color"
    case border = "color-border"
    case borderStrong = "color-border-strong"
    case background = "color-bg"
    case backgroundRaised = "color-bg-raised"
    case backgroundInset = "color-bg-inset"
    case backgroundSubtle = "color-bg-subtle"
    case success = "color-success"
    case warning = "color-warning"
    case danger = "color-danger"
    case info = "color-info"

    public var cssVariable: String { "--\(rawValue)" }
}
