# Notch quick access

Enable **Settings → Appearance → Notch quick access** on a compatible display. DockGrove detects the camera housing with `NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea`, and `auxiliaryTopRightArea`; it does not rely on a Mac model list.

The collapsed controls live in the notch row, beside the camera housing. The center is left empty. Hover over that area briefly or click either side to open the widget browser. Hover-opened panels close after the pointer leaves; clicked-open panels stay until collapsed. An open widget remains available while you interact with it.

The browser includes all widgets permitted by the user's purchase tier, with current Dock widgets first, search, and page arrows. Layout-only spacers and separators are excluded. Opening a widget uses its existing controls and data; adding it to the main Dock is not required. No camera access is requested.

The feature is opt-in and persists across launches. It uses the first connected compatible display, hides when DockGrove is hidden or during full-screen apps, lock, and sleep, and disappears when no compatible display is attached. Reconnecting a compatible display restores availability. The main toolbar remains independently available.

## Validation

`--notch-test /tmp/dockgrove-notch-preview` checks unsupported/missing geometry, non-finite insets, negative display origins, notch-row positioning, persistent enablement, suppression cleanup, hover dwell/leave/manual-collapse behavior, and purchase-filtered catalog completeness. It also renders compact and expanded panels.

The development Mac reports a 1512×982-point built-in display with a 185×32-point camera housing. Native checks covered enablement, expanding/collapsing from the notch row, widget paging, opening Focus controls, and hiding during a blank native full-screen test. Physical lock/sleep and external-display reconnection were not manually exercised; suppression and coordinate cases were tested in code. Hover timing was validated by state tests; native pointer-hover automation is unavailable in the current tool.

Apple API reference: https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets
