# Settings audit and Dock IA proposal

Base: `9add9f4` (feat/notch-hover-options). Read-only audit. No code was changed.
Trigger: the user could not find **Dock length**, **hide/show**, or **restore the original Dock**.

All line numbers refer to `app/Sources/` at `9add9f4`. Other agents are editing
`DockStudioSettings.swift` right now, so expect its line numbers to move.

---

## 0. Reference: macOS 26 Tahoe ▸ System Settings ▸ Desktop & Dock

Apple's Tahoe help page ([mchlp1119, 26.0](https://support.apple.com/guide/mac-help/change-desktop-dock-settings-mchlp1119/26.0/mac/26.0))
lists the **Dock** group in this order. The label on screen comes first. The Tahoe help-page wording follows in brackets where it differs.

| # | macOS control | Type | Values |
|---|---|---|---|
| 1 | **Size** | slider (Small … Large) | |
| 2 | **Magnification** | switch plus slider (Small … Large) | |
| 3 | **Position on screen** [help: "Dock position on screen"] | popup or segmented control | Left · Bottom · Right |
| 4 | **Minimize windows using** [help: "Minimized windows animation"] | popup | Genie Effect · Scale Effect |
| 5 | **Double-click a window's title bar to** [help: "Window title bar double-click action"] | popup | Fill · Zoom · Minimize · Do Nothing |
| 6 | **Minimize windows into application icon** | switch | |
| 7 | **Automatically hide and show the Dock** | switch | |
| 8 | **Animate opening applications** | switch | |
| 9 | **Show indicators for open applications** | switch | |
| 10 | **Show suggested and recent apps in Dock** | switch | |

The next groups on the same pane are **Desktop & Stage Manager** (Show Items, Click wallpaper to reveal desktop,
Stage Manager, Show recent apps in Stage Manager, Show windows from an application), **Widgets**,
**Default web browser**, **Windows** (Prefer tabs…, Ask to keep changes…, Close windows when quitting…,
*Drag windows to left or right edge of screen to tile*, *Drag windows to menu bar to fill screen*,
*Hold ⌥ key while dragging windows to tile*, *Tiled windows have margins*) and **Mission Control**,
which ends in **Shortcuts…** and **Hot Corners…** buttons.

Takeaways for DockGrove:
- Users expect **Size → Magnification → Position → … → Automatically hide and show** near the top of one "Dock" group.
- Apple says **"Automatically hide and show the Dock"**, not "Turn Hiding On" or "Automatically hide DockGrove".
- Apple has no "length" control. DockGrove's width is an *extra*, so it should sit next to Size, where people look first.
- macOS 26's own "Hold ⌥ key while dragging windows to tile" is the same idea as DockGrove's "Require Option while dragging". Reuse Apple's wording.
- Items 4, 5 and 6 are system-wide window behaviours that DockGrove does not own. At most, link to them ("Window animation settings… → System Settings").

---

## 1. Map of every current setting

### Settings window structure
- `App.swift:93-96`: a single `NSWindow` (1080×780), titled "DockGrove", hosting `SettingsView`.
- `DockWorkspace.swift:44-45`: each extra dock gets its own copy of the same `SettingsView`.
- `DockStudioSettings.swift:4-18`: the sidebar has five sections, **Library · Appearance · Behavior · Connections · Purchases**.
- `DockStudioSettings.swift:101-109`: the sidebar footer has the links **Manage docks…** (primary dock only), **Restore Apple Dock** and **Quit DockGrove**.
- `DockStudioSettings.swift:80`: `.toggleStyle(.switch)` is applied to the whole window.
- `DockStudioSettings.swift:51-57`: a live `DockStudioPreview` sits above Library, Appearance and Behavior.

### Library (`DockStudioSettings.swift:115-228`)
| Control | Line |
|---|---|
| Widgets / Apps segmented control, search, refresh apps | 134-137 |
| Widget category chips | 142-147 |
| Widget cards (click or drag to add or remove) | 151-155, 186-227 |
| App cards (click or drag to pin or unpin) | 159-180 |

