import Testing
import WebUI
import WebUIBlocks
import WebUIDesignSystem
import WebUIShowcaseContent

// w4.4: accessibility is checkable. the six starter rules are proven on
// synthetic markup (positive and negative controls), the typed aria surface
// is proven on its bytes and escaping, and the framework's own pages —
// showcase + every block — are proven clean end to end.

@Suite struct A11yTests {

	// MARK: the six rules fire

	@Test func buttonWithoutANameIsReported() {
		let html = "<button class=\"icon-only\"><svg aria-hidden=\"true\"></svg></button>"
		let findings = A11yAudit.audit(html)
		#expect(findings.contains { $0.rule == A11yAudit.buttonNoName })
	}

	@Test func imageWithoutAltIsReported() {
		let html = "<img src=\"chart.png\">"
		let findings = A11yAudit.audit(html)
		#expect(findings.contains { $0.rule == A11yAudit.imageNoAlt })
	}

	@Test func formControlWithoutLabelIsReported() {
		let html = "<form><input type=\"text\"><select><option>a</option></select></form>"
		let findings = A11yAudit.audit(html)
		#expect(findings.filter { $0.rule == A11yAudit.controlNoLabel }.count == 2)
	}

	@Test func interactiveElementWithoutNameIsReported() {
		let html = "<a href=\"/x\"></a><div role=\"tab\" aria-selected=\"true\"></div>"
		let findings = A11yAudit.audit(html)
		#expect(findings.filter { $0.rule == A11yAudit.interactiveNoName }.count == 2)
	}

	@Test func skippedHeadingLevelIsReported() {
		let html = "<h1>A</h1><h3>C</h3>"
		let findings = A11yAudit.audit(html)
		#expect(findings.contains { $0.rule == A11yAudit.headingSkip })
	}

	@Test func roleMissingRequiredAriaIsReported() {
		let html = "<div role=\"checkbox\">accept</div><div role=\"tab\">tab</div>"
		let findings = A11yAudit.audit(html)
		#expect(findings.filter { $0.rule == A11yAudit.roleMissingAria }.count == 2)
	}

	@Test func dialogWithoutANameIsReported() {
		let html = "<div role=\"dialog\">content</div>"
		let findings = A11yAudit.audit(html)
		#expect(findings.contains { $0.rule == A11yAudit.roleMissingAria && $0.message.contains("dialog") })
	}

	// MARK: clean markup stays silent

	@Test func completeMarkupHasNoFindings() {
		let html = """
		<h1>Title</h1>
		<p><a href="/x">Read more</a></p>
		<p><img src="deco.png" alt=""></p>
		<p><img src="hero.png" alt="A hero"></p>
		<form>
		  <label for="name">Name</label><input id="name" type="text">
		  <label>Email <input type="email"></label>
		  <button type="submit">Go</button>
		</form>
		<div role="checkbox" aria-checked="true" aria-label="Accept terms" tabindex="0"></div>
		<div role="dialog" aria-modal="true" aria-labelledby="t"><h2 id="t">Tips</h2></div>
		"""
		#expect(A11yAudit.audit(html).isEmpty)
	}

	@Test func ariaHiddenSubtreesAreExempt() {
		let html = "<div aria-hidden=\"true\"><button>×</button><img src=\"x.png\"></div>"
		#expect(A11yAudit.audit(html).isEmpty)
	}

	@Test func presentationRoleIsExempt() {
		let html = "<img src=\"x.png\" role=\"presentation\">"
		#expect(A11yAudit.audit(html).isEmpty)
	}

	@Test func placeholderIsNotALabel() {
		let html = "<input type=\"text\" placeholder=\"Name\">"
		let findings = A11yAudit.audit(html)
		#expect(findings.contains { $0.rule == A11yAudit.controlNoLabel })
	}

	@Test func realLabelsCountLegally() {
		let html = "<input type=\"search\" aria-label=\"Find\">"
		#expect(A11yAudit.audit(html).isEmpty)
	}

	@Test func headingSequencesThatDescendAreAllowed() {
		let html = "<h1>A</h1><h2>B</h2><h3>C</h3><h1>D</h1>"
		#expect(A11yAudit.audit(html).isEmpty)
	}

	@Test func labelledbyResolvesTheTargetText() {
		let html = "<button aria-labelledby=\"desc\"></button><span id=\"desc\">Save work</span>"
		#expect(A11yAudit.audit(html).isEmpty)
	}

	// MARK: the typed aria surface

	@Test func ariaRoleRawValuesAreTheServedBytes() {
		#expect(AriaRole.button.rawValue == "button")
		#expect(AriaRole.treeitem.rawValue == "treeitem")
		#expect(AriaRole.radioGroup.rawValue == "radiogroup")
	}

