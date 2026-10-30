# Website design review — October 29, 2026

## Summary

Rating after fixes: Good. This is a responsive HTML/CSS/JavaScript product website for Mac users exploring DockGrove and its test purchase flow. Its defining element is the illustrative Dock and the hands-on app replacement example; supporting controls stay quiet and legible. The pet redesign is explicitly excluded from this publication. The review applied web-relevant principles from the user-requested [Apple Design Skill](https://github.com/dickwu/apple-design-skill/blob/main/SKILL.md), not native menu-bar or mobile-tab conventions.

Read ten references: accessibility, layout, typography, color, writing, buttons, text-fields, dark-mode, motion, and cross-platform. No scripts or dependencies from that repository were executed.

## Fixes

- **High — text scaling:** fixed-size CSS text and intrinsic grid widths made enlarged text fragile. Converted type sizes to rem, retained the system font stack, allowed controls/cards to wrap and made appearance options stack when needed. A local 200% root-font fixture at 320px initially measured 369px document width; after fixes it measures 320px with no overflowing elements. `layout.md › Adaptability`: “Be prepared for text-size changes.” [Reference](https://github.com/dickwu/apple-design-skill/blob/main/references/hig/layout.md#adaptability). `typography.md › Supporting Dynamic Type`: “Make sure your app’s layout adapts to all font sizes.” [Reference](https://github.com/dickwu/apple-design-skill/blob/main/references/hig/typography.md#supporting-dynamic-type).
- **Medium — touch and keyboard clarity:** interactive buttons, appearance segments, FAQ summaries and supporting links now have 44px minimum height. Inputs have a distinct semantic border; focus rings use separate light/dark tokens. Search reports its result count through a polite status region. `buttons.md › Best practices`: “Make buttons easy for people to use.” [Reference](https://github.com/dickwu/apple-design-skill/blob/main/references/hig/buttons.md#best-practices). `text-fields.md › Best practices`: “Ensure that tabbing between multiple fields flows as people expect.” [Reference](https://github.com/dickwu/apple-design-skill/blob/main/references/hig/text-fields.md#best-practices).
- **Medium — accessibility appearance:** corrected increased-contrast selector specificity so it also applies to dark appearance overrides. Reduced-transparency Dock sample now switches its text and meter to semantic colors, avoiding dark text on a dark opaque surface. These media-query paths were code-reviewed; no OS accessibility setting was changed. `color.md › Best practices`: “Make sure all your app’s colors work well in light, dark, and increased contrast contexts.” [Reference](https://github.com/dickwu/apple-design-skill/blob/main/references/hig/color.md#best-practices).
- **Low — readable sample context and restraint:** enlarged tiny sample labels and placed them on a solid high-contrast backing. Removed 01/02 markers because these features are not sequential steps (design judgment). Added hover and press feedback without extra motion. `writing.md › Getting started`: “Be clear.” [Reference](https://github.com/dickwu/apple-design-skill/blob/main/references/hig/writing.md#getting-started).

## Tokens and computed contrast

Existing quiet sage surfaces and system typography are retained. The Dock preview remains the signature; no new animation or decorative component was added. Regular layout is paired feature columns and an illustrative Dock; compact layout stacks the features and keeps the same interactive controls. Font preference changes preserve information and allow controls to stack.

Ratios use WCAG relative luminance computed from CSS hex values, not screenshot sampling. Solid background/surface/soft tokens: light #f8f7f4 / #ffffff / #eeeee8; dark #151915 / #20261f / #293026.

| Role | Light | Minimum ratio across three surfaces | Dark | Minimum ratio across three surfaces |
| --- | --- | --- | --- | --- |
| Main text | #202321 | 13.62:1 | #f3f5ec | 12.35:1 |
| Secondary text | #656961 | 4.81:1 | #a5afa2 | 5.99:1 |
| Focus ring | #526b27 | 5.16:1 on soft | #d8f482 | 11.12:1 on soft |
| Input border | #818879 | 3.15:1 on soft | #7e8e75 | 3.89:1 on soft |

The prior focus ring #71893f already met 3:1 on soft backgrounds (light 3.37:1, dark 3.46:1); the new role-specific values improve visibility. Gradient artwork and transparency are not covered by these solid-color calculations. The sample captions now use white on #263023 (13.73:1) instead of translucent small text over the illustration. `accessibility.md › Vision`: “Strive to meet color contrast minimum standards.” [Reference](https://github.com/dickwu/apple-design-skill/blob/main/references/hig/accessibility.md#vision).

## Verification and limits

Chrome keyboard review: Enter opens Replace and focuses search; type Unity, ArrowDown and Return performs replacement; Enter on Undo restores Visual Studio Code; Escape cancels and returns focus to Replace. Computed focus ring was 3px #d8f482 and Replace min-height 44px. The polite results status is represented in the accessibility tree. This is not a complete VoiceOver audit.

At 320 × 740, normal and 200% root-font layouts remain 320px wide. The enlarged-text fixture was removed after testing; no test-only page ships. Light/dark appearance and prior 390px checks remain relevant, and the final source retains reduced-motion styles. Browser viewport overrides are restored after review. The static checkout remains disabled and no payment/provider configuration changed. Site release checks and eight frontend behavioral checks pass.

## Published static version

Published October 29, 2026 to https://wavedock-preview.limit-dylanlasensky.workers.dev using the existing Worker and zero bindings. Cloudflare version: `d0ff1466-eb19-49cb-abc9-2b180fd9606c`. Uploaded 14 packaged static files (10 changed assets). No commerce Worker, database, storage bucket or live payments were deployed.

Post-deploy browser review confirmed the app-focused page and disabled checkout. Live `product.json` reports amount 999 USD cents, test mode, `available:false`; both `/downloads/DockGrove-0.8.0.zip` and `/assets/companions/dragon.png` return HTTP 404. Local release checks, eight frontend behavior checks and eleven test-backend cases passed. Desktop dark and 390px light layouts, keyboard app replacement and Undo were verified.

## Final visual correction: original identity restored

Following user feedback, the publication now restores the original 0.8 homepage structure and visual identity instead of the intermediate storefront: spacious light editorial sections, floating navigation, Find your flow headline, a large charcoal Dock illustration, sticky window story, dark AI usage section, and interactive layout/accent examples. The searchable app picker replaces the old pet card. Pricing is secondary at the footer with Coming soon; internal test-mode setup remains on dedicated utility pages.

Final browser QA verified desktop hero/workspace, 390px mobile hero/navigation/pricing, 320px document width with no horizontal overflow, keyboard provider switching, Unity replacement and Undo, and light/dark Dock illustration controls (light #f7f8f6/#28312a; dark #242a27/#f0f4ef). Browser viewport and appearance preview returned to defaults. The earlier 200% fixture and token table describe the intermediate shared utility stylesheet, not a fresh full-page 200% audit of the restored homepage. No such acceptance is claimed for the new homepage. Site release checks, nine frontend security/behavior cases, and eleven commerce cases pass. No native Sources files changed.

Final restored-design publication: https://wavedock-preview.limit-dylanlasensky.workers.dev — Cloudflare version `5896ef10-bb84-46f6-827f-be3b0206d3ae`, October 29, 2026. This supersedes the intermediate d0ff1466 version. The deployed page was checked in Chrome and shows Find your flow, the restored sections, and disabled Coming soon. Static package: 16 files, no bindings, no pet artwork, no public app binaries.
