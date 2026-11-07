# Mac App Store readiness audit

Audited 2026-11-06 against `origin/main` at `9786d30`. This is a code and documentation audit. Nothing was built, run or submitted, so every statement about runtime sandbox behaviour comes from Apple's documentation or from the stock sandbox profile on the audit Mac (`/System/Library/Sandbox/Profiles/application.sb`, SDK 27.0). None of it was observed in a sandboxed DockGrove. No statement here predicts what App Review will do. `docs/COMMERCE.md` still records the selected route (direct sale); this document does not change that decision.

Paths in the form `File.swift:12` are under `app/Sources/`.

## Verdict

**DockGrove as it exists today cannot ship on the Mac App Store.** This is not a packaging problem. The features that define the product are ones the App Sandbox forbids, and the Mac App Store requires the sandbox.

| Blocker | Why | Can it be fixed by configuration? |
| --- | --- | --- |
| Replacing Apple's Dock | Changes another app's preferences and kills another app. Apple lists both as forbidden in a sandbox. Guidelines 2.5.8 and 2.5.9 are separate risks. | No |
| Window management (Windows widget, shelf, snapping) | Uses Accessibility on other apps. Apple's DTS: "It's not possible to use the Accessibility APIs from a sandboxed app." `com.apple.security.accessibility` "isn't a thing". | No |
| CLI-based AI usage (Claude Code, Codex, Gemini) | Runs tools from the user's home, reads their sign-in, edits `~/.claude/settings.json`. | No |
| License keys and web checkout | Guideline 2.4.5(vi) and 3.1.1 forbid license keys. | Yes, by compiling them out and using in-app purchase |

A **reduced edition** could plausibly be built: a floating dock and widget bar that runs *alongside* Apple's Dock, sold through in-app purchase. It would lose the headline feature. Approval is uncertain even then, because 2.5.8 says "Apps that create alternate desktop/home screen environments will be rejected", and Launchpad look-alikes have been rejected under 5.2.5 (see [Guideline issues](#guideline-issues)).

**Recommendation:** ship the full product directly with Developer ID and notarization (Route A). Treat a store edition as an optional, separate product, and ask App Review about the concept before spending engineering time on it (Route B).

## How to read the status labels

