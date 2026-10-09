import WebUICore

// MARK: - DesignTokenAxis

/// the five axes a ``DesignTheme`` reads tokens through.
///
/// the partition is a *name contract*: a token's axis follows from its css
/// name, so the flat ``@Theme`` members, the synthesized ``DesignTheme``
/// conformance and a hand-written one all group the vocabulary the same way.
/// the families are: `space*`/`spacing*` → spacing, `radius*` → radii, the
/// `font*`/`fs*`/`line-height*`/`letter-spacing*`/`text*` families →
/// typography, `transition*`/`ease*` → motion, and everything else → palette
/// (the catch-all where every colour, ring, shadow, z-index and border token
/// lives).
public enum DesignTokenAxis: String, Sendable, Equatable, CaseIterable {
	case palette
	case spacing
	case radii
	case typography
	case motion
}

extension DesignToken {
	/// the axis this token belongs to, by the documented name contract.
	///
	/// the prefix families are the same ones `WebUIThemeMacro` uses to
	/// partition flat ``@Theme`` members — a token whose name starts with a
	/// family prefix always lands on that family's axis, and anything else
	/// lands on the palette catch-all. because the vocabulary is camelCased
	/// from the same names, ``DesignToken.axis`` agrees with the macro's
	/// partition for every generated case (pinned by the token-completeness
	/// suite).
	public var axis: DesignTokenAxis {
		let name = rawValue
		if name.hasPrefix("space") || name.hasPrefix("spacing") { return .spacing }
		if name.hasPrefix("radius") { return .radii }
		if name.hasPrefix("font") || name.hasPrefix("fs")
			|| name.hasPrefix("line-height") || name.hasPrefix("letter-spacing")
			|| name.hasPrefix("text") { return .typography }
		if name.hasPrefix("transition") || name.hasPrefix("ease") { return .motion }
		return .palette
	}
}
