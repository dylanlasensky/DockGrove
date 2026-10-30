# DockGrove validation

## Version 1.0 non-pet publication — October 29, 2026

This publication excludes the local pet redesign. `Sources/Companion.swift`, `Sources/WidgetCards.swift`, `Sources/WorkspaceTests.swift` and the entire `Assets/` tree remain identical to baseline `97c9fed`; no new companion motion/drawing modules or generated rigs are included. The existing six-pose companions remain in the native app. The public website omits the pet gallery and new pet artwork.

The changes cover app search/replacement/Undo, adaptive appearance, native window actions, separate development identity, fail-closed commercial activation, the static website, and test-only commerce infrastructure. Provider credentials, deployed commerce, actual payments, Apple signing and installed-app replacement are outside this publication.

The isolated publication checkout passed a universal Apple Silicon/Intel development build, strict ad-hoc signature verification, plist validation, the complete fixture self/integration suite, and native rendering/window-state tests. Native checks rendered all 39 widgets plus Automatic light/dark Dock, settings and app-picker views. Existing companion six-pose checks passed unchanged. No installed app or system Dock preferences were changed. Local evidence is `/tmp/dockgrove-non-pet-{build,selftest,native}.log` and `.build/non-pet-native/`. These are local tests, not Intel hardware or every supported macOS version certification. Historical versioned evidence remains separate.

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
zsh Tests/validate.sh --native --live
```

This performs two complete universal builds with offline regression tests, signature/plist/architecture verification, native rendering and window-state tests, and explicitly opted-in live GitHub/Codex reads. Omit `--native` on a headless session; omit `--live` for offline tests. Logs are local under `.build/validation/` and excluded from Git.

## Results on October 28, 2026

Both full passes of `zsh Tests/validate.sh --native --live` passed for 0.4. Each built arm64 and x86_64, ran all offline regressions, checked signature/plist/architectures, rendered all 30 functional widgets, checked native window states, and successfully read live public GitHub and Codex allowances.

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

A dedicated AppKit test host is included as `Tests/DockTestHost.swift`. Run `zsh Tests/fullscreen-host.sh` to open it. It provides a real native full-screen window without using personal documents. Verify twice: enter full screen, confirm the bar is hidden, exit, confirm the bar returns. Test replacement enable/disable/quit while checking that `com.apple.dock autohide` and `autohide-delay` return to their original values.

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