### Appearance (`DockStudioSettings.swift:230-266`)
| Panel | Control | Line |
|---|---|---|
| Pick a mood | Automatic · Glass · Graphite · Pearl | 234-246 |
| **Notch quick access** (primary only) | see the Notch table below | 247 |
| **Toolbar size** | Compact · Balanced · Spacious presets | 412-417 |
| | **Toolbar width** (35–100 %) ← *this is "Dock length"* | 418 |
| | Toolbar height (88–180 pt) | 419 |
| | Icon size (32–64 pt) ← *this is Apple's "Size"* | 420 |
| | Fit width to content (switch) | 421 |
| | Reset size | 425 |
| Widget shapes | per-widget shape picker | 268-292 |
| Color | color collections and accent, custom ColorPicker | 294-367 |
| | Rich widget cards | 252 |
| | Use album colors in music widgets | 253 |
| **Position** | Dock name (text field) | 257 |
| | Horizontal position (0–100 %) | 258 |
| | Edge: Bottom · Top · Floating (disabled while replacing the Dock) | 259-261 |
| | Vertical position (Floating only) | 262 |

### Notch (`Notch.swift:413-463`, shown inside Appearance)
| Control | Line |
|---|---|
| Enable notch access | 439 |
| Open notch (button) | 442 |
| Open when the pointer reaches the notch | 446 |
| Close when the pointer leaves | 447 |
| Notch width (600–1600 pt) | 449 |
| Compact / Balanced / Wide presets | 451-453 |

### Behavior (`DockStudioSettings.swift:369-395`)
| Panel | Control | Line |
|---|---|---|
| **At a glance** | Show Applications stack first | 375 |
| | Show clock and date | 376 |
| | Show Codex usage tile (locked label if no AI access) | 377 |
| | **Use DockGrove as my Dock** (primary only) ← *the restore control, buried here* | 379-380 |
| | **Show DockGrove** | 382 |
| | system error text | 383 |
| **Layout & profiles** (`ToolViews.swift:210-231`) | Display (choice grid) | 217 |
| | **Automatically hide DockGrove** ← *Apple's hide/show, buried here* | 218 |
| | Hide when windows overlap | 219 |
| | Include unpinned running apps | 220 |
| | Name this layout… / Save layout | 221 |
| | Saved layouts: Apply / Remove | 222-224 |
| | Export layouts… / Import layouts… | 225 |
| | Open DockGrove at login (`ToolViews.swift:238`) | 227 |
| **Window snapping** (`WindowSnapper.swift:130-141`, primary only) | Snap dragged windows to screen edges | 135 |
| | Require Option while dragging | 136 |
| | Allow Accessibility (button) | 138 |
| **Codex usage** (if AI access) | Account settings (button that jumps to Connections) | 388-391 |

### Connections (`ConnectionSettings.swift:34-97`, `AIConnectionSettings.swift`)
- Provider tiles for ChatGPT/Codex, Claude, Gemini, Cursor, OpenAI and Anthropic, plus Apple Music, Spotify, Calendar, Google Calendar and Reminders (`ConnectionSettings.swift:56-79`).
- Codex options: executable path, **Auto-refresh**, Refresh usage (`AIConnectionSettings.swift:69-71`).
- API-token providers: token field, **Auto-refresh hourly**, Refresh saved token, Remove saved token (`AIConnectionSettings.swift:146-163`).
- Claude: Enable usage capture, Remove usage capture, Clear saved usage (`:190-192`). Gemini: Import session JSON, Copy capture command, Clear (`:217-219`).
- Non-AI providers show the widget's own popover contents (`ConnectionSettings.swift:88`).

### Purchases
- `PurchaseViews.swift:29+`: Restore Purchases, Reload prices. `Licensing.swift:224+`: Buy, Restore purchase, Refresh activation, Deactivate this Mac.

### Outside the settings window
| Surface | Controls | Location |
|---|---|---|
| Menu-bar status item | Settings… · Show / hide DockGrove · Refresh usage · **Restore Apple Dock** · Quit DockGrove | `App.swift:100` |
| App menu (only when Settings is key) | Settings… · Close Settings · Quit | `App.swift:63-66` |
| Right-click on the Dock bar | **Turn Hiding On/Off** · Position on Screen ▸ Bottom/Top/Floating · Dock Settings… | `Views.swift:189-202` |
| Right-click on an app tile | Keep in Dock, Show in Finder, Show All Windows, Hide, Quit, Replace app…, Move left/right | `Views.swift:236-272` |
| Right-click on a widget | Widget shape ▸, Move earlier/later, Remove from Dock | `ToolViews.swift:89-100` |
| "Your Docks" window | per-dock name, **Visible** toggle, Customize, Remove, Add a Dock | `DockWorkspace.swift:74-94` |
| CLI | `DockGrove --restore-dock` | `App.swift:267-270` |

