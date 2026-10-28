# WaveDock 0.3 validation

## Reproduce

```sh
zsh Tests/validate.sh --native --live
```

This performs two complete universal builds with offline regression tests, signature/plist/architecture verification, native rendering and window-state tests, and explicitly opted-in live GitHub/Codex reads. Omit `--native` on a headless session; omit `--live` for offline tests. Logs are local under `.build/validation/` and excluded from Git.

## Results on October 28, 2026

Both complete passes of `zsh Tests/validate.sh --native --live` passed on the final source. Each included a fresh arm64/x86_64 build, all offline regression checks, 23 native widget views, window-state checks, signature/plist/architecture verification, and successful live GitHub and Codex reads. Native tests reported the Dock visible on the ordinary desktop in both passes.

## Automated coverage

- Full-screen/session suppression takes priority over interaction; edge dwell, hide grace period, overlap mode, manual hiding and negative display coordinates.
- Replacement journaling before writes, repeated enable, restoring absent preferences, retries after write/restore errors, and durable crash recovery.
- Actual `/usr/bin/defaults` boolean write/read subprocess tests in disposable temporary preferences. This caught a real compatibility issue: this macOS version accepts `true`/`false`, but not `0`/`1`, for `-bool`.
- App ordering, profile import sanitization, notes/tasks/shelf/widget persistence, deduplication, focus completion and clipboard opt-in defaults.
- Bookmark validation, daily habit toggles, water rollover, stopwatch pause/resume/reset, unit conversions and invalid inputs, folder search/sorting/error states, world-clock identifiers.
- GitHub repository-name validation, safe link destinations and queued workflow status. Regression coverage includes preserving a reading when a text field commits an unchanged repository and clearing it for a different repository. Public live reads verify metadata, issues and Actions; Codex live checks verify real allowance buckets without printing credentials or account details.
- Native rendering of all 23 functional widget popovers (plus two layout entries), bounded bottom replacement geometry, full-screen collection flags, and actual panel order-out behavior for session/sleep/manual hiding.

## Manual checks on the development Mac

The development host reports macOS 27.2, Apple Silicon, one built-in display. The app targets macOS 14+ and is compiled for both arm64 and x86_64; a universal binary does not establish execution on Intel hardware or every supported OS.

A dedicated AppKit test host is included as `Tests/DockTestHost.swift`. Run `zsh Tests/fullscreen-host.sh` to open it. It provides a real native full-screen window without using personal documents. Verify twice: enter full screen, confirm the bar is hidden, exit, confirm the bar returns. Test replacement enable/disable/quit while checking that `com.apple.dock autohide` and `autohide-delay` return to their original values.

Manual checks exercised native full-screen entry/exit twice on the final build, GitHub refresh and close/reopen retention, and converter input plus reverse conversion. Quit restoration returned the development machine’s original auto-hide value (`false`) and removed the previously absent reveal-delay key. The command-line recovery path was also verified after an interrupted test process. The test suite's view captures establish successful layout/rendering; they do not prove every external permission or every click action.

## Explicitly not certified

- Calendar and Apple Reminders approval/revocation and live edits, Music/Spotify Automation approval and playback, screen-capture permission, color-sampler interaction and login-item approval across OS versions.
- Private GitHub authorization or GitHub Enterprise, additional AI providers, weather availability across cities and network failures.
- Physical sleep/lock, Mission Control, external monitors, Sidecar, games, all browser full-screen video variants, or accessibility-based screen-space reservation.
- Full CoolDock feature parity, production security review, Developer ID signing, Apple notarization, automatic updates or App Store acceptance.

These limits are retained rather than converting fixture or rendering evidence into claims of complete end-to-end certification.