	@Test func ariaEnumSpellingsRenderARIAValues() {
		#expect(AriaChecked.yes.rawValue == "true")
		#expect(AriaChecked.mixed.rawValue == "mixed")
		#expect(AriaExpanded.yes.rawValue == "true")
		#expect(AriaCurrent.page.rawValue == "page")
	}

	@Test func ariaRenderProducesAnEscapedAttributePair() {
		let rendered = Aria.label("a\"b<c>").render()
		#expect(rendered == " aria-label=\"a&quot;b&lt;c&gt;\"")
	}

	@Test func ariaRoleRenderIsEscaped() {
		#expect(AriaRole.status.render() == " role=\"status\"")
	}

	@Test func ariaAttributesComposeRoleFirst() {
		let composed = Aria.attributes([.label("L"), .hidden(.yes)], role: .status)
		#expect(composed == " role=\"status\" aria-label=\"L\" aria-hidden=\"true\"")
	}

	@Test func ariaModifiersEmitTypedAttributes() {
		let html = Text("hi").role(.status).ariaLive(.polite).ariaLabel("x").focusable().markup.html
		#expect(html.contains("role=\"status\""))
		#expect(html.contains("aria-live=\"polite\""))
		#expect(html.contains("aria-label=\"x\""))
		#expect(html.contains("tabindex=\"0\""))
		#expect(A11yAudit.audit(html).isEmpty)
	}

	// MARK: the last hand-written emitters (w5.0) went typed

	@Test func migratedEmittersUseTheTypedSurface() {
		let drawer = WebUIDrawer(title: "t") { Text("x") }.markup.html
		#expect(drawer.contains("role=\"dialog\""))
		#expect(drawer.contains("aria-modal=\"true\""))
		#expect(WebUISeparator().markup.html.contains("role=\"separator\""))
		#expect(WebUIEngineStatus().markup.html.contains("role=\"status\""))
		let otp = WebUIOTP().markup.html
		#expect(otp.contains("aria-label=\"One-time code\""))
		#expect(otp.contains("aria-label=\"Digit 1\""))
		// the slider's fractional value survives the typed surface byte-identically.
		#expect(WebUISlider(50).markup.html.contains("aria-valuenow=\"50.0\""))
		#expect(Aria.valuenowDouble(50.0).render() == " aria-valuenow=\"50.0\"")
	}

	@Test func migratedEmittersStayA11yClean() {
		let rendered = [
			WebUIEngineStatus().markup.html,
			WebUISeparator().markup.html,
			WebUIOTP().markup.html,
			WebUIStepper(1).markup.html,
			WebUIReactions(reactions: []).markup.html,
			WebUITypingIndicator().markup.html,
		]
		for html in rendered {
			let findings = A11yAudit.audit(html)
			let report = findings.map { "[\($0.rule)] \($0.element) — \($0.message)" }.joined(separator: "\n")
			#expect(findings.isEmpty, "findings: \(report)")
		}
	}

	// MARK: the audit modifier

	@Test func auditModifierRunsOverRenderedMarkup() {
		let findings = Text("").role(.button).a11yAudit()
		#expect(findings.contains { $0.rule == A11yAudit.buttonNoName })
	}

	// MARK: the framework's own pages are clean

	@Test func showcasePageIsA11yClean() {
		let html = RenderContext.$current.withValue(RenderContext(router: EventRouter())) {
			ShowcasePage(state: ShowcaseState()).markup.html
		}
		let findings = A11yAudit.audit(html)
		// this is the teeth: zero framework-caused findings. if this fails,
		// dump the whole list so the fix is the list.
		let report = findings.map { "[\($0.rule)] \($0.element) — \($0.message)" }.joined(separator: "\n")
		#expect(findings.isEmpty, "showcase findings: \(report)")
	}

	@Test func everyBlockPageIsA11yClean() {
		for block in WebUIBlocks.all {
			let html = WebUIBlocks.page(for: block)
			let findings = A11yAudit.audit(html)
			let report = findings.map { "[\($0.rule)] \($0.element) — \($0.message)" }.joined(separator: "\n")
			#expect(findings.isEmpty, "\(block.rawValue) findings: \(report)")
		}
	}

	@Test func blocksIndexPageIsA11yClean() {
		let findings = A11yAudit.audit(WebUIBlocks.indexPage())
		let report = findings.map { "[\($0.rule)] \($0.element) — \($0.message)" }.joined(separator: "\n")
		#expect(findings.isEmpty, "index findings: \(report)")
	}
}