---

## 2. Problems found

### 2a. Why the user could not find the three settings
1. **Dock length** is labelled **"Toolbar width"** (`DockStudioSettings.swift:418`). It sits in the fourth panel of *Appearance*, below the mood picker and the large Notch panel. The words "Dock", "length" and "size" never appear near it.
   - It also often has **no visible effect**. "Fit width to content" defaults to ON (`Model.swift:128`). In that mode the width is `min(requested, natural)` (`Model.swift:184`), so raising "Toolbar width" past the content width does nothing. The user drags the control, nothing happens, and they conclude the setting does not exist.
2. **Hide/show** is labelled **"Automatically hide DockGrove"** (`ToolViews.swift:218`). It sits inside a panel titled **"Layout & profiles"** next to Save layout and Export, which is the wrong place to look for it.
   - It is **silently ignored when Edge = Floating** (`App.swift:215-216`). The only caption that explained this was in the dead `DockAppearanceSettings` (`DockWorkspace.swift:105`).
   - The Dock right-click label "Turn Hiding On/Off" (`Views.swift:194`) is a third wording.
3. **Restore original Dock** exists in three places, and none of them looks like a primary control:
   - a `.link`-styled text button in the sidebar footer, between "Manage docks…" and "Quit" (`DockStudioSettings.swift:106`)
   - a switch called **"Use DockGrove as my Dock"** under **"At a glance"**, mixed in with clock and usage tiles (`:379`)
   - the menu-bar item (`App.swift:100`)

   These use two different vocabularies ("Restore Apple Dock" and "Use DockGrove as my Dock") for the same state.

### 2b. Duplicates
| Setting | Places | Notes |
|---|---|---|
| Replace or restore the Apple Dock | sidebar link (`DockStudioSettings.swift:106`), switch (`:379`), status menu (`App.swift:100`) | Keep the switch as the source of truth. The other two should read "Restore Apple Dock" and be disabled when `!replacingDock`. |
| DockGrove visible | "Show DockGrove" (`DockStudioSettings.swift:382`), "Show / hide DockGrove" (`App.swift:100`), "Visible" (`DockWorkspace.swift:93`) | Three labels for one value. |
| Auto-hide | Behavior switch (`ToolViews.swift:218`), Dock right-click (`Views.swift:194`) | Different wording. |
| Edge / position | Appearance ▸ Position ▸ Edge (`DockStudioSettings.swift:259`), Dock right-click "Position on Screen" (`Views.swift:195`) | Settings calls it "Edge" and the menu calls it "Position on Screen". |
| Codex usage tile | Behavior ▸ At a glance (`:377`), Behavior ▸ Codex usage panel (`:387-392`) | The second panel only links to Connections. |
| Codex auto-refresh | "Auto-refresh" (`AIConnectionSettings.swift:70`), "Refresh usage automatically" (`AISignIn.swift:145`, test-only view) | Same `usageEnabled`. |
| Width, height and icon size | Toolbar width / height / icon size (`:418-420`) plus 3 presets plus Reset | Height is clamped by icon size (`Model.swift:177`), so the two overlap. |

### 2c. Dead toggles and code
- **`DockAppearanceSettings`** (`DockWorkspace.swift:95-112`) is never instantiated in the app; only `DockCoverageTests.swift:1235` uses it. It has its own copies of Dock name, a theme list with a stale **"System"** option, Maximum width, Horizontal position, Position, Floating height, Reset position, Show Codex usage tile, album colors and Manage all docks. Delete it, or move its useful bits (the Floating caption and "Reset position") into the real panel.
- **`CodexConnectionView`** (`AISignIn.swift:137-149`) is used only by `IntegrationsCoverageTests.swift:587`.
- **"Restore Apple Dock" in an extra dock's settings window is dead.** `ExtraDock` never sets `changeDockAction` (`DockWorkspace.swift:46-47`, `App.swift:141-150`), so the sidebar button at `DockStudioSettings.swift:106` does nothing there. Hide it when `model.isAdditionalDock`, as "Manage docks…" already is.
- The "Restore Apple Dock" menu item (`App.swift:100`) and the sidebar link are always enabled, even when DockGrove is not replacing the Dock.
- `selectedBucket` is persisted (`Model.swift:23,144`) but has no UI. This is not a user setting, so it is fine. It is listed only for completeness.

### 2d. Controls with no visible effect, or a confusing one
- **Toolbar width** has no effect above the content width while "Fit width to content" is on (see 2a.1).
- **Automatically hide** and **Hide when windows overlap** do nothing when Edge = Floating, and nothing tells the user.
- **Edge** is disabled while replacing the Dock (`DockStudioSettings.swift:261`) with no explanation.
- **Notch width** and its presets (`Notch.swift:449-453`) stay enabled when notch access is off or not available, unlike the hover switches (`:448`).
- **Show DockGrove = off while replacing the Dock** leaves the user with **no Dock at all**: Apple's Dock has a 24 h autohide delay (`DockBehavior.swift:55`). The only ways back are the menu-bar item or reopening the app. At minimum, show a caption under the switch.
- **Toolbar height** can look like a no-op because `tileHeight = max(64, iconSize+20, toolbarHeight-24)` (`Model.swift:177`).

### 2e. Checkboxes that should be switches
The settings window forces `.switch` (`DockStudioSettings.swift:80`), but the same views also appear in **widget popovers** and the **Your Docks** window, which do not. There they render as checkboxes:
- `DockWorkspace.swift:93`: "Visible" in Your Docks.
- `ToolViews.swift:200`: "Capture copied text" (Clipboard popover).
- `UtilityViews.swift:65`: "Hourly reminder while DockGrove is open".
- `AIUsage.swift:206`: "Refresh hourly while DockGrove is open".
- `GitHubView.swift:9-10`: "Use existing GitHub CLI sign-in" and "Refresh every five minutes".
- `MusicPlayer.swift:167`: "Allow access".
- `CalendarWidget.swift:97`: "Allow calendar access".
- Leave these as checkboxes, because they are multi-select lists: `CalendarWidget.swift:104` (calendar list) and `ExtraWidgets.swift:262` (app-group membership).

Fix: apply `.toggleStyle(.switch)` at the popover root (`ToolViews.swift:102-106`), on the notch content host and on `DockWorkspaceView`.

### 2f. Unclear labels and misplaced controls
| Current | Problem | Proposed |
|---|---|---|
| Toolbar size / Toolbar width / Toolbar height | The product is a Dock, not a toolbar. | Dock size / **Dock length** / Dock height |
| Icon size | Apple calls it "Size". | **Size** (in the Dock group) |
| Edge: Bottom/Top/Floating | Apple says "Position on screen". "Edge" plus "Floating" is odd. | **Position on screen**: Bottom · Top · Floating |
| Horizontal position | Ambiguous. | **Alignment** (Left … Center … Right) |
| Vertical position | Applies only to Floating. | **Height above bottom** (Floating only) |
| Automatically hide DockGrove / Turn Hiding On | Not Apple's wording. | **Automatically hide and show the Dock** |
| Hide when windows overlap | OK. | Hide when a window overlaps the Dock |
| Include unpinned running apps | Closest match to Apple's suggested/recent apps. | **Show open apps that aren't kept in the Dock** |
| Use DockGrove as my Dock | Fine, but in the wrong panel. | **Replace the Apple Dock with DockGrove**, plus a visible **Restore Apple Dock** button beside it |
| Show DockGrove | Unclear next to the line above. | **Show this Dock** |
| At a glance (panel) | Mixes Dock replacement, visibility and tiles. | Split into "Dock" and "Items" |
| Layout & profiles (panel) | Holds display and auto-hide. | Keep it for profiles only |
| Rich widget cards (in Color) | Not a color setting. | Move to Widget shapes as "Show rich widget cards" |
| Dock name (in Position) | Not a position setting. | Move to the top of the Dock group or to Your Docks |
| Notch quick access (in Appearance) | It is a feature, not appearance. | Give it its own "Notch" section, or put it in Behavior |
| Require Option while dragging | macOS 26 says "Hold ⌥ key while dragging windows to tile". | **Hold ⌥ key while dragging windows to snap** |

