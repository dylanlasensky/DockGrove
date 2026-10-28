# WaveDock

**Your apps, useful widgets, and AI usage in one native Mac Dock.**

WaveDock is a free, open-source Mac app created by Dylan Lasensky. It gives you a customizable glass Dock with app launchers, a widget library, saved layouts, and a tile for the usage limits returned by your ChatGPT account's Codex service.

Built with Swift, SwiftUI, and AppKit. No Electron, web wrapper, subscription, account with WaveDock, or third-party package dependencies.

> **Early access, v0.4.0.** WaveDock is inspired by the usefulness of widget docks. It is an independent project, not affiliated with CoolDock or OpenAI. It does not yet match CoolDock's full catalog or production maturity. See the feature matrix and limitations below.

## Requirements

- macOS 14 Sonoma or newer.
- Apple Silicon or Intel Mac. The build produces a universal app.
- Xcode Command Line Tools to build from source (`xcode-select --install`).
- A compatible Codex CLI signed in with ChatGPT for Codex allowances. API/team usage widgets require their own provider admin keys; other widgets work without these connections.

## Install

### Download a build

Open [Actions](https://github.com/dylanlasensky/WaveDock/actions), choose a **successful** "Build and test macOS app" run, and download **WaveDock-macOS-universal-pass-1** (or pass-2) under Artifacts. GitHub may require you to sign in. Extract the artifact, then extract the enclosed `WaveDock.zip`. Drag `WaveDock.app` into Applications and open it.

Builds are ad-hoc signed for local testing, **not Developer ID signed or notarized by Apple**. If macOS blocks a build you trust, use its **System Settings → Privacy & Security → Open Anyway** flow. Do not disable Gatekeeper globally.

### Build from source

```sh
git clone https://github.com/dylanlasensky/WaveDock.git
cd WaveDock
zsh build.sh
open dist/WaveDock.app
```

The build uses the installed Apple toolchain and creates `dist/WaveDock.app`. It generates the app icon from the included drawing script. Build outputs are excluded from version control. Ad-hoc rebuilds may require you to re-enable macOS privacy permissions; stable distribution requires a consistent Developer ID signature.

## First setup

1. Open Settings from the wave icon in your menu bar or the sliders button in WaveDock.
2. Choose icon size and an accent: Mint, Blue, Lilac, or Coral.
3. Pin apps with **Pin apps…** or the search widget. Drag pinned icons over another pinned icon to reorder them. Right-click for pin, unpin, move, reveal, and quit actions.
4. Choose a display. Replacement mode stays at the bottom. Enable automatic hiding or hide-on-overlap if you prefer; hold the pointer at the physical bottom edge for a quarter second to reveal it.
5. Enable your widgets in **Widget library**. A full Dock scrolls horizontally.
6. **Use WaveDock as my Dock** is enabled by default for the new replacement workflow. Apple’s Dock is hidden and its edge reveal is delayed while WaveDock runs. Disable replacement to use a separate top or bottom bar. Your original Apple Dock preferences return when you disable replacement or quit.
7. Save a named layout to switch between app collections, widgets, icon sizes, and accent colors. Export/import layout JSON to move those layouts to another Mac. App paths must exist on the destination Mac.

The menu-bar wave always gives access to Settings, show/hide, usage refresh, Apple Dock restoration, and Quit. **Done** closes Settings. ⌘W closes Settings and ⌘Q quits while WaveDock is active.

## Features

| Feature | Available now |
| --- | --- |
| Native glass Dock | Bottom replacement; top/bottom companion mode; selected display; full-screen/session/sleep suppression; true auto-hide; optional hide-on-overlap; icon sizes, accents, horizontal overflow |
| App management | Pinned apps, optional unpinned running apps, running indicators, hover animation, drag reorder, contextual actions |
| App search | Searches installed apps in Applications and System Applications; open or pin from results |
| Saved layouts | Save/apply/remove layouts; JSON export and import |
| ChatGPT plan usage | Actual returned Codex allowance buckets, percentages remaining, reset times, manual or five-minute refresh |
| Focus timer | 5, 15, 25, and 50 minute presets; pause, resume, reset, completion sound |
| Quick note | Editable note saved automatically on this Mac |
| Tasks | Local tasks, completion toggles, individual removal, clear completed |
| File shelf | Add files and folders, drop file shortcuts, drag out, open, reveal, and open Downloads |
| System information | Battery/charging state, installed RAM, available disk space, CPU core count, Activity Monitor shortcut |
| Calendar | Opt-in access to the next seven days of Mac calendar events; manual refresh |
| Clipboard | Opt-in text history, up to 20 entries in memory, click to copy, clear history |
| Weather | Manual city lookup and refresh, current and feels-like temperature in Fahrenheit, Open-Meteo attribution |
| GitHub | Public repositories or existing `gh` sign-in; stars/forks, open issues and PRs, latest Actions run, optional five-minute refresh, stale/error states |
| Bookmarks | Local named HTTP/HTTPS links; add, open, remove |
| Folders & Downloads | Choose a folder, navigate up/into subfolders, search, sort by name or newest, open, reveal, drag files out |
| Stopwatch | Start, pause/resume, laps, reset |
| Drink water | Personal daily goal, count, midnight reset, optional hourly sound while running |
| Habits | Daily completion toggles and up to 366 recorded completion dates per habit |
| Time progress | Day, month and year progress in your local calendar |
| World clocks | Add/remove IANA time zones, including daylight-saving handling |
| Converter | Offline length, mass, temperature, decimal/binary data conversions |
| Screenshot | Interactive region capture to clipboard; macOS screenshot/recording toolbar |
| Color picker | Native screen sampler; copy hex color |
| Quick controls | Mission Control, Emoji & Symbols, Trash, sound/display/network settings shortcuts |
| Apple Reminders | Explicit opt-in connection, read incomplete reminders, mark selected reminders complete |
| Widget organization | Search library, move widgets earlier/later, remove by right-click, space and separator entries |
| Login startup | Native macOS login item registration; approval status shown |
| Music | Opt-in Spotify or Apple Music connection, track/artist, previous/play-pause/next, ten-second polling while connected |

## New in 0.4

- Whole-tile Dock pages prevent right-edge overflow. Previous/next controls, page count and Settings stay visible, including with all widgets enabled.
- **Windows**: move a selected window to halves, quarters, maximize or center, choose a display, focus, minimize and undo. Allow WaveDock in Privacy & Security → Accessibility, then Refresh windows. Native full-screen windows must leave full screen first. Apps may enforce their own minimum sizes; WaveDock reports constraints and preserves Undo. This does not implement drag-to-edge snapping or thumbnails.
- **Google Calendar**: add Google in macOS Internet Accounts, enable Calendars, then connect the widget and select calendars belonging to that account. WaveDock reads the next seven days through EventKit; macOS owns Google sign-in and synchronization. The general Calendar widget can include iCloud, Google and other configured calendars. Both refresh while connected and support Disconnect. No custom Google OAuth client is needed.
- **Spotify and Apple Music**: separate widgets can be enabled together. Open the installed player, then Connect / refresh and allow Automation. Track, artist, playback state and transport controls refresh every ten seconds while connected. Reads run off the UI thread with a timeout; an exited player or failed read clears stale track data. The original Music widget remains as a combined panel.
- **OpenAI API, Claude API and Cursor team usage**: enable each from the widget library, enter that provider's organization/team admin API key in its secure field, and press Save & connect. Keys are stored in macOS Keychain. Refresh is explicit, with optional hourly polling for the current session. Disconnect & forget removes the saved key. Reports cover the last seven days; API widgets show tokens and Cursor shows separate activity counts. These require admin access and do not show ChatGPT Plus, Claude Pro/Max or personal Cursor subscription allowances. No API inference is performed.

API references: [OpenAI organization usage](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/completions), [Claude usage reports](https://platform.claude.com/docs/en/manage-claude/usage-cost-api), [Cursor team analytics](https://cursor.com/docs/account/teams/admin-api). Calendar setup: [Apple's calendar account guide](https://support.apple.com/guide/calendar/add-calendars-and-calendar-accounts-icl4308d6701/mac).

## Connect Codex allowance usage

1. Sign in with **ChatGPT** in Codex.
2. In WaveDock Settings, choose **Connect & refresh**.
3. If the executable is not detected, select it with **Choose…**. Common locations include `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, and the Codex CLI bundled with the ChatGPT desktop app.
4. Enable **Refresh usage automatically** if desired. Clicking the usage tile shows allowance details and reset times.

WaveDock calls the documented local `account/rateLimits/read` app-server method. It does not send prompts, run inference, redeem reset credits, scrape your chats, copy browser cookies, or parse credential files. Codex owns authentication and contacts OpenAI to retrieve your account's limits.

**This is not a general ChatGPT message counter.** It displays the allowance buckets the Codex service exposes for your account. Regular chat message quotas may not be included. API-key-only accounts may not expose subscription usage. Missing data is shown as unavailable; a failed refresh keeps a clearly marked previous reading.

Protocol reference: [OpenAI Codex App Server](https://developers.openai.com/codex/app-server/).

## GitHub widget

Enable **GitHub** in the widget library. Enter `owner/repository` or a GitHub repository URL, then press **Refresh GitHub**. Public access uses GitHub’s public REST API and needs no sign-in. For private repositories, install GitHub CLI, sign in yourself using `gh auth login`, and select **Use existing GitHub CLI sign-in**. WaveDock only runs `gh api --hostname github.com --method GET`; it does not request tokens or edit repositories. CLI errors are shown without printing potentially sensitive stderr.

Latest build status distinguishes queued/running/completed states. A failed refresh keeps a visibly marked previous reading. Switching repositories or access modes clears the previous repository and ignores responses from old requests. Actions or issues that are unavailable do not erase otherwise available repository metadata. This widget supports github.com, not GitHub Enterprise hosts yet.

## Permissions and data

- **Reminders:** requested only from Connect / refresh Reminders. Completing a reminder writes that selected change to Apple Reminders.
- **Screen capture / color:** invoked only by their buttons; macOS handles any required permission. Screenshot capture goes to the clipboard; the toolbar can choose a save location.
- **GitHub:** sends the repository name to GitHub when refreshed. Optional CLI mode uses the account already signed in to `gh`. No WaveDock credential store.
- **Window management:** opt-in Accessibility access permits reading window titles and moving/resizing selected windows. Titles remain in memory.
- **AI API widgets:** explicitly saved admin keys reside in Keychain and are sent only to the provider API. Reports stay in memory. Credentials are never exported with profiles.
- **Calendar:** requested only when you press Connect / refresh calendar. Events are read into memory; WaveDock does not edit them.
- **Music:** macOS asks for Automation permission for your chosen player. Open Spotify or Music and play a track before connecting. Disconnect stops polling.
- **Clipboard:** disabled on every launch until explicitly enabled. Text history stays in memory and clears when you quit. Copies marked concealed, transient, or automatically generated are skipped. Apps do not all mark sensitive text, so disable capture when copying sensitive information.
- **Weather:** sends your typed city to Open-Meteo's geocoding API, then the matching coordinates to its forecast API only when you refresh. No GPS/location permission. The public API is intended for noncommercial use; commercial distributors should review [Open-Meteo's terms](https://open-meteo.com/en/terms).
- **Notes, tasks, shelf paths, layouts, preferences:** stored locally in WaveDock's macOS preferences. Layout exports contain app paths and appearance settings, not notes, tasks, credentials, or clipboard history.
- **File shelf:** stores shortcuts to originals. Removing a shelf item does not delete the file. Moved/deleted original files need to be re-added.
- **Telemetry:** no WaveDock analytics or tracking server.

## Apple Dock restoration

Replacement mode journals the original `autohide` and `autohide-delay` preferences before making changes, including whether each key was absent. It sets auto-hide and a long reveal delay so Apple’s Dock does not compete with WaveDock at the bottom edge. It does not patch macOS or remove Dock icons. A brief desktop flash occurs when the native Dock restarts.

Quitting or choosing Restore Apple Dock restores the exact journaled values. Relaunch recovers an interrupted session before reapplying the saved replacement choice. If WaveDock crashes, preferences remain changed until recovery; the menu-bar Restore action and this command are available:

```sh
/path/to/WaveDock.app/Contents/MacOS/WaveDock --restore-dock
```

Quit a running WaveDock before using command-line recovery. If necessary, change auto-hide directly in System Settings → Desktop & Dock. Restoration failures retain the journal for retry. A second normal WaveDock instance cannot take ownership of the first instance’s Dock settings.

WaveDock excludes native full-screen Spaces and suppresses its panel when a regular app covers the selected display, during session inactivity, and while displays sleep. Hidden means no visible panel and no interception of clicks. A quarter-second edge dwell reveals an auto-hidden Dock; it hides 0.7 seconds after leaving. Full-screen suppression takes precedence over popovers. Background utilities’ transparent overlays are excluded from full-screen detection. Window-bounds detection is conservative; unusual games/video players and more display configurations still need hardware validation.

## Tests

```sh
zsh build.sh
chmod +x Tests/fixture_codex.py
dist/WaveDock.app/Contents/MacOS/WaveDock --self-test --fixture-cli "$PWD/Tests/fixture_codex.py"
codesign --verify --strict dist/WaveDock.app
```

For two complete build/test passes, run `zsh Tests/validate.sh`. Logs and local widget render captures are written under `.build/validation/`. On a logged-in desktop, pass `--native` to include native view and window-state checks; pass `--live` to also check public GitHub and the existing Codex sign-in. Live service checks are explicitly separate from offline regression tests.

The fixture runs locally without credentials or network calls. It checks the actual subprocess handshake, notification handling, and split response framing. Decoder tests cover multiple usage buckets, legacy fallback, missing windows, percentage bounds, and persistence formats for layouts and tasks. Regression tests also cover Dock visibility timing, negative display coordinates, durable preference restoration and failure retries, local utility persistence, stopwatch timing, folder search, bookmark validation, unit conversions, and GitHub response states. GitHub Actions runs two independent universal builds and offline test jobs on pushes and pull requests. See [validation details](docs/VALIDATION.md).

## Current limitations and roadmap

This is a substantial early-access app, not a complete CoolDock clone. In particular:

- One Dock on one selected display at a time. No per-display simultaneous docks, left/right layout, or automatic profile switching yet.
- Connected calendars refresh every minute and on Calendar changes. Weather refreshes manually and currently uses the first matching city and Fahrenheit.
- Tasks are WaveDock-local; Apple Reminders is a separate opt-in widget. Focus sessions and stopwatch laps do not survive quitting the app.
- System information does not yet include CPU/RAM utilization charts or network speed history.
- No window thumbnails, minimized-window tiles, custom app-icon packs, folder groups, or full native Dock drag/drop semantics.
- No automatic update service, Apple notarization, or App Store distribution yet. Login startup needs an installed app and may require macOS approval.
- Codex allowances, GitHub, OpenAI API token usage, Claude API token usage, and Cursor team analytics are supported. OpenAI/Claude consumer-plan allowances and commerce/mail integrations remain unimplemented. API metrics do not represent consumer-plan limits.
- Screenshots, unit conversions and color picking are supported. Voice recording, currency rates, wallpaper marketplace, app groups and window thumbnails remain unimplemented.
- Music and calendar need end-to-end validation across OS versions and real permission states. Multi-display placement needs testing on more hardware.

See [CoolDock comparison](docs/COOLDOCK-COMPARISON.md) for the sourced gap audit. Next priorities are app groups, window previews, additional supported providers, and multi-display hardware coverage. Production readiness requires broader testing and a signed/notarized release process.

## Project structure

```text
Sources/App.swift        App lifecycle, windows, placement, auto-hide, menu
Sources/DockBehavior.swift Visibility policy and transactional Apple Dock recovery
Sources/Utilities.swift   Local utility models and native system integrations
Sources/UtilityViews.swift Local utility popovers
Sources/GitHubWidget.swift Read-only GitHub REST and CLI client
Sources/GitHubView.swift  GitHub connection and activity UI
Sources/BehaviorTests.swift Regression checks
Sources/NativeTests.swift Opt-in native rendering/window checks
Sources/Model.swift      Apps, layouts and settings
Sources/Usage.swift      Read-only Codex usage client and data models
Sources/Views.swift      Main Dock, app tiles, usage details, settings
Sources/Toolkit.swift    Widget state, persistence, timers, integrations
Sources/ToolViews.swift  Widget popovers and library settings
Sources/SelfTests.swift  Decoding and persistence-format checks
Tests/fixture_codex.py   Offline app-server protocol fixture
Scripts/MakeIcon.swift   Reproducible native app-icon drawing
build.sh                Universal app build and local signing
```

## Contributing

Issues and pull requests are welcome. For bugs, include macOS version, processor type, app version, reproduction steps, and expected behavior. Do not attach credentials, private calendar data, or clipboard contents. Keep optional permissions and integrations opt-in, and include checks appropriate to changed behavior.

## License

[MIT](LICENSE). Use, modify, and share freely. Apple, Spotify, OpenAI, and other product names belong to their respective owners.
