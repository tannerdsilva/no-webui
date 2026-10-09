// Localization.swift — the framework's own strings, resolved through the render
// context (w4.5).
//
// every quoted English string a component renders has exactly one home here.
// a host localizing a page sets the localized environment on its
// `RenderContext` once (or passes `strings`/`locale`/`direction` to
// `WebUIDocument`), and every component in the pass reads its strings from
// there. the English defaults are the byte-identity contract of the showcase:
// they are pinned by the `WebUIShowcase --generate` byte gate, so a reworded
// default is a regression, not a pin to update.

/// a catalog of the framework's own strings. a host overrides any subset;
/// anything it omits keeps the English default.
public struct WebUIStrings: Sendable {
    public var dismiss: String = "Dismiss"
    public var close: String = "Close"
    public var addReaction: String = "Add reaction"
    public var loading: String = "Loading"
    public var required: String = "Required"
    public var selectAllRows: String = "Select all rows"
    /// a row's selection label with its stable row id.
    public var selectRow: @Sendable (String) -> String = { "Select row \($0)" }
    /// a row's expander label with its stable row id.
    public var expandRow: @Sendable (String) -> String = { "Expand row \($0)" }
    public var remove: String = "Remove"
    public var showOmittedItems: String = "Show omitted items"
    public var pagination: String = "Pagination"
    public var previousPage: String = "Previous page"
    public var nextPage: String = "Next page"
    public var rowsPerPage: String = "Rows per page"
    public var someoneIsTyping: String = "Someone is typing"
    public var notifications: String = "Notifications"
    /// appended to ``notifications`` when the bell carries an unread count.
    public var unreadCount: @Sendable (Int) -> String = { ", \($0) unread" }
    public var messages: String = "Messages"
    public var removeAttachment: String = "Remove attachment"
    public var sent: String = "Sent"
    public var delivered: String = "Delivered"
    public var read: String = "Read"
    public var stepper: String = "Stepper"
    public var decrease: String = "Decrease"
    public var increase: String = "Increase"
    public var oneTimeCode: String = "One-time code"
    /// a single otp cell's label, with its one-based position.
    public var digit: @Sendable (Int) -> String = { "Digit \($0)" }
    public var scan: String = "Scan"
    public var enterCode: String = "Enter code"
    public var verify: String = "Verify"
    public var select: String = "Select…"
    public var filter: String = "Filter…"
    public var signHere: String = "Sign here"
    public var clear: String = "Clear"
    public var save: String = "Save"
    public var cancel: String = "Cancel"
    /// a rating's accessible name, e.g. "4 of 5".
    public var ratingValue: @Sendable (Double, Int) -> String = { "\($0) of \($1)" }
    /// a tag's remove label with the tag's own name.
    public var removeItem: @Sendable (String) -> String = { "Remove \($0)" }
    public var cardNumber: String = "Card number"
    public var cardHolder: String = "Card holder"
    public var typeAndPressEnter: String = "Type and press enter…"
    public var search: String = "Search"
    public var menu: String = "Menu"
    public var primary: String = "Primary"
    public var options: String = "Options"
    public var tableOfContents: String = "Table of contents"
    public var onThisPage: String = "On this page"
    public var breadcrumb: String = "Breadcrumb"
    /// a masked input whose revealed value is hidden — the input's aria name.
    public var maskedValue: String = "masked value"
    public var add: String = "Add"
    public var previous: String = "Previous"
    public var next: String = "Next"
    public var noMatches: String = "No matches"
    public var typeACommand: String = "Type a command…"
    public var backToTop: String = "Back to top"
    public var today: String = "Today"
    public var findTimezone: String = "Find a timezone…"
    public var searchCountries: String = "Search countries…"
    public var tasks: String = "Tasks"
    /// the formula-bar prefix on a data sheet (universal spreadsheet glyph).
    public var formula: String = "Fx"
    /// the visible copy button text on a code block.
    public var copy: String = "copy"
    /// the copy button's accessible name on a code block.
    public var copyLabel: String = "Copy"
    public var map: String = "map"
    public var mainNavigation: String = "Main"
    /// a carousel dot's accessible name with its one-based slide position.
    public var slide: @Sendable (Int) -> String = { "Slide \($0)" }

