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

## Executed audit checks

- Native baseline: the full `Tests-4` run completed with 298 tests, 6 skips and 0 failures. This precedes the final motion/geometry and test-harness adjustments; final exact-build native results remain pending.
- The focused final companion suite passes all 14 tests after AX harness initialization. The full final `Tests-8` run is in progress. A universal arm64/x86_64 build passed strict signature and plist verification; the final identifier refresh and installed-app review remain pending.
- Both initial PR CI jobs failed one assertion that depended on the runner's Reduce Motion preference. The harness now injects that preference deterministically. The corrected final CI results remain pending.
- Offline commerce/backend: 22 passing test invocations (11 unique cases are imported by both entry points). They cover webhook signatures, product/amount/environment validation, activation caps, refunds, failed payments, recovery, rate limits and configuration failure.
- Legacy website client: 9 passing behavior checks.
- Current website: lint, TypeScript checking, production static export and 49 tests pass after the dependency patches. The tests cover client API gating, fallback/error handling, checkout redirects, recovery, unavailable downloads, page structure/metadata, routes, assets, payload budgets and security headers.
- All 18 WebKit smoke tests pass on the final export: five public page routes at 390 px, clean console/network, no text/page overflow, Escape/focus return in mobile navigation, Dock sizing/fit/hide/presets at 320/390/768/1280 px, launcher touch targets, and notch hover/keyboard/touch controls. The test server and browser closed after the run; no production deployment was performed.
- `git diff --check` passed at the audit checkpoint.
- The initial static checks required a missing `website/web/out`; they were rerun successfully after building. The first build stopped after compilation with the Next.js advisory warning. The final patched build exits successfully without that warning. The standalone Node runtime is required locally because the desktop app's embedded Node enforces library-signing restrictions on the native SWC dependency.

The website results above remain unchanged. Final native tests, CI, live focus/window interactions, and artifact checks still require results for the completed change. Intel execution, older supported macOS versions, external displays, clean signed upgrades, spoken VoiceOver, Developer ID/notarization and production payment configuration remain separate release gates when that environment is unavailable.

One live observation still needs reproduction: Settings' Done/Escape/Close actions did not dismiss an inactive window through the accessibility automation session. It is not yet established whether this is app focus behavior or the automation session targeting an inactive surface. Test those actions with the Settings window visibly active before treating it as a product defect.

An earlier native run exposed an existing fixture that sent live AX messages to its own test host from a detached task. macOS logged an `NSMenu` main-thread violation; XCTest then stalled during issue symbolication. The corrected fixture uses an unavailable PID for AX operations and asserts failure/nil outcomes. Production discovery already excludes DockGrove's own PID. The subsequent `Tests-4` baseline passed; the earlier diagnostic sample is `/tmp/dockgrove-native-test2.sample.txt`.

## Requested interaction changes

- Pet clicks from the Dock and notch open a reusable Companion Playroom window. It can resize and enter full screen, while Details contains the name field and care meters. Feed, Play, Rest/Wake and floor clicks have visible feedback; the scene pauses when its window closes and respects Reduce Motion.
- Playroom travel speed is relative to the pet's body size, so widening the room does not accelerate the animal. Shared scene geometry keeps the sprite contained and aligns destination clicks with the rendered floor and travel area. Final native and live motion checks are pending.
- The windows cube opens a grouped, searchable overview. Discovery continues across bounded scans, handles missing AX subroles, retains unavailable-app readings with an explicit stale warning, and removes closed-window readings after a complete scan. Mission Control opens the system's live previews; DockGrove does not capture screen contents.
- Hide-on-overlap defaults on for new preferences and also applies to floating docks. A hidden retained child window no longer keeps a Dock above other apps. Hidden docks ignore mouse input. Existing explicit visibility choices are preserved.

The focus change follows AppKit's distinction between ordinary key windows and [nonactivating panels](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel). Window discovery keeps [AX messaging timeouts](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) on worker tasks and treats deadlines as cooperative rather than hard interruptions.

## Orange cat asset

The built-in imagegen tool edited `app/Assets.xcassets/Companions/Companion-orange-cat-pixel.imageset/orange-cat-pixel.png` from the existing atlas. Prompt: preserve the transparent 4×4 sheet, all sixteen poses, grid positions, scale, outlines, golden eyes, pink ears, white paws, chest and muzzle; change only the dark orange fur to soft light apricot with warm caramel stripes. No added objects or backgrounds.

The native asset validator passed all nine animals: 16 occupied poses each, clear cell boundaries, common crop/scale, and 32 mirrored render-bound checks per animal. This validates the atlas structure; it does not alone prove perceived motion quality.

Initial artwork review found the lighter orange cat consistent with the requested apricot palette and existing pixel style. The cached playroom screenshot omitted the GPU-rendered sprite, so it cannot establish the pet's live appearance or motion. A live playroom review is still required.
