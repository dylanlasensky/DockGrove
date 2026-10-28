# CoolDock comparison, checked October 28, 2026

This audit compares WaveDock's actual source with CoolDock's published documentation, rather than claiming parity from similar labels. CoolDock is an independent commercial product with a much larger catalog. WaveDock uses original native code and does not copy its artwork or implementation.

Sources: [widget catalog](https://cooldock.app/docs/widgets), [layout behavior](https://cooldock.app/docs/layout), [connected widgets](https://cooldock.app/docs/integrations), [release notes](https://cooldock.app/updates).

| Area | WaveDock 0.2 | WaveDock 0.3 |
| --- | --- | --- |
| Bottom replacement | Enabled Apple auto-hide, but Apple Dock could reveal underneath | Journals original hide/delay values, delays native reveal, restores on quit and recovers after interrupted sessions |
| Full screen | Explicitly joined full-screen Spaces | Excludes full-screen Spaces; detects display-covering regular app windows; session/sleep suppression |
| Auto-hide | 3% opacity and whole old rectangle as trigger | Fully ordered out; physical-edge dwell; pointer/interaction grace period; optional overlap hiding |
| Widgets and apps | Ten widget types; pinned/running apps; app ordering | 25 library entries, including spacers/separators; search and widget ordering; app hide/show |
| Local tools | Note, tasks, focus, shelf, clock, system facts | Adds bookmarks, folder browser, stopwatch, water reminders, habits, day/month/year progress, world clocks and unit converter |
| System tools | System facts, clipboard | Adds screenshot tools, color sampler, Mission Control, emoji, settings shortcuts and Trash access |
| Apple data | Calendar and Music/Spotify controls | Adds a separate Apple Reminders connection and individual completion actions |
| Developer / AI | Codex allowance buckets | Adds public/private GitHub repository activity and Actions status; verifies Codex read path |
| Startup | Manual | Native login-item control |

## Added in 0.4

32 library entries now include separate Google Calendar, Spotify, Apple Music, Windows, OpenAI API, Claude API and Cursor team widgets. Codex allowances remain a dedicated tile. Dock pages keep complete tiles within the selected display, with Settings always reachable. Window management offers halves, quarters, maximize, center, monitor selection, focus, minimize and undo through macOS Accessibility. Google calendars use macOS Internet Accounts and EventKit. Music transport requests are bounded and run off the UI thread.

AI integrations use documented organization/admin usage endpoints with Keychain storage, explicit refresh, optional hourly polling, pagination validation and error states. API tokens/team activity are distinct from consumer subscription allowances. These widgets require provider admin access; adding a UI and fixture tests does not establish live account validation.

## Added in 0.5

Rich information cards replace the icon-only widget presentation, with optional compact mode. Original monochrome branding, a new app icon, White/None accents and arbitrary custom RGB colors provide a consistent visual identity. Adds CPU history, memory use, network throughput, system audio output/volume, local voice recording, arithmetic calculator, daily currency conversion, app groups and web search. Window placement now waits for actual layout convergence and retries off the UI thread.

## Remaining gaps

These are **not** implemented, and the UI does not pretend otherwise:

- Consumer plan limits for Claude and personal Cursor, and AI providers beyond the implemented Codex/OpenAI API/Claude API/Cursor team integrations.
- Commerce, analytics, mail, social, and other service integrations beyond GitHub.
- Multiple simultaneous docks, left/right/floating layouts, automatic profiles, window thumbnails and drag-to-edge snapping, accessibility-based reserved space, badges, custom icon packs and complete native Dock drag/drop behavior.
- Hardware temperature and peripheral battery monitoring, per-app audio mixing, background sounds and wallpaper/photo services.
- Provider permissions and data behavior across all supported macOS versions, physical multi-monitor testing, signed/notarized distribution, automatic updates and the polish expected of a mature commercial app.

The user selected **AI usage and GitHub** as the next integration priority. GitHub and three additional API/team usage widgets are implemented; consumer-plan coverage and other providers remain explicit follow-up work. This release materially improves replacement behavior and local capabilities but does not claim CoolDock's entire catalog or production maturity.
