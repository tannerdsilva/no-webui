import Foundation
import Testing
@testable import WebUIAssetTool

// MARK: - the token surface, pruned
//
// T9's acceptance is "a catalog using 40 of 174 tokens emits a sheet with 40". The count is
// asserted at the CLI level (`TokenPruningCLITests`); these cases are the parser, where the
// failures are silent — a value that contains a `;`, a comment that looks like a declaration,
// a `var()` reference mistaken for one, a block left unbalanced.

@Suite("token pruning")
struct TokenPruningTests {

	@Test("a kept declaration is copied verbatim, a dropped one is gone")
	func keepsAndDrops() {
		let css = """
		:root {
			--alpha: 1;
			--beta: 2;
		}
		"""
		let out = TokenPruning.prune(css, keeping: ["alpha"])
		#expect(out.css.contains("--alpha: 1;"))
		#expect(!out.css.contains("--beta"))
		#expect(out.dropped == ["beta"])
		#expect(out.kept == ["alpha"])
		#expect(out.emittedTokens == 1)
		#expect(out.declarations == 2)
	}

	@Test("a :root nested in an at-rule is pruned too — the dark pass is part of the surface")
	func nestedRoot() {
		let css = """
		:root {
			--alpha: 1;
		}
		@media (prefers-color-scheme: dark) {
			:root {
				--beta: 2;
			}
		}
		"""
		let out = TokenPruning.prune(css, keeping: ["alpha"])
		#expect(out.dropped == ["beta"])
		#expect(!out.css.contains("--beta"))
		#expect(out.css.contains("@media (prefers-color-scheme: dark)"))
	}

	@Test("a component-scoped custom property is not a design token and is never touched")
	func componentScoped() {
		// `--btn-bg` is declared inside a component rule, not on `:root`: it is not in the
		// vocabulary a theme overrides, so pruning the token surface must not reach it.
		let css = """
		:root {
			--alpha: 1;
			--beta: 2;
		}
		.button {
			--btn-bg: var(--alpha);
			background: var(--btn-bg);
		}
		"""
		let out = TokenPruning.prune(css, keeping: ["alpha"])
		#expect(out.css.contains("--btn-bg: var(--alpha);"))
		#expect(!out.css.contains("--beta"))
		#expect(out.declarations == 2, "only the :root declarations count")
	}

	@Test("a value containing a semicolon is dropped whole, quotes and calls included")
	func valueWithSemicolons() {
		let css = """
		:root {
			--dropme: url("data:image/svg+xml;base64,AAA");
			--keepme: color-mix(in oklab, red 50%, blue 50%);
			--alpha: 1;
		}
		.rule {
			color: var(--alpha);
		}
		"""
		let out = TokenPruning.prune(css, keeping: ["alpha", "keepme"])
		#expect(!out.css.contains("--dropme"))
		#expect(!out.css.contains("base64"))
		#expect(out.css.contains("--keepme: color-mix(in oklab, red 50%, blue 50%);"))
		#expect(out.css.contains(".rule {\n\tcolor: var(--alpha);\n}"), "the rule after the dropped value survives intact")
	}

	@Test("a comment copies through, and is never read as a declaration")
	func commentsPreserved() {
		let css = """
		/* --commented-out: 1; */
		:root {
			/* --also-commented: 2; */
			--alpha: 1;
			--beta: 2;
		}
		"""
		let out = TokenPruning.prune(css, keeping: ["alpha"])
		#expect(out.css.contains("/* --commented-out: 1; */"))
		#expect(out.css.contains("/* --also-commented: 2; */"))
		#expect(out.dropped == ["beta"], "a commented name is not a declaration")
		#expect(out.declarations == 2)
	}

	@Test("a var() reference is a use, not a declaration")
	func referencesAreNotDeclarations() {
		// this is the alias shape: `--alpha` is declared, `--beta` is only referenced. the
		// reference must survive (the keep-set's job is to have kept `beta` if it mattered),
		// and it must never be counted — or dropped — as a declaration of its own.
		let css = """
		:root {
			--alpha: var(--beta);
		}
		"""
		let out = TokenPruning.prune(css, keeping: ["alpha"])
		#expect(out.css.contains("--alpha: var(--beta);"))
		#expect(out.dropped.isEmpty)
		#expect(out.declarations == 1)
	}

	@Test("an unterminated last declaration leaves the block balanced")
	func missingSemicolon() {
		let css = """
		:root {
			--alpha: 1;
			--beta: 2
		}
		.rule { color: red; }
		"""
		let out = TokenPruning.prune(css, keeping: ["alpha"])
		#expect(out.css.filter { $0 == "{" }.count == out.css.filter { $0 == "}" }.count)
		#expect(!out.css.contains("--beta"))
		#expect(out.css.contains(".rule { color: red; }"), "the following rule is untouched")
	}

	@Test("the same token declared twice is dropped once, and still counts twice")
	func repeatedToken() {
		let css = """
		:root { --alpha: 1; --beta: 2; }
		@media (prefers-color-scheme: dark) { :root { --beta: 3; } }
		"""
		let out = TokenPruning.prune(css, keeping: ["alpha"])
		#expect(out.dropped == ["beta"], "the report is per name, not per occurrence")
		#expect(out.declarations == 3)
		#expect(!out.css.contains("--beta"))
	}

	@Test("a listing tolerates comments, commas, and optional -- prefixes")
	func listingFormat() {
		let listing = """
		# the tokens this app resolves
		--alpha, beta
		gamma  delta
		"""
		let names = TokenPruning.names(inListing: listing)
		#expect(names == ["alpha", "beta", "gamma", "delta"])
	}

	@Test("a guard stylesheet's references are found, app-invented properties included")
	func guardReferences() {
		let names = TokenPruning.referencedNames(in: """
		.x { color: var(--color-bg); background: var(--chat-bubble); }
		.y { border-color: var(--color-border, #ccc); }
		""")
		#expect(names.contains("color-bg"))
		#expect(names.contains("chat-bubble"), "scanned as text: an unknown name simply matches no declaration")
		#expect(names.contains("color-border"), "the fallback form still names the token")
	}
}