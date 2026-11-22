# Interaction reliability audit — November 21, 2026

Scope: the native DockGrove app and its existing website/commerce checks, starting from `21a089e`.
This is a finite regression inventory, not a claim that every application, account, or Mac has been certified.
Personal layouts, stored pet identifiers and names, and system permissions must be preserved while testing.

## Additional fixes found during the audit

- Reminders kept old items visible when a later permission request failed, treated a failed fetch as a successful empty list, and allowed an older asynchronous refresh to replace a newer result. Refresh generations now reject obsolete replies; failures clear the stale reading and explain what happened. Completing a reminder also invalidates an earlier pending read, so it cannot put completed work back into the list.
- The Applications stack preview cache only checked its sort, count, and first/last application. Replacing an application in the middle of a same-size catalog could leave its old icon in the stack. The cache now follows the catalog's revision.
- The Applications stack icon's hover lift and scaling ignored Reduce Motion even though the adjacent application tiles honored it. The stack now uses the same accessibility behavior.
- The website was pinned to Next.js 16.4.3, which its build and npm advisory scan identified as affected by the November security advisories. Next.js and its matching ESLint configuration are now pinned to 16.4.6. The existing TypeScript ESLint dependency was updated within its allowed 8.x range to 8.73.0, bringing in patched minimatch 11.0.9. The final npm audit reports zero known vulnerabilities. This static export does not run the affected image optimizer, Edge routes, or server cache paths; that limits applicability without making a vulnerable dependency desirable. Sources: [Next.js security release](https://nextjs.org/blog/november-2026-security-release), [16.4.6 release](https://github.com/vercel/next.js/releases/tag/v16.4.6), and [minimatch advisory](https://github.com/advisories/GHSA-g3hv-75wg-m249).

Regression cases are in `IntegrationsUtilitiesTests` and `ApplicationsStackTests`; native execution evidence and its limits are recorded below.

## Verification inventory

| Area | Cases to exercise | Existing regression sources / evidence boundary |
| --- | --- | --- |
| Pet interaction | Rename after opening from Dock and notch; repeated opening; typing, Return and cancellation; empty/long names; feeding, play, rest and wake; resizing/full screen; saved names and needs | Companion state/motion, integration, and native-render tests; live focus must be checked separately |
| Window overview | Permission missing/granted/revoked; slow/nonresponsive app; partial and repeated scans; open and minimized windows; search/grouping; restore/minimize/focus; vanished windows; action cancellation; negative screen coordinates | `CoreCoverageTestsWindows`, native window fixtures; browser tabs inside one window are not separate AX windows |
| Dock visibility | Large ordinary windows; overlap on each supported edge; deliberate edge reveal; active interactions; native full screen; manual hide; quit/crash recovery; extra Docks | `BehaviorTests`, `CoreCoverageTestsApp`, `DockCoverageTests`, `WorkspaceTests`; physical multi-display and session changes need real hardware checks |
| Application launch and pins | Missing/moved app; launch failure; add/replace duplicate; Undo; search aliases; refreshed catalog; keyboard chooser navigation; stack sort/grid/list/fan; Escape/outside click | `AppManagementTests`, `AppIndexTests`, `ApplicationsStackTests`; launched-app effects use isolated fixtures |
| Layout and Settings | Mixed widget shapes and sizes; page bounds; drag and dwell; locked features; undo; import/export sanitation; stored profiles; light/dark and Reduce Motion | `DockStudioTests`, `SettingsCoverageTests*`, `WorkspaceTests`, `DockCoverageTests`; preferences must be compared semantically after live review |
| Notch | Width bounds; page navigation; search; keyboard Escape; open/close preferences; hover exit; keyboard focus and window opening | `NotchTests`, settings and native-render tests; actual hardware notch dimensions are a separate check |
| Calendar and Reminders | Authorization denial/revocation; stale async replies; nil/error/empty data; account selection; failed save; completed items; disconnect clears readings | `IntegrationsCalendarTests`, `IntegrationsUtilitiesTests`; fake EventKit stores never read/write personal events |
| Music | App missing/closed; denied Automation; timeout; stopped/paused/playing; malformed response; stale reconnect/artwork; failed artwork; transport busy state | `IntegrationsMusicTests`, artwork/client tests; personal Spotify/Apple Music transport is not implied by fixtures |
| Usage and services | Disabled/unconfigured; authentication failure; pagination; stale request; invalid metrics; local CLI absent; failed process; canceled sign-in; weather query changes; rate limit/offline response | `AIUsage`, `LocalAIUsage`, `AISignIn`, `WeatherTests`, integration tests; live private account access needs its own evidence |
| Utility widgets | Focus complete once; start/pause/reset; private clipboard exclusion; calculator invalid input; currency response and overflow; files/folders; hydration/day rollover; stopwatch; microphone denied/record/play/export failures | `WidgetsCoverageTests*`, `CoreCoverageTestsModel`, `IntegrationTests`; microphone/login/capture system actions stay behind test seams |
| Purchases and licensing | Verified-only entitlements; revoked/unknown/expired products; pending/canceled purchase; recovery; offline license; malformed signing configuration; stale refresh | `LicensingTests`, purchase/settings fixtures, commerce tests; no live sale or Apple distribution is certified |
| Website | Client API disabled/enabled behavior; allowed redirects; checkout unavailable state; static routes/assets/budget; responsive layout and keyboard/motion smoke tests | Node client tests and build-dependent static/Playwright suites; production deployment is separate |

## Initial audit checks — November 21

- Native `Tests-8` completed with 304 tests, 6 opt-in skips and 0 failures, including the final motion, geometry and focus changes. The focused companion suite separately passed all 14 tests. A final store-recovery regression also passed in `Index-10`, covering all 12 lines of the quoted-string parser; the full suite and CI are rerunning with that additional test.
- `Live-9` passed all five available read-only checks: Codex usage, public GitHub data, currency rates, audio output discovery and CPU/memory sampling. Apple Weather's live signed-entitlement path was excluded; its offline failure cases passed in the normal suite.
- The universal arm64/x86_64 Development build passed strict ad-hoc signature and plist verification. The review archive is separate from `/Applications/DockGrove.app`, which has not been replaced.
- Both initial PR CI jobs failed one assertion that depended on the runner's Reduce Motion preference. The harness now injects that preference deterministically. Website and native-render CI passed on the updated review branch; final app/coverage CI results belong in the PR validation summary.
- Offline commerce/backend: 22 passing test invocations (11 unique cases are imported by both entry points). They cover webhook signatures, product/amount/environment validation, activation caps, refunds, failed payments, recovery, rate limits and configuration failure.
- Legacy website client: 9 passing behavior checks.
- Current website: lint, TypeScript checking, production static export and 49 tests pass after the dependency patches. The tests cover client API gating, fallback/error handling, checkout redirects, recovery, unavailable downloads, page structure/metadata, routes, assets, payload budgets and security headers.
- All 18 WebKit smoke tests pass on the final export: five public page routes at 390 px, clean console/network, no text/page overflow, Escape/focus return in mobile navigation, Dock sizing/fit/hide/presets at 320/390/768/1280 px, launcher touch targets, and notch hover/keyboard/touch controls. The test server and browser closed after the run; no production deployment was performed.
- `git diff --check` passed at the audit checkpoint.
- The initial static checks required a missing `website/web/out`; they were rerun successfully after building. The first build stopped after compilation with the Next.js advisory warning. The final patched build exits successfully without that warning. The standalone Node runtime is required locally because the desktop app's embedded Node enforces library-signing restrictions on the native SWC dependency.

These were the initial, pre-installation results. The November 22 checkpoint below supersedes the installation and Accessibility status. Intel execution, older supported macOS versions, external displays, clean signed upgrades, spoken VoiceOver, Developer ID/notarization and production payment configuration remain separate release gates when that environment is unavailable.

Live computer-use review in isolated `--ui-test` preferences verified name-field typing and Return, species switching while preserving the custom name, feeding, playing, rest/wake, full-screen entry/exit, and Command-W dismissal. The room remained contained and the lighter orange cat rendered correctly in the real GPU scene. Settings' Done and Escape controls and the overview's Done control dismissed correctly; the earlier inactive-window observation did not reproduce. Personal pet/layout preferences were not used for these edits.

An earlier native run exposed an existing fixture that sent live AX messages to its own test host from a detached task. macOS logged an `NSMenu` main-thread violation; XCTest then stalled during issue symbolication. The corrected fixture uses an unavailable PID for AX operations and asserts failure/nil outcomes. Production discovery already excludes DockGrove's own PID. The subsequent `Tests-4` baseline passed; the earlier diagnostic sample is `/tmp/dockgrove-native-test2.sample.txt`.

## Installed-build verification — November 22

The reviewed universal Development build was installed at `/Applications/DockGrove.app`. Its executable SHA-256 is `1aeb4293adb6709e4de8dcab12be0cdda507168c3ba3d3a34777cc19790deb78`. Strict ad-hoc signature, plist and both architecture checks passed. The previous process was closed before installation; the end-of-review process check found one DockGrove process and no test host.

After owner authentication, the exact installed app was re-added in System Settings → Device Control and Data Access. DockGrove then recognized Accessibility. A disposable native window was searched by app name, minimized through the overview's context menu, and restored by clicking its card. The Minimized filter included it and the Open filter excluded it. Read-only Window Server observations independently confirmed that the window left the visible window list on minimize and returned on restore. No personal app window was minimized or changed.

Live review found and fixed three additional overview problems: background helper windows cluttered the results, intrinsic content sizing made the window taller than the display, and the filter label wrapped. Normal discovery now lists regular applications; an explicitly scoped accessory app can still be inspected. AppKit owns the resizable viewport, the scroll area stays within it, and the frame is constrained to the available screen. The resulting overview measured 840 × 652 points on a 1470 × 956 display, with its footer visible. The native regression fixture exercises 36 results, filtering, scrolling, user resizing and a small display area.

That installed build also passed full-screen hide/return and companion name-field typing. The preceding build additionally passed playroom full-screen entry/exit and Command-M followed by pet-tile restoration and typing again; the changes between these builds were confined to window discovery and overview layout. The temporary name was restored before saving. The user's overlap preference was restored, and a semantic preference comparison found only the companion's normal `lastUpdate` timestamp changed.

Further reliability changes cover app-specific discovery continuation, confirmed minimize/restore outcomes, released extra-Dock controllers, single-instance handoff before Apple Dock side effects, refreshed login-item status, and Command/Option app-click actions. Option-Command hides other apps only after the target opens successfully and is still active.

The app-menu regression renders stopped → running → stopped states, asserts the available actions, invokes Open in both stopped states, and verifies that the pin remains unchanged. A standalone Swift 6.4 result-builder reproduction showed that a preceding optional block with a nested condition could incorrectly assign the later `else` branch zero coverage even when it executed twice. Separating the application-action builder from the window-list builder preserves the captured running-app snapshot and menu order while avoiding that counter mapping. The coverage gate and its allowlist are unchanged. Both focused menu tests passed after extraction, with body coverage 22/22 and helper coverage 11/11; the subsequent universal build passed signature, plist and architecture checks. Its final installation and CI results are recorded in the PR.

Exact-head CI results and the merge/publication state are maintained in PR #43. Website export validation and a successful merge are separate from Cloudflare publication; neither implies that production payments or a notarized public app release are enabled.

Known behavior boundaries remain: browser tabs stay inside their browser windows, overview cards use app icons and titles while Mission Control supplies system previews, and DockGrove stays hidden in another app's native full-screen Space. The Apple Dock's system keyboard-focus shortcut and Finder drag-to-pin behavior are not implemented by this change.

## Requested interaction changes

- Pet clicks from the Dock and notch open a reusable Companion Playroom window. It can resize and enter full screen, while Details contains the name field and care meters. Feed, Play, Rest/Wake and floor clicks have visible feedback; the scene pauses when its window closes and respects Reduce Motion.
- Playroom travel speed is relative to the pet's body size, so widening the room does not accelerate the animal. Shared scene geometry keeps the sprite contained and aligns destination clicks with the rendered floor and travel area. Native regressions cover speed, frame phase, arrival and bounds across room sizes; live review confirmed full-screen containment and visible movement.
- The windows cube opens a grouped, searchable overview. Discovery continues across bounded scans, handles missing AX subroles, retains unavailable-app readings with an explicit stale warning, and removes closed-window readings after a complete scan. Mission Control opens the system's live previews; DockGrove does not capture screen contents.
- Hide-on-overlap defaults on for new preferences and also applies to floating docks. A hidden retained child window no longer keeps a Dock above other apps. Hidden docks ignore mouse input. Existing explicit visibility choices are preserved.

The focus change follows AppKit's distinction between ordinary key windows and [nonactivating panels](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel). Window discovery keeps [AX messaging timeouts](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) on worker tasks and treats deadlines as cooperative rather than hard interruptions.

## Orange cat asset

The built-in imagegen tool edited `app/Assets.xcassets/Companions/Companion-orange-cat-pixel.imageset/orange-cat-pixel.png` from the existing atlas. Prompt: preserve the transparent 4×4 sheet, all sixteen poses, grid positions, scale, outlines, golden eyes, pink ears, white paws, chest and muzzle; change only the dark orange fur to soft light apricot with warm caramel stripes. No added objects or backgrounds.

The native asset validator passed all nine animals: 16 occupied poses each, clear cell boundaries, common crop/scale, and 32 mirrored render-bound checks per animal. This validates the atlas structure; it does not alone prove perceived motion quality.

The lighter orange cat matches the requested apricot palette and existing pixel style in the atlas and live playroom. Cached AppKit screenshots omit GPU-rendered SpriteKit content, so the live computer-use review, rather than those cached images, establishes the in-app appearance.
