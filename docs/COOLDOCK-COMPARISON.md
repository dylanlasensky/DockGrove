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

## Remaining gaps

These are **not** implemented, and the UI does not pretend otherwise:

- Additional AI plan/API providers beyond Codex. Each requires a supported provider-specific authentication and usage contract; a webpage shortcut is not usage tracking.
- Commerce, analytics, mail, social, and other service integrations beyond GitHub.
- Multiple simultaneous docks, left/right/floating layouts, automatic profiles, app groups, thumbnail/window management, accessibility-based reserved space, badges, custom icon packs and complete native Dock drag/drop behavior.
- Live CPU/network history, hardware temperature and peripheral battery monitoring, per-app audio, voice memos, calculator, currency rates, background sounds and wallpaper/photo services.
- Provider permissions and data behavior across all supported macOS versions, physical multi-monitor testing, signed/notarized distribution, automatic updates and the polish expected of a mature commercial app.

The user selected **AI usage and GitHub** as the next integration priority. GitHub is implemented here; further AI providers remain explicit follow-up work. This release materially improves replacement behavior and local capabilities but does not claim CoolDock's entire catalog or production maturity.