| Label | Meaning |
| --- | --- |
| **Keep** | Should work in a sandbox with at most an entitlement. Still needs a test. |
| **Rework** | Possible in a sandbox, but the code must change. |
| **Exception** | Needs a temporary-exception entitlement. Apple DTS: "App Review rarely approves folks to use temporary exception entitlements." ([forum 823455](https://developer.apple.com/forums/thread/823455)) |
| **Cannot ship** | Forbidden by the sandbox or a guideline, with no realistic exception. |
| **Unknown** | Evidence is thin. Test it. |

## What the sandbox forbids

Apple's [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) lists these as forbidden. Five of them apply to DockGrove, shown in bold:

- Use of Authorization Services API
- **Use of accessibility APIs in assistive apps**
- **Sending Apple Events to arbitrary apps**
- Sending `userInfo` dictionaries in distributed notifications to other tasks
- Loading kernel extensions
- Simulating user input in Open and Save dialogs
- **Accessing or modifying preferences in other apps**
- Configuring network settings
- **Terminating other running apps**

Two further facts drive most of the table below.

1. **The home folder moves.** The sandboxed app "doesn't have unrestricted access to the user's home folder" and file APIs resolve into its container (same page). `NSHomeDirectory()` and `homeDirectoryForCurrentUser` are expected to return the container, so code that builds `~/...` paths will silently look in the wrong place rather than fail loudly.
2. **Child processes stay in the box.** `Process()` can start `/usr/bin/*`, `/bin/*`, `/usr/sbin/*`, `/sbin/*`, `/System/*`, `/Applications/*` and the app bundle (`application.sb:377`, `:533-540`, `:564-568`), but the child is expected to inherit the sandbox. Other locations, including `~/.local/bin` and `/opt/homebrew/bin`, have no such rule. Signals are limited to `(target same-sandbox)` (`application.sb:791`), which is why `killall Dock` cannot work.

## Feature-by-feature sandbox feasibility

### Dock and windows

| Feature | Code | Status | Notes |
| --- | --- | --- | --- |
| Hide Apple's Dock (`defaults write com.apple.dock autohide`, `autohide-delay 86400`) | `DockBehavior.swift:171-173`, `:209-226`, `:251-258`; `App.swift:217`, `:347-358` | **Cannot ship** | `defaults` can start, but changing another app's preferences is on Apple's forbidden list. A `shared-preference.read-write` [temporary exception](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html) exists on paper, but it would not solve the restart below, and the purpose itself runs into 2.5.9. |
| Restart the Dock (`killall Dock`) | `DockBehavior.swift:226` | **Cannot ship** | Signals outside the app's own sandbox are not allowed (`application.sb:791`). Terminating other apps is on the forbidden list. |
| Restore Apple Dock, journal, `--restore-dock` | `DockBehavior.swift:126-200`; `App.swift:331-343`, `:368-377`, `:395-398` | Remove | No purpose without replacement. `applicationShouldTerminate` runs the restore on every quit (`App.swift:370`), so it must be compiled out, not just hidden. |
| Floating dock panels, extra docks, auto-hide, edge reveal | `App.swift:264-323`; `DockWorkspace.swift` | **Keep** | Own windows and `NSEvent.mouseLocation` need no permission. In this mode the native Dock can still reveal at the bottom edge; the comment at `DockBehavior.swift:172` explains why replacement delays it. Dock on another edge, or offer a button to Desktop & Dock settings and let the user turn on auto-hide themselves. |
| Overlap and full-screen detection (`CGWindowListCopyWindowInfo`) | `App.swift:118`, `:301-311`; `Notch.swift:270`, `:286-300` | **Keep** | Reads only owner PID, layer, alpha and bounds, not window names, so no Screen Recording permission should be needed. **Unknown** whether all of these fields stay populated in a sandbox. Test it. |
| List, move, resize, focus, minimize windows through AX | `WindowManager.swift:37-60`, `:119-141`, `:147-154`, `:212-250`, `:290-311` | **Cannot ship** | See [Accessibility](#accessibility). Removes the Windows widget and the Windows cube (`Views.swift:64`), "Show All Windows" (`Views.swift:302`), and the `AXIsProcessTrusted` prompts. |
| Window snapping | `WindowSnapper.swift:128-142` | **Cannot ship** as written | Same. |
| Global Esc (`addGlobalMonitorForEvents(.keyDown)`) | `Notch.swift:132-135`; `WindowSnapper.swift:34` | **Rework** | Apple: "Key-related events may only be monitored if accessibility is enabled or if your application is trusted" ([docs](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))). It would silently do nothing. Keep the local monitor at `Notch.swift:128-131`. |
| Global mouse monitors | `Notch.swift:125`; `ApplicationsStack.swift:158`; `AppsStackPopover.swift:248` | **Keep** | The documentation restricts key events only. |
| Carbon hot key (⌥⌘D) | `DockBehavior.swift:86-119` | **Keep** | Needs no Accessibility permission. |
| CGEvent tap | None found | Not applicable | The brief listed one; `app/Sources` has no `CGEvent`, `tapCreate` or `IOHID` use. |
| `launchctl`, LaunchAgents | None found | Not applicable | Login startup uses `SMAppService` only. |

### Apps

| Feature | Code | Status | Notes |
| --- | --- | --- | --- |
| Open at Login for DockGrove (`SMAppService.mainApp`) | `Utilities.swift:189-193` | **Keep** | It is a user toggle, which matches 2.4.5(iii). Check it stays off by default. |
| Open at Login for *other* apps (System Events `make login item`) | `Utilities.swift:195-223`; `Views.swift:297` | **Cannot ship** | Sending events to System Events for login items needs an exception, and it changes other apps' startup. 2.4.5(i) and (iii) both apply. |
| Scan `/Applications` and `/System/Applications` | `Toolkit.swift:31`, `:199-222` | **Keep** | `file-read*` is allowed for both (`application.sb:376`, `:533-540`). |
| Scan `~/Applications` | `Toolkit.swift:31` | **Rework** | `NSHomeDirectory()` resolves to the container. The folder needs a user grant, or drop it. |
| Launch apps, open URLs, reveal in Finder | `Model.swift:118-120`; `AppWindows.swift:34-37` | **Keep**, test | Standard `NSWorkspace` calls. `.reveal` and dropped-file opening need a test. |
| Running apps list, icons | `AppWindows.swift:69-71` | **Keep** | |
| Quit and Force Quit other apps | `Views.swift:306`; `AppWindows.swift:39-40` | **Cannot ship** | Apple: "Sandboxed applications can't use this method to terminate other applications" ([terminate](https://developer.apple.com/documentation/appkit/nsrunningapplication/terminate()), [forceTerminate](https://developer.apple.com/documentation/appkit/nsrunningapplication/forceterminate())). Both return `false`, so the menu items would look broken. Remove them. |
| Hide or show other apps | `Views.swift:303`; `AppWindows.swift:38` | **Unknown** | Not on Apple's list. Test it. |

### Automation

| Feature | Code | Status | Notes |
| --- | --- | --- | --- |
| Apple Music | `MusicPlayer.swift:47`, `:63-81`, `:109`, `:120-151` | **Rework** | Music publishes scripting access groups. In the local `com.apple.Music.sdef`, `com.apple.Music.playback` covers transport commands (`:86-124`), `current track` (`:233-234`) and `player state` (`:250-251`), and `com.apple.Music.library.read` exists (`:100`). Use `com.apple.security.scripting-targets`, which is not a temporary exception. Move from a child `osascript` to in-process `NSAppleScript` or Scripting Bridge. **Unknown** whether artwork `raw data` is reachable, since that property lists no group of its own (`:286`). [Forum reports](https://developer.apple.com/forums/thread/126435) show this entitlement misbehaving. Spike it first. |
| Spotify | `Toolkit.swift:78`; same player code | **Exception** or drop | Spotify was not installed on the audit Mac, so whether it publishes access groups is **Unknown**. Without them, the only route is `temporary-exception.apple-events`. The alternative is the Spotify Web API with OAuth, which is new work and subject to 5.2.2. The private MediaRemote framework is not an option. |
| Mission Control, Emoji, Settings shortcuts | `UtilityViews.swift:121-129` | **Keep** | The `x-apple.systempreferences:` extension IDs are not documented API. See [Private API](#private-or-undocumented-api-use). |
| Open Trash | `UtilityViews.swift:129` | **Rework** | Uses `homeDirectoryForCurrentUser/.Trash`, which is the container in a sandbox. |

### Subprocesses and AI tools

| Feature | Code | Status | Notes |
| --- | --- | --- | --- |
| `claude -p /usage` | `LocalAIUsage.swift:260-297` | **Cannot ship** | The search path is built from the container home (`AISignIn.swift:20-32`). Installed locations have no exec rule. Even if started, it could not read its sign-in. 2.5.2 also applies. |
| `claude auth login`, `codex login` | `AISignIn.swift:78-119` | **Cannot ship** | Same. |
| `codex app-server` | `Usage.swift:61-135` | **Cannot ship** | `/Applications/ChatGPT.app/.../codex` could be started (`application.sb:533-540`), but it inherits the sandbox and would not reach its own sign-in. |
| Gemini sign-in (writes a `.command`, opens it in Terminal) | `AISignIn.swift:53-64`, `:211-222` | **Cannot ship** | Writing a script and handing it to Terminal escapes the sandbox, and 2.5.2 applies. The `gemini` it runs is also not reachable from the sandbox. |
| Claude status line wrap, edits `~/.claude/settings.json` | `LocalAIUsage.swift:298-356`, `:414-427` | **Cannot ship** | Writes outside the container (2.5.2) and installs a command that another tool will execute. `settingsURL` (`:301`) would resolve to a file in the container, so it could silently report success while doing nothing. |
| `--claude-statusline --then`, which runs `/bin/sh -c` | `App.swift:393`; `LocalAIUsage.swift:141-168` | **Cannot ship** | Compile out. |
| `--gemini-report`, Copy capture command | `App.swift:394`; `LocalAIUsage.swift:440-443` | **Cannot ship** | Compile out. Depends on the app being driven from a shell. |
| Custom CLI path | `AISignIn.swift:167`; `Model.swift:33` | **Cannot ship** | Runs a user-chosen executable. Compile out. |
| Import Gemini JSON from a file picker | `LocalAIUsage.swift:428-432` | **Keep** | User-selected file. |
| Admin-key usage (OpenAI, Anthropic, Cursor) over HTTPS | `AIUsage.swift:22-44`, `:141-166`, `:180-187` | **Keep** | Network plus Keychain. Review the 5.1.2 and 5.2.2 notes below. |
| GitHub through `gh` | `GitHubWidget.swift:64`, `:104-126`; `GitHubView.swift:9` | **Cannot ship** | Would lose private repositories. |
| GitHub public REST | `GitHubWidget.swift:89` | **Keep** | Public repositories only. A private-repo option would need OAuth, which is new work. |

No direct read of `~/.claude/` credentials was found. The home reads are the CLI search list (`AISignIn.swift:21-26`, including a listing of `~/.nvm/versions/node`) and `~/.claude/settings.json`. `~/Library/` is reached only through `FileManager` Application Support (`BrandStorage.swift:5-11`), which works and lands in the container.

### Files, data and services

| Feature | Code | Status | Notes |
| --- | --- | --- | --- |
| File shelf, notch tray | `Toolkit.swift:15`, `:32-35`, `:159-162`; `Notch.swift:214-238`; `NotchWorkspace.swift` | **Rework** | Picked or dropped files work for the session, but `files` stores plain path strings, so access is lost after relaunch. Store security-scoped bookmarks with `com.apple.security.files.bookmarks.app-scope`, and bracket each use with `startAccessingSecurityScopedResource`. |
| Folders & Downloads widget | `Utilities.swift:64`, `:120-126`; `UtilityViews.swift:35-41` | **Rework** | The default `~/Downloads` is built from the home directory. "Up" walks outside the granted folder and will fail. Use the Downloads entitlement or require a picked folder, and limit "Up". |
| Layout import and export | `Model.swift:129-136`, `:294-309` | **Keep** | Save and open panels. |
| Voice memos | `ExtraWidgets.swift:129-211`; `Info.plist:48` | **Keep** | `device.audio-input`. Files land in the container, so "All recordings in Finder" (`ExtraWidgets.swift:227`) opens a container path. Test it. |
| AirDrop tray | `Notch.swift:183-196` | **Keep**, test | `NSSharingService`. |
| Clipboard history | `Toolkit.swift:92`, `:147-153`; `ToolViews.swift:209` | **Keep**, test | Opt-in, in memory. `NSPasteboard.AccessBehavior` exists since macOS 15.4 (SDK header). [Reports](https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4) say the prompt is off by default as of macOS 26. **Unknown** for macOS 27 and for a timer-driven reader. Polling once a second is also a 2.4.2 point. |
| Screenshot | `Utilities.swift:138`, `:147-155` | **Keep**, test | `application.sb:44-45` has a specific rule for `/usr/sbin/screencapture` interactive mode, so this looks intended to work. Test it. The fallback is the existing Screenshot.app button (`UtilityViews.swift:116`). |
| Color picker | `Utilities.swift:187` | **Keep** | `NSColorSampler`. |
| Calendar and "Google Calendar" | `CalendarWidget.swift`; `Info.plist:44` | **Keep** | EventKit with `personal-information.calendars`. |
| Reminders | `Utilities.swift:162-176`; `Info.plist:50` | **Keep** | EventKit. Reminders access is believed to use the same calendars entitlement; confirm. |
| Weather | `WeatherClient.swift:34-68`; `DockGrove.entitlements` | **Keep** | Needs the capability on the store App ID. No location is requested (`WeatherClient.swift:42`). |
| Currency | `ExtraWidgets.swift:85-100` | **Keep** | Sends the currency pair to frankfurter.dev. |
| Album art | `AlbumArtwork.swift` | **Keep** | Network. |
| System stats (CPU, memory, network, battery) | `SystemMonitor.swift:31-63`; `Toolkit.swift:223-235` | **Keep**, test | Public Mach, `getifaddrs` and IOKit calls. |
| Audio output and volume | `SystemMonitor.swift:78-114` | **Unknown** | CoreAudio writes. Likely fine; test it. |
| Keychain | `AIUsage.swift:141-166` | **Keep** | |
| Notch panel | `Notch.swift`; `NotchWorkspace.swift` | **Keep** | Public `NSScreen` API. See Private API. |
| Companions, clock, notes, tasks, habits, timers, converters | Various | **Keep** | Local. |
| Network generally | All `URLSession` use | **Keep** | `network.client`. |

### Accessibility

Apple is unusually direct here. DTS: "It's not possible to use the Accessibility APIs from a sandboxed app" and "your only path forward here is to directly distribute your app using Developer ID signing" ([forum 805556](https://developer.apple.com/forums/thread/805556)). Developers report that a sandboxed app gets no prompt and `AXIsProcessTrusted` stays false ([forum 810677](https://developer.apple.com/forums/thread/810677)). Older store apps such as Magnet are often cited as counter-examples, but Quinn notes that an app published before the sandbox requirement "might not be sandboxed", so that precedent does not help a new app.

Two leads, both untested. Neither should be planned around without a spike.

- **System Events scripting target.** The local `SystemEvents.sdef:1133`, `:1648` and `:1661` publishes an access group, `com.apple.systemevents.window.position`, with read/write on window `position` and `size`. This suggests a sandboxed app might move and resize windows with `com.apple.security.scripting-targets`, with no AX in its own process. It would not cover raising, minimizing or focusing, and it was not found documented anywhere. Whether System Events would still need Accessibility permission, and whether Review accepts it, are both **Unknown**. Worth a one-day spike only if Route B goes ahead.
- **Delegating to Shortcuts.** A third-party [write-up](https://blakecrosley.com/blog/window-manager-mac-app-store-sandbox) describes store apps that hand window moves to the Shortcuts app. Second-hand, and it needs a separate install step for the user.

PopClip left the store in 2024, reportedly after being told to drop new Accessibility functionality from a sandboxed update ([Michael Tsai](https://mjtsai.com/blog/2024/03/21/popclip-leaving-the-mac-app-store/); second-hand).

## Private or undocumented API use

The result here is good. Searches of `app/Sources` found **no** `dlsym`, `dlopen`, `@_silgen_name`, `NSClassFromString`, `objc_msgSend`, method swizzling, `CGS*` or `SLS*` calls, SkyLight, CoreDock, or any `PrivateFrameworks` import. The imports are all public frameworks. There are no third-party packages (`project.yml` has no `packages:` key). `Purchases.swift` and all StoreKit code use public API.

Items worth attention:

| Item | Code | Risk |
| --- | --- | --- |
| `"AXEnhancedUserInterface"` | `WindowManager.swift:297-300` | Not in the SDK 27.0 HIServices headers, so it is undocumented. Goes away with AX removal. Developer ID builds are unaffected by store rules. |
| `"AXFullScreen"` | `WindowManager.swift:172`; `WindowSnapper.swift:139` | Same. Only `kAXFullScreenButtonAttribute` is public. |
| `autohide-delay` Dock preference | `DockBehavior.swift:136` | Undocumented preference. Goes away with Dock replacement. |
| `x-apple.systempreferences:` extension IDs | `UtilityViews.swift:124-128`; `CalendarWidget.swift:98` | Not documented API and can break between macOS releases. Low risk. Keep a fallback. |
| Notch positioning | `Notch.swift:18` | Uses public `safeAreaInsets` and `auxiliaryTopLeftArea`. A panel at `.statusBar` level near the menu bar is public API. The concern, if any, is 2.5.9, not 2.5.1. |
| Synthetic `NSEvent` within own window | `App.swift:68`, `:89` | Sent only to DockGrove's own window. Public API. |
| Test code in the shipping target | `NativeTests.swift`; `ReleaseVisualTests.swift`; `App.swift:128`, `:233` | `--native-test <path>` runs a test harness from the production binary, and it uses `Selector(("selectAll:"))`. Exclude both files from store builds. |

Clean source does not guarantee a clean automated scan. Run the App Store Connect validation.

## Guideline issues

Text is from the current [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/). Ratings describe risk, not a predicted outcome.

| Guideline | Text, shortened | DockGrove today | Reduced edition |
| --- | --- | --- | --- |
| **2.4.5(i)** | "must be appropriately sandboxed" | Fails: `ENABLE_APP_SANDBOX: NO` (`project.yml:19`) | Passes after work |
| **2.4.5(ii)** | Self-contained, no shared install | The status-line command lives in another tool's config | Passes |
| **2.4.5(iii)** | No auto-launch "without consent", no processes that outlive the app | Own login item is opt-in. Changing other apps' login items is a concern | Passes if removed |
| **2.4.5(iv)** | No downloading code | No updater or downloader found | Passes |
| **2.4.5(v)** | No root | No `sudo`, Authorization Services or setuid found | Passes |
| **2.4.5(vi)** | "may not present a license screen at launch, require license keys, or implement their own copy protection" | Fails in Commercial: `Licensing.swift`; `DockStudioSettings.swift:86-87`, `:95-96`; `Model.swift:139` | Passes if compiled out |
| **2.4.5(vii)** | Updates only through the store | Passes: no Sparkle or updater found. README confirms none | Passes |
| **2.4.5(viii)** | No deprecated or optionally installed tech | Depends on optional CLIs | Passes if removed |
| **2.5.1** | Public APIs, used as intended | See table above | Passes after AX removal |
| **2.5.2** | No reading or writing outside the container, no executing code that changes features "including other apps" | Fails: `~/.claude/settings.json`, Terminal script, `/bin/sh -c`, CLIs | Passes if removed |
| **2.5.8** | "Apps that create alternate desktop/home screen environments will be rejected." | **High risk.** The product is pitched as a Dock replacement | **Real risk.** The largest unknown. A dock with app launching and pinned apps may be read this way. No source found applying 2.5.8 to a Mac dock, so this is a reading of the text, not precedent |
| **2.5.9** | Apps that "alter or disable the functions of standard switches ... or other native user interface elements or behaviors will be rejected" | **High risk**: disabling the native Dock | Lower, because the Dock is left alone. A notch overlay may draw attention |
| **2.4.2** | Efficient power use | A 0.2 s timer calls `CGWindowListCopyWindowInfo` (`App.swift:209`, `:285`), plus 1 s (`Toolkit.swift:119`). Measure it | Measure it |
| **3.1.1** | Unlocking features must use in-app purchase. No "license keys" | Fails in Commercial | Passes with StoreKit |
| **3.1.1(a)/3.1.3** | Links to external purchase are limited, with a US-storefront carve-out | "Buy" opens the website (`Licensing.swift:221`; `:238`) | The carve-out allows links on the US storefront only, and it does **not** lift the license-key ban. Remove the whole flow |
| **3.1.3(b)** | Web-bought access is allowed only if it is also available as an in-app purchase | License holders have no path, and a license key may not unlock the store build | Do not cross-grant. Sell the two editions separately and say so clearly |
| **4.1** | No copying, no impersonation | Modest. The app is original, but see 5.2.5 | Same |
| **4.2** | Must be useful beyond a wrapper | No concern | No concern |
| **5.1.1(i)** | Privacy policy in App Store Connect **and in the app** | `website/public/privacy.html` exists, but it describes the direct candidate, and no in-app link was found | Rewrite and add a link |
| **5.1.1(ii)** | Consent, with purpose strings | Purpose strings are clear (`Info.plist:43-51`) | Passes |
| **5.1.1(iii)** | Minimise data. Prefer pickers | Calendar and Reminders request full access. Justifiable for widgets | Passes |
| **5.1.1(v)** | No login unless needed | No DockGrove account. Admin keys are optional | Passes |
| **5.1.2(i)** | Disclose sharing, "including with third-party AI", and get explicit permission | Direct-only concern today | Admin keys go to the chosen provider and usage totals come back. No prompts or personal content are sent. **Unknown** whether Review treats this as AI sharing. Describe it in Review notes |
| **5.2.1, 5.2.2** | No third-party marks without permission. Must be permitted to use a service | Brand marks `fa-claude`, `fa-openai`, `fa-google` (`app/Assets.xcassets/FontAwesome/`) and the names Spotify, Cursor, GitHub, Gemini. Provider terms for reading usage were not reviewed. "Authorization must be provided upon request" | Remove the marks for removed widgets. Check the remaining terms |
| **5.2.5** | Don't appear "confusingly similar to an existing Apple product, interface" | **Medium to high.** Tile menus deliberately copy the Mac Dock (`ApplicationsStack.swift:59`; "Keep in Dock", "Show All Windows", "Options" at `Views.swift:295-306`) | **Medium.** [AppHub](https://www.ifun.de/apphub-fuer-macos-tahoe-launchpad-alternative-geht-apple-zu-weit-265475/) (German report, 2025) was reportedly rejected under 5.2.5 as a Launchpad copy. Give the edition its own look and wording |

**Precedent.** uBar's developer says the sandbox "prevents Applications from performing many operations" that are "crucial to a fully functioning Dock replacement", and sold a [reduced store version](https://ubarapp.freshdesk.com/support/solutions/articles/150000000939-upgrading-from-the-mac-app-store-version-of-ubar-to-the-full-version) alongside the full one. A [store listing](https://apps.apple.com/us/app/ubar-3/id1073691121?mt=12) exists. This shows a reduced edition has been accepted in the past, but it is an older app, and it does not establish how Review treats a new one today.

### Trademarks and imagery

Apple's [trademark list](https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html) does not include "Dock". It does include Mission Control, Finder, Launchpad, Spotlight, AirDrop and Apple Music. So:

- **The name.** "DockGrove" uses no listed Apple mark. A reviewer may still read "Dock" as implying the system feature. Uncertain, and low to medium.
- **"Apple Dock" in the UI** (`App.swift:193`, `:334`, `:341`, `:372`; `DockStudioSettings.swift:133`, `:405-408`; `Views.swift:226`) is removed along with the feature. Avoid "replacement for the Dock" in store metadata.
- **Descriptive use** of AirDrop, Mission Control, Apple Music and Apple Reminders is reasonable when it names the feature used. Follow Apple's rule: adjectives, never plural or possessive. "Restore Apple's Dock" already goes away.
- **"Apple Weather"** (`WeatherAttributionView.swift:15`) is required by WeatherKit attribution. Keep it.
- **The icon** is an original three-bar mark and no Apple logo is used (`docs/BRAND.md`, README). The Applications tile shows the system folder icon (`ApplicationsStack.swift:17`), which is fine.
- **"Google Calendar"** (`WidgetCatalog.swift:14`) is a filtered EventKit view. Consider naming it "Calendar account" to avoid implying a Google integration.

## Commerce in a store build

The StoreKit code is the most ready part of this project. `Purchases.swift` and `PurchaseViews.swift` handle verified transactions, refund revocation, restore, pending and failure, and `app/PurchaseTests` covers them with `StoreKitTest` (nine tests passed on 2026-10-30 per `docs/IN-APP-PURCHASES.md`). `DOCKGROVE_STOREKIT` is on in Debug and Release (`project.yml:57`).

What must change:

1. **Compile the license flow out.** With `DOCKGROVE_STOREKIT` the license UI is unreachable (`Model.swift:139`; `DockStudioSettings.swift:95-96`), but it is still in the binary: `LicenseManager.shared` is constructed and runs a 60-second timer (`Licensing.swift:150`; `App.swift:218`; `Model.swift:195`), the "Buy" and `recover.html` code ships, and `Info.plist:9-14` carries license keys. Add `DOCKGROVE_APPSTORE` and exclude `Licensing.swift`, or stub `permitsFeatures`.
2. **Refresh the products.** The drafts promise "every widget, all companions, GitHub, and AI usage" (`DockGrove.storekit`). `PurchaseViews.swift:67-70`, `:96-100` advertise "Codex usage" and music. These must match the reduced edition, per 2.3.
3. **Trim the catalog.** Remove `.windows`, `.claudeCodeUsage`, `.geminiUsage`, and `.spotify` unless solved, from `WidgetCatalog.swift:4-8`, `:38-44`, plus the Codex widget. Imported layouts must tolerate missing kinds.
4. **Decide the model.** Free with Plus and Full Access in-app purchases, or one paid download. The tier design already exists; the $9.99 direct price and Apple's commission should be compared by the owner.
5. **Submit together.** Per `docs/IN-APP-PURCHASES.md`, first purchases go with an app version and need review screenshots. The Paid Apps Agreement was accepted.

## Build and packaging

| Item | Today | Needed for the store |
| --- | --- | --- |
| Build configuration | Debug, Release, Development, Commercial, CommercialQA (`project.yml:7-12`) | Add `AppStore` config and a `DockGrove App Store` scheme with `archive: config: AppStore`. Set `DOCKGROVE_STOREKIT DOCKGROVE_APPSTORE`. Regenerate the project with XcodeGen |
| Sandbox | `ENABLE_APP_SANDBOX: NO` (`project.yml:19`) | `YES` for `AppStore` only. Leave direct builds alone |
| Bundle ID | `com.dylan.wavedock.development` on App Store Connect app 6829005855 | Do not ship this ID. Choose before the first upload: Apple says "You can't change this property after you upload a build" ([help](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)). `docs/IN-APP-PURCHASES.md` records no upload, but confirm in the account. Use a distinct ID from direct builds, because `com.dylan.wavedock` is the Commercial ID and the license audience (`project.yml:72`; `Licensing.swift:85`). If the record must be recreated, the draft purchases need recreating too; whether their product IDs can be reused is **Unknown** |
| Display name | `DockGrove Development` in base settings (`project.yml:59`); the `DockGrove` scheme archives Release (`project.yml:178`) | Set `DockGrove`. Archiving today would produce the wrong name and ID |
| Signing | Ad hoc `-` for distributables, Apple Development in base (`project.yml:15`, `:25-36`) | Apple Distribution certificate, Mac Installer Distribution certificate, Mac App Store provisioning profile for the new App ID, with WeatherKit and In-App Purchase enabled |
| Hardened runtime | Not set | Not required by notarization rules for store apps, since [store apps need no notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Harmless to enable. **Required** for Developer ID |
| Entitlements | `com.apple.developer.weatherkit` only | See below |
| Privacy manifest | None | See below |
| `LSApplicationCategoryType` | Missing | Add `public.app-category.productivity` or `.utilities` |
| Export compliance | Missing | Add `ITSAppUsesNonExemptEncryption` = `NO`. OS HTTPS is typically exempt per [Apple](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations). `CryptoKit` is used only for license signature checks, which go away. Confirm the answer, and check whether an annual self-classification report applies |
| Icons | All ten sizes, 16 to 1024 px, in `AppIcon.appiconset`. The 1024 px file was checked | Sufficient as far as checked. Confirm `CFBundleIconName` appears in the archived `Info.plist` |
| Usage strings | Apple Events, Calendars, Reminders, Microphone (`Info.plist:42-51`) | All present and specific. Reword Apple Events to name Apple Music only if Spotify goes |
| Custom plist keys | `DockGroveLicense*` (`Info.plist:9-14`) | Remove with a separate `Info-AppStore.plist` or a preprocess step |
| Minimum OS | 14.0 (`project.yml:4`; `Info.plist:28`) | No reason to change. Keep the two values in step |
| Architectures | Universal, verified by CI lipo (`build.yml:49-50`) | Set `ONLY_ACTIVE_ARCH: NO` for `AppStore` |
| Version | 1.0.0 (11), hard-coded (`Info.plist:24-26`) | Each upload needs a unique build number |
| Updater | None. No Sparkle or appcast found | Nothing to remove. 2.4.5(vii) is met |
| `.storekit` file | `buildPhase: none` in the app target (`project.yml:51-52`) | Not bundled. Verify in the archive |
| Test code | `Sources` includes `NativeTests.swift`, `ReleaseVisualTests.swift` | Exclude from `AppStore` |
| Quarantine | Not applicable yet | Apple rejects uploads whose files carry `com.apple.quarantine` ([requirements](https://developer.apple.com/news/upcoming-requirements/)) |
| Install | `.pkg` from the Xcode Organizer or `xcodebuild -exportArchive` | 2.4.5(ii) requires Xcode-provided packaging |
| SDK minimum | CI uses the newest Xcode on `macos-26` (`build.yml:25`) | Apple's [published minimum](https://developer.apple.com/news/upcoming-requirements/) (Xcode 26, from 28 April 2026) names iOS, iPadOS, tvOS, visionOS and watchOS, **not macOS**. No published macOS minimum was found. Build with the latest release Xcode anyway; 2.4.5(viii) and 2.5.1 require running on the current OS. Check App Store Connect's upload messages |
| `LSUIElement` | `true` (`Info.plist:40`) | Allowed as far as known. First launch shows Settings (`App.swift:232`). Keep a clear path to Settings and Quit in the status menu |
| `SWIFT_VERSION` | 5.0 | No store issue |

### Entitlements for a store build

| Entitlement | Why |
| --- | --- |
| `com.apple.security.app-sandbox` | Required |
| `com.apple.security.network.client` | Weather, GitHub, currency, album art, admin-key usage |
| `com.apple.security.files.user-selected.read-write` | Shelf, tray, folder widget, layout export, memo export |
| `com.apple.security.files.bookmarks.app-scope` | Keep shelf and folder access after relaunch |
| `com.apple.security.files.downloads.read-only` | Default folder widget target. Drop it if the widget starts empty |
| `com.apple.security.device.audio-input` | Voice memos |
| `com.apple.security.personal-information.calendars` | Calendar and Reminders |
| `com.apple.security.scripting-targets` with `com.apple.Music`: `com.apple.Music.playback`, `com.apple.Music.library.read` | Apple Music widget. Confirm the groups in a spike |
| `com.apple.developer.weatherkit` | Weather. Already present |

Avoid every `temporary-exception` key. If one is unavoidable, Apple asks you to explain it in App Store Connect and file a bug. No `com.apple.security.accessibility` entitlement exists, per DTS. `com.apple.security.automation.apple-events` applies to the hardened runtime and belongs in the Developer ID entitlements.

### `PrivacyInfo.xcprivacy`

Whether this is enforced on macOS is **unclear**. The [key reference](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) lists macOS 14.0+, the [required-reason page](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) names only iOS, iPadOS, tvOS, visionOS and watchOS, and third-party sources [disagree](https://techconcepts.org/blog/privacyinfo-xcprivacy-guide-ios-developers). Include the file anyway; it costs little. Place it in `Contents/Resources`.

Declare `NSPrivacyTracking` false, no tracking domains, and collected data types empty if the edition has no server of its own.

| Category | Reason | Code using it | Note |
| --- | --- | --- | --- |
| User defaults (`NSPrivacyAccessedAPICategoryUserDefaults`) | `CA92.1` own data | `App.swift:114`; `Model.swift:92`; `Toolkit.swift:90`; `Utilities.swift:53`; `Companion.swift:41`; `CalendarWidget.swift:30`; `GitHubWidget.swift:138`; `DockWorkspace.swift:53`, `:65` | Suites are named `com.wavedock...` and live in the container. Reading `com.apple.dock` would not fit `CA92.1`, but that goes away |
| File timestamp (`...FileTimestamp`) | `DDA9.1` shown to the user; `C617.1` own container; `3B52.1` user-granted | `ExtraWidgets.swift:155-163` memos (`C617.1`, `DDA9.1`); `Utilities.swift:123`, `:130-131` folder widget (`3B52.1`); `DockLayout.swift:69-72` stack sort; `Toolkit.swift:202-208` scan cache | **The last two have no clean reason.** `/Applications` is neither the container nor user-granted, and a sort or cache is not a display. `addedToDirectoryDateKey` is not on the list, but creation and modification are. Either remove date sorting and key the cache on `CFBundleVersion`, or ask Apple. **Uncertain** |
| System boot time (`...SystemBootTime`) | `35F9.1` elapsed time | `WindowManager.swift:57` (goes away); `App.swift:68`, `:89` | The `App.swift` uses can pass the triggering event's timestamp instead, which removes the category |
| Disk space (`...DiskSpace`) | `85F4.1` display | `Toolkit.swift:225-226`, shown at `SystemMonitor.swift:159` | |
| Active keyboards | Not used | | |

`Model.swift:302` calls `attributesOfItem` for size only, under a user-chosen file, so it is not a listed timestamp key. No `stat`, `getattrlist` or `mach_absolute_time` use was found in `app/Sources`.

### App Store Connect work

- Metadata: name, subtitle, description, keywords without "Apple", privacy policy URL, support URL.
- Screenshots: 16:10 at 1280×800, 1440×900, 2560×1600 or 2880×1800, no alpha ([spec](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/)).
- App privacy labels, the updated age-rating questions, and EU trader status ([requirements](https://developer.apple.com/news/upcoming-requirements/)).
- In-app purchase screenshots and notes.
- Review notes. 2.3.1 requires features to be accessible for review, so explain the widgets, how to test Apple Music and Calendar, and that the edition leaves Apple's Dock untouched.

## What survives in each route

| Feature | Route A: Direct | Route B: Reduced store edition |
| --- | --- | --- |
| Replace Apple's Dock | Yes | **No** |
| Floating docks, multiple docks, layouts, themes | Yes | Yes |
| App launching, search, pinned apps, Applications stack | Yes | Yes, `~/Applications` needs a grant |
| Quit and Force Quit from tiles | Yes | **No** |
| Windows widget, cube, Show All Windows, snapping | Yes | **No** (lead: System Events target, move and size only, untested) |
| Open at Login for other apps | Yes | **No** |
| Open at Login for DockGrove | Yes | Yes |
| Notch shelf and AirDrop | Yes | Yes, with bookmarks and no global Esc |
| Apple Music | Yes | Probably, after a spike |
| Spotify | Yes | **Not without an exception or a Web API rewrite** |
| Calendar, Reminders, Weather, voice memo, clipboard | Yes (Weather needs a Developer ID profile) | Yes |
| Claude Code, Codex, Gemini CLI sign-in and usage | Yes | **No** |
| Gemini report import from a file | Yes | Yes |
| OpenAI, Anthropic, Cursor admin-key usage | Yes | Yes |
| GitHub public | Yes | Yes |
| GitHub private through `gh` | Yes | **No** |
| Companions, local tools | Yes | Yes |
| Payment | License token, Stripe | In-app purchase only |
| Updates | Must add an updater, or manual | App Store |

**Plain list: these cannot ship in a sandboxed build.** Replacing or hiding Apple's Dock, restarting the Dock, window management through Accessibility including snapping, global keyboard monitoring, quitting other apps, changing other apps' login items, every feature that runs `claude`, `codex`, `gemini` or `gh`, editing `~/.claude/settings.json`, the Gemini Terminal script, the shell pass-through, and the license key flow.

## The two routes

Estimates are rough, for one engineer who knows this code. They exclude owner time on accounts, and they exclude waiting on Apple.

### Route A: stay direct (recommended)

Keeps the whole product. Apple's own guidance for this category is direct distribution.

| Work | Estimate |
| --- | --- |
| Developer ID certificate, hardened runtime, entitlements (`com.apple.security.automation.apple-events`, `device.audio-input`, `personal-information.calendars`) | 1 to 2 days |
| WeatherKit under Developer ID: the Commercial config clears entitlements and signs ad hoc (`project.yml:29-33`), so weather cannot authenticate today. Needs a [Developer ID profile](https://forums.developer.apple.com/forums/thread/722378) embedded. Check the capability table | 1 day |
| CI: protected signing, `notarytool`, stapling, Gatekeeper check on a clean Mac | 2 days |
| Set `LicenseConfiguration.environment` beyond the hard-coded `"test"` (`Licensing.swift:11`), with the live-mode review `docs/COMMERCE.md` requires | 1 to 2 days |
| Optional updater. None exists, so customers would otherwise update by hand | 2 to 3 days |

**Total: about 1 to 2 weeks**, plus the live commerce tasks already listed in `docs/COMMERCE.md`, which are not re-audited here. Note that automation under a child `osascript` and hardened runtime permissions need a real signed test; this has not been verified.

### Route B: reduced store edition

A separate product. Do it after Route A, and only if App Review's response is encouraging.

| Work | Estimate |
| --- | --- |
| App Review consultation with a short concept demo (App Review appointments in Meet with Apple, as mentioned in [forum 823455](https://developer.apple.com/forums/thread/823455)) | Do first |
| Spikes: Music scripting targets, sandbox smoke run, System Events window lead | 2 to 3 days |
| `AppStore` config, `DOCKGROVE_APPSTORE` gates across Dock, AX, CLI, license code and menus | 4 to 6 days |
| Bookmarks for shelf and folders, home path fixes | 3 to 4 days |
| Music in-process, Spotify decision | 1 to 3 days |
| Catalog, IAP copy, onboarding without replacement, distinct visual language for 5.2.5 | 3 to 5 days |
| Plist, privacy manifest, timestamp cleanup, in-app privacy link | 2 days |
| Tests and CI below | 4 to 5 days |
| Store metadata, screenshots, TestFlight | 2 to 3 days |

**Total: about 4 to 6 engineer-weeks, plus 2 to 6 weeks elapsed for review rounds, with a real chance of rejection under 2.5.8 or 5.2.5.** Every later release also carries the cost of a second gated build.

### Both

Possible and consistent with uBar's model. Customers must be told plainly which edition has which features, and purchases do not cross over. Keep the store edition on a distinct bundle ID.

## Tests and CI needed

The existing CI builds Development and Commercial, runs a coverage gate, and lints the bundle. Nothing tests a sandboxed build.

| Check | Purpose |
| --- | --- |
| Build `AppStore` on every PR | Catch gate rot |
| Run `DockGrove Tests` under `AppStore`, with `CheckCoverage.swift` and `coverage-allowlist.txt` updated for the new gates | The suite relies on injected fakes and CLI fixtures, so many tests will need exclusion |
| Sandbox smoke test: launch the sandboxed app, confirm the panel appears, then exercise files, calendar, weather and network | Most runtime claims in this document are unverified until this exists |
| Bookmark persistence: pick a file, relaunch, read it | The largest new failure mode |
| Binary lint: `nm -um` and `strings` must not show `AXUIElement*`, `osascript`, `/usr/bin/defaults`, `killall`, `WD1-`, `purchase.html`, `/bin/sh` | Proves code was compiled out |
| Entitlement lint: `codesign -d --entitlements :-` has `app-sandbox`, has no `temporary-exception`, and matches an allowlist | Stops drift |
| Plist lint: bundle ID, display name, category, `ITSAppUsesNonExemptEncryption`, no `DockGroveLicense*` | Stops the `.development` mistake |
| Manifest lint: `PrivacyInfo.xcprivacy` is present and parses | |
| Bundle lint: no `.storekit`, no test code, no quarantine attribute, universal | |
| `PurchaseTests` in CI | Today it runs only by hand |
| Archive, export with `app-store-connect`, `xcrun altool --validate-app`, upload to TestFlight, in a protected workflow | Real submission path |
| Manual pass: macOS 14 and current, notched and non-notched Macs, Intel if still supported, TestFlight sandbox purchases, restore, refund | Real-world evidence |
| Developer ID job for Route A: `notarytool`, `stapler validate`, `spctl` | Per `docs/MALCOLM-SIGNING-HANDOFF.md` |

## Ordered checklist

Route A first:

1. Owner confirms direct sale remains the primary route.
2. Create the Developer ID certificate and enable hardened runtime for Commercial.
3. Add a Developer ID profile so Weather works, then re-test Apple Events, microphone and calendar under hardened runtime.
4. Add a signed, notarized CI job and verify on a clean Mac.
5. Finish the live items in `docs/COMMERCE.md`. Decide on an updater.

Route B, only if wanted:

6. Book an App Review consultation. Ask directly about 2.5.8 and 5.2.5 for a floating dock that leaves Apple's Dock untouched. Stop here if the answer is negative.
7. Run the spikes: a sandboxed smoke build, Music scripting targets, the screenshot and audio checks, the Unknown rows above.
8. Decide the edition's scope, name, look, and pricing.
9. Choose the store bundle ID and fix the App Store Connect record **before any upload**. Enable WeatherKit and In-App Purchase on it.
10. Add the `AppStore` config, scheme, entitlements, `Info` plist and `DOCKGROVE_APPSTORE`.
11. Compile out Dock replacement, AX, global key monitors, terminate actions, other-app login items, every `Process()` use except screenshot, CLI arguments, licensing, and test harness files.
12. Add bookmarks, fix home paths, trim the catalog, update the purchase copy.
13. Add `PrivacyInfo.xcprivacy`, category, export key. Resolve the timestamp reasons.
14. Rewrite the privacy policy, and add in-app privacy and support links.
15. Add the lints and sandbox tests.
16. Upload to TestFlight, test purchases, measure power.
17. Complete metadata, age rating, privacy labels, trader status and review notes. Submit the version with both purchases.
18. Plan for rejection: keep the direct edition independent of the outcome.

## Open questions

- How App Review reads 2.5.8 and 5.2.5 for a floating dock. Nothing here can settle that.
- Whether the System Events `window.position` group works, and whether it would be accepted.
- Whether Music artwork `raw data` is reachable through the published access groups.
- Whether Spotify publishes scripting access groups.
- Whether privacy-manifest reasons are enforced for macOS uploads, and how to declare the `/Applications` timestamp uses.
- Whether a macOS minimum SDK applies.
- Whether the draft purchases can move to a new bundle ID or record.
- The terms of OpenAI, Anthropic, Cursor and Spotify for this use (5.2.2).

## Sources

Apple:
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) ·
[Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) ·
[Temporary exception entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html) ·
[Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) ·
[Required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) ·
[NSPrivacyAccessedAPIType](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) ·
[Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) ·
[Encryption export](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations) ·
[LSApplicationCategoryType](https://developer.apple.com/documentation/bundleresources/information-property-list/lsapplicationcategorytype) ·
[App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/) ·
[Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/) ·
[Supported capabilities (macOS)](https://developer.apple.com/help/account/reference/supported-capabilities-macos/) ·
[Embedding a helper tool](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app) ·
[Trademark list](https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html)

Apple forums:
[805556, Accessibility in the sandbox](https://developer.apple.com/forums/thread/805556) ·
[810677, window manager](https://developer.apple.com/forums/thread/810677) ·
[103998, 2018 DTS note](https://developer.apple.com/forums/thread/103998) ·
[823455, Apple Event exceptions](https://developer.apple.com/forums/thread/823455) ·
[126435, Music entitlements](https://developer.apple.com/forums/thread/126435) ·
[722378, WeatherKit with notarization](https://forums.developer.apple.com/forums/thread/722378)

Third party, treat as second-hand:
[Crosley on window managers](https://blakecrosley.com/blog/window-manager-mac-app-store-sandbox) ·
[Tsai on PopClip](https://mjtsai.com/blog/2024/03/21/popclip-leaving-the-mac-app-store/) ·
[Tsai on pasteboard privacy](https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4) ·
[ifun.de on AppHub](https://www.ifun.de/apphub-fuer-macos-tahoe-launchpad-alternative-geht-apple-zu-weit-265475/) ·
[uBar support](https://ubarapp.freshdesk.com/support/solutions/articles/150000000939-upgrading-from-the-mac-app-store-version-of-ubar-to-the-full-version)
