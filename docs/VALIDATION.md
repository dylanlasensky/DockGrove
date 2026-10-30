# DockGrove validation

## Version 1.0 non-pet publication — October 29, 2026

This publication excludes the local pet redesign. `app/Sources/Companion.swift`, `app/Sources/WidgetCards.swift`, `app/Sources/WorkspaceTests.swift` and the entire `app/Assets/` tree remain identical to baseline `97c9fed`; no new companion motion/drawing modules or generated rigs are included. The existing six-pose companions remain in the native app. The public website omits the pet gallery and new pet artwork.

The changes cover app search/replacement/Undo, adaptive appearance, native window actions, separate development identity, fail-closed commercial activation, the static website, and test-only commerce infrastructure. Provider credentials, deployed commerce, actual payments, Apple signing and installed-app replacement are outside this publication.

The isolated publication checkout passed a universal Apple Silicon/Intel development build, strict ad-hoc signature verification, plist validation, the complete fixture self/integration suite, and native rendering/window-state tests. Native checks rendered all 39 widgets plus Automatic light/dark Dock, settings and app-picker views. Existing companion six-pose checks passed unchanged. No installed app or system Dock preferences were changed. Local evidence is `/tmp/dockgrove-non-pet-{build,selftest,native}.log` and `app/.build/non-pet-native/`. These are local tests, not Intel hardware or every supported macOS version certification. Historical versioned evidence remains separate.

## Version 0.8 coverage

The page-drag timer covers initial dwell, stationary repeat, reverse direction, leaving an arrow, cancellation and first/last-page bounds. The stable Dock owns the gesture while tile views change. Live QA performed two rounds moving Chrome and the companion forward and backward by dropping on arrows (eight successful drags). All nine animal choices were selected twice; rest/wake was exercised twice. The computer-use drag API releases immediately at the destination, so a sustained physical hover-and-hold is not claimed as manually verified. Its timing is covered by production-state tests.

All nine bundled six-pose sheets are checked for dimensions, sprite-boundary bleed, valid frame sequences and Reduce Motion. Native captures render all poses on contrasting backgrounds as well as every widget. The full local suite runs twice, and CI builds and tests independently twice. The final PR records exact-commit results.

## Version 0.7 coverage

Regression tests add all edge and corner snap zones on negative-coordinate screens, edge dwell/cancellation, per-edge window reservations, small custom Dock widths, theme persistence, companion needs/levels and exactly-once focus rewards, and artwork source/format validation. Native tests exercise four independent Dock models, separate content/themes, screen containment, session/sleep suppression, removal, and all 39 functional widget views. Live Accessibility acceptance depends on macOS granting this rebuilt app access; offline geometry tests are not proof of a live gesture.

Website tests and browser acceptance cover the new layout and companion demos at desktop and phone widths. Exact-commit results and any live permission limitations are recorded in the release PR.

## Version 0.6 coverage

The two-pass suite now covers Claude Code status-line reports, expired and missing allowance windows, invalid percentages and costs, Gemini per-model tokens without overlapping cache counts, replacement imports, private-field exclusion, local file permissions, and preserving custom Claude settings. Native checks render both new widgets with empty and populated data, including three allowance windows and a long model list. Personal Claude/Gemini accounts are not part of live acceptance for this release.

Website checks validate local links, assets, identifiers, JavaScript syntax, accessibility/motion safeguards, the packaged download, and a static-only Cloudflare configuration. Browser acceptance covers desktop and phone layouts, provider tabs and keyboard navigation, timer start/pause, accent previews, FAQ disclosure, and mobile navigation. CI runs the build, offline regressions, package, and website checks independently twice. Exact-commit results and deployment checks are recorded in the pull request.

## 0.5 verification

