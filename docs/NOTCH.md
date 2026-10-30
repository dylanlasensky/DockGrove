# Notch workspace

Enable **Settings → Appearance → Notch quick access** on a compatible display. DockGrove detects the camera housing with `NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea`, and `auxiliaryTopRightArea`; it does not rely on a Mac model list.

The collapsed panel exactly matches the system camera housing, with no extra side controls. Hover over the notch briefly or click it to expand the workspace from the top of the display. The expanded workspace is 760 points wide, capped to the screen, while retaining the original expanded height (camera housing plus 324 points). The expanded header leaves the physical camera area empty. Hover-opened panels close after the pointer leaves; clicked-open panels stay until collapsed. An open widget remains available while you interact with it.

- **Home** combines music controls, Focus, and a searchable widget grid with four cards per page. Dock favorites appear first. Only widgets permitted by the purchase tier appear; layout-only spacers and separators are excluded. Widget controls open inline using their existing data.
- **Tray** shares the persistent File Shelf, included in Plus and Full Access. Drag local files or folders onto the notch to expand directly into Tray, or use Add files. Shortcuts support opening, dragging out, revealing in Finder, sharing through the system share sheet, and removal. Clearing or removing shortcuts never deletes or moves the originals. Missing files are marked unavailable; duplicate paths are ignored.

Choose **Tabs** or **Rounded pills** under **Settings → Appearance → Notch navigation**. The inline preview cards apply the style immediately and remember it across launches.

No camera access is requested. The feature is opt-in and persists across launches. It uses the first connected compatible display, hides when DockGrove is hidden or during full-screen apps, lock, and sleep, and disappears when no compatible display is attached. Reconnecting a compatible display restores availability. The main toolbar remains independently available.

## Validation

`--notch-test /tmp/dockgrove-notch-preview` checks unsupported/missing geometry, non-finite insets, negative display origins, exact collapsed housing bounds, persistent enablement, suppression cleanup, hover dwell/leave/manual-collapse behavior, and purchase-filtered catalog completeness and navigation style persistence. File checks cover native pasteboard URL decoding, existing local files and folders, invalid URLs, duplicates, persistence, tier gating, and preserving originals after shortcut removal. It renders collapsed, Home, Tray, and inline Focus states.

The development Mac reports a 1512×982-point built-in display with a 185×32-point camera housing. Native checks covered enablement, expanding/collapsing, widget paging, inline Focus controls, adding a test file through the native picker, removing its shortcut while preserving its contents, and hiding during a blank native full-screen test.

Physical Finder-to-notch and notch-to-app drag gestures, sharing, lock/sleep, and external-display reconnection have not been manually certified. Hover timing, suppression, file intake, and coordinate cases were tested in code; native pointer-hover automation is unavailable in the current tool.

Apple API reference: https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets
