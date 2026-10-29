# Native UI review

Reviewed the SwiftUI/AppKit utility against the user-provided [Apple Design Skill](https://github.com/dickwu/apple-design-skill/blob/main/SKILL.md), reading ten reference files: accessibility, layout, typography, color, designing-for-macos, settings, liquid-glass, dark-mode, buttons, and search-fields. This is a source review and targeted implementation, not a blanket HIG certification or a measured contrast audit.

## Changes

- Settings now disclose development-only license testing instead of putting a large purchase form ahead of personalization. Commercial activation remains visible. This follows `layout.md` → Visual hierarchy: “Use progressive disclosure to make layouts cleaner and easier to interact with.” Activation uses a standard prominent button and shows progress during requests (`buttons.md` → Style). No license verification or feature gate changed.
- Settings cards use AppKit control-background and separator colors; Dock borders and usage labels use adaptive semantic colors. Small usage captions and the release label are at least 10 pt (`accessibility.md` → Vision; `typography.md` → Ensuring legibility; `dark-mode.md` → Dark Mode colors). Existing manual appearance overrides remain because the user explicitly wants them; system-following remains available. Liquid Glass remains on the floating functional surface, not added to settings content (`liquid-glass.md` → The two layers).
- The app picker focuses search on opening, provides a labeled Clear action, distinguishes scanning from no results, and explains how to recover from an empty result. Search updates immediately (`search-fields.md` → Best practices). Native List selection and Return/Escape actions remain. Filtering now clears an invisible selection and the action resolves only a currently visible result, preventing a hidden app from being added or replaced. A published scan state reflects the existing asynchronous scan rather than a simulated delay.
- Pet artwork, behavior, and the existing visible widget title remain at the baseline version; pet redesign is excluded from this publication.
- Running indicators and Quit App compare standardized paths, matching DockApp identity and avoiding URL trailing-directory-slash mismatches.

## Scope and evidence

The design stays a quiet desktop utility: familiar controls frame the distinctive animated companions. No full navigation rewrite, new theme, or color-token palette was introduced. Mac personalization guidance (`designing-for-macos.md` → Best practices) and settings grouping (`settings.md` → General settings) informed this bounded scope. No physical screen contrast ratio is claimed for adaptive colors; light/dark and accessibility visual checks remain part of release validation.

Swift frontend parse passed for every edited native file. The earlier local candidate passed full-source arm64 Swift type-check. This non-pet publication is validated independently; see the final integration results. Source inspection confirms commercial gates remain intact and no raw-value migration was introduced. No installed app or live Dock preference was modified by this review.