---

## 3. Proposed information architecture

Sidebar: **Dock · Library · Appearance · Notch · Windows · Connections · Purchases**.
The new **Dock** section comes first and mirrors Desktop & Dock. Footer links: Manage docks… · Quit DockGrove.
"Restore Apple Dock" moves out of the footer and becomes a real button in Dock ▸ Replacement.
The footer can keep it as a link, but only when `replacingDock` is true.

### Dock (new, first)
Ordered to match macOS 26. **Bold** marks Apple-equivalent controls. *Italics* mark DockGrove extras placed beside their Apple sibling.

**Group: Dock** (mirrors System Settings ▸ Desktop & Dock ▸ Dock)
1. **Size**: slider, Small … Large (today's Icon size, 32–64 pt)
   - *Dock length*: slider, 35–100 % of display
   - *Fit length to content*: switch. Caption when on: "Length shrinks to fit your items; the slider sets the maximum."
2. **Magnification**: not built yet. Either omit it, or add a disabled row reading "Coming soon" if parity matters.
3. **Position on screen**: segmented control, Bottom · Top · Floating
   - When replacing the Dock, show it disabled with the caption: "DockGrove stays at the bottom while it replaces Apple's Dock."
   - *Alignment*: slider, Left … Right
   - *Height above bottom*: shown only for Floating
4. *(Minimize windows using, Double-click title bar, Minimize into app icon: DockGrove does not own these.)* Add one link: **"Window animation settings…"**, opening `x-apple.systempreferences:com.apple.Desktop-Settings.extension`.
5. **Automatically hide and show the Dock**: switch
   - *Hide when a window overlaps the Dock*: switch
   - Caption when Position = Floating: "Floating docks stay visible; hiding applies to top and bottom docks." Disable both switches in that case.
6. **Show indicators for open applications**: switch. This needs a new model bool; today the dot is always drawn at `Views.swift:225`.
7. **Show open apps that aren't kept in the Dock**: switch (today's "Include unpinned running apps"). This is the closest match to Apple's "Show suggested and recent apps in Dock".

**Group: Replacement** (DockGrove extra, primary dock only)
- **Replace the Apple Dock with DockGrove**: switch
- **Restore Apple Dock**: bordered button, enabled only while replacing
- Caption: "Apple's Dock comes back when you turn this off, click Restore, or quit DockGrove."
- system error text

**Group: Visibility** (DockGrove extras)
- **Show this Dock**: switch. Caption while replacing: "Turning this off leaves you without a Dock. Use the menu bar icon to bring it back."
- **Display**: choice grid
- **Open DockGrove at login**: switch

### Library
Unchanged.

### Appearance
1. Mood (Automatic · Glass · Graphite · Pearl)
2. Color: collections and accent, *Use album colors in music widgets*
3. Widgets: Widget shapes, *Show rich widget cards*
4. Items: Show Applications stack first · Show clock and date · Show Codex usage tile
5. Dock name (or move it to Your Docks)
6. Advanced size: Dock height, Compact / Balanced / Spacious presets, Reset size

### Notch (own section, primary only)
The current `NotchSettingsView`, with Notch width and its presets disabled when notch access is off.

### Windows (primary only)
- Snap dragged windows to screen edges
- Hold ⌥ key while dragging windows to snap
- Allow Accessibility
- Layouts: save / apply / remove / export / import (moved from "Layout & profiles")

### Connections, Purchases
Unchanged. Remove the duplicate "Codex usage" panel from Behavior, because Connections already covers it.

### Surfaces outside Settings: use the same words
- Dock right-click (`Views.swift:194-200`): **Turn Hiding On / Turn Hiding Off** and **Position on Screen ▸ Bottom/Top/Floating** both stay as they are, because Apple's own Dock right-click menu uses the same wording. Add a **Restore Apple Dock** item when replacing.
- Status menu (`App.swift:100`): Settings… · **Show Dock / Hide Dock** (dynamic title) · Refresh usage · **Restore Apple Dock** (disabled unless replacing) · Quit DockGrove.

---

## 4. Prioritised small edits

Each edit is small, and the file is named. DockStudioSettings edits must be coordinated with the three agents working there now.

**P0: fix discoverability of the three missing settings**
1. Rename "Toolbar width" to **"Dock length"** and "Icon size" to **"Size"**. Retitle the panel "Toolbar size" to **"Dock size"**. (`DockStudioSettings.swift:412,418,420`)
2. Make Dock length visibly work: when the user changes it while "Fit width to content" is on, either turn fit off, or show the caption "Length shrinks to fit your items; the slider sets the maximum". (`DockStudioSettings.swift:418-421`)
3. Rename "Automatically hide DockGrove" to **"Automatically hide and show the Dock"** and move it out of "Layout & profiles" into the Dock/size panel. (`ToolViews.swift:218`)
4. Move **"Use DockGrove as my Dock"** out of "At a glance" into its own "Replacement" panel, and put a **Restore Apple Dock** bordered button beside it. (`DockStudioSettings.swift:379-383`)
5. Add a **Dock** sidebar section ordered as in §3. Move the size panel, Position panel, auto-hide and replacement into it. (`DockStudioSettings.swift:4-18` plus the moved views)

**P1: dead or misleading behaviour**

6. Hide the sidebar "Restore Apple Dock" link for extra docks, because there it is a no-op. Also hide or disable it when `!replacingDock`. (`DockStudioSettings.swift:106`)
7. Disable the status-menu "Restore Apple Dock" item unless `replacingDock`, and make "Show / hide DockGrove" a dynamic "Show Dock / Hide Dock". (`App.swift:100`, via `validateMenuItem` or a menu delegate)
8. Disable auto-hide and hide-on-overlap when Edge = Floating, and add the Floating caption. (`ToolViews.swift:218-219`)
9. Add the caption "DockGrove stays at the bottom while it replaces Apple's Dock" under the disabled Edge picker. (`DockStudioSettings.swift:259-261`)
10. Add a warning caption under "Show DockGrove" while `replacingDock`. (`DockStudioSettings.swift:382`)
11. Disable Notch width and its presets when `!notchEnabled`. (`Notch.swift:449-453`)
12. Delete the dead `DockAppearanceSettings` (`DockWorkspace.swift:95-112`) and its test (`DockCoverageTests.swift:1235-1250`). Also delete `CodexConnectionView` (`AISignIn.swift:137-149`) and its test, or wire them up.

**P2: consistency and polish**

13. Apply `.toggleStyle(.switch)` at the widget popover root (`ToolViews.swift:102-106`), on the notch content host, and on `DockWorkspaceView` (`DockWorkspace.swift:78`).
14. Rename "Edge" to **"Position on screen"** (`DockStudioSettings.swift:259`), and "Horizontal position" to **"Alignment"** (`:258`).
15. Rename "Include unpinned running apps" to **"Show open apps that aren't kept in the Dock"**. (`ToolViews.swift:220`)
16. Rename "Show DockGrove" to **"Show this Dock"**. Use the same word in Your Docks "Visible". (`DockStudioSettings.swift:382`, `DockWorkspace.swift:93`)
17. Move "Rich widget cards" from the Color panel into Widget shapes. Move "Dock name" out of Position. (`DockStudioSettings.swift:252,257`)
18. Remove the Behavior "Codex usage" panel, which duplicates Connections. (`DockStudioSettings.swift:387-392`)
19. Rename "Require Option while dragging" to **"Hold ⌥ key while dragging windows to snap"**. (`WindowSnapper.swift:136`)
20. Add a "Window animation settings…" link to `x-apple.systempreferences:com.apple.Desktop-Settings.extension` for the system-owned items (Minimize effect, title-bar double-click, minimize into app icon).
21. Optional parity: a **"Show indicators for open applications"** switch, which needs a new `DockModel` bool used at `Views.swift:225`, and **Magnification**, which is not implemented.

Sources: [Apple, Change Desktop & Dock settings on Mac (macOS Tahoe 26)](https://support.apple.com/guide/mac-help/change-desktop-dock-settings-mchlp1119/26.0/mac/26.0),
[Apple, Desktop & Dock settings (macOS 14)](https://support.apple.com/en-asia/guide/mac-help/mchlp1119/14.0/mac),
[MacMost, double-click a window's title bar](https://macmost.com/double-click-a-windows-title-bar.html).
