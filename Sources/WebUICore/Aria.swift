// Aria.swift — the typed aria surface (w4.4).
//
// one case per aria attribute, one `AriaRole` per role the framework emits:
// a component author spells a state, not a string. a value that cannot be
// spelled wrong cannot ship — an aria attribute a component invents out of
// thin air is a compile error, not an unnamed string in the markup.
//
// every value renders through `htmlEscape` (invariant 5) and the framework's
// own emitters build their aria/role attributes through this surface, so the
// served bytes and the typed surface cannot drift.

/// the roles the framework emits, as an enum. `AriaRole` is exhaustive and
/// spelled by case, so `role="cReAtIv3"` is unrepresentable in framework code.
public enum AriaRole: String, Sendable, CaseIterable {
	case alert
	case banner
	case button
	case checkbox
	case complementary
	case dialog
	case form
	case group
	case img
	case listbox
	case log
	case main
	case menu
	case menuitem
	case menuItemCheckbox = "menuitemcheckbox"
	case menuItemRadio = "menuitemradio"
	case navigation
	case option
	case presentation
	case progressbar
	case radioGroup = "radiogroup"
	case region
	case search
	case separator
	case status
	case tab
	case tablist
	case tooltip
	case tree
	case treeitem

	/// ` role="name"`, ready to splice into an opening tag. escape the raw
	/// value exactly like any other attribute value (invariant 5).
	public func render() -> String {
		" role=\"\(htmlEscape(rawValue))\""
	}
}

// MARK: - typed aria values
//
// the plan's spellings are `yes`/`no`/`mixed`, but the ARIA attribute values
// are `true`/`false`/`mixed` — so the case names are the mnemonic and the raw
// values are the served bytes. a component that writes `.expanded(.yes)`
// ships `aria-expanded="true"`.

/// the tri-state family: `aria-checked`, `aria-pressed`.
public enum AriaChecked: String, Sendable, CaseIterable {
	case yes = "true"
	case no = "false"
	case mixed = "mixed"
}

/// `aria-pressed` — same vocabulary as ``AriaChecked``, named by its attribute.
public enum AriaPressed: String, Sendable, CaseIterable {
	case yes = "true"
	case no = "false"
	case mixed = "mixed"
}

/// the yes/no family: `aria-expanded`, and its siblings below.
public enum AriaExpanded: String, Sendable, CaseIterable {
	case yes = "true"
	case no = "false"
}

public enum AriaSelected: String, Sendable, CaseIterable {
	case yes = "true"
	case no = "false"
}

public enum AriaModal: String, Sendable, CaseIterable {
	case yes = "true"
	case no = "false"
}

public enum AriaHidden: String, Sendable, CaseIterable {
	case yes = "true"
	case no = "false"
}

public enum AriaBusy: String, Sendable, CaseIterable {
	case yes = "true"
	case no = "false"
}

/// `aria-live` — the politeness of a live region announcement.
public enum AriaLive: String, Sendable, CaseIterable {
	case off
	case polite
	case assertive
}

/// `aria-current` — which item of the current set is the one in force.
public enum AriaCurrent: String, Sendable, CaseIterable {
	case page
	case step
	case location
	case date
	case time
	case yes = "true"
}

/// `aria-sort` — a sortable column's declared order.
public enum AriaSort: String, Sendable, CaseIterable {
	case none
	case ascending
	case descending
	case other
}

/// `aria-haspopup` — the kind of popup a control reveals.
public enum AriaHasPopup: String, Sendable, CaseIterable {
	case menu
	case listbox
	case tree
	case grid
	case dialog
	case yes = "true"
}

/// `aria-orientation` — a widget's primary axis.
public enum AriaOrientation: String, Sendable, CaseIterable {
	case horizontal
	case vertical
}

// MARK: - Aria (one case per attribute)

/// one typed aria attribute. `render()` produces the escaped
/// ` key="value"` pair; `key`/`value` expose the pieces for callers that
/// assemble their own attribute strings (the modifier path uses them).
public enum Aria: Sendable, Equatable {
	case label(String)
	case labelledby(String)
	case describedby(String)
	case hidden(AriaHidden)
	case busy(AriaBusy)
	case modal(AriaModal)
	case checked(AriaChecked)
	case pressed(AriaPressed)
	case expanded(AriaExpanded)
	case selected(AriaSelected)
	case current(AriaCurrent)
	case live(AriaLive)
	case sort(AriaSort)
	case hasPopup(AriaHasPopup)
	case orientation(AriaOrientation)
	case disabled(Bool)
	case invalid(Bool)
	case controls(String)
	case level(Int)
	case valuemin(Int)
	case valuemax(Int)
	case valuenow(Int)

	/// the attribute name, e.g. `aria-label`.
	public var key: String {
		switch self {
		case .label: return "aria-label"
		case .labelledby: return "aria-labelledby"
		case .describedby: return "aria-describedby"
		case .hidden: return "aria-hidden"
		case .busy: return "aria-busy"
		case .modal: return "aria-modal"
		case .checked: return "aria-checked"
		case .pressed: return "aria-pressed"
		case .expanded: return "aria-expanded"
		case .selected: return "aria-selected"
		case .current: return "aria-current"
		case .live: return "aria-live"
		case .sort: return "aria-sort"
		case .hasPopup: return "aria-haspopup"
		case .orientation: return "aria-orientation"
		case .disabled: return "aria-disabled"
		case .invalid: return "aria-invalid"
		case .controls: return "aria-controls"
		case .level: return "aria-level"
		case .valuemin: return "aria-valuemin"
		case .valuemax: return "aria-valuemax"
		case .valuenow: return "aria-valuenow"
		}
	}

	/// the value, before escaping (the enum's spellings where the attribute
	/// takes a fixed vocabulary, the caller's string otherwise).
	public var value: String {
		switch self {
		case .label(let v), .labelledby(let v), .describedby(let v),
		     .controls(let v): return v
		case .hidden(let v): return v.rawValue
		case .busy(let v): return v.rawValue
		case .modal(let v): return v.rawValue
		case .checked(let v): return v.rawValue
		case .pressed(let v): return v.rawValue
		case .expanded(let v): return v.rawValue
		case .selected(let v): return v.rawValue
		case .current(let v): return v.rawValue
		case .live(let v): return v.rawValue
		case .sort(let v): return v.rawValue
		case .hasPopup(let v): return v.rawValue
		case .orientation(let v): return v.rawValue
		case .disabled(let v), .invalid(let v): return v ? "true" : "false"
		case .level(let v): return String(v)
		case .valuemin(let v), .valuemax(let v), .valuenow(let v): return String(v)
		}
	}

	/// ` key="value"`, escaped, with the leading space so a component can
	/// splice the pair into an opening tag the way it splices class and id.
	public func render() -> String {
		" \(key)=\"\(htmlEscape(value))\""
	}

	/// assemble a run of attributes into one string, role first (the
	/// framework's opening-tag convention), then each attribute in order.
	public static func attributes(_ attributes: [Aria], role: AriaRole? = nil) -> String {
		var out = ""
		if let role { out += role.render() }
		for attribute in attributes { out += attribute.render() }
		return out
	}
}

// MARK: - view modifiers
//
// the plan's typed surface for page authors: a `role`, a typed `aria`, and
// the two sugars, each going through the framework's attribute merge so the
// value rides the same escaped path as every other attribute.

public extension View {
	/// expose this element with the given role: ` role="..."`.
	func role(_ role: AriaRole) -> ModifiedView<Self, HTMLAttribute> {
		ModifiedView(content: self, modifier: HTMLAttribute("role", role.rawValue))
	}

	/// one typed aria attribute.
	func aria(_ attribute: Aria) -> ModifiedView<Self, HTMLAttribute> {
		ModifiedView(content: self, modifier: HTMLAttribute(attribute.key, attribute.value))
	}

	/// `aria-label`, the most common attribute, spelled as its own modifier.
	func ariaLabel(_ label: String) -> ModifiedView<Self, HTMLAttribute> {
		aria(.label(label))
	}

	/// `aria-live`, for live regions.
	func ariaLive(_ live: AriaLive) -> ModifiedView<Self, HTMLAttribute> {
		aria(.live(live))
	}

	/// make this element keyboard-focusable (`tabindex="0"`); passing `false`
	/// makes it explicitly unfocusable (`tabindex="-1"`).
	func focusable(_ on: Bool = true) -> ModifiedView<Self, HTMLAttribute> {
		ModifiedView(content: self, modifier: HTMLAttribute("tabindex", on ? "0" : "-1"))
	}
}
