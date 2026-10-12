import Testing
import WebUI
import WebUIDesignSystem

// w4.5: the framework's own strings live in one catalog and resolve through
// the render context. english defaults are the byte-identity contract (pinned
// by the showcase byte gate and the spreadsheet of rendered literals), so the
// first suite pins them; the rest proves the threading and the override rules.

/// a test localization: a custom catalog/locale/direction composed by the test.
private struct TestLocale: LocalizedEnvironment {
	var strings: WebUIStrings
	var locale: String
	var direction: Directionality

	init(strings: WebUIStrings = .english, locale: String = "en", direction: Directionality = .ltr) {
		self.strings = strings
		self.locale = locale
		self.direction = direction
	}
}

private func renderInLocale<V: View>(_ env: LocalizedEnvironment, _ build: () -> V) -> String {
	RenderContext.$current.withValue(RenderContext(router: EventRouter(), localized: env)) {
		build().markup.html
	}
}

@Suite struct LocalizationTests {

	// MARK: english defaults are byte-identical

	@Test func englishDefaultsAreTheShippedLiterals() {
		let s = WebUIStrings.english
		#expect(s.dismiss == "Dismiss")
		#expect(s.close == "Close")
		#expect(s.addReaction == "Add reaction")
		#expect(s.loading == "Loading")
		#expect(s.required == "Required")
		#expect(s.selectAllRows == "Select all rows")
		#expect(s.selectRow("r2") == "Select row r2")
		#expect(s.remove == "Remove")
		#expect(s.showOmittedItems == "Show omitted items")
		#expect(s.pagination == "Pagination")
		#expect(s.previousPage == "Previous page")
		#expect(s.nextPage == "Next page")
		#expect(s.rowsPerPage == "Rows per page")
		#expect(s.someoneIsTyping == "Someone is typing")
		#expect(s.notifications == "Notifications")
		#expect(s.unreadCount(3) == ", 3 unread")
		#expect(s.messages == "Messages")
		#expect(s.removeAttachment == "Remove attachment")
		#expect(s.sent == "Sent")
		#expect(s.delivered == "Delivered")
		#expect(s.read == "Read")
		#expect(s.stepper == "Stepper")
		#expect(s.decrease == "Decrease")
		#expect(s.increase == "Increase")
		#expect(s.oneTimeCode == "One-time code")
		#expect(s.digit(1) == "Digit 1")
		#expect(s.scan == "Scan")
		#expect(s.enterCode == "Enter code")
		#expect(s.verify == "Verify")
		#expect(s.select == "Select…")
		#expect(s.filter == "Filter…")
		#expect(s.signHere == "Sign here")
		#expect(s.clear == "Clear")
		#expect(s.save == "Save")
		#expect(s.cancel == "Cancel")
		#expect(s.ratingValue(4, 5) == "4.0 of 5")
		#expect(s.removeItem("Docs") == "Remove Docs")
		#expect(s.cardNumber == "Card number")
		#expect(s.cardHolder == "Card holder")
		#expect(s.typeAndPressEnter == "Type and press enter…")
		#expect(s.search == "Search")
		#expect(s.menu == "Menu")
		#expect(s.primary == "Primary")
		#expect(s.options == "Options")
		#expect(s.tableOfContents == "Table of contents")
		#expect(s.onThisPage == "On this page")
		#expect(s.breadcrumb == "Breadcrumb")
		#expect(s.maskedValue == "masked value")
		#expect(s.add == "Add")
		#expect(s.previous == "Previous")
		#expect(s.next == "Next")
		#expect(s.noMatches == "No matches")
		#expect(s.typeACommand == "Type a command…")
		#expect(s.backToTop == "Back to top")
		#expect(s.today == "Today")
		#expect(s.findTimezone == "Find a timezone…")
		#expect(s.searchCountries == "Search countries…")
		#expect(s.tasks == "Tasks")
		#expect(s.formula == "Fx")
		#expect(s.copy == "copy")
		#expect(s.copyLabel == "Copy")
		#expect(s.map == "map")
		#expect(s.mainNavigation == "Main")
		#expect(s.slide(1) == "Slide 1")
		#expect(s.connected == "connected")
		#expect(s.reconnecting == "reconnecting…")
		#expect(s.reasoning == "Reasoning")
	}

	// MARK: english renders outside any context

	@Test func componentsRenderEnglishOutsideAContext() {
		#expect(WebUIAlert(message: "m", dismissible: true).markup.html
			.contains("aria-label=\"Dismiss\""))
		#expect(WebUIToast(message: "m").markup.html
			.contains("aria-label=\"Dismiss\""))
		#expect(WebUIModal(title: "t") { Text("x") }.markup.html
			.contains("aria-label=\"Close\""))
		let page = WebUIPagination(page: 2, pages: 5).markup.html
		#expect(page.contains("aria-label=\"Pagination\""))
		#expect(page.contains("aria-label=\"Previous page\""))
		#expect(page.contains("aria-label=\"Next page\""))
		#expect(WebUIBell(count: 3).markup.html
			.contains("aria-label=\"Notifications, 3 unread\""))
		#expect(WebUIOTP().markup.html.contains("aria-label=\"One-time code\""))
		#expect(WebUIOTP().markup.html.contains("aria-label=\"Digit 1\""))
		#expect(WebUIMultiSelect(options: []).markup.html
			.contains(">Select…</span>"))
		#expect(WebUIBell(count: 0).markup.html
			.contains("aria-label=\"Notifications\""))
	}

	// MARK: threading through the render context

	@Test func stringsResolveThroughTheRenderContext() {
		var catalog = WebUIStrings.english
		catalog.dismiss = "Dismissed!"
		let env = TestLocale(strings: catalog)
		let html = renderInLocale(env) {
			WebUIAlert(message: "m", dismissible: true)
		}
		#expect(html.contains("aria-label=\"Dismissed!\""))
		#expect(!html.contains("aria-label=\"Dismiss\""))
	}

	@Test func aHostOverridesASubsetAndKeepsEnglishForTheRest() {
		var catalog = WebUIStrings.english
		catalog.close = "Cerrar"
		let env = TestLocale(strings: catalog)
		let modal = renderInLocale(env) {
			WebUIModal(title: "t") { Text("x") }
		}
		#expect(modal.contains("aria-label=\"Cerrar\""))
		// dismiss was not overridden, so the alert keeps the english default.
		let alert = renderInLocale(env) {
			WebUIAlert(message: "m", dismissible: true)
		}
		#expect(alert.contains("aria-label=\"Dismiss\""))
	}

	@Test func outsideAContextTheLookupFallsBackToEnglish() {
		#expect(RenderContext.currentStrings.dismiss == "Dismiss")
		#expect(RenderContext.currentStrings.rowsPerPage == "Rows per page")
		#expect(RenderContext.currentStrings.connected == "connected")
		#expect(RenderContext.currentStrings.reconnecting == "reconnecting…")
		#expect(RenderContext.currentStrings.reasoning == "Reasoning")
	}

	// MARK: the last status strings (w5.0) resolve through the context

	@Test func engineAndReasoningStringsResolveThroughTheContext() {
		let status = WebUIEngineStatus().markup.html
		#expect(status.contains(">connected<"))
		#expect(status.contains(">reconnecting…<"))
		#expect(WebUIReasoningBlock("x").markup.html.contains("<summary>Reasoning</summary>"))
		var catalog = WebUIStrings.english
		catalog.connected = "Online"
		catalog.reasoning = "Thoughts"
		let env = TestLocale(strings: catalog)
		let html = renderInLocale(env) {
			WebUIEngineStatus()
		}
		#expect(html.contains(">Online<"))
		#expect(!html.contains(">connected<"))
		let reasoning = renderInLocale(env) {
			WebUIReasoningBlock("x")
		}
		#expect(reasoning.contains("<summary>Thoughts</summary>"))
		#expect(reasoning.contains("<summary>Reasoning</summary>") == false)
	}

	// MARK: the shipped arabic catalog

	@Test func theArabiceCatalogRendersArabicStrings() {
		let env = TestLocale(strings: .arabic, locale: "ar-SA", direction: .rtl)
		let html = renderInLocale(env) {
			WebUIAlert(message: "م", dismissible: true)
		}
		#expect(html.contains("aria-label=\"تجاهل\""))
		let bell = renderInLocale(env) {
			WebUIBell(count: 3)
		}
		#expect(bell.contains("aria-label=\"الإشعارات، 3 غير مقروء\""))
		let reactions = renderInLocale(env) {
			WebUIReactions(reactions: [])
		}
		#expect(reactions.contains("aria-label=\"أضف رد فعل\""))
	}

	// MARK: locale and direction on the document

	@Test func theDocumentCarriesLocaleAndTypedDirection() {
		let html = WebUIDocument(
			title: "t",
			body: .trusted("<p>x</p>"),
			locale: "ar-SA",
			strings: .arabic,
			direction: .rtl
		).markup.html
		#expect(html.contains("<html lang=\"ar-SA\" dir=\"rtl\">"))
	}

	@Test func theDefaultDocumentDeclaresEnglishAndNoDirection() {
		let html = WebUIDocument(title: "t", body: .trusted("<p>x</p>")).markup.html
		#expect(html.contains("<html lang=\"en\""))
		#expect(!html.contains(" dir="))
	}

	@Test func theRenderContextCarriesTheLocalizedEnvironment() {
		var ctx = RenderContext(router: EventRouter())
		ctx.localized = TestLocale(strings: .arabic, locale: "ar-SA", direction: .rtl)
		#expect(ctx.strings.addReaction == "أضف رد فعل")
		#expect(ctx.locale == "ar-SA")
		#expect(ctx.direction == .rtl)
		let plain = RenderContext(router: EventRouter())
		#expect(plain.strings.dismiss == "Dismiss")
		#expect(plain.locale == "en")
		#expect(plain.direction == .ltr)
	}
}
