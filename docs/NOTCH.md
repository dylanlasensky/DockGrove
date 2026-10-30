# Horizontal notch strip

Enable **Settings → Appearance → Notch quick access** on a compatible display. DockGrove detects the camera housing with `NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea`, and `auxiliaryTopRightArea`; it does not rely on a Mac model list.

The collapsed panel exactly matches the system camera housing. Hover or click to expand a 760-point-wide strip, capped to the screen. Its content adds only 112 points below the camera row: on the development Mac, the total expanded size is 760×144 points, down from 760×356. The camera area remains empty.

The header has two compact tabs: **Home** and **Files**. Home contains Music, Focus, and unlocked widget cards in one horizontally scrolling row. Files holds the separate file tray; additional shortcuts extend its horizontal row. There are no widget page buttons, and switching tabs does not change the strip height. Search in the header filters widget cards. Opening a widget replaces its card with bounded inline controls and scrolls it into view; longer controls can scroll within that fixed-height area without growing the strip.

The tray shares the persistent File Shelf, included in Plus and Full Access. Drag local files or folders onto the notch to select Files automatically, or select the second Files tab and use Add files. Shortcuts support opening, dragging out, revealing in Finder, system sharing, and removal. Clearing or removing shortcuts never deletes or moves originals. Missing files are marked unavailable; duplicate paths are ignored.

Hover-opened strips close after the pointer leaves; clicked-open strips stay until collapsed. Active widget interactions keep the strip open. No camera access is requested. The feature is opt-in and persists across launches. It uses the first connected compatible display, hides when DockGrove is hidden or during full-screen apps, lock, and sleep, and disappears when no compatible display is attached. The main toolbar remains independently available.

## Validation

`--notch-test /tmp/dockgrove-notch-preview` checks unsupported/missing geometry, non-finite insets, negative display origins, exact collapsed bounds, fixed expanded height, persistent enablement, suppression cleanup, hover behavior, and purchase-filtered catalog completeness. File checks cover native pasteboard URL decoding, existing local files and folders, invalid URLs, duplicates, persistence, tier gating, and preserving originals after shortcut removal. It checks automatic Files-tab selection for accepted file drops and renders collapsed, Home, Files, and inline Focus states.

The development Mac reports a 1512×982-point built-in display with a 185×32-point camera housing. Native checks verified sideways scrolling (the scroll offset moved from 0 to 0.164), search filtering, inline Focus controls, and clearing search back to the initial sections. Prior checks covered enablement, file-picker intake, shortcut removal with original contents unchanged, and hiding during a blank native full-screen test.

Physical Finder-to-notch and notch-to-app drag gestures, sharing, lock/sleep, and external-display reconnection have not been manually certified. Hover timing, suppression, file intake, and coordinate cases were tested in code.

Apple API reference: https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets
