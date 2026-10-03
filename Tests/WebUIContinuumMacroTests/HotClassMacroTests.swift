import Testing
@testable import WebUIContinuumMacros

// MARK: - expansion fixtures

@Suite("@HotClass macro expansion")
struct HotClassMacroExpansionTests {

	@Test("both classes, internal struct")
	func bothClasses() {
		assertExpansion(
			"""
@HotClass("feed-item", "feed-item__meta")
struct FeedItem {
}
""",
			expanded: """
struct FeedItem {

    static let continuumClasses: [String] = ["feed-item", "feed-item__meta"]
}
"""
		)
}

	@Test("a public struct gets a public inventory member")
	func publicStruct() {
		assertExpansion(
			"""
@HotClass("feed-item")
public struct PublicFeedItem {
}
""",
			expanded: """
public struct PublicFeedItem {

    public static let continuumClasses: [String] = ["feed-item"]
}
"""
		)
}

	@Test("the generated member is named continuumClasses — assert by name")
	func memberName() {
		let text = expandedText(of: "@HotClass(\"feed-item\")\npublic struct PublicFeedItem {\n}")
		#expect(text.contains("continuumClasses"))
		#expect(text.contains("feed-item"))
		#expect(!text.contains("continuumDescriptor"))
}
}

// MARK: - negative cases

@Suite("@HotClass macro misuse")
struct HotClassMacroNegativeTests {

	@Test("non-struct targets throw")
	func nonStructThrows() {
		assertExpansionThrows(
			"""
			@HotClass("feed-item")
			enum NotAComponent {
			}
			""",
			message: "@HotClass can only be applied to a struct (a component); move the class vocabulary onto the component type"
		)
}

	@Test("no classes throw")
	func noClassesThrows() {
		assertExpansionThrows(
			"""
			@HotClass()
			struct Bare {
			}
			""",
			message: "@HotClass requires at least one class name — as @HotClass(\"feed-item\", \"feed-item__meta\")"
		)
}

	@Test("a non-literal argument throws")
	func nonLiteralThrows() {
		assertExpansionThrows(
			"""
			@HotClass(feedItem)
			struct Referenced {
			}
			""",
			message: "continuum macros take string literals only, e.g. @HotView(\"feed\") or @HotClass(\"feed-item\")"
		)
}
}
