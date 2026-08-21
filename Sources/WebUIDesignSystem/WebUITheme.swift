import Foundation
import WebUI

// MARK: - WebUITheme
public enum WebUITheme {

    public static let neutralPalette = CSSRule(":root", [
        CSSDeclaration("--color-neutral-50", "#f8fafc"),
        CSSDeclaration("--color-neutral-100", "#f1f5f9"),
        CSSDeclaration("--color-neutral-200", "#e2e8f0"),
        CSSDeclaration("--color-neutral-300", "#cbd5e1"),
        CSSDeclaration("--color-neutral-400", "#94a3b8"),
        CSSDeclaration("--color-neutral-500", "#64748b"),
        CSSDeclaration("--color-neutral-600", "#475569"),
        CSSDeclaration("--color-neutral-700", "#334155"),
        CSSDeclaration("--color-neutral-800", "#1e293b"),
        CSSDeclaration("--color-neutral-900", "#0f172a"),
        CSSDeclaration("--color-neutral-950", "#0a0f1c")
    ])

    public static let primaryPalette = CSSRule(":root", [
        CSSDeclaration("--color-primary-50", "#ecfdf9"),
        CSSDeclaration("--color-primary-100", "#d1faf1"),
        CSSDeclaration("--color-primary-200", "#a5f3e4"),
        CSSDeclaration("--color-primary-300", "#6ee7d3"),
        CSSDeclaration("--color-primary-400", "#34d3b8"),
        CSSDeclaration("--color-primary-500", "#10b89f"),
        CSSDeclaration("--color-primary-600", "#0c9488"),
        CSSDeclaration("--color-primary-700", "#0d756c"),
        CSSDeclaration("--color-primary-800", "#0f5e57"),
        CSSDeclaration("--color-primary-900", "#114e48"),
        CSSDeclaration("--color-primary-950", "#042f2e")
    ])
    public static let primarySolid = CSSRule(":root", [
        CSSDeclaration("--color-primary-solid", "var(--color-primary-700)"),
        CSSDeclaration("--color-primary-solid-hover", "var(--color-primary-800)"),
        CSSDeclaration("--color-primary-solid-active", "var(--color-primary-900)"),
        CSSDeclaration("--color-on-primary-solid", "#ffffff")
    ])

    public static let semanticColors = CSSRule(":root", [
        CSSDeclaration("--color-success", "#16a34a"),
        CSSDeclaration("--color-success-strong", "#15803d"),
        CSSDeclaration("--color-success-soft", "#dcfce7"),
        CSSDeclaration("--color-success-ring", "#22c55e"),

        CSSDeclaration("--color-warning", "#d97706"),
        CSSDeclaration("--color-warning-strong", "#b45309"),
        CSSDeclaration("--color-warning-soft", "#fef3c7"),
        CSSDeclaration("--color-warning-ring", "#f59e0b"),

        CSSDeclaration("--color-danger", "#dc2626"),
        CSSDeclaration("--color-danger-strong", "#b91c1c"),
        CSSDeclaration("--color-danger-soft", "#fee2e2"),
        CSSDeclaration("--color-danger-ring", "#ef4444"),

        CSSDeclaration("--color-info", "#2563eb"),
        CSSDeclaration("--color-info-strong", "#1d4ed8"),
        CSSDeclaration("--color-info-soft", "#dbeafe"),
        CSSDeclaration("--color-info-ring", "#3b82f6")
    ])

    public static let surfaceColors = CSSRule(":root", [
        CSSDeclaration("--color-bg", "#f6f8fa"),
        CSSDeclaration("--color-bg-raised", "#ffffff"),
        CSSDeclaration("--color-bg-inset", "#eef2f6"),
        CSSDeclaration("--color-bg-subtle", "#f1f5f9"),

        CSSDeclaration("--color-text", "#1e293b"),
        CSSDeclaration("--color-text-muted", "#64748b"),
        CSSDeclaration("--color-text-faint", "#94a3b8"),
        CSSDeclaration("--color-on-color", "#ffffff"),

        CSSDeclaration("--color-border", "#e2e8f0"),
        CSSDeclaration("--color-border-strong", "#cbd5e1")
    ])
    public static let focusTokens = CSSRule(":root", [
        CSSDeclaration("--color-focus-ring", "rgba(16, 184, 159, 0.45)"),
        CSSDeclaration("--color-focus-ring-danger", "rgba(220, 38, 38, 0.45)"),
        CSSDeclaration("--color-focus", "var(--color-primary-400)")
    ])
    public static let scrollbarTokens = CSSRule(":root", [
        CSSDeclaration("--scrollbar-track", "transparent"),
        CSSDeclaration("--scrollbar-thumb", "#cbd5e1"),
        CSSDeclaration("--scrollbar-thumb-hover", "#94a3b8")
    ])

