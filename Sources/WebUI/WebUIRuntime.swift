import Foundation

// MARK: - WebUIRuntime
public enum WebUIRuntime {
    public static let source: String = WebUIAssets.js
    public static let bootstrap: String = """
    WebUIRuntime.init();
    """
}