The redesigned app adds 36 functional widget views, rich cards, custom accents, live system graphs, audio output control, calculator, currency, local voice memos and app groups. Two full local passes succeeded on the initial 0.5 implementation. Final verification also asserts that window placement reserves the exact rendered Dock height and reads live currency/system/audio data. Both final local passes and both CI jobs on commit 9367483 succeeded. Live testing then verified all ten window layouts and Undo twice on the blank AppKit host, two calculator results, both directions of currency conversion, White/None accents twice, and two audio volume changes with exact restoration. A final standard Edit-menu fix restores native Select All/Cut/Copy/Paste/Undo shortcuts; see PR #1 for its exact-commit validation status.

Regression coverage includes delayed Accessibility layout acknowledgement, bounded retries, true minimum-size constraints, refused writes, arithmetic precedence and invalid input, currency response validation, network counter resets, custom accent persistence and app-group persistence. The design-preview capture uses explicitly labeled synthetic data. The user approved microphone testing. Two local AAC clips were recorded and validated (about 10 seconds and 1 second), including pause/resume/stop; neither was uploaded. Playback now uses an in-process AVAudioPlayer so it does not import memos into another media app. Arbitrary third-party account access still requires separate live account checks.

## Earlier 0.4 evidence

## Reproduce

```sh
zsh app/Tests/validate.sh --native --live
```

This performs two complete universal builds with offline regression tests, signature/plist/architecture verification, native rendering and window-state tests, and explicitly opted-in live GitHub/Codex reads. Omit `--native` on a headless session; omit `--live` for offline tests. Logs are local under `app/.build/validation/` and excluded from Git.

## Results on October 28, 2026

Both full passes of `zsh app/Tests/validate.sh --native --live` passed for 0.4. Each built arm64 and x86_64, ran all offline regressions, checked signature/plist/architectures, rendered all 30 functional widgets, checked native window states, and successfully read live public GitHub and Codex allowances.

