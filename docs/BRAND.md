# WaveDock identity

WaveDock is a native workspace utility. Its promise is **Thoughtfully at hand.** The product should feel calm, useful and personal, with real information visible before the user opens a panel.

The original mark uses two flowing strokes that suggest both a wave and a W. It appears in the app icon, Settings, menu bar and repository wordmark. The editable vector wordmark is in `Assets/Brand/WaveDock.svg`; the app icon is reproducibly drawn by `Scripts/MakeIcon.swift`. Neither uses Apple's trademark artwork or CoolDock's assets.

## Visual system

- Graphite surfaces, pearl text and a restrained optional accent.
- SF system typography, semibold labels, monospaced numerical readouts and secondary explanatory text.
- Continuous rounded cards with a fine highlight and subtle vertical shading.
- Cards display genuine state: a timer, agenda item, task list, track, graph or connection prompt. No fabricated activity or sample data appears in the shipping UI.
- Inline actions are circular and have accessibility labels. The main card opens details; controls remain separate buttons.
- White and None are first-class choices. Eight curated presets and the native RGB color picker are available.
- Navigation and Settings remain outside the paged content area. Whole cards stay inside the selected display.

The test-only design gallery is generated from the same SwiftUI card components and explicitly labels its synthetic sample data. It is a visual QA artifact, not evidence of connected accounts.