    public static let typography = CSSRule(":root", [
        CSSDeclaration("--font-sans", "-apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, \"Helvetica Neue\", Arial, \"Noto Sans\", sans-serif"),
        CSSDeclaration("--font-mono", "ui-monospace, SFMono-Regular, \"SF Mono\", Menlo, Consolas, \"Liberation Mono\", \"Courier New\", monospace"),

        CSSDeclaration("--font-size-xs", "0.75rem"),
        CSSDeclaration("--font-size-sm", "0.875rem"),
        CSSDeclaration("--font-size-base", "1rem"),
        CSSDeclaration("--font-size-lg", "1.125rem"),
        CSSDeclaration("--font-size-xl", "1.25rem"),
        CSSDeclaration("--font-size-2xl", "1.5rem"),
        CSSDeclaration("--font-size-3xl", "1.875rem"),
        CSSDeclaration("--font-size-4xl", "2.25rem"),
        CSSDeclaration("--font-size-5xl", "3rem"),

        CSSDeclaration("--font-weight-normal", "400"),
        CSSDeclaration("--font-weight-medium", "500"),
        CSSDeclaration("--font-weight-semibold", "600"),
        CSSDeclaration("--font-weight-bold", "700"),

        CSSDeclaration("--line-height-tight", "1.25"),
        CSSDeclaration("--line-height-normal", "1.5"),
        CSSDeclaration("--line-height-relaxed", "1.75"),

        CSSDeclaration("--letter-spacing-tight", "-0.02em"),
        CSSDeclaration("--letter-spacing-normal", "0"),
        CSSDeclaration("--letter-spacing-wide", "0.02em"),
        CSSDeclaration("--letter-spacing-wider", "0.08em"),

        CSSDeclaration("--fs-hero", "clamp(2rem, 1.4rem + 2.4vw, 3.25rem)")
    ])

    public static let spacing = CSSRule(":root", [
        CSSDeclaration("--space-0", "0px"),
        CSSDeclaration("--space-1", "0.25rem"),
        CSSDeclaration("--space-2", "0.5rem"),
        CSSDeclaration("--space-3", "0.75rem"),
        CSSDeclaration("--space-4", "1rem"),
        CSSDeclaration("--space-5", "1.25rem"),
        CSSDeclaration("--space-6", "1.5rem"),
        CSSDeclaration("--space-8", "2rem"),
        CSSDeclaration("--space-10", "2.5rem"),
        CSSDeclaration("--space-12", "3rem"),
        CSSDeclaration("--space-16", "4rem"),
        CSSDeclaration("--space-20", "5rem"),
        CSSDeclaration("--space-24", "6rem")
    ])

    public static let borders = CSSRule(":root", [
        CSSDeclaration("--radius-none", "0px"),
        CSSDeclaration("--radius-sm", "0.125rem"),
        CSSDeclaration("--radius-md", "0.375rem"),
        CSSDeclaration("--radius-lg", "0.5rem"),
        CSSDeclaration("--radius-xl", "0.75rem"),
        CSSDeclaration("--radius-2xl", "1rem"),
        CSSDeclaration("--radius-full", "9999px"),

        CSSDeclaration("--border-width", "1px"),
        CSSDeclaration("--border-width-2", "2px")
    ])

    public static let shadows = CSSRule(":root", [
        CSSDeclaration("--shadow-sm", "0 1px 2px rgba(15,23,42,0.06), 0 1px 1px rgba(15,23,42,0.04)"),
        CSSDeclaration("--shadow-md", "0 4px 8px -2px rgba(15,23,42,0.10), 0 2px 4px -2px rgba(15,23,42,0.08)"),
        CSSDeclaration("--shadow-lg", "0 16px 32px -8px rgba(15,23,42,0.18), 0 8px 16px -8px rgba(15,23,42,0.10)"),
        CSSDeclaration("--shadow-xl", "0 24px 48px -12px rgba(15,23,42,0.28), 0 12px 24px -12px rgba(15,23,42,0.16)"),

        CSSDeclaration("--ring-focus", "0 0 0 3px var(--color-focus-ring)"),
        CSSDeclaration("--ring-focus-danger", "0 0 0 3px var(--color-focus-ring-danger)")
    ])

    public static let motion = CSSRule(":root", [
        CSSDeclaration("--transition-fast", "150ms ease"),
        CSSDeclaration("--transition-base", "200ms ease"),
        CSSDeclaration("--transition-slow", "300ms ease"),
        CSSDeclaration("--ease-out", "cubic-bezier(0.16, 1, 0.3, 1)")
    ])

    public static let zIndex = CSSRule(":root", [
        CSSDeclaration("--z-base", "1"),
        CSSDeclaration("--z-dropdown", "10"),
        CSSDeclaration("--z-sticky", "20"),
        CSSDeclaration("--z-nav", "30"),
        CSSDeclaration("--z-overlay", "40"),
        CSSDeclaration("--z-modal", "50"),
        CSSDeclaration("--z-toast", "60"),
        CSSDeclaration("--z-tooltip", "70")
    ])

    public static let darkMode = CSSMediaQuery("prefers-color-scheme: dark", rules: [
        CSSRule(":root", [
            CSSDeclaration("--color-neutral-50", "#0a0f1c"),
            CSSDeclaration("--color-neutral-100", "#0f172a"),
            CSSDeclaration("--color-neutral-200", "#1e293b"),
            CSSDeclaration("--color-neutral-300", "#334155"),
            CSSDeclaration("--color-neutral-400", "#475569"),
            CSSDeclaration("--color-neutral-500", "#64748b"),
            CSSDeclaration("--color-neutral-600", "#94a3b8"),
            CSSDeclaration("--color-neutral-700", "#cbd5e1"),
            CSSDeclaration("--color-neutral-800", "#e2e8f0"),
            CSSDeclaration("--color-neutral-900", "#f1f5f9"),
            CSSDeclaration("--color-neutral-950", "#f8fafc"),

            CSSDeclaration("--color-primary-50", "#042f2e"),
            CSSDeclaration("--color-primary-100", "#114e48"),
            CSSDeclaration("--color-primary-200", "#0f5e57"),
            CSSDeclaration("--color-primary-300", "#0d756c"),
            CSSDeclaration("--color-primary-400", "#0c9488"),
            CSSDeclaration("--color-primary-500", "#34d3b8"),
            CSSDeclaration("--color-primary-600", "#6ee7d3"),
            CSSDeclaration("--color-primary-700", "#a5f3e4"),
            CSSDeclaration("--color-primary-800", "#d1faf1"),
            CSSDeclaration("--color-primary-900", "#ecfdf9"),
            CSSDeclaration("--color-primary-950", "#ecfdf9"),

            CSSDeclaration("--color-primary-solid", "var(--color-primary-500)"),
            CSSDeclaration("--color-primary-solid-hover", "var(--color-primary-400)"),
            CSSDeclaration("--color-primary-solid-active", "var(--color-primary-300)"),
            CSSDeclaration("--color-on-primary-solid", "#042f2e"),

            CSSDeclaration("--color-success", "#22c55e"),
            CSSDeclaration("--color-success-strong", "#4ade80"),
            CSSDeclaration("--color-success-soft", "#052e16"),
            CSSDeclaration("--color-success-ring", "#22c55e"),

            CSSDeclaration("--color-warning", "#f59e0b"),
            CSSDeclaration("--color-warning-strong", "#fbbf24"),
            CSSDeclaration("--color-warning-soft", "#451a03"),
            CSSDeclaration("--color-warning-ring", "#f59e0b"),

            CSSDeclaration("--color-danger", "#ef4444"),
            CSSDeclaration("--color-danger-strong", "#f87171"),
            CSSDeclaration("--color-danger-soft", "#450a0a"),
            CSSDeclaration("--color-danger-ring", "#ef4444"),

            CSSDeclaration("--color-info", "#3b82f6"),
            CSSDeclaration("--color-info-strong", "#60a5fa"),
            CSSDeclaration("--color-info-soft", "#172554"),
            CSSDeclaration("--color-info-ring", "#3b82f6"),

            CSSDeclaration("--color-bg", "#0a0e17"),
            CSSDeclaration("--color-bg-raised", "#101625"),
            CSSDeclaration("--color-bg-inset", "#0d121f"),
            CSSDeclaration("--color-bg-subtle", "#0f1522"),

            CSSDeclaration("--color-text", "#e6edf7"),
            CSSDeclaration("--color-text-muted", "#8892a8"),
            CSSDeclaration("--color-text-faint", "#5a6478"),
            CSSDeclaration("--color-on-color", "#0a0e17"),

            CSSDeclaration("--color-border", "#1e2740"),
            CSSDeclaration("--color-border-strong", "#2a3550"),

            CSSDeclaration("--color-focus-ring", "rgba(52, 211, 184, 0.50)"),
            CSSDeclaration("--color-focus-ring-danger", "rgba(239, 68, 68, 0.50)"),
            CSSDeclaration("--color-focus", "var(--color-primary-400)"),

            CSSDeclaration("--scrollbar-track", "transparent"),
            CSSDeclaration("--scrollbar-thumb", "#2a3550"),
            CSSDeclaration("--scrollbar-thumb-hover", "#3a4560"),

            CSSDeclaration("--shadow-sm", "0 1px 2px rgba(0,0,0,0.3)"),
            CSSDeclaration("--shadow-md", "0 4px 8px -2px rgba(0,0,0,0.4), 0 2px 4px -2px rgba(0,0,0,0.3)"),
            CSSDeclaration("--shadow-lg", "0 16px 32px -8px rgba(0,0,0,0.5), 0 8px 16px -8px rgba(0,0,0,0.3)"),
            CSSDeclaration("--shadow-xl", "0 24px 48px -12px rgba(0,0,0,0.6), 0 12px 24px -12px rgba(0,0,0,0.4)")
        ]),
    ])

    public static let all: [CSSRule] = [
        neutralPalette,
        primaryPalette,
        primarySolid,
        semanticColors,
        surfaceColors,
        focusTokens,
        scrollbarTokens,
        typography,
        spacing,
        borders,
        shadows,
        motion,
        zIndex,
    ]
    public static let allMediaQueries: [CSSMediaQuery] = [
        darkMode,
    ]
    public static func render() -> String {
        var result = CSSStylesheet(all).render()
        for mq in allMediaQueries {
            result += "\n\n" + mq.render()
        }
        return result
    }
}
