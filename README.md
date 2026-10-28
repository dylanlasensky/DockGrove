# WaveDock

**Your apps, useful widgets, and AI usage in one native Mac Dock.**

WaveDock is a free, open-source Mac app created by Dylan Lasensky. It gives you a customizable glass Dock with app launchers, a widget library, saved layouts, and a tile for the usage limits returned by your ChatGPT account's Codex service.

Built with Swift, SwiftUI, and AppKit. No Electron, web wrapper, subscription, account with WaveDock, or third-party package dependencies.

> **Early access, v0.2.0.** WaveDock is inspired by the usefulness of widget docks. It is an independent project, not affiliated with CoolDock or OpenAI. It does not yet match CoolDock's full catalog or production maturity. See the feature matrix and limitations below.

## Requirements

- macOS 14 Sonoma or newer.
- Apple Silicon or Intel Mac. The build produces a universal app.
- Xcode Command Line Tools to build from source (`xcode-select --install`).
- A compatible Codex CLI signed in with ChatGPT for AI usage tracking. Other widgets work without it.

## Install

### Download a build

Open [Actions](https://github.com/dylanlasensky/WaveDock/actions), choose a **successful** "Build and test macOS app" run, and download **WaveDock-macOS-universal** under Artifacts. GitHub may require you to sign in. Extract the artifact, then extract the enclosed `WaveDock.zip`. Drag `WaveDock.app` into Applications and open it.

Builds are ad-hoc signed for local testing, **not Developer ID signed or notarized by Apple**. If macOS blocks a build you trust, use its **System Settings → Privacy & Security → Open Anyway** flow. Do not disable Gatekeeper globally.

### Build from source

```sh
git clone https://github.com/dylanlasensky/WaveDock.git
cd WaveDock
zsh build.sh
open dist/WaveDock.app
```

The build uses the installed Apple toolchain and creates `dist/WaveDock.app`. It generates the app icon from the included drawing script. Build outputs are excluded from version control.

## First setup

1. Open Settings from the wave icon in your menu bar or the sliders button in WaveDock.
2. Choose icon size and an accent: Mint, Blue, Lilac, or Coral.
3. Pin apps with **Pin apps…** or the search widget. Drag pinned icons over another pinned icon to reorder them. Right-click for pin, unpin, move, reveal, and quit actions.
4. Choose a display and top or bottom placement. Enable automatic hiding if you prefer a quieter desktop. Move the pointer into the Dock area to reveal it.
5. Enable your widgets in **Widget library**. A full Dock scrolls horizontally.
6. Optionally enable **Use WaveDock as my Dock**. This temporarily enables Apple's Dock auto-hide; WaveDock restores the original preference when you disable replacement mode or quit.
7. Save a named layout to switch between app collections, widgets, icon sizes, and accent colors. Export/import layout JSON to move those layouts to another Mac. App paths must exist on the destination Mac.

The menu-bar wave always gives access to Settings, show/hide, usage refresh, Apple Dock restoration, and Quit. **Done** closes Settings. ⌘W closes Settings and ⌘Q quits while WaveDock is active.

## Features

| Feature | Available now |
| --- | --- |
| Native glass Dock | Top or bottom, selectable display, icon sizes, four accents, clock/date, horizontal overflow |
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
| Music | Opt-in Spotify or Apple Music connection, track/artist, previous/play-pause/next, ten-second polling while connected |

## Connect AI usage

1. Sign in with **ChatGPT** in Codex.
2. In WaveDock Settings, choose **Connect & refresh**.
3. If the executable is not detected, select it with **Choose…**. Common locations include `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, and the Codex CLI bundled with the ChatGPT desktop app.
4. Enable **Refresh usage automatically** if desired. Clicking the usage tile shows allowance details and reset times.

WaveDock calls the documented local `account/rateLimits/read` app-server method. It does not send prompts, run inference, redeem reset credits, scrape your chats, copy browser cookies, or parse credential files. Codex owns authentication and contacts OpenAI to retrieve your account's limits.

**This is not a general ChatGPT message counter.** It displays the allowance buckets the Codex service exposes for your account. Regular chat message quotas may not be included. API-key-only accounts may not expose subscription usage. Missing data is shown as unavailable; a failed refresh keeps a clearly marked previous reading.

Protocol reference: [OpenAI Codex App Server](https://developers.openai.com/codex/app-server/).

## Permissions and data

- **Calendar:** requested only when you press Connect / refresh calendar. Events are read into memory; WaveDock does not edit them.
- **Music:** macOS asks for Automation permission for your chosen player. Open Spotify or Music and play a track before connecting. Disconnect stops polling.
- **Clipboard:** disabled on every launch until explicitly enabled. Text history stays in memory and clears when you quit. Copies marked concealed, transient, or automatically generated are skipped. Apps do not all mark sensitive text, so disable capture when copying sensitive information.
- **Weather:** sends your typed city to Open-Meteo's geocoding API, then the matching coordinates to its forecast API only when you refresh. No GPS/location permission. The public API is intended for noncommercial use; commercial distributors should review [Open-Meteo's terms](https://open-meteo.com/en/terms).
- **Notes, tasks, shelf paths, layouts, preferences:** stored locally in WaveDock's macOS preferences. Layout exports contain app paths and appearance settings, not notes, tasks, credentials, or clipboard history.
- **File shelf:** stores shortcuts to originals. Removing a shelf item does not delete the file. Moved/deleted original files need to be re-added.
- **Telemetry:** no WaveDock analytics or tracking server.

## Apple Dock restoration

Replacement mode records the original `com.apple.dock autohide` preference before changing it. Apple's Dock is restarted to apply the setting. It remains available at the screen edge; WaveDock does not patch macOS or delete your existing Dock icons.

Disabling replacement mode or quitting restores the saved preference. After a crash, the next WaveDock launch attempts recovery. Restoration is not immediate while WaveDock is closed. You can always change auto-hide yourself in **System Settings → Desktop & Dock**.

## Tests

```sh
zsh build.sh
chmod +x Tests/fixture_codex.py
dist/WaveDock.app/Contents/MacOS/WaveDock --self-test --fixture-cli "$PWD/Tests/fixture_codex.py"
codesign --verify --strict dist/WaveDock.app
```

The fixture runs locally without credentials or network calls. It checks the actual subprocess handshake, notification handling, and split response framing. Decoder tests cover multiple usage buckets, legacy fallback, missing windows, percentage bounds, and persistence formats for layouts and tasks. GitHub Actions builds the universal app and runs these checks on pushes and pull requests.

## Current limitations and roadmap

This is a substantial early-access app, not a complete CoolDock clone. In particular:

- One Dock on one selected display at a time. No per-display simultaneous docks, left/right layout, or automatic profile switching yet.
- Calendar and weather refresh manually. Weather currently uses the first matching city and Fahrenheit.
- Tasks are WaveDock-local, not synced with Apple Reminders. Focus sessions do not survive quitting the app.
- System information does not yet include CPU/RAM utilization charts or network speed history.
- No window thumbnails, minimized-window tiles, custom app-icon packs, folder groups, or full native Dock drag/drop semantics.
- No launch-at-login UI, automatic update service, Apple notarization, or App Store distribution yet.
- No Shopify, Stripe, GitHub, Linear, Supabase, mail, or other business-service widgets.
- No screenshots widget, voice recorder, currency converter, color picker, or wallpaper marketplace yet.
- Music and calendar need end-to-end validation across OS versions and real permission states. Multi-display placement needs testing on more hardware.

Priorities: strengthen recovery and accessibility; improve multi-display behavior and keyboard shortcuts; add notification support and calendar updates; then add integrations with clear authentication and data handling. Production readiness requires broader testing and a signed/notarized release process.

## Project structure

```text
Sources/App.swift        App lifecycle, windows, placement, auto-hide, menu
Sources/Model.swift      Apps, layouts, settings, Dock restoration
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
