# Refined DockGrove integration review

This branch combines Malcolm's PR stack (#9, #10, and the integration PR #11) with the November landing-page and companion direction. The stack shares ancestry; it must be merged once, preserving its commits, rather than applying the same changes three times.

## Product changes

- The owner-selected three-bar Dock logo replaces the earlier G mark in the app icon, native brand catalog, website, and repository wordmark. `MakeConceptBrand.swift` is the reproducible source.
- A bright silver landing page has an interactive focus timer, appearance previews, all nine selectable companions, responsive navigation, and reduced-motion support. Illustrations are explicitly sample data; checkout remains disabled.
- Nine new whole-body pixel atlases replace the prior artwork. Tuxedo cat has white paws, bib and muzzle; the blue dragon has front arms and a flying cycle. Sixteen fixed cells share a crop and scale. Existing autonomous motion, sleep and reduced-motion behavior are preserved.
- The main pet tile now uses its full space for the animal. Name, needs and care remain in its click-open panel and accessible label.

## Review corrections

- Weather requests for a changed city supersede older requests without dropping the new lookup. Duplicate requests for the same revision remain suppressed. Geocoder no-result errors produce the correct city-not-found message.
- Reconnecting Claude no longer deletes its saved usage report.
- Combined music controls open the correct provider connection settings.
- Only pinned apps appear in the editable Studio layout; running unpinned apps no longer expose ineffective removal controls.
- Existing layouts do not gain an unsolicited Applications tile. Fresh installs still include it.
- Cancelling the Applications launcher restores the previous app; launching closes the panel before opening the chosen app.
- Background widget access follows the same license/tier conditions as the Dock and stops locked work after license changes.
- Drag-opened notch panels can collapse after a cancelled drag, without changing manually opened panels. Already-hidden notch panels avoid repeated published updates.
- One window snapshot is shared by the Docks and notch during a visibility tick.

## Verification

Local production website build, lint, exported-page/client tests, all nine atlas cell/mirrored-bound checks, and a 180-second native companion simulation are exercised for this release. Browser checks cover desktop and 390px layouts, appearance switching, timer state and all-nine companion selection. Generated review media is kept outside the repository.

The complete hosted XCTest suite and coverage gate remain required in GitHub CI. The local macOS 27 test runner stalled while symbolicating a UI-test issue; do not describe that interrupted run as a pass. Signing/notarization, StoreKit product configuration, and live commerce remain owner-managed release steps.
