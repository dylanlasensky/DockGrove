# WaveDock 0.4 validation

## Reproduce

```sh
zsh Tests/validate.sh --native --live
```

This performs two complete universal builds with offline regression tests, signature/plist/architecture verification, native rendering and window-state tests, and explicitly opted-in live GitHub/Codex reads. Omit `--native` on a headless session; omit `--live` for offline tests. Logs are local under `.build/validation/` and excluded from Git.

## Results on October 28, 2026

Both full passes of `zsh Tests/validate.sh --native --live` passed for 0.4. Each built arm64 and x86_64, ran all offline regressions, checked signature/plist/architectures, rendered all 30 functional widgets, checked native window states, and successfully read live public GitHub and Codex allowances.

The prior CI run 40750383530 was cancelled before either job ran: GitHub reported that no hosted runner acquired the jobs and cited macOS ARM capacity constraints. The workflow now uses the documented `macos-15-intel` standard runner, still builds both architectures, and runs two independent test jobs. The first Intel run built the app and passed every regression, then exposed an Xcode 16 `lipo` argument-order incompatibility. Both CI and the local validation script now place the input binary before `-verify_arch`. CI run [40756654494](https://github.com/dylanlasensky/WaveDock/actions/runs/40756654494) then passed both Intel jobs, including builds, every regression, architecture checks and artifact uploads. Runtime refinement commit e7cb66e also passed both jobs in run [40758439489](https://github.com/dylanlasensky/WaveDock/actions/runs/40758439489). Subsequent changes must pass CI on their own commit; see the PR for the latest exact-commit results.

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
- Spotify successfully returned track/artist and changed from paused to playing and back to paused through WaveDock. Disconnect cleared the track.
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
