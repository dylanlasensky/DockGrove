# DockGrove brand

DockGrove is the product name. The canonical website is https://dockgrove.com and the repository is https://github.com/dylanlasensky/DockGrove.

The owner supplied `Assets/Brand/DockGrove-brand-sheet.png`. The production wordmark and app icon are exact raster crops from that image, not AI regenerations or new drawings. `Scripts/ExtractBrand.swift` records the source rectangles; the icon's outside corners are masked to its supplied rounded silhouette. `Scripts/MakeIcon.swift` resamples that crop into the macOS icon sizes. The website and native UI share the same icon PNG. The source is finite-resolution raster artwork; an original vector file would improve very large exports without changing the design.

Palette: black `#111111`, graphite `#34383F`, cool grey `#A3AAB5`, white `#FFFFFF`, blue `#4D83E8`.

## Compatibility identifiers

Visible names, executable, bundle filenames, icon, exports, UI, documentation, GitHub links and website use DockGrove. The existing `com.dylan.wavedock` bundle identifier and its development/QA variants remain stable to preserve preferences and OS identity. Keychain service names, extra-Dock defaults suites and the commerce encryption salt also retain their established bytes. These are compatibility identifiers, not public branding.

Existing Application Support/WaveDock libraries continue to be read in place so recordings and AI reports are not orphaned. Fresh libraries use Application Support/DockGrove. Old layout exports still import. The original historical MIT license and Git history are not rewritten.

The existing Cloudflare Worker retains its internal `wavedock-preview` service ID so old preview links keep working; dockgrove.com is the canonical public address. Custom domains are explicitly recorded in the deployment config after connection.
