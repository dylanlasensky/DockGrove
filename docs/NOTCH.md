# Horizontal notch strip

Enable **Settings → Appearance → Notch quick access** on a compatible display. DockGrove detects the camera housing with `NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea`, and `auxiliaryTopRightArea`; it does not rely on a Mac model list.

The collapsed panel exactly matches the system camera housing. Hover or click to expand a strip with adjustable width, capped to the screen. In Appearance settings, drag the Notch width number, use its minus/plus buttons, or choose Compact (640), Balanced (760), or Wide (1000). The preferred width is saved across launches, with a 600–1600-point range. Its content adds only 112 points below the camera row: on the development Mac, the total expanded size is 760×144 points, down from 760×356. The camera area remains empty.

Music, Focus, widget cards, and file shortcuts use wider horizontal layouts. Disconnected music opens Settings → Connections instead of displaying a Connect button.

The header has two compact tabs: **Home** and **Files**. Home contains wider Music, Focus, and unlocked widget cards in one horizontally scrolling row. Files holds the separate file tray; additional shortcuts extend its horizontal row. Each saved-file card also fills half the available width, so card sizes follow the width setting and display bounds. There are no widget page buttons, and switching tabs does not change the strip height. Search in the header filters widget cards. Opening a widget replaces its card with bounded inline controls and scrolls it into view; longer controls can scroll within that fixed-height area without growing the strip.

The Files tab has two drop zones that each fill half the available notch width: **File tray** keeps shortcuts locally; **AirDrop** opens a custom inline review panel in the right half without adding anything to the tray. The left File Tray drop zone remains present throughout review, and saved tray items remain available by scrolling. Drop or add files to preview them, remove individual files through their context menus, or clear the selection from the selection-count context menu. Nothing is handed to AirDrop until Choose device is clicked. That button opens Apple’s device chooser; recipient selection and transfer remain in the system interface. Returning from the chooser retains the selection for retry or reuse; Clear removes it explicitly. The app does not treat the chooser completion callback as proof of delivery. Closing review restores the AirDrop drop zone in the right half. Playback, settings, and review actions use plain icons or text rather than boxed buttons.

The tray shares the persistent File Shelf, included in Plus and Full Access. Drag local files or folders onto the notch to select Files automatically, or select the second Files tab and use Add files. Shortcuts open directly and support dragging out. Their context menus provide Finder reveal, system sharing, and removal; the item-count context menu clears the tray. Clearing or removing shortcuts never deletes or moves originals. Missing files are marked unavailable; duplicate paths are ignored.

Hover-opened strips close after the pointer leaves; clicked-open strips stay until collapsed. Active widget interactions keep the strip open. No camera access is requested. The feature is opt-in and persists across launches. It uses the first connected compatible display, hides when DockGrove is hidden or during full-screen apps, lock, and sleep, and disappears when no compatible display is attached. The main toolbar remains independently available.

## Validation

The notch regression tests (part of the **DockGrove Tests** XCTest suite) check unsupported/missing geometry, non-finite insets, negative display origins, exact collapsed bounds, fixed expanded height, persistent enablement, suppression cleanup, hover behavior, and purchase-filtered catalog completeness. File checks cover native pasteboard URL decoding, existing local files and folders, invalid URLs, duplicates, persistence, tier gating, and preserving originals after shortcut removal. It checks automatic Files-tab selection, separate native drop routing, no tray mutation for AirDrop, saved width, and width bounds for accepted file drops and renders collapsed, Home, Files, and inline Focus states.

The development Mac reports a 1512×982-point built-in display with a 185×32-point camera housing. Native checks verified sideways scrolling (the scroll offset moved from 0 to 0.164), search filtering, inline Focus controls, and clearing search back to the initial sections. Prior checks covered enablement, file-picker intake, shortcut removal with original contents unchanged, and hiding during a blank native full-screen test.

The AirDrop chooser was opened with an agent-created temporary file and listed a nearby device; cancelling left the tray empty. Physical Finder-to-notch and notch-to-app drag gestures, completed AirDrop transfer, lock/sleep, and external-display reconnection have not been manually certified. Hover timing, suppression, file intake, and coordinate cases were tested in code.

Apple API reference: https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets

AirDrop uses [NSSharingService.sendViaAirDrop](https://developer.apple.com/documentation/appkit/nssharingservice/name/sendviaairdrop) and the system sharing interface.