    /// the default catalog — every string's byte-identical English.
    public static let english = WebUIStrings()

    /// an Arabic catalog (w4.5's shipped example override). any string a
    /// locale does not need to differ keeps the English default — overriding
    /// a subset is the designed behavior, not an error.
    public static let arabic = WebUIStrings(
        dismiss: "تجاهل",
        close: "إغلاق",
        addReaction: "أضف رد فعل",
        loading: "جارٍ التحميل",
        required: "مطلوب",
        selectAllRows: "تحديد كل الصفوف",
        selectRow: { "تحديد الصف \($0)" },
        remove: "إزالة",
        showOmittedItems: "إظهار العناصر المحذوفة",
        pagination: "ترقيم الصفحات",
        previousPage: "الصفحة السابقة",
        nextPage: "الصفحة التالية",
        rowsPerPage: "صفوف لكل صفحة",
        someoneIsTyping: "شخص يكتب الآن",
        notifications: "الإشعارات",
        unreadCount: { "، \($0) غير مقروء" },
        messages: "الرسائل",
        removeAttachment: "إزالة المرفق",
        sent: "أُرسل",
        delivered: "وصل",
        read: "قُرئ",
        stepper: "عداد",
        decrease: "إنقاص",
        increase: "زيادة",
        oneTimeCode: "رمز لمرة واحدة",
        digit: { "رقم \($0)" },
        scan: "امسح",
        enterCode: "أدخل الرمز",
        verify: "تحقق",
        select: "اختر…",
        filter: "تصفية…",
        signHere: "وقّع هنا",
        clear: "مسح",
        save: "حفظ",
        cancel: "إلغاء",
        ratingValue: { "\($0) من \($1)" },
        removeItem: { "إزالة \($0)" },
        cardNumber: "رقم البطاقة",
        cardHolder: "اسم حامل البطاقة",
        typeAndPressEnter: "اكتب ثم اضغط إدخال…",
        search: "بحث",
        menu: "قائمة",
        primary: "رئيسي",
        options: "خيارات",
        tableOfContents: "جدول المحتويات",
        onThisPage: "في هذه الصفحة",
        breadcrumb: "مسار التنقل",
        maskedValue: "قيمة مخفية",
        add: "إضافة",
        previous: "السابق",
        next: "التالي",
        noMatches: "لا توجد نتائج",
        typeACommand: "اكتب أمرًا…",
        backToTop: "العودة إلى الأعلى",
        today: "اليوم",
        findTimezone: "ابحث عن منطقة زمنية…",
        searchCountries: "ابحث عن الدول…",
        tasks: "المهام",
        formula: "Fx",
        copy: "نسخ",
        copyLabel: "نسخ",
        map: "خريطة",
        mainNavigation: "التنقل الرئيسي",
        slide: { "الشريحة \($0)" }
    )
}

/// everything a render pass needs to know about how to speak to its reader.
/// conforming types are value types: a page composes one (strings catalog,
/// BCP-47 locale, writing direction) and hands it to the render context.
public protocol LocalizedEnvironment: Sendable {
    var strings: WebUIStrings { get }
    /// the page's language, as a BCP-47 tag (e.g. "ar-SA"), feeding `<html lang>`.
    var locale: String { get }
    /// the page's base writing direction (`ltr` / `rtl`), feeding `<html dir>`.
    var direction: Directionality { get }
}

/// the concrete default localization: english strings, `en`, ltr — the
/// byte-identical baseline every unlocalized render pass produces.
public struct WebUILocalization: LocalizedEnvironment {
    public var strings: WebUIStrings
    public var locale: String
    public var direction: Directionality

    public init(
        strings: WebUIStrings = .english,
        locale: String = "en",
        direction: Directionality = .ltr
    ) {
        self.strings = strings
        self.locale = locale
        self.direction = direction
    }
}