The prior CI run 40750383530 was cancelled before either job ran: GitHub reported that no hosted runner acquired the jobs and cited macOS ARM capacity constraints. The workflow now uses the documented `macos-15-intel` standard runner, still builds both architectures, and runs two independent test jobs. The first Intel run built the app and passed every regression, then exposed an Xcode 16 `lipo` argument-order incompatibility. Both CI and the local validation script now place the input binary before `-verify_arch`. CI run [40756654494](https://github.com/dylanlasensky/DockGrove/actions/runs/40756654494) then passed both Intel jobs, including builds, every regression, architecture checks and artifact uploads. Runtime refinement commit e7cb66e also passed both jobs in run [40758439489](https://github.com/dylanlasensky/DockGrove/actions/runs/40758439489). Subsequent changes must pass CI on their own commit; see the PR for the latest exact-commit results.

## Automated coverage

- Full-screen/session suppression takes priority over interaction; edge dwell, hide grace period, overlap mode, manual hiding and negative display coordinates.
- Replacement journaling before writes, repeated enable, restoring absent preferences, retries after write/restore errors, and durable crash recovery.
- Actual `/usr/bin/defaults` boolean write/read subprocess tests in disposable temporary preferences. This caught a real compatibility issue: this macOS version accepts `true`/`false`, but not `0`/`1`, for `-bool`.
- App ordering, profile import sanitization, notes/tasks/shelf/widget persistence, deduplication, focus completion and clipboard opt-in defaults.
- Bookmark validation, daily habit toggles, water rollover, stopwatch pause/resume/reset, unit conversions and invalid inputs, folder search/sorting/error states, world-clock identifiers.
- GitHub repository-name validation, safe link destinations and queued workflow status. Regression coverage includes preserving a reading when a text field commits an unchanged repository and clearing it for a different repository. Public live reads verify metadata, issues and Actions; Codex live checks verify real allowance buckets without printing credentials or account details.
- Native rendering of all 30 functional widget popovers (plus two layout entries), bounded bottom replacement geometry, full-screen collection flags, and actual panel order-out behavior for session/sleep/manual hiding.

- Whole-tile paging with 40 apps and every widget across eight screen widths and three icon sizes. Every entry is reachable exactly once, each page fits, and the outer Dock remains within the display.
- All ten window layouts, halves meeting exactly, negative monitor origins and oversized-window centering.
- Spotify/Apple Music payload decoding, paused/playing states, empty artists, multiline titles, malformed responses, subprocess timeout and clearing stale tracks when a player exits.
- Separate Google/general calendar selection persistence, disconnected defaults and clearing events on Disconnect.
- OpenAI/Claude/Cursor endpoint, method and authentication headers using synthetic keys; token/activity totals; pagination and repeated-cursor rejection; 401/403/429/500/redirect responses; missing, negative and boolean metric rejection; valid zero usage.

## Manual checks on the development Mac

The development host reports macOS 27.2, Apple Silicon, one built-in display. The app targets macOS 14+ and is compiled for both arm64 and x86_64; a universal binary does not establish execution on Intel hardware or every supported OS.

A dedicated AppKit test host is included as `app/Tests/DockTestHost.swift`. Run `zsh app/Tests/fullscreen-host.sh` to open it. It provides a real native full-screen window without using personal documents. Verify twice: enter full screen, confirm the bar is hidden, exit, confirm the bar returns. Test replacement enable/disable/quit while checking that `com.apple.dock autohide` and `autohide-delay` return to their original values.

The 0.3 baseline manual checks exercised native full-screen entry/exit twice, GitHub refresh and close/reopen retention, and converter input plus reverse conversion. Quit restoration returned the development machine’s original auto-hide value (`false`) and removed the previously absent reveal-delay key. The command-line recovery path was also verified after an interrupted test process. The test suite's view captures establish successful layout/rendering; they do not prove every external permission or every click action.

## Live integration evidence for 0.4

- The full library fits across three Dock pages on the development display. First/last pages and persistent Settings/page navigation were inspected visually.
- Spotify successfully returned track/artist and changed from paused to playing and back to paused through DockGrove. Disconnect cleared the track.
- Apple Music read a loaded local track and completed two play/pause cycles, returning to paused. Disconnect cleared its track. The follow-up Spotify check found that Spotify rejects the Apple Music `exists current track` event; that guard is now emitted only for Apple Music.
- Calendar permission was granted in macOS and the final widget successfully listed available iCloud, birthday and subscribed calendars. Disconnect cleared them. Only iCloud was configured in Internet Accounts; Google synchronization requires adding the user's Google account before it can be validated.
- The ad-hoc rebuilt app can require renewed macOS permissions. Initial window discovery showed incomplete results; discovery was moved off the main thread with a longer timeout and standard-window filtering. The stale permission entry was replaced with the exact app path, after which standard-window discovery worked. Live placement/Undo actions were exercised on the blank host; macOS constrained requested sizes, and the widget reported that limitation. Unrestricted resizing across arbitrary apps is not certified.
- No OpenAI/Claude organization or Cursor team admin key was provided. Those clients passed offline request/response tests; live authenticated reports are not claimed.

## Explicitly not certified

- Google account synchronization, Apple Reminders live edits, all Apple Music transport/queue scenarios, screen-capture permission, color-sampler interaction and login-item approval across OS versions. Error reporting distinguishes denied Automation, timeouts and a missing current track. Apple Music read/play/pause was verified with a loaded track; previous/next were not exercised on the personal library. Spotify read/play/pause was verified live.
- Private GitHub authorization or GitHub Enterprise, live OpenAI/Claude organization and Cursor team admin-key reports, weather availability across cities and network failures. API fixtures validate protocol logic, not account access or live totals.
- Physical sleep/lock, Mission Control, external monitors, Sidecar, games, all browser full-screen video variants, or accessibility-based screen-space reservation.
- Full CoolDock feature parity, production security review, Developer ID signing, Apple notarization, automatic updates or App Store acceptance.

These limits are retained rather than converting fixture or rendering evidence into claims of complete end-to-end certification.

## October 30, 2026: Settings studio and asset catalog

- The signed Xcode Debug build succeeds. The separate unrestricted Debug build passes all 25 offline regression checks.
- `--studio-test` passes insertion, reorder, duplicate prevention, remove/undo, persistence, invalid payload/target rejection, and purchase enforcement.
- The user manually confirmed dragging library cards into both the preview bar and the actual Dock. Preview page arrows were verified through the native UI.
- `--assets-test /tmp/dockgrove-sprites` passes app-icon/catalog lookup, light/dark palette resolution, nine transparent SpriteKit renders, animation bounds, texture reuse, and Reduce Motion/rest.
- Standalone `actool` packaging produces `AppIcon.icns`, `Assets.car`, and a valid partial Info.plist. The signed app passes `codesign --verify --strict`.
- Nine StoreKitTest purchase tests passed locally. App Store Connect products are saved drafts; no App Store production sale, review approval, or distribution build is claimed.

## October 30, 2026: Color collections and widget shapes

- Expanded the asset catalog to 16 color packs and 92 named accent colors, grouped into Essentials, Nature, Soft, Vivid, Earth, and Seasonal. Asset lookup and light/dark rendering checks pass. The native Settings flow was verified by selecting Neon and a swatch, then restoring Classic/White.
- Added per-widget Card, Square, Circle, and Pill styles. The signed Xcode Debug build and all 26 unrestricted offline regression checks pass.
- Shape tests cover mixed-width pagination, preference persistence, saved-profile round trips, legacy profiles, drag payload styling, undo, and rejection of invalid styles. Settings renders were checked in light and dark appearance.
- In the running signed app, selecting Circle for Focus updated the preview and actual Dock; clicking the circular tile opened the full Focus controls. Undo restored the original Card shape. Settings was left open to Appearance.

## October 30, 2026: Toolbar sizing and Settings controls

- Toolbar width, height, and icon size support live adjustment, Compact/Balanced/Spacious presets, fit-to-content or fixed width, reset, saved layouts, and undo. Height accounts for the selected icon size; shaped widgets retain their geometry.
- Settings uses draggable number badges with discrete minus/plus buttons instead of sliders, searchable selection sheets for widgets and displays, and switch-style on/off controls. Segmented choices remain directly selectable.
- The signed Debug build and studio suite pass, including 288 size/shape/paging combinations, saved preference/profile migration, bounds, and undo. Light/dark Settings renders and three native toolbar renders pass, including matching visible/reserved panel heights.
- Native UI verification: the height increase button changed 92 to 94 pt, Undo restored 92 pt, and the custom widget sheet filtered to Tasks and applied that selection. Switch roles are exposed in the accessibility tree. Automated dragging of the new number badges was not exercised.

## October 30, 2026: Inline choices and purchase comparison

- Widget and display selectors now expand searchable choice grids directly inside Settings. Selecting a card keeps the panel open; Collapse closes it. Native widget search and selection were verified in the same Settings window with no modal sheet.
- Purchases compares Free, Plus, and Full Access in three cards with StoreKit-localized prices, current/unlocked status, concise feature lists, and inline widget-detail grids. The purchase page uses its full content area for comparison; the Dock preview remains in customization sections.
- Purchase/restore calls and entitlement gating retain the existing StoreKit flow. This UI change does not create or submit App Store products.
- Final comparison build and light/dark renders pass. Native Purchases shows Free, $4.99 Plus, and $9.99 Full Access; expanding Full Access reveals the correct companion/GitHub/AI/Codex cards inline. No purchase or restore transaction was initiated during this UI check.

## October 30, 2026: Notch access

- Added opt-in notch-row controls using public screen safe-area and auxiliary-area geometry. The center camera region has no controls; the widget panel expands from the notch row.
- All tier-permitted widgets are browsable, with Dock widgets first, search, and pagination. Hover and click opening use separate close behavior.
- Signed builds, notch state/geometry/render tests, and the studio suite pass. The final committed-source unrestricted regression build passed all 28 checks, including hover and catalog behavior.
- Native checks verified compatible detection, persisted enablement, click expansion/collapse, widget paging, Focus and Weather controls, search, and fullscreen suppression. See NOTCH.md for untested hardware scenarios.

## October 30, 2026: System-sized notch workspace and file tray

- Resting bounds now equal the detected camera housing exactly (185×32 points on the development Mac); the 760-point-wide expansion combines Home and Widgets alongside Tray. The camera region remains empty in the expanded header.
- Home includes music, Focus, and the widget grid in one section. All unlocked widgets are available, with current Dock widgets first. Inline Appearance settings offer Tabs or Rounded pills for Home/Tray navigation, with persistent selection. The expanded height remains camera housing plus 324 points; only width increases. Paging shows four widgets at a time; full controls open inline.
- Tray uses the persistent, tier-gated File Shelf with native file drops, a file picker, drag-out providers, Finder reveal, system sharing, and shortcut-only removal.
- Signed and unrestricted builds pass. All 28 unrestricted regression checks pass, including native pasteboard URL round trips, file/folder validation, duplicate prevention, persistence, access gating, and original-file preservation.
- Native UI verification added a temporary text file through Add files, displayed its tray card, removed its shortcut, and confirmed the original contents were unchanged. Inline Focus controls were verified in the same notch window. Home, Tray, and Focus renders were visually inspected.
- The running signed app exposed both navigation preview cards in Appearance. Selecting Tabs updated the Home/Tray navigation, and the wider combined Home rendered without clipping.
- Physical drag-in/drag-out gestures and sharing remain manual validation gaps; the file intake and drag-provider implementation are not presented as end-to-end gesture certification.

## October 30, 2026: Short horizontal notch strip

- Replaced Home/Tray tabs and widget paging with one horizontal scroll view. Controls, files, and widget cards are adjacent sections; file shortcuts extend the same row. Removed the obsolete tab-style setting.
- Expanded size on the development Mac is 760×144 points, down from 760×356. Closed bounds still exactly match the 185×32-point camera housing. Geometry tests assert the fixed short height.
- Signed Debug build and all 28 unrestricted regression checks pass. Strict code-signature verification passes.
- Native scroll actions moved the horizontal offset from 0 to 0.164 and revealed the widget row. Search filtered to Focus, its controls opened inline without growing the strip, and clearing search restored the initial sections. Longer widget controls scroll within their fixed-height area.
- File drag gesture certification remains outstanding as documented in NOTCH.md; existing intake, persistence, tier, and preservation tests pass.

## October 30, 2026: Separate Files tab

- Moved the tray from the Home row into a second Files tab in the existing header. Home retains horizontal controls and widgets; Files scrolls its shortcuts horizontally. Expanded geometry remains 760×144 points on the development Mac.
- Dropping accepted files automatically selects Files. The File Shelf card is omitted from Home to avoid a duplicate tray entry.
- Signed and unrestricted builds and their focused notch suites pass, including automatic Files selection, purchase gating, and fixed-height assertions. Strict code-signature verification passes.
- Native UI verification confirmed Home contains widgets and no file drop area; selecting the second Files tab shows the drop area and Add files action. The app was left on Files.

## October 30, 2026: Wider components, separate drop zones, and Connections settings

- Widened music, Focus, widget, and file cards while keeping the 112-point content height. Appearance adds a saved 600–1600-point Notch width control and Compact/Balanced/Wide presets. Actual width is capped to the display.
- Files now contains two persistent 280-point drop zones. Tray stores shortcuts; AirDrop uses the native sharing service and never inserts those files into the tray. Native drop destinations route separately, including while the resting notch expands.
- Tests cover native pasteboard routing to both destinations, invalid files, purchase gating, no cross-destination effects, saved width, non-finite values, display bounds, and unchanged height. A width-normalization recursion found during testing was fixed before the successful final runs. Signed and unrestricted builds and all 28 regression checks pass.
- Native checks changed width from 760 to 780 and restored Balanced, and verified the notch music settings button opens Connections with Apple Music selected. Connections centralizes music/calendar access switches, reminders permission, usage keys, and local-usage setup. Widget views retain settings shortcuts and routine controls.
- Activating the AirDrop zone opened its file picker. Selecting an agent-created temporary text file opened the native AirDrop chooser and listed a nearby device. The chooser was cancelled; no transfer was sent and the tray remained empty. Physical drag gestures and completed device-to-device transfer remain unverified.

## October 30, 2026: Half-width tray cards and custom AirDrop review

- Both drop zones and each saved tray card now occupy half the available content width, after outer padding and one inter-card gap. Geometry checks cover the full saved-width range and display clamping. Height remains unchanged.
- AirDrop opens an inline review view with selected-file previews, individual removal, Add files, Clear, Back, and Choose device. Drops stage files without invoking the sharing service. Choose device performs the native recipient handoff.
- Queue tests cover deduplication, removal, empty selection rejection, explicit handoff, cancellation-safe staging, separation from tray shortcuts, and reset to the two zones when a new drag enters the resting notch. Signed and unrestricted builds and focused notch suites pass; the broader regression run passed all 28 checks.
- Native verification opened the custom AirDrop panel, added an agent-created text file, and confirmed it stayed in the review view until Choose device. The system chooser opened only after that action; no recipient was selected.
- The live Cancel path reported a completion callback on this Mac. The handler now retains the review queue and reports that the chooser closed, without claiming delivery. A regression assertion covers this callback and selection preservation.

## October 30, 2026: Minimal notch controls

- Removed bordered button styling from Focus, music settings, and AirDrop handoff. Back and Add use small labeled icons. File cards open and drag directly; secondary file actions and clear commands live in context menus. Accessibility actions remain available for removing files and clearing selections. Missing files retain their removal action.
- Signed build and the focused notch suite pass. Native Home and AirDrop screenshots verify the unboxed controls; the accessibility tree retains named Back, Add files, playback, and settings actions. The half-width layout and short height remain intact.

## October 30, 2026: Keep File Tray visible during AirDrop review

- Fixed the review layout replacing both halves: File Tray now remains in the left half while the right half contains either the AirDrop zone or its custom review controls. Saved tray cards remain available while review is open.
- A native-view regression assertion verifies that the registered File Tray drop target still exists in the AirDrop-review render. Both focused notch suites cover this layout without changing the height or half-width sizing.
- Native UI verification opened AirDrop review and confirmed the separate File Tray drop zone stayed visible. Activating File Tray opened its own picker with “Choose files to keep in the tray”; cancelling returned to the two-section view.


## October 30, 2026: AI provider sign-in

- Added ChatGPT / Codex to Connections, with browser sign-in through the installed CLI, existing-account detection and usage refresh. Claude Code has the same controls and enables the existing status-line bridge after successful authentication. Gemini opens its official Google sign-in flow in Terminal, followed by the existing session-report import. API/team providers link to their account dashboards and retain explicit admin-key setup.
- Signed Debug and unrestricted regression builds succeeded. Strict code-signature verification passed. Four focused sign-in checks covered both CLIs' login/status argument contracts, success, refused login, duplicate-start prevention, cancellation, retry, timeout, failed launch and Gemini shell quoting/environment/no-prompt behavior. The full 28-check offline regression suite passed.
- Native Settings inspection verified all new provider controls. Using an existing Codex account completed successfully and loaded live allowance data. New-account browser authorization was not completed, and no personal Claude/Gemini session or API admin key was used. Those providers' live usage remains unverified.
- Login output is discarded; credentials remain with each CLI. The app does not parse credential files, read browser cookies, or generate AI requests to refresh usage.
