# DockGrove brand

DockGrove is the product name. The canonical website is https://dockgrove.com and the repository is https://github.com/dylanlasensky/DockGrove.

The owner supplied `app/Assets.xcassets/Brand/DockGrove-brand-sheet.imageset/DockGrove-brand-sheet.png`. The production wordmark and app icon are exact raster crops from that image, not AI regenerations or new drawings. `app/Scripts/ExtractBrand.swift` records the source rectangles; the icon's outside corners are masked to its supplied rounded silhouette. `app/Scripts/MakeIcon.swift` resamples that crop into the macOS icon sizes. The website and native UI share the same icon PNG. The source is finite-resolution raster artwork; an original vector file would improve very large exports without changing the design.

The native asset catalog also includes `AppIcon.appiconset` with all ten macOS sizes, four brand image sets, eighteen companion image sets, and 16 named color packs (92 accents): Classic, Coastal, Orchard, Dusk, Forest, Arctic, Sorbet, Blossom, Neon, Arcade, Desert, Coffee, Slate, Autumn, Aurora, and Festive. All packs beyond Classic include light/dark variants. Use the Appearance color-pack picker to choose them; arbitrary custom accents remain supported.

Palette: black `#111111`, graphite `#34383F`, cool grey `#A3AAB5`, white `#FFFFFF`, blue `#4D83E8`.

## Compatibility identifiers

Visible names, executable, bundle filenames, icon, exports, UI, documentation, GitHub links and website use DockGrove. The existing `com.dylan.wavedock` bundle identifier and its development/QA variants remain stable to preserve preferences and OS identity. Keychain service names, extra-Dock defaults suites and the commerce encryption salt also retain their established bytes. These are compatibility identifiers, not public branding.

Existing Application Support/WaveDock libraries continue to be read in place so recordings and AI reports are not orphaned. Fresh libraries use Application Support/DockGrove. Old layout exports still import. The original historical MIT license and Git history are not rewritten.

The existing Cloudflare Worker retains its internal `wavedock-preview` service ID so old preview links keep working; dockgrove.com is the canonical public address. Custom domains are explicitly recorded in the deployment config after connection.

## Font Awesome action icons

The `FontAwesome` group in `app/Assets.xcassets` contains 13 unmodified SVGs from
[Font Awesome Free 7.3.1](https://github.com/FortAwesome/Font-Awesome/releases/tag/7.3.1),
by Fonticons, Inc. Provider marks represent only their respective services.
The vector image sets preserve vector data and render as templates, so the native
foreground color adapts to light/dark appearance. `FontAwesomeLabel` pairs the icons
with readable button labels; decorative images are hidden from accessibility.

SVG attribution comments are preserved. `app/Resources/FontAwesome-LICENSE.txt`
contains the upstream license and is included by both the Xcode and shell builds.
The SVG icons are licensed under CC BY 4.0; see https://fontawesome.com/license/free.
